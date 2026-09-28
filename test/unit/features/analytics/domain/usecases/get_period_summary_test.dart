import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/period_summary.dart';
import 'package:moneyora/features/analytics/domain/entities/transfer_totals.dart';
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

  group('transfers. FR-TRF-004, E-02', () {
    // Rs200 of cash drawn from card 2 into cash account 1.
    setUp(() {
      analytics
        ..transfers[1] = const TransferTotals(inCents: 20000, outCents: 0)
        ..transfers[2] = const TransferTotals(inCents: 0, outCents: 20000);
    });

    test('money transferred in raises the chosen account balance', () async {
      final summary = (await summarise(request(accountId: 1))).toNullable()!;

      expect(summary.transferInCents, 20000);
      expect(summary.balanceCents, summary.netSavingsCents + 20000);
    });

    test('money transferred out lowers it', () async {
      final summary = (await summarise(request(accountId: 2))).toNullable()!;

      expect(summary.transferOutCents, 20000);
      expect(summary.balanceCents, summary.netSavingsCents - 20000);
    });

    test('is never income or spending', () async {
      final scoped = (await summarise(request(accountId: 1))).toNullable()!;
      final all = (await summarise(request())).toNullable()!;

      // The fake answers per range, not per account, so the income and
      // spending figures are the same either way: a transfer added nothing.
      expect(scoped.incomeCents, all.incomeCents);
      expect(scoped.expenseCents, all.expenseCents);
      expect(scoped.netSavingsCents, all.netSavingsCents);
    });

    test('across every account is not asked for: the legs cancel', () async {
      final summary = (await summarise(request())).toNullable()!;

      expect(analytics.transferQueries, isEmpty);
      expect(summary.transferInCents, 0);
      expect(summary.transferOutCents, 0);
      expect(summary.balanceCents, summary.netSavingsCents);
    });

    test('a failed read is the failure, not a balance without it', () async {
      analytics.failTransfers = const CacheFailure('no');

      final result = await summarise(request(accountId: 1));

      expect(result, const Left<Failure, PeriodSummary>(CacheFailure('no')));
    });
  });
}

class _FakeAnalytics implements AnalyticsRepository {
  /// Per account id; asked only when one account is chosen.
  final Map<int, TransferTotals> transfers = {};
  final List<AnalyticsQuery> transferQueries = [];
  Failure? failTransfers;

  @override
  Future<Either<Failure, TransferTotals>> transfersForPeriod(
    AnalyticsQuery query,
  ) async {
    transferQueries.add(query);
    if (failTransfers case final f?) return Left(f);
    return Right(transfers[query.accountId] ?? TransferTotals.none);
  }

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
