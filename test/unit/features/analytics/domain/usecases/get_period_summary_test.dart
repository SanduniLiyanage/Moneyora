import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_summary.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_period_summary.dart';

/// FR-RPT-006's figures, over a fake repository that answers per range.
void main() {
  final september = DateRange.month(2026, 9);
  final august = DateRange.month(2026, 8);

  CategoryTotal total(int id, String name, int cents) => CategoryTotal(
    categoryId: id,
    name: name,
    color: '#000000',
    amountCents: cents,
  );

  late _FakeAnalytics analytics;
  late GetPeriodSummary summarise;

  setUp(() {
    analytics = _FakeAnalytics()
      ..spending[september] = [
        total(1, 'Food', 600000),
        total(2, 'Bills', 900000),
        total(3, 'Car', 150000),
      ]
      ..spending[august] = [total(1, 'Food', 1100000)]
      ..income[september] = 3000000;
    summarise = GetPeriodSummary(analytics);
  });

  SummaryRequest request({
    DateRange? previous,
    int? days = 27,
    int? accountId,
  }) => SummaryRequest(
    query: AnalyticsQuery(range: september, accountId: accountId),
    previousRange: previous,
    daysElapsed: days,
  );

  test('the six figures, from the same totals the charts draw', () async {
    final summary = (await summarise(request(previous: august))).toNullable()!;

    expect(summary.incomeCents, 3000000);
    expect(summary.expenseCents, 1650000);
    expect(summary.netSavingsCents, 1350000);
    // Over the 27 days that have happened, not the 30 the month has.
    expect(summary.averageDailySpendCents, 1650000 ~/ 27);
    expect(summary.largestCategory?.name, 'Bills');
    expect(summary.previousExpenseCents, 1100000);
    // 1,650,000 against 1,100,000: half as much again.
    expect(summary.expenseChangePercent, 50);
  });

  test('a fall is negative, rounded toward zero', () async {
    analytics.spending[august] = [total(1, 'Food', 2000000)];

    final summary = (await summarise(request(previous: august))).toNullable()!;

    // 1,650,000 against 2,000,000 is -17.5%.
    expect(summary.expenseChangePercent, -17);
  });

  test(
    'no change is given against nothing spent, or no period before',
    () async {
      analytics.spending[august] = [];
      final nothingBefore = (await summarise(request(previous: august)))
          .toNullable()!;
      final noPeriod = (await summarise(request())).toNullable()!;

      expect(nothingBefore.previousExpenseCents, 0);
      expect(nothingBefore.expenseChangePercent, isNull);
      expect(noPeriod.previousExpenseCents, isNull);
      expect(noPeriod.expenseChangePercent, isNull);
    },
  );

  test('no average without days to divide by', () async {
    final allTime = (await summarise(request(days: null))).toNullable()!;
    final notStarted = (await summarise(request(days: 0))).toNullable()!;

    expect(allTime.averageDailySpendCents, isNull);
    expect(notStarted.averageDailySpendCents, isNull);
  });

  test('a tie for largest goes to the first by name', () async {
    analytics.spending[september] = [
      total(1, 'Food', 500000),
      total(2, 'Bills', 500000),
    ];

    final summary = (await summarise(request())).toNullable()!;

    expect(summary.largestCategory?.name, 'Bills');
  });

  test('nothing spent has no largest category', () async {
    analytics.spending[september] = [];

    final summary = (await summarise(request())).toNullable()!;

    expect(summary.largestCategory, isNull);
    expect(summary.expenseCents, 0);
  });

  test('the period before is read with the same account', () async {
    await summarise(request(previous: august, accountId: 4));

    expect(
      analytics.queries,
      contains(AnalyticsQuery(range: august, accountId: 4)),
    );
  });

  test('a failure anywhere is the answer', () async {
    analytics.fail = const CacheFailure('locked');

    expect(
      await summarise(request(previous: august)),
      const Left<Failure, PeriodSummary>(CacheFailure('locked')),
    );
  });

  test('refuses an inverted period', () async {
    final result = await summarise(
      SummaryRequest(
        query: AnalyticsQuery(
          range: DateRange(
            from: DateTime(2026, 9, 2),
            to: DateTime(2026, 9, 1),
          ),
        ),
        previousRange: null,
        daysElapsed: 1,
      ),
    );

    expect(result.isLeft(), isTrue);
  });
}

class _FakeAnalytics implements AnalyticsRepository {
  final Map<DateRange, List<CategoryTotal>> spending = {};
  final Map<DateRange, int> income = {};
  final List<AnalyticsQuery> queries = [];
  Failure? fail;

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async {
    queries.add(query);
    if (fail case final f?) return Left(f);
    return Right(spending[query.range] ?? const []);
  }

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) async {
    if (fail case final f?) return Left(f);
    return Right(income[query.range] ?? 0);
  }

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
