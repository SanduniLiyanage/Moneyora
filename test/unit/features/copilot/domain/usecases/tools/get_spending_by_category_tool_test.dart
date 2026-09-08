import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/spending_by_category_reader.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_result.dart';
import 'package:moneyora/features/copilot/domain/usecases/tools/get_spending_by_category_tool.dart';

/// Records what it was asked for, and can be told to fail.
///
/// Hand-written rather than generated: the port has one method, and the test
/// needs to know both that it was called and with what.
class _FakeReader implements SpendingByCategoryReader {
  DateTime? from;
  DateTime? to;
  int calls = 0;
  Failure? failWith;
  Map<String, int> totals = const {'Food': 3420000, 'Transport': 900000};

  @override
  Future<Either<Failure, Map<String, int>>> totalsByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    calls++;
    this.from = from;
    this.to = to;
    if (failWith case final failure?) return Left(failure);
    return Right(totals);
  }
}

void main() {
  late _FakeReader reader;
  late GetSpendingByCategoryTool tool;

  setUp(() {
    reader = _FakeReader();
    tool = GetSpendingByCategoryTool(reader);
  });

  Map<String, dynamic> august() => {'from': '2026-08-01', 'to': '2026-08-31'};

  group('descriptor', () {
    test('declares the name the registry and the model both use', () {
      // The loop looks a call up by name. A descriptor naming one thing and a
      // registry keyed on another means the model asks for a tool that, as far
      // as the loop can tell, does not exist — and the agent quietly gets
      // worse rather than failing.
      expect(tool.descriptor.name, GetSpendingByCategoryTool.toolName);
    });

    test('declares both dates, and declares them required', () {
      final parameters = tool.descriptor.parameters;
      final properties = parameters['properties']! as Map<String, dynamic>;

      expect(properties.keys, containsAll(<String>['from', 'to']));
      expect(parameters['required'], <String>['from', 'to']);
    });

    test('describes the question it answers, not the schema', () {
      // The description is the model's only guide to when this tool is
      // useful, and the unit it answers in.
      expect(tool.descriptor.description.toLowerCase(), contains('spent'));
      expect(tool.descriptor.description.toLowerCase(), contains('cents'));
    });
  });

  group('execute', () {
    test('returns the totals the reader gave, keyed by category', () async {
      final result = await tool.execute(august());

      expect(result.isRight(), isTrue);
      result.fold((f) => fail('unexpected failure: $f'), (toolResult) {
        expect(toolResult.toolName, GetSpendingByCategoryTool.toolName);
        expect(toolResult.aggregate['totals_cents'], {
          'Food': 3420000,
          'Transport': 900000,
        });
      });
    });

    test('echoes the range back, so the answer can name the period', () async {
      // NFR-USA-005: "you spent 34,200" is not an answer; "in August you spent
      // 34,200" is. The model can only say the period if the period is in the
      // result it reasons over.
      final result = await tool.execute(august());

      result.fold((f) => fail('unexpected failure: $f'), (toolResult) {
        expect(toolResult.aggregate['from'], '2026-08-01');
        expect(toolResult.aggregate['to'], '2026-08-31');
      });
    });

    test('reads the range the model asked for', () async {
      await tool.execute(august());

      expect(reader.calls, 1);
      expect(reader.from, DateTime(2026, 8));
      expect(reader.to, DateTime(2026, 8, 31));
    });

    test('passes a reader failure through unchanged', () async {
      // A locked database is not a malformed question. Reporting it as one
      // would send the user rephrasing something that was already fine.
      reader.failWith = const CacheFailure('database is locked');

      final result = await tool.execute(august());

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('should not have produced a result'),
      );
    });

    test(
      'carries only aggregates — no rows, ids, merchants or notes',
      () async {
        // FR-COP-010 / NFR-PRI-003. The egress guard test covers the payload
        // builder; this covers the tool that feeds it, because a tool that
        // returns a raw row leaves the builder honest and the data on the wire
        // anyway. Everything here is a period string or a category total.
        final result = await tool.execute(august());

        result.fold((f) => fail('unexpected failure: $f'), (toolResult) {
          expect(
            toolResult.aggregate.keys,
            containsAll(<String>['from', 'to']),
          );
          expect(toolResult.aggregate.keys.length, 3);
          final totals = toolResult.aggregate['totals_cents']! as Map;
          for (final value in totals.values) {
            expect(value, isA<int>(), reason: 'money must stay integer cents');
          }
        });
      },
    );

    test('an empty month is an empty map, not a failure', () async {
      // A quiet month is an answer — "nothing went out in that period" — not
      // an error state.
      reader.totals = const {};

      final result = await tool.execute(august());

      result.fold((f) => fail('unexpected failure: $f'), (toolResult) {
        expect(toolResult.aggregate['totals_cents'], isEmpty);
      });
    });

    test(
      'produces a ToolResult the loop can hand straight to the model',
      () async {
        final result = await tool.execute(august());

        expect(result.getRight().toNullable(), isA<ToolResult>());
      },
    );
  });

  group('rejects what the model gets wrong (FR-COP-006)', () {
    // A language model invents plausible arguments as readily as correct ones.
    // Every one of these has to end as a skipped call — never a crash, and
    // never an answer about a period nobody asked about.
    final malformed = <String, Map<String, dynamic>>{
      'no dates at all': <String, dynamic>{},
      'only a start': {'from': '2026-08-01'},
      'only an end': {'to': '2026-08-31'},
      'a month name': {'from': 'August 2026', 'to': '2026-08-31'},
      'an unpadded date': {'from': '2026-8-1', 'to': '2026-08-31'},
      'a timestamp': {'from': '2026-08-01T00:00:00Z', 'to': '2026-08-31'},
      'a number': {'from': 20260801, 'to': '2026-08-31'},
      'a null': {'from': null, 'to': '2026-08-31'},
      'a day that does not exist': {'from': '2026-02-31', 'to': '2026-03-31'},
      'a range that runs backwards': {'from': '2026-08-31', 'to': '2026-08-01'},
    };

    malformed.forEach((description, args) {
      test('rejects $description without touching the database', () async {
        final result = await tool.execute(args);

        expect(result.isLeft(), isTrue, reason: '$args should be rejected');
        result.fold(
          (failure) => expect(failure, isA<ValidationFailure>()),
          (_) => fail('should not have produced a result'),
        );
        expect(reader.calls, 0);
      });
    });

    test(
      'names the argument at fault, so the loop can say what it skipped',
      () {
        final failure = GetSpendingByCategoryTool.validate({
          'from': '2026-08-01',
          'to': 'later',
        });

        expect(failure, isNotNull);
        expect(failure!.field, 'to');
      },
    );

    test('accepts a single-day range', () async {
      // from == to is a real question ("what did I spend yesterday?"), and the
      // backwards-range check must not swallow it.
      final result = await tool.execute({
        'from': '2026-08-01',
        'to': '2026-08-01',
      });

      expect(result.isRight(), isTrue);
      expect(reader.calls, 1);
    });
  });
}
