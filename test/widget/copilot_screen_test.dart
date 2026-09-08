@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/network/network_info.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/copilot/data/datasources/secure_llm_api_key_store.dart';
import 'package:moneyora/features/copilot/domain/entities/agent_tool.dart';
import 'package:moneyora/features/copilot/domain/entities/llm_step.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_call.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_exchange.dart';
import 'package:moneyora/features/copilot/domain/entities/tool_result.dart';
import 'package:moneyora/features/copilot/domain/repositories/llm_repository.dart';
import 'package:moneyora/features/copilot/domain/usecases/run_copilot_query.dart';
import 'package:moneyora/features/copilot/domain/usecases/tools/copilot_tool.dart';
import 'package:moneyora/features/copilot/presentation/pages/copilot_page.dart';
import 'package:moneyora/injection.dart';

/// The Copilot screen, over a scripted model and no network at all.
///
/// The screen is where the feature's promises become visible: that a question
/// in flight shows as one, that the tools used are named in plain language,
/// that being offline reads as a temporary limit on one feature rather than as
/// a broken app, and that nothing can be asked before a key exists.
class _ScriptedLlm implements LlmRepository {
  _ScriptedLlm(this.steps, {this.gate});

  final List<Either<Failure, LlmStep>> steps;

  /// Held open to keep a question in flight for as long as a test wants to
  /// look at the loading state. Without it the scripted reply resolves inside
  /// the same frame and the state is never observably loading.
  final Completer<void>? gate;

  int _turn = 0;

  @override
  Future<Either<Failure, LlmStep>> reason({
    required String question,
    required List<AgentTool> tools,
    required List<ToolExchange> history,
  }) async {
    if (gate != null) await gate!.future;
    final step = steps[_turn.clamp(0, steps.length - 1)];
    _turn++;
    return step;
  }
}

class _StubTool implements CopilotTool {
  @override
  AgentTool get descriptor => const AgentTool(
    name: 'get_spending_by_category',
    description: 'totals per category',
    parameters: {'type': 'object'},
  );

  @override
  Future<Either<Failure, ToolResult>> execute(
    Map<String, dynamic> args,
  ) async => const Right(
    ToolResult(
      toolName: 'get_spending_by_category',
      aggregate: {
        'totals_cents': {'Food': 3420000},
      },
    ),
  );
}

class _FakeNetwork implements NetworkInfo {
  _FakeNetwork({required this.connected});

  final bool connected;

  @override
  Future<bool> get isConnected async => connected;
}

void main() {
  const askedForFood = [
    Right<Failure, LlmStep>(
      ToolCallsRequested([
        ToolCall(
          toolName: 'get_spending_by_category',
          args: {'from': '2026-08-01', 'to': '2026-08-31'},
        ),
      ]),
    ),
    Right<Failure, LlmStep>(
      FinalAnswer('You spent Rs. 34,200 on food in August.'),
    ),
  ];

  Widget boot({
    List<Either<Failure, LlmStep>> script = askedForFood,
    bool online = true,
    String? apiKey = 'test-key',
    Completer<void>? hold,
  }) => ProviderScope(
    overrides: [
      llmApiKeyStoreProvider.overrideWithValue(InMemoryLlmApiKeyStore(apiKey)),
      networkInfoProvider.overrideWithValue(_FakeNetwork(connected: online)),
      copilotToolsProvider.overrideWith((ref) async => [_StubTool()]),
      runCopilotQueryProvider.overrideWith(
        (ref) async => RunCopilotQuery(
          _ScriptedLlm(script, gate: hold),
          _FakeNetwork(connected: online),
          tools: [_StubTool()],
        ),
      ),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const CopilotPage()),
  );

  Future<void> askSomething(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), 'what did I spend on food?');
    await tester.tap(find.text('Ask'));
  }

  group('before a key exists', () {
    testWidgets('asks for one instead of offering a question box', (
      tester,
    ) async {
      await tester.pumpWidget(boot(apiKey: null));
      await tester.pumpAndSettle();

      expect(find.text('Connect the assistant'), findsOneWidget);
      expect(find.text('Ask'), findsNothing);
    });

    testWidgets('says the rest of the app is unaffected', (tester) async {
      // NFR-REL-004. A missing key disables one feature, and the screen must
      // not imply anything more than that.
      await tester.pumpWidget(boot(apiKey: null));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('every other part of Moneyora'),
        findsOneWidget,
      );
    });

    testWidgets('hides the key as it is typed', (tester) async {
      // It is a credential. A key read off a shoulder is a key to replace.
      await tester.pumpWidget(boot(apiKey: null));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, isTrue);
    });

    testWidgets('a saved key opens the question box', (tester) async {
      await tester.pumpWidget(boot(apiKey: null));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'a-new-key');
      await tester.tap(find.text('Save key'));
      await tester.pumpAndSettle();

      expect(find.text('Ask'), findsOneWidget);
      expect(find.text('Connect the assistant'), findsNothing);
    });
  });

  group('asking', () {
    testWidgets('offers examples before the first question', (tester) async {
      // An empty box tells a person nothing about what this can do.
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      expect(find.text('Try asking'), findsOneWidget);
      expect(find.textContaining('spend on food in August'), findsWidgets);
    });

    testWidgets('shows that it is working, and blocks a second ask', (
      tester,
    ) async {
      // FR-COP-002. A second request while one is in flight spends another
      // round trip to overwrite the first.
      final held = Completer<void>();
      addTearDown(() {
        if (!held.isCompleted) held.complete();
      });

      await tester.pumpWidget(boot(hold: held));
      await tester.pumpAndSettle();

      await askSomething(tester);
      await tester.pump();

      expect(find.text('Thinking…'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('shows the answer', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await askSomething(tester);
      await tester.pumpAndSettle();

      expect(
        find.text('You spent Rs. 34,200 on food in August.'),
        findsOneWidget,
      );
    });

    testWidgets('names the tools it used, in plain language', (tester) async {
      // FR-COP-003. The model sees `get_spending_by_category`; the user should
      // see something they can check the answer against.
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await askSomething(tester);
      await tester.pumpAndSettle();

      expect(find.text('I looked at'), findsOneWidget);
      expect(find.text('your spending by category'), findsOneWidget);
      expect(find.textContaining('get_spending_by_category'), findsNothing);
    });
  });

  group('when it cannot answer', () {
    testWidgets('offline reads as a limit, not a fault', (tester) async {
      // FR-COP-014.
      await tester.pumpWidget(boot(online: false));
      await tester.pumpAndSettle();

      await askSomething(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('needs a connection'), findsOneWidget);
      expect(
        find.textContaining('Everything else in Moneyora works'),
        findsOneWidget,
      );
    });

    testWidgets('a spent quota says to come back later', (tester) async {
      // FR-COP-015. Retrying now cannot work, so the message must not suggest
      // it.
      await tester.pumpWidget(
        boot(
          script: const [
            Left<Failure, LlmStep>(
              QuotaFailure('The assistant has used up its quota for now.'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await askSomething(tester);
      await tester.pumpAndSettle();

      expect(find.textContaining('quota'), findsOneWidget);
    });

    testWidgets('a blank question does nothing at all', (tester) async {
      await tester.pumpWidget(boot());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ask'));
      await tester.pumpAndSettle();

      // Still the resting state: no spinner, no error, no wasted request.
      expect(find.text('Try asking'), findsOneWidget);
    });
  });
}
