import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/monthly_spending_reader.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_history.dart';
import 'package:moneyora/features/money_plan/domain/usecases/check_plan_history.dart';

class _FakeReader implements MonthlySpendingReader {
  _FakeReader(this.result);

  final Either<Failure, List<MonthlySpending>> result;
  (DateTime, DateTime)? asked;

  @override
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    asked = (from, to);
    return result;
  }
}

MonthlySpending _month(DateTime month, int count, {int categoryId = 1}) =>
    MonthlySpending(
      categoryId: categoryId,
      name: 'Food',
      month: month,
      amountCents: count * 1000,
      transactionCount: count,
    );

void main() {
  // Asked on 13 September 2026: the window is March to August.
  final today = DateTime(2026, 9, 13);
  final window = LookbackWindow.before(today);
  final query = PlanHistoryQuery(window: window, today: today);

  Future<PlanHistory> check(List<MonthlySpending> rows) async {
    final result = await CheckPlanHistory(_FakeReader(Right(rows)))(query);
    return result.getOrElse((f) => throw StateError('$f'));
  }

  test('reads from the window start on to today', () async {
    final reader = _FakeReader(const Right([]));

    await CheckPlanHistory(reader)(query);

    expect(reader.asked, (DateTime(2026, 3), today));
  });

  test('nothing recorded at all is empty, and not enough', () async {
    final history = await check(const []);

    expect(history.isEmpty, isTrue);
    expect(history.isEnough, isFalse);
    expect(history.thisMonthEnds, DateTime(2026, 9, 30));
  });

  test(
    "this month's spending does not count yet, and is counted apart",
    () async {
      final history = await check([_month(DateTime(2026, 9), 25)]);

      expect(history.expenses, 0);
      expect(history.expensesThisMonth, 25);
      expect(history.isEmpty, isFalse);
      expect(history.isEnough, isFalse);
    },
  );

  test('one whole month with ten expenses is enough', () async {
    final history = await check([
      _month(DateTime(2026, 8), 6),
      _month(DateTime(2026, 8), 4, categoryId: 2),
    ]);

    expect(history.expenses, 10);
    expect(history.monthsWithSpending, 1);
    expect(history.isEnough, isTrue);
  });

  test('nine expenses is not, however many months they cover', () async {
    final history = await check([
      _month(DateTime(2026, 6), 3),
      _month(DateTime(2026, 7), 3),
      _month(DateTime(2026, 8), 3),
    ]);

    expect(history.expenses, PlanHistory.minExpenses - 1);
    expect(history.monthsWithSpending, 3);
    expect(history.isEnough, isFalse);
  });

  test('a month before the window is not counted', () async {
    final history = await check([_month(DateTime(2026, 2), 40)]);

    expect(history.expenses, 0);
    expect(history.expensesThisMonth, 0);
  });

  test('a failure reading passes through', () async {
    final result = await CheckPlanHistory(
      _FakeReader(const Left(CacheFailure())),
    )(query);

    expect(result, const Left<Failure, PlanHistory>(CacheFailure()));
  });
}
