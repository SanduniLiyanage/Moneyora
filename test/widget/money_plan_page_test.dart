@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/ports/calendar_settings.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_request.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_mode.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/presentation/pages/money_plan_page.dart';
import 'package:moneyora/injection.dart';

/// The wizard's first step: what it builds, what it refuses, where it goes.
///
/// The review route is a stub that records the request handed to it, so
/// the test can assert the screen's output without running the engine.
void main() {
  final now = DateTime(2026, 9, 13);

  Widget boot(
    List<AllocationRequest> handedOn, {
    CalendarSettings calendar = CalendarSettings.defaults,
  }) => ProviderScope(
    overrides: [
      // FR-SET-004 and FR-SET-012: how periods are cut and how far back the
      // plan looks, both read from Settings.
      calendarSettingsProvider.overrideWith((ref) => Stream.value(calendar)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.moneyPlan,
        routes: [
          GoRoute(
            path: Routes.moneyPlan,
            builder: (context, state) => MoneyPlanPage(now: now),
          ),
          GoRoute(
            path: Routes.moneyPlanReview,
            builder: (context, state) {
              handedOn.add(state.extra! as AllocationRequest);
              return const Scaffold(body: Text('review stub'));
            },
          ),
        ],
      ),
    ),
  );

  Future<void> generate(WidgetTester tester) async {
    // The button is the last row of a lazy list: scrolled to, not looked up.
    await tester.scrollUntilVisible(
      find.text('Generate plan'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Generate plan'));
    await tester.pumpAndSettle();
  }

  testWidgets('opens on next month, from history, over the stored lookback', (
    tester,
  ) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(boot(handedOn));
    await tester.pumpAndSettle();

    expect(find.text('Create Money Plan'), findsOneWidget);
    expect(find.text('October 2026 · 31 days'), findsOneWidget);
    // FR-PLN-003, FR-SET-012: stated, with where to change it, and not
    // changeable here.
    expect(
      find.text(
        'Based on the last 6 months of spending — change this under '
        'Settings › Calendar.',
      ),
      findsOneWidget,
    );

    await generate(tester);

    expect(find.text('review stub'), findsOneWidget);
    expect(
      handedOn.single,
      AllocationRequest(
        period: PlanPeriod.month(2026, 10),
        lookback: LookbackWindow.before(now),
      ),
    );
    expect(handedOn.single.lookback.months, LookbackWindow.defaultMonths);
  });

  testWidgets('reads the lookback from Settings and says so', (tester) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(
      boot(handedOn, calendar: const CalendarSettings(planAnalysisMonths: 12)),
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Based on the last 12 months of spending'),
      findsOneWidget,
    );

    await generate(tester);

    expect(handedOn.single.lookback, LookbackWindow.before(now, months: 12));
  });

  testWidgets('cuts a week and a month where Settings says', (tester) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(
      boot(
        handedOn,
        calendar: const CalendarSettings(
          firstWeekday: DateTime.monday,
          firstDayOfMonth: 25,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Next month's first day is 1 October, which falls before a 25th
    // start: the month that began on 25 September.
    expect(find.text('Sep 25 – Oct 24, 2026 · 30 days'), findsOneWidget);

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    // 1 October 2026 is a Thursday: Monday the 28th to Sunday the 4th.
    expect(find.text('Sep 28 – Oct 4, 2026 · 7 days'), findsOneWidget);
  });

  testWidgets('a number of days is counted from the start date', (
    tester,
  ) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(boot(handedOn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Number of days'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Days'), '10');
    await tester.pumpAndSettle();

    expect(find.text('Oct 1 – Oct 10, 2026 · 10 days'), findsOneWidget);

    await generate(tester);

    expect(handedOn.single.period, PlanPeriod.days(DateTime(2026, 10), 10));
  });

  testWidgets('a week and a year take their shape from the date', (
    tester,
  ) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(boot(handedOn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Week'));
    await tester.pumpAndSettle();
    // 1 October 2026 is a Thursday. Under the stored default the week
    // starts on Sunday: the 27th to Saturday the 3rd.
    expect(find.text('Sep 27 – Oct 3, 2026 · 7 days'), findsOneWidget);

    await tester.tap(find.text('Year'));
    await tester.pumpAndSettle();
    expect(find.text('2026 · 365 days'), findsOneWidget);

    await generate(tester);
    expect(handedOn.single.period, PlanPeriod.year(2026));
  });

  testWidgets('a total must be entered before the plan is generated', (
    tester,
  ) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(boot(handedOn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set a total'));
    await tester.pumpAndSettle();
    await generate(tester);

    expect(find.text('Enter a total budget.'), findsOneWidget);
    expect(handedOn, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Total budget'),
      '100,000',
    );
    await generate(tester);

    expect(handedOn.single.mode, const BudgetMode.total(10000000));
  });

  testWidgets('a savings target outside 0–100 is refused in the use '
      "case's words", (tester) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(boot(handedOn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suggest from income'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Savings target'),
      '150',
    );
    await generate(tester);

    expect(
      find.text('The savings target is a percentage from 0 to 100.'),
      findsOneWidget,
    );
    expect(handedOn, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextField, 'Savings target'),
      '15',
    );
    await generate(tester);

    expect(
      handedOn.single.mode,
      const BudgetMode.suggested(savingsTargetPct: 15),
    );
  });

  testWidgets('the savings figure starts from the stored target. FR-SET-008', (
    tester,
  ) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(
      boot(handedOn, calendar: const CalendarSettings(savingsTargetPct: 20)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suggest from income'));
    await tester.pumpAndSettle();
    await generate(tester);

    expect(
      handedOn.single.mode,
      const BudgetMode.suggested(savingsTargetPct: 20),
    );
  });

  testWidgets('with no stored target, the suggestion is 10%', (tester) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(boot(handedOn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Suggest from income'));
    await tester.pumpAndSettle();
    await generate(tester);

    expect(
      handedOn.single.mode,
      const BudgetMode.suggested(savingsTargetPct: 10),
    );
  });

  testWidgets('zero days is refused', (tester) async {
    final handedOn = <AllocationRequest>[];
    await tester.pumpWidget(boot(handedOn));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Number of days'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Days'), '0');
    await generate(tester);

    expect(find.text('Enter at least one day.'), findsOneWidget);
    expect(handedOn, isEmpty);
  });
}
