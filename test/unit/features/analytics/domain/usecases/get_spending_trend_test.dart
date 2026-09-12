import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/spending_trend.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_trend.dart';

/// Answers `spendingTrend` from a script and records what it was asked.
class _FakeRepository implements AnalyticsRepository {
  List<TrendPoint> points = const [];
  Failure? failWith;
  AnalyticsQuery? askedQuery;
  TrendGranularity? askedGranularity;

  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) async {
    askedQuery = query;
    askedGranularity = granularity;
    if (failWith case final failure?) return Left(failure);
    return Right(points);
  }

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) =>
      throw UnimplementedError();
}

TrendPoint _point(
  DateTime bucket, {
  int categoryId = 1,
  String name = 'Food',
  String color = '#eb6834',
  required int cents,
}) => TrendPoint(
  bucket: bucket,
  categoryId: categoryId,
  name: name,
  color: color,
  amountCents: cents,
);

void main() {
  late _FakeRepository repository;
  late GetSpendingTrend getSpendingTrend;

  setUp(() {
    repository = _FakeRepository();
    getSpendingTrend = GetSpendingTrend(repository);
  });

  final year = AnalyticsQuery(range: DateRange.year(2026));
  final september = AnalyticsQuery(range: DateRange.month(2026, 9));

  group('granularity follows the span of the period', () {
    test('a day, a week and a month are cut by day', () {
      final day = DateTime(2026, 9, 9);
      expect(
        GetSpendingTrend.granularityFor(DateRange.day(day)),
        TrendGranularity.day,
      );
      expect(
        GetSpendingTrend.granularityFor(DateRange.week(day)),
        TrendGranularity.day,
      );
      expect(
        GetSpendingTrend.granularityFor(DateRange.month(2026, 9)),
        TrendGranularity.day,
      );
    });

    test('a year and all time are cut by month', () {
      expect(
        GetSpendingTrend.granularityFor(DateRange.year(2026)),
        TrendGranularity.month,
      );
      expect(
        GetSpendingTrend.granularityFor(DateRange.allTime()),
        TrendGranularity.month,
      );
    });

    test('a custom interval switches at about a quarter', () {
      final from = DateTime(2026, 1, 1);
      final justUnder = DateRange(
        from: from,
        to: from.add(
          const Duration(days: GetSpendingTrend.maxDailySpanDays - 1),
        ),
      );
      final atTheLine = DateRange(
        from: from,
        to: from.add(const Duration(days: GetSpendingTrend.maxDailySpanDays)),
      );

      expect(GetSpendingTrend.granularityFor(justUnder), TrendGranularity.day);
      expect(
        GetSpendingTrend.granularityFor(atTheLine),
        TrendGranularity.month,
      );
    });

    test('passes the chosen granularity to the repository', () async {
      await getSpendingTrend(year);

      expect(repository.askedGranularity, TrendGranularity.month);
    });
  });

  group('the account filter (FR-RPT-003)', () {
    test('passes the whole query through, account included', () async {
      final narrowed = year.withAccount(2);

      await getSpendingTrend(narrowed);

      expect(repository.askedQuery, narrowed);
      expect(repository.askedQuery?.accountId, 2);
    });
  });

  group('the series it builds', () {
    test('has every bucket of the period, none skipped', () async {
      final result = await getSpendingTrend(year);

      result.fold((f) => fail('unexpected failure: $f'), (trend) {
        expect(trend.granularity, TrendGranularity.month);
        expect(trend.buckets.length, 12);
        expect(trend.buckets.first, DateTime(2026, 1));
        expect(trend.buckets.last, DateTime(2026, 12));
      });
    });

    test('a bucket a category was not spent in is zero, not missing', () async {
      repository.points = [
        _point(DateTime(2026, 2), cents: 100),
        _point(DateTime(2026, 11), cents: 300),
      ];

      final result = await getSpendingTrend(year);

      result.fold((f) => fail('unexpected failure: $f'), (trend) {
        final food = trend.series.single;
        expect(food.amountsCents.length, 12);
        expect(food.amountsCents[1], 100);
        expect(food.amountsCents[10], 300);
        expect(food.amountsCents.where((c) => c == 0).length, 10);
        expect(food.totalCents, 400);
      });
    });

    test('carries the category identity and colour once per line', () async {
      repository.points = [
        _point(DateTime(2026, 9, 1), cents: 100),
        _point(DateTime(2026, 9, 2), cents: 100),
      ];

      final result = await getSpendingTrend(september);

      result.fold((f) => fail('unexpected failure: $f'), (trend) {
        expect(trend.series.single.categoryId, 1);
        expect(trend.series.single.name, 'Food');
        expect(trend.series.single.color, '#eb6834');
        expect(trend.buckets.length, 30);
      });
    });

    test(
      'orders lines by their total over the period, largest first',
      () async {
        repository.points = [
          _point(DateTime(2026, 1), cents: 100),
          _point(DateTime(2026, 2), cents: 100),
          _point(
            DateTime(2026, 6),
            categoryId: 2,
            name: 'Transport',
            color: '#2a78d6',
            cents: 500,
          ),
        ];

        final result = await getSpendingTrend(year);

        result.fold((f) => fail('unexpected failure: $f'), (trend) {
          expect(trend.series.map((s) => s.name), ['Transport', 'Food']);
        });
      },
    );

    test('breaks a tie on total by name, so the order is stable', () async {
      repository.points = [
        _point(DateTime(2026, 3), categoryId: 2, name: 'Transport', cents: 5),
        _point(DateTime(2026, 3), categoryId: 1, name: 'Food', cents: 5),
      ];

      final result = await getSpendingTrend(year);

      result.fold((f) => fail('unexpected failure: $f'), (trend) {
        expect(trend.series.map((s) => s.name), ['Food', 'Transport']);
      });
    });

    test(
      'nothing spent is an empty trend with a full axis, not a failure',
      () async {
        final result = await getSpendingTrend(september);

        result.fold((f) => fail('unexpected failure: $f'), (trend) {
          expect(trend.isEmpty, isTrue);
          expect(trend.buckets.length, 30);
        });
      },
    );

    test(
      'a point outside the period is dropped rather than crashing',
      () async {
        repository.points = [_point(DateTime(2027, 1), cents: 100)];

        final result = await getSpendingTrend(year);

        result.fold((f) => fail('unexpected failure: $f'), (trend) {
          expect(trend.isEmpty, isTrue);
        });
      },
    );
  });

  group('validation', () {
    test('refuses an inverted range with the donut\'s own sentence', () async {
      final result = await getSpendingTrend(
        AnalyticsQuery(
          range: DateRange(from: DateTime(2026, 9, 30), to: DateTime(2026, 9)),
        ),
      );

      expect(
        result,
        const Left<Failure, SpendingTrend>(
          ValidationFailure(
            'The start of the period is after its end.',
            field: 'from',
          ),
        ),
      );
      expect(repository.askedQuery, isNull);
    });

    test('a repository failure passes through untouched', () async {
      repository.failWith = const CacheFailure('Could not read the trend.');

      final result = await getSpendingTrend(year);

      expect(
        result,
        const Left<Failure, SpendingTrend>(
          CacheFailure('Could not read the trend.'),
        ),
      );
    });
  });
}
