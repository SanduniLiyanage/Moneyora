import 'package:fpdart/fpdart.dart';

import '../../../../../core/errors/failures.dart';
import '../../entities/agent_tool.dart';
import '../../entities/tool_result.dart';
import '../../repositories/spending_by_category_reader.dart';
import 'copilot_tool.dart';

/// Answers "how much did I spend on food in August?" — the first tool, and the
/// one the whole single-tool path is proven with.
///
/// Runs entirely on-device against the encrypted database and returns category
/// totals only: no transaction ids, no merchants, no notes (FR-COP-010,
/// FR-COP-022).
///
/// Refs: FR-COP-007, FR-COP-022, FR-COP-030.
class GetSpendingByCategoryTool implements CopilotTool {
  /// Creates the tool over a [SpendingByCategoryReader].
  const GetSpendingByCategoryTool(this._reader);

  final SpendingByCategoryReader _reader;

  /// The tool's name, and the key it is registered under.
  static const String toolName = 'get_spending_by_category';

  static final RegExp _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  @override
  AgentTool get descriptor => const AgentTool(
    name: toolName,
    description:
        'Returns the total spent per category, in integer cents, between two '
        'dates inclusive. Use this for any question about how much was spent, '
        'on what, or over which period. Transfers between accounts '
        'the user owns are excluded.',
    parameters: {
      'type': 'object',
      'properties': {
        'from': {
          'type': 'string',
          'description':
              'First day of the range, ISO 8601 YYYY-MM-DD, '
              'inclusive.',
        },
        'to': {
          'type': 'string',
          'description':
              'Last day of the range, ISO 8601 YYYY-MM-DD, '
              'inclusive.',
        },
      },
      'required': ['from', 'to'],
    },
  );

  @override
  Future<Either<Failure, ToolResult>> execute(Map<String, dynamic> args) async {
    final failure = validate(args);
    if (failure != null) return Left(failure);

    // Safe after validate: both keys exist, are strings, and parse.
    final from = args['from']! as String;
    final to = args['to']! as String;

    final totals = await _reader.totalsByCategory(
      from: DateTime.parse(from),
      to: DateTime.parse(to),
    );

    return totals.map(
      (byCategory) => ToolResult(
        toolName: toolName,
        aggregate: {'from': from, 'to': to, 'totals_cents': byCategory},
      ),
    );
  }

  /// Returns the reason [args] cannot be used, or null when they are fine.
  ///
  /// The arguments arrive from a language model, which invents plausible dates
  /// (`August 2026`, `2026-02-31`) as readily as correct ones, and omits a
  /// required one when the question did not mention it. Every one of those has
  /// to end as a skipped call rather than a crash (FR-COP-006).
  ///
  /// Static so the loop, or a future registry check, can validate a call
  /// without constructing the tool.
  static ValidationFailure? validate(Map<String, dynamic> args) {
    final from = _parseDate(args['from'], 'from');
    final to = _parseDate(args['to'], 'to');

    return from.match(
      (failure) => failure,
      (start) => to.match(
        (failure) => failure,
        (end) => start.isAfter(end)
            ? const ValidationFailure(
                'The start of the range is after its end.',
                field: 'from',
              )
            : null,
      ),
    );
  }

  /// Parses [value] as an inclusive ISO date, or says why it could not.
  ///
  /// `Either` rather than a nullable [DateTime] because "missing" and
  /// "not a real date" are different mistakes and deserve different messages.
  static Either<ValidationFailure, DateTime> _parseDate(
    Object? value,
    String field,
  ) {
    if (value is! String || !_isoDate.hasMatch(value)) {
      return Left(
        ValidationFailure(
          'Expected $field as a YYYY-MM-DD date.',
          field: field,
        ),
      );
    }
    final parsed = DateTime.tryParse(value);
    // `DateTime.parse` rolls an impossible day forward — 2026-02-31 becomes
    // 3 March — so a value that parses is not yet a date that exists. Compare
    // the round trip to catch it, rather than silently answering about the
    // wrong month.
    if (parsed == null || !parsed.toIso8601String().startsWith(value)) {
      return Left(
        ValidationFailure('$value is not a real date.', field: field),
      );
    }
    return Right(parsed);
  }
}
