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
import '../../domain/entities/exchange_rate.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/usecases/remove_exchange_rate.dart';

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

/// Choosing the base currency. FR-SET-003.
class BaseCurrencyController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Stores [code]. Returns the failure, for its sentence.
  Future<Failure?> set(String code) async {
    state = const AsyncValue<void>.loading();
    final setBaseCurrency = await ref.read(setBaseCurrencyProvider.future);
    return _settle(await setBaseCurrency(code));
  }

  Failure? _settle(Either<Failure, Unit> result) => result.match(
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

/// Controller for the base-currency choice.
final baseCurrencyControllerProvider =
    AutoDisposeAsyncNotifierProvider<BaseCurrencyController, void>(
      BaseCurrencyController.new,
    );

/// The three calendar settings. FR-SET-004, FR-SET-012.
///
/// One controller because they are one section and one `users` row, and
/// each write is a use case with its own refusal, shown never swallowed.
class CalendarController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Stores the day a week starts on: [DateTime.sunday] or [DateTime.monday].
  Future<Failure?> setFirstDayOfWeek(int weekday) async {
    state = const AsyncValue<void>.loading();
    final set = await ref.read(setFirstDayOfWeekProvider.future);
    return _settle(await set(weekday));
  }

  /// Stores the day a month starts on, 1–28.
  Future<Failure?> setFirstDayOfMonth(int day) async {
    state = const AsyncValue<void>.loading();
    final set = await ref.read(setFirstDayOfMonthProvider.future);
    return _settle(await set(day));
  }

  /// Stores how many months the Money Plan learns from, 1–24.
  Future<Failure?> setPlanAnalysisMonths(int months) async {
    state = const AsyncValue<void>.loading();
    final set = await ref.read(setPlanAnalysisMonthsProvider.future);
    return _settle(await set(months));
  }

  Failure? _settle(Either<Failure, Unit> result) => result.match(
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

/// Controller for the calendar section.
final calendarControllerProvider =
    AutoDisposeAsyncNotifierProvider<CalendarController, void>(
      CalendarController.new,
    );

/// Every stored exchange rate, kept live. FR-SET-003.
final exchangeRatesProvider = StreamProvider<List<ExchangeRate>>((ref) {
  return Stream.fromFuture(ref.watch(watchExchangeRatesProvider.future))
      .asyncExpand((watchRates) => watchRates(const NoParams()))
      .transform(
        StreamTransformer<
          Either<Failure, List<ExchangeRate>>,
          List<ExchangeRate>
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// Storing and forgetting exchange rates. FR-SET-003, E-34.
///
/// Both refusals are the use case's — a code that is not three letters, a
/// currency against itself, a rate of nothing — and are shown, never
/// swallowed.
class ExchangeRateController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Stores [rate], replacing any held for the same pair.
  Future<Failure?> set(ExchangeRate rate) async {
    state = const AsyncValue<void>.loading();
    final setRate = await ref.read(setExchangeRateProvider.future);
    return _settle(await setRate(rate));
  }

  /// Forgets the rate for [pair].
  Future<Failure?> remove(CurrencyPair pair) async {
    state = const AsyncValue<void>.loading();
    final removeRate = await ref.read(removeExchangeRateProvider.future);
    return _settle(await removeRate(pair));
  }

  Failure? _settle(Either<Failure, Unit> result) => result.match(
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

/// Controller for the rate edits.
final exchangeRateControllerProvider =
    AutoDisposeAsyncNotifierProvider<ExchangeRateController, void>(
      ExchangeRateController.new,
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
