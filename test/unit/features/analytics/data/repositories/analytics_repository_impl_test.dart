import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/spending_by_category_reader.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/data/models/category_total_model.dart';
import 'package:moneyora/features/analytics/data/models/trend_point_model.dart';
import 'package:moneyora/features/analytics/data/repositories/analytics_repository_impl.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';

/// Returns canned totals, or throws whatever it is handed.
class _FakeDataSource implements AnalyticsLocalDataSource {
  _FakeDataSource({this.throws});

  final AppException? throws;
  DateTime? from;
  DateTime? to;
  int? accountId;

  List<CategoryTotalModel> totals = const [
    CategoryTotalModel(
      categoryId: 1,
      name: 'Food',
      color: '#FF7043',
      amountCents: 3420000,
    ),
    CategoryTotalModel(
      categoryId: 4,
      name: 'Transport',
      color: '#42A5F5',
      amountCents: 900000,
    ),
  ];
  int income = 9000000;
  TrendGranularity? granularity;
  List<TrendPointModel> points = [
    TrendPointModel(
      bucket: DateTime(2026, 8, 3),
      categoryId: 1,
      name: 'Food',
      color: '#FF7043',
      amountCents: 120000,
    ),
  ];

  @override
  Future<List<CategoryTotalModel>> spendingByCategory({
    required DateTime from,
    required DateTime to,
    int? accountId,
  }) async {
    this.from = from;
    this.to = to;
    this.accountId = accountId;
    if (throws case final failure?) throw failure;
    return totals;
  }

  @override
  Future<int> incomeForPeriod({
    required DateTime from,
    required DateTime to,
    int? accountId,
  }) async {
    this.from = from;
    this.to = to;
    if (throws case final failure?) throw failure;
    return income;
  }

  @override
  Future<List<TrendPointModel>> spendingTrend({
    required DateTime from,
    required DateTime to,
    required TrendGranularity granularity,
    int? accountId,
  }) async {
    this.from = from;
    this.to = to;
    this.accountId = accountId;
    this.granularity = granularity;
    if (throws case final failure?) throw failure;
    return points;
  }
}

void main() {
  final august = DateRange(from: DateTime(2026, 8), to: DateTime(2026, 8, 31));

  group('as the analytics repository', () {
    test('returns the totals with their ids and colours', () async {
      // The chart needs both: the id to filter by when a slice is tapped, the
      // colour to draw the arc without a second query.
      final repository = AnalyticsRepositoryImpl(_FakeDataSource());

      final result = await repository.spendingByCategory(
        AnalyticsQuery(range: august),
      );

      result.fold((f) => fail('unexpected failure: $f'), (totals) {
        expect(totals.first.categoryId, 1);
        expect(totals.first.color, '#FF7043');
      });
    });

    test('turns a cache exception into a failure at this boundary', () async {
      // Nothing above data/ has a try/catch, so if this does not convert, a
      // sqflite error reaches a widget.
      final repository = AnalyticsRepositoryImpl(
        _FakeDataSource(throws: const CacheException('disk is full')),
      );

      final result = await repository.spendingByCategory(
        AnalyticsQuery(range: august),
      );

      result.fold((failure) {
        expect(failure, isA<CacheFailure>());
        expect(failure.message, 'disk is full');
      }, (_) => fail('should not have returned totals'));
    });
  });

  group('income for a period', () {
    test('returns what the datasource read', () async {
      final repository = AnalyticsRepositoryImpl(_FakeDataSource());

      final result = await repository.incomeForPeriod(
        AnalyticsQuery(range: august),
      );

      result.fold(
        (f) => fail('unexpected failure: $f'),
        (income) => expect(income, 9000000),
      );
    });

    test('turns a cache exception into a failure at this boundary', () async {
      final repository = AnalyticsRepositoryImpl(
        _FakeDataSource(throws: const CacheException('disk is full')),
      );

      final result = await repository.incomeForPeriod(
        AnalyticsQuery(range: august),
      );

      result.fold((failure) {
        expect(failure, isA<CacheFailure>());
        expect(failure.message, 'disk is full');
      }, (_) => fail('should not have returned an amount'));
    });
  });

  group('spending over time (FR-RPT-005)', () {
    test('returns the points with their buckets, ids and colours', () async {
      final repository = AnalyticsRepositoryImpl(_FakeDataSource());

      final result = await repository.spendingTrend(
        AnalyticsQuery(range: august),
        TrendGranularity.day,
      );

      result.fold((f) => fail('unexpected failure: $f'), (points) {
        expect(points.single.bucket, DateTime(2026, 8, 3));
        expect(points.single.categoryId, 1);
        expect(points.single.color, '#FF7043');
        expect(points.single.amountCents, 120000);
      });
    });

    test('passes the period, account and granularity through', () async {
      final datasource = _FakeDataSource();
      final repository = AnalyticsRepositoryImpl(datasource);

      await repository.spendingTrend(
        AnalyticsQuery(range: august, accountId: 2),
        TrendGranularity.month,
      );

      expect(datasource.from, august.from);
      expect(datasource.to, august.to);
      expect(datasource.accountId, 2);
      expect(datasource.granularity, TrendGranularity.month);
    });

    test('turns a cache exception into a failure at this boundary', () async {
      final repository = AnalyticsRepositoryImpl(
        _FakeDataSource(throws: const CacheException('disk is full')),
      );

      final result = await repository.spendingTrend(
        AnalyticsQuery(range: august),
        TrendGranularity.day,
      );

      result.fold((failure) {
        expect(failure, isA<CacheFailure>());
        expect(failure.message, 'disk is full');
      }, (_) => fail('should not have returned points'));
    });
  });

  group('as the SpendingByCategoryReader that other features see', () {
    test('is the same object, so the query is written once', () {
      // The point of the port: no adapter, no second query, no chance of the
      // Copilot and the donut chart disagreeing about what counts as spending.
      expect(
        AnalyticsRepositoryImpl(_FakeDataSource()),
        isA<SpendingByCategoryReader>(),
      );
    });

    test('hands out names and amounts only', () async {
      // FR-COP-010: what crosses this port may be sent to a language model, so
      // the ids and colours are dropped here rather than by whoever calls it.
      final SpendingByCategoryReader reader = AnalyticsRepositoryImpl(
        _FakeDataSource(),
      );

      final result = await reader.totalsByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      result.fold((f) => fail('unexpected failure: $f'), (totals) {
        expect(totals, {'Food': 3420000, 'Transport': 900000});
      });
    });

    test('passes the dates through unchanged', () async {
      final source = _FakeDataSource();
      final SpendingByCategoryReader reader = AnalyticsRepositoryImpl(source);

      await reader.totalsByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      expect(source.from, DateTime(2026, 8));
      expect(source.to, DateTime(2026, 8, 31));
    });

    test('a quiet period is an empty map, not a failure', () async {
      final source = _FakeDataSource()..totals = const [];
      final SpendingByCategoryReader reader = AnalyticsRepositoryImpl(source);

      final result = await reader.totalsByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      result.fold(
        (f) => fail('unexpected failure: $f'),
        (totals) => expect(totals, isEmpty),
      );
    });

    test('reports a database failure rather than an empty answer', () async {
      // "Nothing was spent" and "the database could not be read" must not look
      // the same to a caller that is about to state one of them as fact.
      final SpendingByCategoryReader reader = AnalyticsRepositoryImpl(
        _FakeDataSource(throws: const CacheException('database is locked')),
      );

      final result = await reader.totalsByCategory(
        from: DateTime(2026, 8),
        to: DateTime(2026, 8, 31),
      );

      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('should not have returned totals'),
      );
    });
  });
}
