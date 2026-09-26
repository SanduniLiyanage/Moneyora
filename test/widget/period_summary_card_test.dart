@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/calendar_settings.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_selection.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_period_summary.dart';
import 'package:moneyora/features/analytics/presentation/providers/analytics_providers.dart';
import 'package:moneyora/features/analytics/presentation/widgets/period_summary_card.dart';
import 'package:moneyora/injection.dart';

/// FR-RPT-006's card over a scripted repository, on a pinned clock.
void main() {
  // Saturday 26 September 2026: 26 days of September have happened.
  final today = DateTime(2026, 9, 26, 12);
  final september = DateRange.month(2026, 9);
  final august = DateRange.month(2026, 8);

  CategoryTotal total(String name, int cents) => CategoryTotal(
    categoryId: name.hashCode,
    name: name,
    color: '#eb6834',
    amountCents: cents,
  );

  Widget boot(
    _Scripted repository, {
    AnalyticsPeriod period = AnalyticsPeriod.month,
  }) => ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => today),
      calendarSettingsProvider.overrideWith(
        (ref) => Stream.value(CalendarSettings.defaults),
      ),
      analyticsPeriodProvider.overrideWith(
        (ref) => PeriodSelection(period: period, anchor: today),
      ),
      getPeriodSummaryProvider.overrideWith(
        (ref) async => GetPeriodSummary(repository),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const Scaffold(body: PeriodSummaryCard()),
    ),
  );

  testWidgets('the six figures for the month, against last month', (
    tester,
  ) async {
    await tester.pumpWidget(
      boot(
        _Scripted()
          ..spending[september] = [
            total('Bills', 1300000),
            total('Food', 260000),
          ]
          ..spending[august] = [total('Food', 1200000)]
          ..income[september] = 5000000,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Rs50,000.00'), findsOneWidget);
    expect(find.text('Rs15,600.00'), findsOneWidget);
    expect(find.text('Rs34,400.00'), findsOneWidget);
    // 15,600.00 over the 26 days so far.
    expect(find.text('Rs600.00'), findsOneWidget);
    expect(find.text('Bills · Rs13,000.00'), findsOneWidget);
    expect(find.text('Spending vs last month'), findsOneWidget);
    expect(find.text('+30%'), findsOneWidget);
  });

  testWidgets('says so when nothing was spent the period before', (
    tester,
  ) async {
    await tester.pumpWidget(
      boot(_Scripted()..spending[september] = [total('Food', 100000)]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Nothing spent last month'), findsOneWidget);
  });

  testWidgets('all time has no average and no comparison', (tester) async {
    await tester.pumpWidget(boot(_Scripted(), period: AnalyticsPeriod.all));
    await tester.pumpAndSettle();

    expect(find.text('Change'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(3));
  });

  testWidgets('shows a failure in its own words', (tester) async {
    await tester.pumpWidget(
      boot(_Scripted()..fail = const CacheFailure('The database is locked.')),
    );
    await tester.pumpAndSettle();

    expect(find.text('The database is locked.'), findsOneWidget);
  });
}

class _Scripted implements AnalyticsRepository {
  final Map<DateRange, List<CategoryTotal>> spending = {};
  final Map<DateRange, int> income = {};
  Failure? fail;

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async =>
      fail != null ? Left(fail!) : Right(spending[query.range] ?? const []);

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) async =>
      fail != null ? Left(fail!) : Right(income[query.range] ?? 0);

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, List<DailyTotal>>> dailySpendingTotals(
    AnalyticsQuery query,
  ) => throw UnimplementedError();
}
