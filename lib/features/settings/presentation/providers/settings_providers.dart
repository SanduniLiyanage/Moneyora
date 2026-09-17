/// Presentation state for the settings feature.
///
/// These talk to **use cases**, never to a repository or a datasource, which
/// is the rule `scripts/check_architecture.sh` enforces and the reason a
/// screen can be tested by overriding one provider.
library;

import 'dart:async';

import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../injection.dart';
import '../../domain/entities/user_settings.dart';

/// The user's preferences, kept live. SRS §3.8.
///
/// A `StreamProvider` because the app root draws the theme from it and the
/// settings screen writes to it, and neither should have to tell the other.
/// A failure beneath surfaces as the stream's error, so a consumer can show
/// the sentence rather than a default it has no reason to trust.
final settingsProvider = StreamProvider<UserSettings>((ref) {
  return Stream.fromFuture(ref.watch(watchSettingsProvider.future))
      .asyncExpand((watchSettings) => watchSettings(const NoParams()))
      // A `Left` goes down the error channel, as `accountsProvider` sends
      // it: `sink.addError` rather than `throw`, because a `Failure` is a
      // value, not an exception.
      .transform(
        StreamTransformer<
          Either<Failure, UserSettings>,
          UserSettings
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// The theme the app root draws in. FR-SET-001.
///
/// Follows the device until the stored choice is known, so the first frame
/// after launch is the one the system would have drawn anyway rather than a
/// flash of light before a dark preference loads. The mapping from the
/// domain's enum to Flutter's lives here, and only here.
final themeModeProvider = Provider<ThemeMode>((ref) {
  final settings = ref.watch(settingsProvider).asData?.value;
  return switch (settings?.theme) {
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
    AppThemeMode.system || null => ThemeMode.system,
  };
});

/// Choosing the theme. FR-SET-001.
class ThemeController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Stores [mode].
  ///
  /// Returns the failure rather than true/false, because the caller needs the
  /// sentence to show and not merely the fact that something went wrong.
  Future<Failure?> set(AppThemeMode mode) async {
    state = const AsyncValue<void>.loading();
    final setTheme = await ref.read(setThemeProvider.future);
    final result = await setTheme(mode);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return failure;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return null;
      },
    );
  }
}

/// Controller for the theme choice.
final themeControllerProvider =
    AutoDisposeAsyncNotifierProvider<ThemeController, void>(
      ThemeController.new,
    );

/// Recalculating every account balance from history. E-18.
///
/// The one Settings action that is a repair rather than a preference. It is
/// reached from here and from nowhere else on purpose: reconciliation reads
/// every transaction of every account, and the E-18 addendum keeps that scan
/// off the launch path so NFR-PER-001's cold start does not pay for a repair
/// nobody asked for.
class RecalculateBalancesController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Re-derives every balance.
  ///
  /// Returns the failure rather than true/false, because the caller needs the
  /// sentence to show and not merely the fact that something went wrong.
  Future<Failure?> run() async {
    state = const AsyncValue<void>.loading();
    final recompute = await ref.read(
      recomputeAllAccountBalancesProvider.future,
    );
    final result = await recompute(const NoParams());
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return failure;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return null;
      },
    );
  }
}

/// Controller for the recalculate-balances action.
final recalculateBalancesControllerProvider =
    AutoDisposeAsyncNotifierProvider<RecalculateBalancesController, void>(
      RecalculateBalancesController.new,
    );
