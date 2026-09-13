@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/database/database_summary.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_calendar.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/features/analytics/presentation/widgets/spending_heatmap.dart';
import 'package:moneyora/injection.dart';

/// FR-RPT-009's heatmap over a scripted repository: one cell per day of the
/// anchor's month, shaded against the month's largest day, and pinned to the
/// calendar month whatever period shape the picker has selected.

class _ScriptedRepository implements AnalyticsRepository {
  _ScriptedRepository({this.days = const [], this.failure, this.hold});

  final List<DailyTotal> days;
  final Failure? failure;
  final Completer<void>? hold;

  final List<AnalyticsQuery> asked = [];

  @override
  Future<Either<Failure, List<DailyTotal>>> dailySpendingTotals(
    AnalyticsQuery query,
  ) async {
    asked.add(query);
    if (hold != null) await hold!.future;
    if (failure case final f?) return Left(f);
    return Right(days);
  }

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => throw UnimplementedError();
}

void main() {
  final anchor = DateTime(2026, 9, 9);

  DailyTotal day(int d, int cents) =>
      DailyTotal(date: DateTime(2026, 9, d), amountCents: cents);

  Widget boot(
    _ScriptedRepository repository, {
    PeriodSelection? selection,
    int transactionsEver = 1,
  }) => ProviderScope(
    overrides: [
      analyticsPeriodProvider.overrideWith(
        (ref) => selection ?? PeriodSelection.monthOf(anchor),
      ),
      getSpendingCalendarProvider.overrideWith(
        (ref) async => GetSpendingCalendar(repository),
      ),
      databaseSummaryProvider.overrideWith(
        (ref) async => DatabaseSummary(
          schemaVersion: 1,
          accounts: 1,
          categories: 18,
          transactions: transactionsEver,
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(
        body: SingleChildScrollView(child: SpendingHeatmap()),
      ),
    ),
  );

  /// The fill behind the day number [d].
  Color cellColor(WidgetTester tester, int d) {
    final box = tester.widget<DecoratedBox>(
      find
          .ancestor(of: find.text('$d'), matching: find.byType(DecoratedBox))
          .first,
    );
    return (box.decoration as BoxDecoration).color!;
  }

  group('the grid', () {
    testWidgets('draws one cell per day of the month', (tester) async {
      await tester.pumpWidget(boot(_ScriptedRepository(days: [day(3, 100)])));
      await tester.pumpAndSettle();

      for (var d = 1; d <= 30; d++) {
        expect(find.text('$d'), findsOneWidget, reason: 'day $d');
      }
      expect(find.text('31'), findsNothing);
      expect(find.text('Mon'), findsOneWidget);
      expect(find.text('Sun'), findsOneWidget);
    });

    testWidgets('shades the busiest day darkest and a quiet day neutral', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(_ScriptedRepository(days: [day(3, 100), day(14, 1000)])),
      );
      await tester.pumpAndSettle();

      final expense = AppTheme.light.extension<AppColors>()!.expense;
      expect(cellColor(tester, 14), expense.withValues(alpha: 1));
      expect(cellColor(tester, 3), expense.withValues(alpha: 0.2));
      expect(
        cellColor(tester, 20),
        AppTheme.light.colorScheme.onSurface.withValues(alpha: 0.06),
      );
    });

    testWidgets('a spent day carries its amount in a tooltip', (tester) async {
      await tester.pumpWidget(
        boot(_ScriptedRepository(days: [day(3, 120000)])),
      );
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && w.message == 'Sep 3 · Rs1,200.00',
        ),
        findsOneWidget,
      );
      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('states the total and the busiest day', (tester) async {
      await tester.pumpWidget(
        boot(_ScriptedRepository(days: [day(3, 100000), day(14, 250000)])),
      );
      await tester.pumpAndSettle();

      expect(find.text('Total Rs3,500.00'), findsOneWidget);
      expect(find.text('Busiest Sep 14, Rs2,500.00'), findsOneWidget);
    });
  });

  group('the month it draws', () {
    testWidgets('is the anchor\'s calendar month over every account', (
      tester,
    ) async {
      final repository = _ScriptedRepository();

      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      expect(repository.asked.single.range, DateRange.month(2026, 9));
      expect(repository.asked.single.isAllAccounts, isTrue);
      expect(
        find.text('September 2026 · always the whole month'),
        findsOneWidget,
      );
    });

    testWidgets('ignores the period shape: a Year is still one month', (
      tester,
    ) async {
      final repository = _ScriptedRepository();
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(SpendingHeatmap)))
          .read(analyticsPeriodProvider.notifier)
          .state = PeriodSelection.monthOf(anchor)
          .withPeriod(AnalyticsPeriod.year);
      await tester.pumpAndSettle();

      // The query key did not change, so nothing was re-asked.
      expect(repository.asked.length, 1);
      expect(
        find.text('September 2026 · always the whole month'),
        findsOneWidget,
      );
    });

    testWidgets('follows the anchor when a date is chosen', (tester) async {
      final repository = _ScriptedRepository();
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(SpendingHeatmap)))
          .read(analyticsPeriodProvider.notifier)
          .state = PeriodSelection.monthOf(anchor)
          .withAnchor(DateTime(2026, 2, 10));
      await tester.pumpAndSettle();

      expect(repository.asked.last.range, DateRange.month(2026, 2));
      expect(
        find.text('February 2026 · always the whole month'),
        findsOneWidget,
      );
    });

    testWidgets('an account change narrows it too (FR-RPT-003)', (
      tester,
    ) async {
      final repository = _ScriptedRepository();
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      ProviderScope.containerOf(tester.element(find.byType(SpendingHeatmap)))
              .read(analyticsAccountFilterProvider.notifier)
              .state =
          2;
      await tester.pumpAndSettle();

      expect(repository.asked.last.accountId, 2);
    });
  });

  group('the states around the data', () {
    testWidgets('shows a spinner while the month is in flight', (tester) async {
      final held = Completer<void>();
      addTearDown(() {
        if (!held.isCompleted) held.complete();
      });

      await tester.pumpWidget(boot(_ScriptedRepository(hold: held)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Mon'), findsNothing);
    });

    testWidgets('a quiet month says so, in its own words (E-22)', (
      tester,
    ) async {
      await tester.pumpWidget(boot(_ScriptedRepository()));
      await tester.pumpAndSettle();

      expect(find.text('No spending in this month.'), findsOneWidget);
      expect(find.text('Mon'), findsNothing);
    });

    testWidgets('a first-time user is told what will appear here (E-22)', (
      tester,
    ) async {
      await tester.pumpWidget(boot(_ScriptedRepository(), transactionsEver: 0));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Which days you spend most on appears here once you have added an '
          'expense.',
        ),
        findsOneWidget,
      );
      expect(find.text('No spending in this month.'), findsNothing);
    });

    testWidgets('a failing query shows its own message', (tester) async {
      await tester.pumpWidget(
        boot(
          _ScriptedRepository(
            failure: const CacheFailure('Could not read the database.'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Could not read the database.'), findsOneWidget);
      expect(find.text('Mon'), findsNothing);
    });
  });
}
