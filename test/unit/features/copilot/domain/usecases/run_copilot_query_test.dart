import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/network/network_info.dart';
import 'package:moneyora/features/copilot/domain/entities/agent_tool.dart';
import 'package:moneyora/features/copilot/domain/entities/llm_step.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_call.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_exchange.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_result.dart';
import 'package:moneyora/features/copilot/domain/repositories/llm_repository.dart';
import 'package:moneyora/features/copilot/domain/usecases/run_copilot_query.dart';
import 'package:moneyora/features/copilot/domain/usecases/tools/copilot_tool.dart';

/// A model on a script.
///
/// The loop's whole job is deciding what to do with each turn a model takes,
/// so the model is replaced by a list of turns. That makes "asks for a tool,
/// then answers" a two-line fixture, and — more usefully — makes "asks for a
/// tool it invented, then answers" one too.
///
/// It also records what it was sent, which is where the history assertions
/// come from: the loop is only an agent if the model can see what the tools
/// returned.
class _ScriptedLlm implements LlmRepository {
  _ScriptedLlm(this.script);

  /// The turns, in order. The last one repeats if the loop keeps asking.
  final List<Either<Failure, LlmStep>> script;

  final List<String> questionsSeen = <String>[];
  final List<List<ToolExchange>> historySeen = <List<ToolExchange>>[];
  final List<List<AgentTool>> toolsSeen = <List<AgentTool>>[];

  int get turns => questionsSeen.length;

  @override
  Future<Either<Failure, LlmStep>> reason({
    required String question,
    required List<AgentTool> tools,
    required List<ToolExchange> history,
  }) async {
    questionsSeen.add(question);
    toolsSeen.add(tools);
    // Copied, because the loop keeps appending to the list it passed in and a
    // stored reference would show the final state at every turn.
    historySeen.add(List<ToolExchange>.of(history));

    final index = turns - 1;
    return script[index < script.length ? index : script.length - 1];
  }
}

/// A tool that answers with whatever it was given, and counts its calls.
class _FakeTool implements CopilotTool {
  _FakeTool(this.name, {this.failWith});

  final String name;
  final Failure? failWith;

  /// Stands in for any aggregate a real tool would return.
  static const Map<String, dynamic> aggregate = {'total_cents': 3420000};

  final List<Map<String, dynamic>> argsSeen = <Map<String, dynamic>>[];

  int get calls => argsSeen.length;

  @override
  AgentTool get descriptor =>
      AgentTool(name: name, description: 'a fake $name', parameters: const {});

  @override
  Future<Either<Failure, ToolResult>> execute(Map<String, dynamic> args) async {
    argsSeen.add(args);
    if (failWith case final failure?) return Left(failure);
    return Right(ToolResult(toolName: name, aggregate: aggregate));
  }
}

class _FakeNetwork implements NetworkInfo {
  bool connected = true;
  int checks = 0;

  @override
  Future<bool> get isConnected async {
    checks++;
    return connected;
  }
}

void main() {
  late _FakeNetwork network;
  late _FakeTool spending;

  const question = 'How much did I spend on food in August?';

  setUp(() {
    network = _FakeNetwork();
    spending = _FakeTool('get_spending_by_category');
  });

  RunCopilotQuery loopOver(
    List<Either<Failure, LlmStep>> script, {
    List<CopilotTool>? tools,
    int maxIterations = 5,
  }) => RunCopilotQuery(
    _ScriptedLlm(script),
    network,
    tools: tools ?? [spending],
    maxIterations: maxIterations,
  );

  // The same script the demo runs on: the model asks for one tool, reads the
  // result, and answers.
  List<Either<Failure, LlmStep>> askThenAnswer([
    String answer = 'You spent 34,200 on food in August.',
  ]) => [
    const Right(
      ToolCallsRequested([
        ToolCall(
          toolName: 'get_spending_by_category',
          args: {'from': '2026-08-01', 'to': '2026-08-31'},
        ),
      ]),
    ),
    Right(FinalAnswer(answer)),
  ];

  group('the single-tool path', () {
    test('runs the tool, then returns the answer the model gave', () async {
      final result = await loopOver(askThenAnswer()).call(question);

      expect(result.isRight(), isTrue);
      result.fold((f) => fail('unexpected failure: $f'), (answer) {
        expect(answer.text, 'You spent 34,200 on food in August.');
      });
      expect(spending.calls, 1);
    });

    test('runs the tool with the arguments the model asked for', () async {
      await loopOver(askThenAnswer()).call(question);

      expect(spending.argsSeen.single, {
        'from': '2026-08-01',
        'to': '2026-08-31',
      });
    });

    test('shows the user which tools it used', () async {
      // FR-COP-003. An answer about someone's own money is worth little if
      // they cannot see where the number came from.
      final result = await loopOver(askThenAnswer()).call(question);

      result.fold((f) => fail('unexpected failure: $f'), (answer) {
        expect(answer.trace.single.toolName, 'get_spending_by_category');
      });
    });

    test('trims the question before sending it', () async {
      final llm = _ScriptedLlm(askThenAnswer());
      await RunCopilotQuery(
        llm,
        network,
        tools: [spending],
      ).call('  $question  ');

      expect(llm.questionsSeen.first, question);
    });
  });

  group('what the model gets to see', () {
    test('the tool result, on the turn after it ran', () async {
      // This is the loop being a loop. Without the result going back, the
      // model is guessing and the tool call was theatre.
      final llm = _ScriptedLlm(askThenAnswer());
      await RunCopilotQuery(llm, network, tools: [spending]).call(question);

      expect(llm.historySeen.first, isEmpty);
      expect(llm.historySeen.last.single.result.aggregate, {
        'total_cents': 3420000,
      });
    });

    test('the same question on every turn', () async {
      final llm = _ScriptedLlm(askThenAnswer());
      await RunCopilotQuery(llm, network, tools: [spending]).call(question);

      expect(llm.questionsSeen, [question, question]);
    });

    test('every registered tool, by its own descriptor name', () async {
      // NFR-POR-007: a tool is registered, not wired in. The registry is keyed
      // off the descriptor so the name the model is told and the name the loop
      // looks up cannot drift apart.
      final income = _FakeTool('get_income_for_period');
      final llm = _ScriptedLlm([const Right(FinalAnswer('done'))]);

      await RunCopilotQuery(
        llm,
        network,
        tools: [spending, income],
      ).call(question);

      expect(llm.toolsSeen.single.map((t) => t.name), [
        'get_spending_by_category',
        'get_income_for_period',
      ]);
    });
  });

  group('several tools in one turn', () {
    test('runs them all, in the order asked, and traces each', () async {
      // FR-COP-031/032: the interesting questions need two or three reads
      // before there is anything to reason about.
      final income = _FakeTool('get_income_for_period');
      final result = await loopOver(
        [
          const Right(
            ToolCallsRequested([
              ToolCall(toolName: 'get_income_for_period', args: {}),
              ToolCall(toolName: 'get_spending_by_category', args: {}),
            ]),
          ),
          const Right(FinalAnswer('Yes, with 8,000 to spare.')),
        ],
        tools: [spending, income],
      ).call('Can I afford Rs. 50,000 this month?');

      expect(income.calls, 1);
      expect(spending.calls, 1);
      result.fold((f) => fail('unexpected failure: $f'), (answer) {
        expect(answer.trace.map((c) => c.toolName), [
          'get_income_for_period',
          'get_spending_by_category',
        ]);
      });
    });
  });

  group('offline (FR-COP-013/014)', () {
    test('says so, and never reaches the network', () async {
      network.connected = false;
      final llm = _ScriptedLlm(askThenAnswer());

      final result = await RunCopilotQuery(
        llm,
        network,
        tools: [spending],
      ).call(question);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<NetworkFailure>()),
        (_) => fail('should not have answered'),
      );
      expect(llm.turns, 0);
      expect(spending.calls, 0);
    });

    test('the message says the rest of the app still works', () async {
      // NFR-REL-004: the Copilot being unavailable must not read like the app
      // is broken. It is one optional feature behind a radio.
      network.connected = false;

      final result = await loopOver(askThenAnswer()).call(question);

      result.fold(
        (failure) => expect(failure.message.toLowerCase(), contains('offline')),
        (_) => fail('should not have answered'),
      );
    });

    test('an empty question is refused before the radio is touched', () async {
      final result = await loopOver(askThenAnswer()).call('   ');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ValidationFailure>()),
        (_) => fail('should not have answered'),
      );
      expect(network.checks, 0);
    });
  });

  group('when the model fails (FR-COP-015)', () {
    test('passes the failure through unchanged', () async {
      // The screen shows a different message for "you are offline" and "the
      // assistant is down". Flattening them here costs it that difference.
      final result = await loopOver([
        const Left(ServerFailure('the assistant is unavailable')),
      ]).call(question);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(
          failure,
          const ServerFailure('the assistant is unavailable'),
        ),
        (_) => fail('should not have answered'),
      );
    });

    test('stops asking after a failure', () async {
      final llm = _ScriptedLlm([const Left(ServerFailure('down'))]);

      await RunCopilotQuery(llm, network, tools: [spending]).call(question);

      expect(llm.turns, 1);
    });

    test(
      'a failure after a tool ran still fails, and runs nothing more',
      () async {
        final result = await loopOver([
          const Right(
            ToolCallsRequested([
              ToolCall(toolName: 'get_spending_by_category', args: {}),
            ]),
          ),
          const Left(ServerFailure('down')),
        ]).call(question);

        expect(result.isLeft(), isTrue);
        expect(spending.calls, 1);
      },
    );
  });

  group('bad tool calls (FR-COP-006)', () {
    test('a tool the model invented is skipped, not crashed on', () async {
      final result = await loopOver([
        const Right(
          ToolCallsRequested([ToolCall(toolName: 'get_horoscope', args: {})]),
        ),
        const Right(FinalAnswer('I can only look at your own figures.')),
      ]).call(question);

      expect(result.isRight(), isTrue);
      result.fold((f) => fail('unexpected failure: $f'), (answer) {
        expect(answer.trace, isEmpty, reason: 'nothing ran, so nothing traced');
      });
    });

    test(
      'the model is told the call was rejected, so it can correct',
      () async {
        // A rejection that vanishes silently leaves the model asking for the
        // same impossible thing until the turns run out — five round trips to
        // arrive at the same place. Telling it is what makes the loop recover.
        final llm = _ScriptedLlm([
          const Right(
            ToolCallsRequested([ToolCall(toolName: 'get_horoscope', args: {})]),
          ),
          const Right(FinalAnswer('I can only look at your own figures.')),
        ]);

        await RunCopilotQuery(llm, network, tools: [spending]).call(question);

        final feedback = llm.historySeen.last.single;
        expect(feedback.call.toolName, 'get_horoscope');
        expect(feedback.result.toolName, 'get_horoscope');
        expect(feedback.result.aggregate['error'], isNotNull);
      },
    );

    test(
      'a rejected argument is skipped, with its reason handed back',
      () async {
        final strict = _FakeTool(
          'get_spending_by_category',
          failWith: const ValidationFailure(
            'Expected from as a YYYY-MM-DD date.',
            field: 'from',
          ),
        );
        final llm = _ScriptedLlm([
          const Right(
            ToolCallsRequested([
              ToolCall(
                toolName: 'get_spending_by_category',
                args: {'from': 'August'},
              ),
            ]),
          ),
          const Right(FinalAnswer('Which month did you mean?')),
        ]);

        final result = await RunCopilotQuery(
          llm,
          network,
          tools: [strict],
        ).call(question);

        expect(result.isRight(), isTrue);
        result.fold(
          (f) => fail('unexpected failure: $f'),
          (answer) => expect(answer.trace, isEmpty),
        );
        expect(
          llm.historySeen.last.single.result.aggregate['error'],
          contains('YYYY-MM-DD'),
        );
      },
    );

    test('a database failure inside a tool does not end the query', () async {
      // One unreadable table should cost the answer that table, not the whole
      // conversation.
      final broken = _FakeTool(
        'get_spending_by_category',
        failWith: const CacheFailure('database is locked'),
      );

      final result = await loopOver(
        [
          const Right(
            ToolCallsRequested([
              ToolCall(toolName: 'get_spending_by_category', args: {}),
            ]),
          ),
          const Right(FinalAnswer('I could not read your spending just now.')),
        ],
        tools: [broken],
      ).call(question);

      expect(result.isRight(), isTrue);
    });

    test('the good calls in a turn still run when one is bad', () async {
      final income = _FakeTool('get_income_for_period');

      await loopOver(
        [
          const Right(
            ToolCallsRequested([
              ToolCall(toolName: 'get_horoscope', args: {}),
              ToolCall(toolName: 'get_income_for_period', args: {}),
            ]),
          ),
          const Right(FinalAnswer('done')),
        ],
        tools: [spending, income],
      ).call(question);

      expect(income.calls, 1);
    });
  });

  group('termination (FR-COP-005)', () {
    // A model that keeps asking for tools is the failure mode that hangs an
    // agent. The model chooses what to call; it never chooses how long to run.
    final neverAnswers = <Either<Failure, LlmStep>>[
      const Right(
        ToolCallsRequested([
          ToolCall(toolName: 'get_spending_by_category', args: {}),
        ]),
      ),
    ];

    test('gives up after the iteration cap, gracefully', () async {
      final result = await loopOver(
        neverAnswers,
        maxIterations: 3,
      ).call(question);

      expect(result.isRight(), isTrue);
      result.fold(
        (f) => fail('unexpected failure: $f'),
        (answer) => expect(answer.text, RunCopilotQuery.couldNotFinish),
      );
    });

    test('asks exactly as many times as it is allowed', () async {
      final llm = _ScriptedLlm(neverAnswers);

      await RunCopilotQuery(
        llm,
        network,
        tools: [spending],
        maxIterations: 3,
      ).call(question);

      expect(llm.turns, 3);
      expect(spending.calls, 3);
    });

    test('still shows what it looked at', () async {
      final result = await loopOver(
        neverAnswers,
        maxIterations: 2,
      ).call(question);

      result.fold(
        (f) => fail('unexpected failure: $f'),
        (answer) => expect(answer.trace.length, 2),
      );
    });

    test('defaults to five turns', () async {
      final llm = _ScriptedLlm(neverAnswers);

      await RunCopilotQuery(llm, network, tools: [spending]).call(question);

      expect(llm.turns, 5);
    });
  });

  test('answers without tools when the model needs none', () async {
    // "What can you help me with?" needs no data, and an empty trace is the
    // honest rendering of that.
    final result = await loopOver([
      const Right(FinalAnswer('Ask me about your spending.')),
    ]).call('what can you do?');

    result.fold((f) => fail('unexpected failure: $f'), (answer) {
      expect(answer.trace, isEmpty);
      expect(answer.text, 'Ask me about your spending.');
    });
    expect(spending.calls, 0);
  });
}
