import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_by_category.dart';

/// Records the range it was asked for, and can be told to fail.
class _FakeRepository implements AnalyticsRepository {
  DateRange? asked;
  Failure? failWith;
  List<CategoryTotal> totals = const [
    CategoryTotal(
      categoryId: 1,
      name: 'Food',
      color: '#FF7043',
      amountCents: 3420000,
    ),
  ];

  @override
  Future<Either<Failure, List<CategoryTotal>>> spendingByCategory(
    AnalyticsQuery query,
  ) async {
    asked = query.range;
    if (failWith case final failure?) return Left(failure);
    return Right(totals);
  }

  @override
  Future<Either<Failure, int>> incomeForPeriod(AnalyticsQuery query) =>
      throw UnimplementedError();
  @override
  Future<Either<Failure, List<TrendPoint>>> spendingTrend(
    AnalyticsQuery query,
    TrendGranularity granularity,
  ) => throw UnimplementedError();
}

/// Every case here is about the period, so each range is wrapped in the
/// all-accounts query the chart sends by default. FR-RPT-003's own cases live
/// in `analytics_query_test.dart` and `account_filter_test.dart`.
AnalyticsQuery over(DateRange range) => AnalyticsQuery(range: range);

void main() {
  late _FakeRepository repository;
  late GetSpendingByCategory getSpendingByCategory;

  setUp(() {
    repository = _FakeRepository();
    getSpendingByCategory = GetSpendingByCategory(repository);
  });

  final august = DateRange(from: DateTime(2026, 8), to: DateTime(2026, 8, 31));

  group('happy path', () {
    test('returns what the repository read, unchanged', () async {
      final result = await getSpendingByCategory(over(august));

      result.fold((f) => fail('unexpected failure: $f'), (totals) {
        expect(totals.single.name, 'Food');
        expect(totals.single.amountCents, 3420000);
      });
    });

    test('passes the range down untouched', () async {
      await getSpendingByCategory(over(august));

      expect(repository.asked, august);
    });

    test('an empty period is an answer, not a failure', () async {
      // A new user, or a quiet month. "You spent nothing" is a result; an
      // error state here would make every empty screen look broken.
      repository.totals = const [];

      final result = await getSpendingByCategory(over(august));

      expect(result.isRight(), isTrue);
      result.fold((f) => fail('unexpected failure: $f'), (totals) {
        expect(totals, isEmpty);
      });
    });

    test('passes a repository failure through unchanged', () async {
      repository.failWith = const CacheFailure('database is locked');

      final result = await getSpendingByCategory(over(august));

      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('should not have returned totals'),
      );
    });
  });

  group('validation', () {
    test('rejects a range that runs backwards, without querying', () async {
      // SQLite answers an inverted range with an empty result, which reads as
      // "you spent nothing" rather than as the mistake it is.
      final result = await getSpendingByCategory(
        over(DateRange(from: DateTime(2026, 8, 31), to: DateTime(2026, 8))),
      );

      result.fold(
        (failure) => expect(failure, isA<ValidationFailure>()),
        (_) => fail('should not have returned totals'),
      );
      expect(repository.asked, isNull);
    });

    test('accepts a single day', () async {
      final oneDay = DateRange(
        from: DateTime(2026, 8, 3),
        to: DateTime(2026, 8, 3),
      );

      expect(GetSpendingByCategory.validate(oneDay), isNull);

      final result = await getSpendingByCategory(over(oneDay));
      expect(result.isRight(), isTrue);
    });

    test('names the field at fault so a picker can highlight it', () {
      final failure = GetSpendingByCategory.validate(
        DateRange(from: DateTime(2026, 9), to: DateTime(2026, 8)),
      );

      expect(failure?.field, 'from');
    });
  });

  group('DateRange.month', () {
    test('covers the whole month, including its last day', () {
      // The last day is DateTime(year, month + 1, 0) — correct, and
      // unmemorable enough that every rediscovery is a chance to write 30.
      expect(DateRange.month(2026, 8).from, DateTime(2026, 8));
      expect(DateRange.month(2026, 8).to, DateTime(2026, 8, 31));
    });

    test('handles the months that catch people out', () {
      expect(DateRange.month(2026, 2).to, DateTime(2026, 2, 28));
      expect(DateRange.month(2024, 2).to, DateTime(2024, 2, 29));
      expect(DateRange.month(2026, 4).to, DateTime(2026, 4, 30));
      expect(DateRange.month(2026, 12).to, DateTime(2026, 12, 31));
    });

    test('is never inverted', () {
      for (var month = 1; month <= 12; month++) {
        expect(DateRange.month(2026, month).isInverted, isFalse);
      }
    });
  });
}
