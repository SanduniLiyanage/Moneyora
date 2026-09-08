import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/network/network_info.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/agent_tool.dart';
import '../entities/copilot_answer.dart';
import '../entities/llm_step.dart';
import '../entities/tool_call.dart';
import '../entities/tool_exchange.dart';
import '../entities/tool_result.dart';
import '../repositories/llm_repository.dart';
import 'tools/copilot_tool.dart';

/// The agent loop: ask the model what it needs, run it on-device, repeat.
///
/// This is the whole difference between an agent and a chatbot. A chatbot
/// answers from what it was told. This asks the model what it needs to know,
/// executes that against the encrypted database on this phone, hands back the
/// aggregate, and asks again — until the model has enough to answer.
///
/// ```
/// question ─▶ model ─▶ "call get_spending_by_category(August)"
///                 ▲                    │
///                 └── {Food: 34,200} ◀─┘   (on-device, never leaves)
///                     ⋯ until the model answers
/// ```
///
/// ## What this use case guarantees
///
/// * It never runs without a connection, and says so plainly (FR-COP-013/014).
/// * It always terminates. The model decides *what* to call, never *how many
///   times* — [maxIterations] does (FR-COP-005).
/// * A tool call it cannot honour is skipped, never crashed on (FR-COP-006).
/// * Only aggregates go outward; every tool runs here (FR-COP-010, FR-COP-022).
///
/// Refs: FR-COP-004, FR-COP-005, FR-COP-006, FR-COP-013, FR-COP-014.
class RunCopilotQuery implements UseCase<CopilotAnswer, String> {
  /// Creates the loop over a model, a set of [tools], and a connectivity check.
  ///
  /// Tools arrive as a list and are indexed by their own descriptor name, so
  /// the key the model is told and the key the loop looks up cannot drift
  /// apart. Adding a tool is one entry in `injection.dart` and no change here
  /// (NFR-POR-007).
  RunCopilotQuery(
    this._llm,
    this._network, {
    required List<CopilotTool> tools,
    this.maxIterations = 5,
  }) : assert(maxIterations > 0, 'the loop must be allowed at least one turn'),
       _tools = {for (final tool in tools) tool.descriptor.name: tool};

  final LlmRepository _llm;
  final Map<String, CopilotTool> _tools;
  final NetworkInfo _network;

  /// How many times the model may be asked before the loop gives up.
  ///
  /// Five is enough for the deepest question the SRS asks for — affordability
  /// needs income, spending, and the goal, then an answer (FR-COP-032) — and
  /// small enough that a model stuck in a rut costs seconds, not minutes.
  final int maxIterations;

  /// The message returned when the model never settles on an answer.
  ///
  /// Said as something the user can act on rather than an apology: FR-COP-005
  /// allows a best-effort answer or a graceful failure, and a graceful failure
  /// that suggests the next move is worth more than a half-derived number.
  static const String couldNotFinish =
      'I could not work that one out. Try asking about one thing at a time — '
      'a single category, or a single month.';

  @override
  Future<Either<Failure, CopilotAnswer>> call(String params) async {
    final question = params.trim();
    if (question.isEmpty) {
      return const Left(ValidationFailure('Ask a question first.'));
    }

    // FR-COP-013. Checked before the request rather than after it fails, so
    // being offline reads as the ordinary state it is and not as an error.
    if (!await _network.isConnected) {
      // Says what is unavailable and no more. The screen adds the reassurance
      // that the rest of the app still works; saying it in both places puts
      // the same sentence on screen twice.
      return const Left(
        NetworkFailure('The Copilot needs a connection, so it is offline too.'),
      );
    }

    final schemas = _tools.values
        .map((tool) => tool.descriptor)
        .toList(growable: false);
    final history = <ToolExchange>[];
    final trace = <ToolCall>[];

    for (var turn = 0; turn < maxIterations; turn++) {
      final step = await _llm.reason(
        question: question,
        tools: schemas,
        history: history,
      );

      final failure = step.getLeft().toNullable();
      // FR-COP-015: a transport or provider failure is the caller's to show,
      // unchanged. Rewriting it here would cost the screen the difference
      // between "you are offline" and "the assistant is down".
      if (failure != null) return Left(failure);

      final current = step.getRight().toNullable()!;
      switch (current) {
        case FinalAnswer(:final text):
          return Right(CopilotAnswer(text: text, trace: trace));

        case ToolCallsRequested(:final calls):
          for (final call in calls) {
            final (result, ran) = await _run(call);
            history.add(ToolExchange(call: call, result: result));
            // Only what actually ran is shown to the user. A trace that listed
            // attempts would say the agent consulted something it never read.
            if (ran) trace.add(call);
          }
      }
    }

    // FR-COP-005. The trace still goes back: it shows what was looked at, even
    // though nothing was concluded from it.
    return Right(CopilotAnswer(text: couldNotFinish, trace: trace));
  }

  /// Runs one requested [call], and says whether it actually produced data.
  ///
  /// A rejected call still returns a result, because the alternative is worse:
  /// a model whose request vanishes silently asks for the same thing again and
  /// again, spending every remaining turn on a round trip that cannot work.
  /// Telling it the call was rejected is what lets it correct itself — the
  /// difference between a loop that recovers and one that runs out of turns.
  ///
  /// The rejection carries the tool name and the reason, both of which the
  /// model itself produced. No financial data is in either (FR-COP-010).
  Future<(ToolResult, bool)> _run(ToolCall call) async {
    final tool = _tools[call.toolName];
    if (tool == null) {
      // The model invented a tool. It happens, and it is recoverable.
      return (
        ToolResult(
          toolName: call.toolName,
          aggregate: const {
            'error':
                'No such tool. Use one of the tools you were given, exactly '
                'as it is named.',
          },
        ),
        false,
      );
    }

    final outcome = await tool.execute(call.args);
    return outcome.match(
      (failure) => (
        ToolResult(
          toolName: call.toolName,
          aggregate: {'error': failure.message},
        ),
        false,
      ),
      (result) => (result, true),
    );
  }

  /// The tools this loop can run, by name. For wiring checks and the UI.
  List<AgentTool> get registeredTools =>
      _tools.values.map((tool) => tool.descriptor).toList(growable: false);
}
