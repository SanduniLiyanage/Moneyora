import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/analytics/domain/entities/analytics_query.dart';
import 'package:moneyora/features/analytics/domain/entities/category_total.dart';
import 'package:moneyora/features/analytics/domain/entities/daily_total.dart';
import 'package:moneyora/features/analytics/domain/entities/spending_calendar.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:moneyora/features/analytics/domain/repositories/analytics_repository.dart';
import 'package:moneyora/features/analytics/domain/usecases/get_spending_calendar.dart';

/// Answers `dailySpendingTotals` from a script and records what it was asked.
class _FakeRepository implements AnalyticsRepository {
  List<DailyTotal> totals = const [];
  Failure? failWith;
  AnalyticsQuery? askedQuery;

  @override
  Future<Either<Failure, List<DailyTotal>>> dailySpendingTotals(
    AnalyticsQuery query,
  ) async {
    askedQuery = query;
    if (failWith case final failure?) return Left(failure);
    return Right(totals);
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
  late _FakeRepository repository;
  late GetSpendingCalendar getSpendingCalendar;

  setUp(() {
    repository = _FakeRepository();
    getSpendingCalendar = GetSpendingCalendar(repository);
  });

  const september = SpendingCalendarQuery.of(2026, 9);

  SpendingCalendar unwrap(Either<Failure, SpendingCalendar> result) =>
      result.getOrElse((f) => fail('unexpected failure: $f'));

  test('asks for the whole calendar month over every account', () async {
    await getSpendingCalendar(september);

    expect(repository.askedQuery?.range, DateRange.month(2026, 9));
    expect(repository.askedQuery?.isAllAccounts, isTrue);
  });

  test('passes the account filter through (FR-RPT-003)', () async {
    await getSpendingCalendar(
      const SpendingCalendarQuery.of(2026, 9, accountId: 2),
    );

    expect(repository.askedQuery?.accountId, 2);
  });

  test('has one amount per day of the month, zero where quiet', () async {
    repository.totals = [
      DailyTotal(date: DateTime(2026, 9, 3), amountCents: 100),
      DailyTotal(date: DateTime(2026, 9, 30), amountCents: 300),
    ];

    final calendar = unwrap(await getSpendingCalendar(september));

    expect(calendar.year, 2026);
    expect(calendar.month, 9);
    expect(calendar.dayCount, 30);
    expect(calendar.amountOn(3), 100);
    expect(calendar.amountOn(30), 300);
    expect(calendar.totalCents, 400);
    expect(calendar.amountsCents.where((c) => c == 0).length, 28);
  });

  test('knows February from a leap year', () async {
    final leap = unwrap(
      await getSpendingCalendar(const SpendingCalendarQuery.of(2028, 2)),
    );
    final plain = unwrap(
      await getSpendingCalendar(const SpendingCalendarQuery.of(2026, 2)),
    );

    expect(leap.dayCount, 29);
    expect(plain.dayCount, 28);
  });

  test('nothing spent is an empty calendar, not a failure', () async {
    final calendar = unwrap(await getSpendingCalendar(september));

    expect(calendar.isEmpty, isTrue);
    expect(calendar.dayCount, 30);
  });

  test('a row outside the month is dropped rather than crashing', () async {
    repository.totals = [
      DailyTotal(date: DateTime(2026, 10, 1), amountCents: 100),
    ];

    final calendar = unwrap(await getSpendingCalendar(september));

    expect(calendar.isEmpty, isTrue);
  });

  test('a repository failure passes through untouched', () async {
    repository.failWith = const CacheFailure('Could not read the calendar.');

    final result = await getSpendingCalendar(september);

    expect(
      result,
      const Left<Failure, SpendingCalendar>(
        CacheFailure('Could not read the calendar.'),
      ),
    );
  });
}
