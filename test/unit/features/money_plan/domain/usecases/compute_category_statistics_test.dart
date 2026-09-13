import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/monthly_spending_reader.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';

/// Answers from a script and records what it was asked.
class _FakeReader implements MonthlySpendingReader {
  List<MonthlySpending> rows = const [];
  Failure? failWith;
  DateTime? askedFrom;
  DateTime? askedTo;

  @override
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    askedFrom = from;
    askedTo = to;
    if (failWith case final failure?) return Left(failure);
    return Right(rows);
  }
}

MonthlySpending _row(
  DateTime month, {
  int categoryId = 1,
  String name = 'Food',
  required int cents,
  int count = 1,
}) => MonthlySpending(
  categoryId: categoryId,
  name: name,
  month: month,
  amountCents: cents,
  transactionCount: count,
);

void main() {
  late _FakeReader reader;
  late ComputeCategoryStatistics compute;

  setUp(() {
    reader = _FakeReader();
    compute = ComputeCategoryStatistics(reader);
  });

  final halfYear = LookbackWindow(months: 6, lastMonth: DateTime(2026, 8));

  List<CategoryStatistics> unwrap(
    Either<Failure, List<CategoryStatistics>> r,
  ) => r.fold((f) => fail('unexpected failure: $f'), (s) => s);

  group('the window', () {
    test('asks the reader for the whole months, inclusive', () async {
      await compute(halfYear);

      expect(reader.askedFrom, DateTime(2026, 3));
      expect(reader.askedTo, DateTime(2026, 8, 31));
    });

    test('refuses a length outside 1 to 24 months without reading', () async {
      final result = await compute(
        LookbackWindow(months: 25, lastMonth: DateTime(2026, 8)),
      );

      result.fold((failure) {
        expect(failure, isA<ValidationFailure>());
        expect((failure as ValidationFailure).field, 'months');
        expect(failure.message, 'Look back over between 1 and 24 months.');
      }, (_) => fail('should have refused'));
      expect(reader.askedFrom, isNull);
    });

    test('validate says the same thing statically', () {
      expect(
        ComputeCategoryStatistics.validate(
          LookbackWindow(months: 0, lastMonth: DateTime(2026, 8)),
        ),
        isA<ValidationFailure>(),
      );
      expect(ComputeCategoryStatistics.validate(halfYear), isNull);
    });
  });

  group('densifying', () {
    test('a month with no row is zero, not missing', () async {
      reader.rows = [
        _row(DateTime(2026, 3), cents: 300),
        _row(DateTime(2026, 6), cents: 600),
      ];

      final stats = unwrap(await compute(halfYear)).single;

      expect(stats.monthlyTotalsCents, [300, 0, 0, 600, 0, 0]);
      expect(stats.monthCount, 6);
      expect(stats.activeMonths, 2);
      expect(stats.meanCents, 150);
      expect(stats.minCents, 0);
      expect(stats.maxCents, 600);
    });

    test('adds up transaction counts across the months', () async {
      reader.rows = [
        _row(DateTime(2026, 3), cents: 300, count: 4),
        _row(DateTime(2026, 6), cents: 600, count: 7),
      ];

      expect(unwrap(await compute(halfYear)).single.transactionCount, 11);
    });

    test('keeps categories apart and carries their names', () async {
      reader.rows = [
        _row(DateTime(2026, 3), cents: 100),
        _row(DateTime(2026, 3), categoryId: 2, name: 'Bills', cents: 900),
      ];

      final stats = unwrap(await compute(halfYear));

      expect(stats.map((s) => s.name), ['Bills', 'Food']);
      expect(stats.first.categoryId, 2);
      expect(stats.first.monthlyTotalsCents, [900, 0, 0, 0, 0, 0]);
    });

    test('a row outside the window is dropped', () async {
      reader.rows = [
        _row(DateTime(2026, 2), cents: 999),
        _row(DateTime(2026, 4), cents: 100),
      ];

      final stats = unwrap(await compute(halfYear)).single;

      expect(stats.monthlyTotalsCents, [0, 100, 0, 0, 0, 0]);
      expect(stats.transactionCount, 1);
    });

    test('a quiet window is an empty list, not a failure', () async {
      expect(unwrap(await compute(halfYear)), isEmpty);
    });
  });

  group('ordering', () {
    test('largest mean first, ties broken by name', () async {
      reader.rows = [
        _row(DateTime(2026, 4), categoryId: 3, name: 'Pets', cents: 100),
        _row(DateTime(2026, 4), categoryId: 2, name: 'Bills', cents: 900),
        _row(DateTime(2026, 4), categoryId: 1, name: 'Food', cents: 100),
      ];

      final stats = unwrap(await compute(halfYear));

      expect(stats.map((s) => s.name), ['Bills', 'Food', 'Pets']);
    });
  });

  test('a failure from the reader passes through unchanged', () async {
    reader.failWith = const CacheFailure('disk is full');

    final result = await compute(halfYear);

    expect(
      result,
      const Left<Failure, List<CategoryStatistics>>(
        CacheFailure('disk is full'),
      ),
    );
  });
}
