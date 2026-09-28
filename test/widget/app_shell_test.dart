@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/app.dart';
import 'package:moneyora/core/database/database_summary.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/ports/conversion_table.dart';
import 'package:moneyora/core/ports/monthly_spending_reader.dart';
import 'package:moneyora/core/ports/notification_taps.dart';
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/presentation/providers/account_providers.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_income_for_period.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_period_summary.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_calendar.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_trend.dart';
import 'package:moneyora/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:moneyora/features/copilot/data/datasources/secure_llm_api_key_store.dart';
import 'package:moneyora/features/money_plan/domain/usecases/check_budget_alerts.dart';
import 'package:moneyora/features/money_plan/domain/usecases/check_plan_history.dart';
import 'package:moneyora/features/money_plan/presentation/pages/active_plan_page.dart';
import 'package:moneyora/features/money_plan/presentation/providers/money_plan_providers.dart';
import 'package:moneyora/injection.dart';

import 'large_text.dart';

/// An empty answer for the home screen's three charts, for every shell test
/// below that does not care about any of them.
///
/// Without this, `getSpendingByCategoryProvider`, `getIncomeForPeriodProvider`,
/// `getSpendingTrendProvider` and `categoryReaderProvider` fall through to
/// `injection.dart`'s real ones, which open a real database — exactly what
/// `databaseSummaryProvider` is already overridden to avoid, for the reason
/// this file's own doc comment gives. `IncomeExpenseBars` (FR-RPT-004) and
/// `SpendingTrendLines` (FR-RPT-005) are the second and third charts the
/// router composes, so each needs its aggregate answered too or its card
/// spins for ever and `pumpAndSettle` never returns.
class _NoSpendingRepository implements AnalyticsRepository {
  @override
  Future<Either<Failure, List<DailyTotal>>> dailySpendingTotals(
    AnalyticsQuery query,
  ) async => const Right([]);

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async => const Right([]);

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) async =>
      const Right(0);
  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) async => const Right([]);
}

class _NoMonths implements MonthlySpendingReader {
  const _NoMonths();

  @override
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async => const Right([]);
}

class _NoCategoryReader implements CategoryReader {
  @override
  Stream<Either<Failure, List<CategoryOption>>> watchAll() =>
      Stream.value(const Right([]));
}

/// FR-RPT-003's picker reads this; an empty list still renders "All accounts".
class _NoAccountReader implements AccountReader {
  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() =>
      Stream.value(const Right([]));
}

/// Notifications the test taps by hand, and the one that launched the app.
class _ScriptedTaps implements NotificationTaps {
  _ScriptedTaps({this.launchedWith});

  final String? launchedWith;
  final StreamController<String> taps = StreamController.broadcast();

  Future<void> close() => taps.close();

  @override
  Future<String?> launchPayload() async => launchedWith;

  @override
  Stream<String> get opened => taps.stream;
}

/// Nothing launched the app and nothing is ever tapped.
class _NoTaps implements NotificationTaps {
  @override
  Future<String?> launchPayload() async => null;

  @override
  Stream<String> get opened => const Stream.empty();
}

final List<Override> _noChartDataOverrides = [
  // The app root asks the notification plugin what launched it (FR-SET-007),
  // over a platform channel that never answers in a widget test. Nothing
  // did, and nothing is tapped; the taps have their own group below.
  notificationTapsProvider.overrideWithValue(_NoTaps()),
  // The gate in front of every route (FR-SET-005) asks the platform keychain
  // whether a passcode is set, and a platform channel never answers in a
  // widget test. No passcode, so the gate stays open; the lock screen has
  // its own test.
  authLocalDataSourceProvider.overrideWith((ref) => InMemoryAuthDataSource()),
  // The saved-plan screen watches the active plan the same way; with no
  // plan it shows its empty state and settles.
  activePlanProvider.overrideWith((ref) => Stream.value(null)),
  // The plan list likewise: with no plans it shows its empty state.
  plansProvider.overrideWith((ref) => Stream.value(const [])),
  // The plan wizard asks how much history there is (E-39): none, as on a
  // new phone.
  checkPlanHistoryProvider.overrideWith(
    (ref) async => const CheckPlanHistory(_NoMonths()),
  ),
  getSpendingByCategoryProvider.overrideWith(
    (ref) async => GetSpendingByCategory(_NoSpendingRepository()),
  ),
  getIncomeForPeriodProvider.overrideWith(
    (ref) async => GetIncomeForPeriod(_NoSpendingRepository()),
  ),
  getSpendingTrendProvider.overrideWith(
    (ref) async => GetSpendingTrend(_NoSpendingRepository()),
  ),
  getSpendingCalendarProvider.overrideWith(
    (ref) async => GetSpendingCalendar(_NoSpendingRepository()),
  ),
  getPeriodSummaryProvider.overrideWith(
    (ref) async => GetPeriodSummary(_NoSpendingRepository()),
  ),
  categoryReaderProvider.overrideWith((ref) async => _NoCategoryReader()),
  accountReaderProvider.overrideWith((ref) async => _NoAccountReader()),
];

/// Widget tests for the app shell: theming, routing, and the three states the
/// home screen can be in.
///
/// [databaseSummaryProvider] is overridden rather than driven by a real
/// database. Widget tests run in a fake-async zone where genuine file I/O never
/// completes, so pumping a real `sqflite` open just hangs — and the database
/// already has 24 unit tests of its own. What is worth testing here is the
/// thing those cannot reach: that each `AsyncValue` state renders something
/// sensible.
///
/// The one claim neither layer can make is that it works on a phone. That is
/// what the screen itself is for.
void main() {
  const ready = DatabaseSummary(
    schemaVersion: 1,
    accounts: 1,
    categories: 18,
    transactions: 0,
  );

  Widget bootApp(Override summaryOverride) => ProviderScope(
    overrides: [summaryOverride, ..._noChartDataOverrides],
    child: const MoneyoraApp(),
  );

  /// The whole app, with one account behind the accounts panel.
  ///
  /// The panel reads accounts through a use case that would open a real
  /// database, which never completes in a widget test's fake-async zone.
  Widget bootWithAccounts() => ProviderScope(
    overrides: [
      databaseSummaryProvider.overrideWith((ref) => ready),
      ..._noChartDataOverrides,
      // The panel converts through the settings feature's table
      // (FR-ACC-005), which would otherwise wait on the same database.
      conversionTableProvider.overrideWith(
        (ref) => Stream.value(const ConversionTable(baseCurrency: 'LKR')),
      ),
      accountsProvider(false).overrideWith(
        (ref) => Stream.value([
          Account(
            id: 1,
            name: 'Cash',
            icon: 'wallet',
            initialBalanceDate: DateTime(2026),
            currentBalanceCents: 125000,
          ),
        ]),
      ),
    ],
    child: const MoneyoraApp(),
  );

  group('a tapped budget alert opens the plan it is about. FR-SET-007', () {
    Widget bootWithTaps(_ScriptedTaps taps) => ProviderScope(
      overrides: [
        databaseSummaryProvider.overrideWith((ref) => ready),
        ..._noChartDataOverrides,
        // Later overrides of the same provider win: this one replaces the
        // silent default above.
        notificationTapsProvider.overrideWithValue(taps),
      ],
      child: const MoneyoraApp(),
    );

    testWidgets('tapped while the app is open', (tester) async {
      final taps = _ScriptedTaps();
      addTearDown(taps.close);
      await tester.pumpWidget(bootWithTaps(taps));
      await tester.pumpAndSettle();
      expect(find.byType(ActivePlanPage), findsNothing);

      taps.taps.add(CheckBudgetAlerts.payload);
      await tester.pumpAndSettle();

      expect(find.byType(ActivePlanPage), findsOneWidget);
    });

    testWidgets('tapped to launch the app from cold', (tester) async {
      final taps = _ScriptedTaps(launchedWith: CheckBudgetAlerts.payload);
      addTearDown(taps.close);

      await tester.pumpWidget(bootWithTaps(taps));
      await tester.pumpAndSettle();

      expect(find.byType(ActivePlanPage), findsOneWidget);
    });

    testWidgets('a payload the app does not know opens nothing', (
      tester,
    ) async {
      final taps = _ScriptedTaps();
      addTearDown(taps.close);
      await tester.pumpWidget(bootWithTaps(taps));
      await tester.pumpAndSettle();

      taps.taps.add('something-else');
      await tester.pumpAndSettle();

      expect(find.byType(ActivePlanPage), findsNothing);
    });
  });

  group('home screen states', () {
    testWidgets('shows a spinner while the database opens', (tester) async {
      // A Completer that is never completed holds the provider in its loading
      // state for as long as the test wants to look at it.
      final held = Completer<DatabaseSummary>();
      addTearDown(() => held.complete(ready));

      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => held.future)),
      );
      // pump, not pumpAndSettle: a spinner animates forever and would never
      // settle.
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('once it opens: shortcuts first, and Add', (tester) async {
      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => ready)),
      );
      await tester.pumpAndSettle();

      // Every part of the app, above the charts, without scrolling.
      for (final label in [
        'Transactions',
        'Scan Receipt',
        'Your plan',
        'Create Money Plan',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.widgetWithText(FloatingActionButton, 'Add'), findsOneWidget);
      // The database's figures are Settings' now, not the home screen's.
      expect(find.text('Database ready'), findsNothing);
      expect(find.text('Coming next'), findsNothing);
    });

    testWidgets('Settings › About says what is in the database', (
      tester,
    ) async {
      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => ready)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Database'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // 15 expense + 3 income, per FR-EXP-003 and FR-INC-002.
      expect(
        find.text('Version 1 · 1 account · 18 categories · 0 transactions'),
        findsOneWidget,
      );
    });

    testWidgets('explains itself when the database cannot be opened', (
      tester,
    ) async {
      // The realistic causes — a keychain entry that vanished, a migration
      // that failed — are indistinguishable from "the app is broken" unless
      // the screen says otherwise.
      await tester.pumpWidget(
        bootApp(
          databaseSummaryProvider.overrideWith(
            (ref) => Future<DatabaseSummary>.error(
              StateError('keychain unavailable'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not open the database'), findsOneWidget);
      expect(find.textContaining('keychain unavailable'), findsOneWidget);
    });
  });

  testWidgets('home holds at the largest font on a 320dp phone. SRS §4.1', (
    tester,
  ) async {
    useLargeTextOnSmallPhone(tester);
    await tester.pumpWidget(
      bootApp(databaseSummaryProvider.overrideWith((ref) => ready)),
    );
    await tester.pumpAndSettle();

    await scrollToEnd(tester);
  });

  group('shell', () {
    Future<void> pumpReady(WidgetTester tester) async {
      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => ready)),
      );
      await tester.pumpAndSettle();
    }

    /// The shortcuts sit at the top of home, above the charts; scrolled to
    /// all the same, so a card added above them fails here rather than
    /// hiding a tile below the 800×600 fold.
    Future<void> tapShortcut(WidgetTester tester, String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
    }

    testWidgets('applies the Moneyora theme rather than Flutter defaults', (
      tester,
    ) async {
      await pumpReady(tester);

      final context = tester.element(find.text('Moneyora'));
      final theme = Theme.of(context);

      expect(
        theme.extension<AppColors>(),
        isNotNull,
        reason: 'without AppColors every screen reading it crashes',
      );
      expect(theme.useMaterial3, isTrue);
    });

    testWidgets('reaches the receipt scanner from the home screen', (
      tester,
    ) async {
      // FR-RCP-001: "Scan Receipt" from the main screen. The screen only
      // asks the device for a photo on a tap, so opening it touches no
      // platform channel.
      await pumpReady(tester);
      await tapShortcut(tester, 'Scan Receipt');

      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });

    testWidgets('reaches the money plan wizard from the home screen', (
      tester,
    ) async {
      // FR-PLN-001: "Create Money Plan" from the main navigation.
      await pumpReady(tester);
      await tapShortcut(tester, 'Create Money Plan');

      expect(find.text('Plan for'), findsOneWidget);
      // A new phone has no history to suggest from, so the way on is a
      // plan the user builds (E-39).
      expect(find.text('Build it yourself'), findsOneWidget);
    });

    testWidgets('Add on home opens the entry screen, and back returns', (
      tester,
    ) async {
      // SCR-001's FAB: recording an expense is the thing done most often,
      // so it is one tap from home rather than two.
      await pumpReady(tester);

      await tester.tap(find.widgetWithText(FloatingActionButton, 'Add'));
      await tester.pumpAndSettle();
      expect(find.text('New expense'), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Transactions'), findsOneWidget);
    });

    testWidgets('Transactions opens with the balance for the chosen period', (
      tester,
    ) async {
      // FR-RPT-006: the list and the home screen report one period and one
      // account, and each says what it left over.
      await pumpReady(tester);
      await tester.tap(find.text('Transactions'));
      // Not pumpAndSettle: the list's own rows come from a database this
      // test does not fake, and their spinner never settles. The balance
      // reads the analytics fakes, which answer at once.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Balance'), findsOneWidget);
      expect(find.textContaining('· All accounts'), findsOneWidget);
    });

    testWidgets('reaches Settings from the app bar', (tester) async {
      await pumpReady(tester);

      await tester.tap(find.byIcon(Icons.settings_outlined));
      await tester.pumpAndSettle();

      // The real screen, not the placeholder it replaced: the settings route
      // was the router's last one without a page behind it. The first row,
      // because the list is taller than the test viewport and builds lazily.
      expect(find.text('Theme'), findsOneWidget);
    });

    testWidgets('every screen opened from home can be left again', (
      tester,
    ) async {
      // `context.go` replaces the location instead of stacking on it, which
      // leaves a screen with no back arrow and a device back button that
      // exits the app. Every destination is checked, because the mistake is
      // per-call-site and one corrected navigation says nothing about the
      // next.
      for (final destination in const [
        'Ask Moneyora',
        'Create Money Plan',
        'Your plan',
        'Saved plans',
        'Scan Receipt',
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              databaseSummaryProvider.overrideWith((ref) => ready),
              ..._noChartDataOverrides,
              // The Copilot screen asks the platform keychain whether a key
              // exists, and a platform channel never answers in a widget test.
              llmApiKeyStoreProvider.overrideWithValue(
                InMemoryLlmApiKeyStore(),
              ),
            ],
            child: const MoneyoraApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tapShortcut(tester, destination);

        expect(
          find.byType(BackButton),
          findsOneWidget,
          reason: '$destination opened with no way back',
        );

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(
          find.widgetWithText(FloatingActionButton, 'Add'),
          findsOneWidget,
        );
      }
    });

    testWidgets('the accounts panel opens from the home screen', (
      tester,
    ) async {
      // FR-ACC-003 asks for the accounts to be reachable "from the main
      // screen". The panel belongs to the accounts feature and the home
      // screen must not import it, so `app_router.dart` composes the two —
      // which means this wiring is only ever exercised through the real
      // router, as it is here.
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();

      expect(find.text('Total balance'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Rs1,250.00'), findsNWidgets(2));
    });

    testWidgets('the panel opens an empty form for a new account', (
      tester,
    ) async {
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();

      expect(find.text('New account'), findsOneWidget);
    });

    testWidgets('tapping an account opens it for editing', (tester) async {
      // The account travels as go_router's `extra`, which is untyped. This is
      // the only test that exercises that cast with a real Account in it.
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Open navigation menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      expect(find.text('Edit account'), findsOneWidget);
      // Filled in, rather than a blank form that would silently create a
      // second account on save.
      expect(find.widgetWithText(TextField, 'Cash'), findsOneWidget);
    });
  });
}
