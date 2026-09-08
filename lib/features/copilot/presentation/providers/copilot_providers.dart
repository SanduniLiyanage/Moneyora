import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../injection.dart';
import '../../domain/entities/copilot_answer.dart';

/// Whether an API key has been stored yet.
///
/// The screen's first branch: with no key there is nothing to ask, and the
/// honest thing to show is how to add one rather than a question box that
/// fails on submit.
final copilotHasKeyProvider = FutureProvider<bool>((ref) async {
  final key = await ref.watch(llmApiKeyStoreProvider).read();
  return key != null && key.isNotEmpty;
});

/// Holds the current answer, and the states on the way to it.
///
/// `null` is the resting state — nothing asked yet — which is different from
/// an empty answer and is rendered differently.
class CopilotNotifier extends AsyncNotifier<CopilotAnswer?> {
  @override
  FutureOr<CopilotAnswer?> build() => null;

  /// Runs [question] through the agent loop.
  ///
  /// The failure lands in [AsyncError] rather than being thrown, so the screen
  /// renders it as a message. Nothing above `data/` catches anything.
  ///
  /// An empty question is *not* filtered out here. The use case rejects it with
  /// a [ValidationFailure] that says so, and a button that answers a tap by
  /// doing nothing at all is indistinguishable from one that is broken.
  Future<void> ask(String question) async {
    state = const AsyncLoading();
    final runQuery = await ref.read(runCopilotQueryProvider.future);
    final result = await runQuery(question);

    state = result.match(
      (failure) => AsyncError(failure, StackTrace.current),
      AsyncData.new,
    );
  }

  /// Returns to the resting state, discarding the current answer.
  void clear() => state = const AsyncData(null);
}

/// The Copilot screen's state.
final copilotProvider = AsyncNotifierProvider<CopilotNotifier, CopilotAnswer?>(
  CopilotNotifier.new,
);

/// Saves an API key and re-reads whether one is present.
///
/// A use case would be one line long and would own no rule, so this stays in
/// the provider layer: writing a key is a settings action, not business logic.
/// It takes a [WidgetRef] because the only caller is the screen that collects
/// the key.
Future<void> saveCopilotApiKey(WidgetRef ref, String key) async {
  await ref.read(llmApiKeyStoreProvider).write(key);
  ref.invalidate(copilotHasKeyProvider);
}

/// A message a person can act on, for anything the screen is handed.
///
/// [Failure]s already carry a written message; anything else reaching here is
/// a bug, and says so without putting a stack trace on screen.
String copilotErrorMessage(Object error) => switch (error) {
  Failure(:final message) => message,
  _ => 'Something went wrong. Please try again.',
};
