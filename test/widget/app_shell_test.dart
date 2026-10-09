@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:moneyora/app.dart';
import 'package:moneyora/core/database/database_summary.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/ports/conversion_table.dart';
import 'package:moneyora/core/ports/monthly_spending_reader.dart';
import 'package:moneyora/core/ports/notification_taps.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/presentation/providers/account_providers.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/transfer_totals.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_income_for_period.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_period_summary.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_calendar.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_trend.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
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
  Future<Either<Failure, TransferTotals>> transfersForPeriod(
    AnalyticsQuery query,
  ) async => const Right(TransferTotals.none);

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

/// Cash, then Bank, for the entry screen's default account.
class _TwoAccounts implements AccountReader {
  const _TwoAccounts();

  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() => Stream.value(
    const Right([
      AccountOption(id: 1, name: 'Cash', balanceCents: 0),
      AccountOption(id: 2, name: 'Bank', balanceCents: 0),
    ]),
  );
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

  /// Opens the menu at the top right of home, then [label] in it.
  ///
  /// Scrolled to all the same, so an item added above it fails here rather
  /// than hiding the rest below the 800×600 fold.
  Future<void> tapInMenu(WidgetTester tester, String label) async {
    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    final menu = find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text(label),
      100,
      scrollable: menu.first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

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

    testWidgets('once it opens: the ring, the balance, − and +', (
      tester,
    ) async {
      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => ready)),
      );
      await tester.pumpAndSettle();

      // One screen, the owner's call on 2026-10-06: the tiles
      // went to the menu, the other charts to Reports.
      expect(find.text('Scan receipt'), findsNothing);
      expect(find.text('Budget plans'), findsNothing);
      expect(find.text('Income vs expenses'), findsNothing);
      expect(find.byTooltip('Period and account'), findsOneWidget);
      expect(find.byTooltip('Transfer'), findsOneWidget);
      expect(find.byTooltip('Menu'), findsOneWidget);
      expect(find.byTooltip('Previous period'), findsOneWidget);
      expect(find.text('Balance'), findsOneWidget);
      expect(find.byTooltip('New expense'), findsOneWidget);
      expect(find.byTooltip('New income'), findsOneWidget);
      expect(find.byType(FloatingActionButton), findsNothing);
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
      await tapInMenu(tester, 'Settings');

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

    // Roomy enough for the ring above everything, or scrolled to the end
    // when the largest font leaves it too little.
    if (find.byType(Scrollable).evaluate().isNotEmpty) {
      await scrollToEnd(tester);
    }
    expect(find.byTooltip('New income').hitTestable(), findsOneWidget);
  });

  testWidgets('both panels hold at the largest font on a 320dp phone', (
    tester,
  ) async {
    useLargeTextOnSmallPhone(tester);
    await tester.pumpWidget(bootWithAccounts());
    await tester.pumpAndSettle();

    // Each panel scrolled to its last row, so every row is laid out once
    // at 2x text in 304dp; an overflow throws.
    Future<void> scrollPanelTo(String label) async {
      await tester.scrollUntilVisible(
        find.text(label),
        100,
        scrollable: find
            .descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.pumpAndSettle();
    }

    await tester.tap(find.byTooltip('Period and account'));
    await tester.pumpAndSettle();
    await scrollPanelTo('Choose date');
    // The scrim, in the 16dp the panel leaves of a 320dp screen.
    await tester.tapAt(const Offset(316, 300));
    await tester.pumpAndSettle();

    await tapInMenu(tester, 'Accounts');
    await scrollPanelTo('Show archived');
    await scrollPanelTo('Settings');
    expect(find.text('Settings'), findsOneWidget);
  });

  group('shell', () {
    Future<void> pumpReady(WidgetTester tester) async {
      await tester.pumpWidget(
        bootApp(databaseSummaryProvider.overrideWith((ref) => ready)),
      );
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
      // FR-RCP-001: "Scan Receipt" from the main screen, in its menu. The
      // screen only asks the device for a photo on a tap, so opening it
      // touches no platform channel.
      await pumpReady(tester);
      await tapInMenu(tester, 'Scan receipt');

      expect(find.text('Take a photo'), findsOneWidget);
      expect(find.text('Choose from gallery'), findsOneWidget);
    });

    testWidgets('reaches the money plan wizard from the home screen', (
      tester,
    ) async {
      // FR-PLN-001: "Create Money Plan" from the main navigation, through
      // Budget plans since 1.0.0's testers found three plan tiles too many.
      await pumpReady(tester);
      await tapInMenu(tester, 'Budget plans');
      await tester.tap(
        find.widgetWithText(FloatingActionButton, 'Create Money Plan'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Plan for'), findsOneWidget);
      // A new phone has no history to suggest from, so the way on is a
      // plan the user builds (E-39).
      expect(find.text('Build it yourself'), findsOneWidget);
    });

    testWidgets('+ on home opens a new income', (tester) async {
      await pumpReady(tester);

      await tester.tap(find.byTooltip('New income'));
      await tester.pumpAndSettle();

      expect(find.text('New income'), findsOneWidget);
    });

    testWidgets('− starts in the account chosen in the left panel', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseSummaryProvider.overrideWith((ref) => ready),
            ..._noChartDataOverrides,
            accountReaderProvider.overrideWith(
              (ref) async => const _TwoAccounts(),
            ),
            analyticsAccountFilterProvider.overrideWith((ref) => 2),
          ],
          child: const MoneyoraApp(),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('New expense'));
      await tester.pumpAndSettle();

      // Not the first account: an entry meant for the account on screen
      // was filed under the first one until the user noticed.
      expect(find.byTooltip('Account: Bank'), findsOneWidget);
    });

    testWidgets('Balance opens the transactions for the same period', (
      tester,
    ) async {
      // The balance opens what it adds up. The list reads the same period and
      // account, which its own test above checks.
      await pumpReady(tester);

      await tester.tap(find.text('Balance'));
      // Not pumpAndSettle: the list's rows come from a database this test
      // does not fake, and their spinner never settles.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.widgetWithText(AppBar, 'Transactions'), findsOneWidget);
    });

    testWidgets('the arrows and a swipe step the period. FR-RPT-002', (
      tester,
    ) async {
      await pumpReady(tester);
      final now = DateTime.now();
      final thisMonth = DateFormat.yMMMM().format(
        DateTime(now.year, now.month),
      );
      final lastMonth = DateFormat.yMMMM().format(
        DateTime(now.year, now.month - 1),
      );
      expect(find.text(thisMonth), findsOneWidget);

      // Nothing after this month can hold anything yet.
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);

      await tester.tap(find.byTooltip('Previous period'));
      await tester.pumpAndSettle();
      expect(find.text(lastMonth), findsOneWidget);

      // Towards the left is the next period, as a page turns.
      await tester.fling(find.text(lastMonth), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text(thisMonth), findsOneWidget);
    });

    testWidgets('Reports holds the charts that left home', (tester) async {
      await pumpReady(tester);

      await tapInMenu(tester, 'Reports');

      expect(find.text('Spending by category'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Income vs expenses'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Income vs expenses'), findsOneWidget);
    });

    testWidgets('− on home opens the entry screen, and back returns', (
      tester,
    ) async {
      // SCR-001: recording an expense is the thing done most often, so it
      // is one tap from home rather than two.
      await pumpReady(tester);

      await tester.tap(find.byTooltip('New expense'));
      await tester.pumpAndSettle();
      expect(find.text('New expense'), findsOneWidget);

      // Cancel, in words; the system back
      // gesture does the same.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('New expense'), findsOneWidget);
    });

    testWidgets('Transactions opens with the balance for the chosen period', (
      tester,
    ) async {
      // FR-RPT-006: the list and the home screen report one period and one
      // account, and each says what it left over.
      await pumpReady(tester);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transactions'));
      // Not pumpAndSettle: the list's own rows come from a database this
      // test does not fake, and their spinner never settles. The balance
      // reads the analytics fakes, which answer at once.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Balance'), findsOneWidget);
      expect(find.textContaining('· All accounts'), findsOneWidget);
    });

    testWidgets('the menu holds every screen, Settings last', (tester) async {
      await pumpReady(tester);
      await tester.tap(find.byTooltip('Menu'));
      await tester.pumpAndSettle();

      const order = [
        'Transactions',
        'Reports',
        'Scan receipt',
        'Transfer',
        'Budget plans',
        'Recurring',
        'Categories',
        'Accounts',
        'Ask Moneyora',
        'Settings',
      ];
      final menu = find.byType(Drawer);
      final tops = [
        for (final label in order)
          tester
              .getTopLeft(find.descendant(of: menu, matching: find.text(label)))
              .dy,
      ];
      for (var i = 1; i < tops.length; i++) {
        expect(
          tops[i],
          greaterThan(tops[i - 1]),
          reason: '${order[i]} should be below ${order[i - 1]}',
        );
      }
      // One door for plans, the owner's call on 1.0.0: three tiles for one
      // thing confused a tester.
      for (final gone in ['Your plan', 'Create Money Plan', 'Saved plans']) {
        expect(find.text(gone), findsNothing);
      }
    });

    testWidgets('reaches Settings from the menu', (tester) async {
      await pumpReady(tester);

      await tapInMenu(tester, 'Settings');

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
        'Budget plans',
        'Scan receipt',
        'Transfer',
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
        await tapInMenu(tester, destination);

        expect(
          find.byType(BackButton),
          findsOneWidget,
          reason: '$destination opened with no way back',
        );

        await tester.pageBack();
        await tester.pumpAndSettle();

        expect(find.byTooltip('New expense'), findsOneWidget);
      }
    });

    testWidgets('a screen gone to rather than pushed still backs out to home', (
      tester,
    ) async {
      // A tester's report, 2026-10-05: after confirming a scanned receipt
      // the list had no back arrow, and swiping back closed the app. Saving
      // a receipt goes to the list instead of stacking on the scanner, and
      // a flat route table made that the only screen left. A back gesture
      // is the system's pop, so that is what this presses.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            databaseSummaryProvider.overrideWith((ref) => ready),
            ..._noChartDataOverrides,
          ],
          child: const MoneyoraApp(),
        ),
      );
      await tester.pumpAndSettle();

      GoRouter.of(tester.element(find.byTooltip('New expense')))
          .go(Routes.scanReceipt);
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.byTooltip('New expense'), findsOneWidget);
    });

    testWidgets('the transfer icon at the top opens a transfer', (
      tester,
    ) async {
      // The owner's call: moving money between accounts is one tap from
      // home, beside the menu rather than inside it.
      await pumpReady(tester);

      await tester.tap(find.byTooltip('Transfer'));
      await tester.pumpAndSettle();
      expect(find.byType(BackButton), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byTooltip('New expense'), findsOneWidget);
    });

    testWidgets('the left panel chooses the period, and closes', (
      tester,
    ) async {
      // FR-RPT-002 from the filter icon, as a side panel: one
      // tap, and what it changed is what is on the screen.
      await pumpReady(tester);

      await tester.tap(find.byTooltip('Period and account'));
      await tester.pumpAndSettle();
      for (final label in ['All accounts', 'Day', 'Week', 'Month', 'Year']) {
        expect(find.text(label), findsWidgets);
      }
      for (final label in ['All', 'Interval', 'Choose date']) {
        expect(find.text(label), findsOneWidget);
      }

      await tester.tap(find.text('Year'));
      await tester.pumpAndSettle();

      expect(find.text('Interval'), findsNothing, reason: 'still open');
      final year = '${DateTime.now().year}';
      // The donut's caption, and the balance under it.
      expect(find.text(year), findsWidgets);
      expect(find.text('$year · All accounts'), findsOneWidget);
    });

    testWidgets('the accounts open in place under Accounts in the menu', (
      tester,
    ) async {
      // FR-ACC-003 asks for the accounts to be reachable "from the main
      // screen". They belong to the accounts feature and the home screen
      // must not import it, so `app_router.dart` composes the two — which
      // means this wiring is only ever exercised through the real router,
      // as it is here.
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tapInMenu(tester, 'Accounts');

      expect(find.byTooltip('New transfer'), findsOneWidget);
      expect(find.byTooltip('New account'), findsOneWidget);
      expect(find.text('Total balance'), findsOneWidget);
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Rs1,250.00'), findsNWidgets(2));
    });

    testWidgets('+ beside the accounts opens an empty form for a new one', (
      tester,
    ) async {
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tapInMenu(tester, 'Accounts');
      await tester.tap(find.byTooltip('New account'));
      await tester.pumpAndSettle();

      expect(find.text('New account'), findsOneWidget);
    });

    testWidgets('tapping an account opens it for editing', (tester) async {
      // The account travels as go_router's `extra`, which is untyped. This is
      // the only test that exercises that cast with a real Account in it.
      await tester.pumpWidget(bootWithAccounts());
      await tester.pumpAndSettle();

      await tapInMenu(tester, 'Accounts');
      await tester.tap(find.text('Cash'));
      await tester.pumpAndSettle();

      expect(find.text('Edit account'), findsOneWidget);
      // Filled in, rather than a blank form that would silently create a
      // second account on save.
      expect(find.widgetWithText(TextField, 'Cash'), findsOneWidget);
    });
  });
}
