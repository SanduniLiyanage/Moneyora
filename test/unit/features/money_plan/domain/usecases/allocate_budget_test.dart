import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/income_reader.dart';
import 'package:moneyora/core/ports/monthly_spending_reader.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_request.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_mode.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan_draft.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/usecases/allocate_budget.dart';
import 'package:moneyora/features/money_plan/domain/usecases/classify_categories.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';

/// The stages beneath are real; only the two ports are scripted, so this
/// proves the whole chain composes and the modes hold their invariants.
class _FakeReader implements MonthlySpendingReader {
  List<MonthlySpending> rows = const [];
  Failure? failWith;

  @override
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    if (failWith case final failure?) return Left(failure);
    return Right(rows);
  }
}

class _FakeIncome implements IncomeReader {
  int income = 0;
  Failure? failWith;
  DateTime? askedFrom;
  DateTime? askedTo;

  @override
  Future<Either<Failure, int>> totalIncome({
    required DateTime from,
    required DateTime to,
  }) async {
    askedFrom = from;
    askedTo = to;
    if (failWith case final failure?) return Left(failure);
    return Right(income);
  }
}

final halfYear = LookbackWindow(months: 6, lastMonth: DateTime(2026, 8));
final september = PlanPeriod.month(2026, 9);

void main() {
  late _FakeReader reader;
  late _FakeIncome income;
  late AllocateBudget allocate;

  setUp(() {
    reader = _FakeReader();
    income = _FakeIncome();
    allocate = AllocateBudget(
      ClassifyCategories(ComputeCategoryStatistics(reader)),
      income,
    );
  });

  /// Six months of [amounts] (oldest first) for a category.
  List<MonthlySpending> series(
    int id,
    String name,
    List<int> amounts, {
    int count = 1,
  }) => [
    for (var i = 0; i < halfYear.months; i++)
      if (amounts[i] > 0)
        MonthlySpending(
          categoryId: id,
          name: name,
          month: halfYear.monthStarts[i],
          amountCents: amounts[i],
          transactionCount: count,
        ),
  ];

  /// Bills: 45,000 flat (Fixed). Food: noisy around 20,000 (Variable).
  /// Car: 10,000 climbing 10% a month (Variable, rising).
  void seedThree() {
    reader.rows = [
      ...series(1, 'Bills', List.filled(6, 4500000)),
      ...series(2, 'Food', [
        1500000,
        2600000,
        1700000,
        2800000,
        1900000,
        2400000,
      ]),
      ...series(3, 'Car', [
        1000000,
        1100000,
        1210000,
        1331000,
        1464000,
        1610000,
      ]),
    ];
  }

  MoneyPlanDraft unwrap(Either<Failure, MoneyPlanDraft> r) =>
      r.fold((f) => fail('unexpected failure: $f'), (d) => d);

  group('unconstrained', () {
    test('one allocation per category, in the statistics order', () async {
      seedThree();

      final draft = unwrap(
        await allocate(
          AllocationRequest(period: september, lookback: halfYear),
        ),
      );

      expect(draft.allocations.map((a) => a.name), ['Bills', 'Food', 'Car']);
      expect(draft.mode, const BudgetMode.unconstrained());
      expect(draft.incomeCents, isNull);
      expect(draft.unallocatedCents, isNull);
    });

    test('Bills gets its flat average, Car its buffer, and the total is '
        'the sum', () async {
      seedThree();

      final draft = unwrap(
        await allocate(
          AllocationRequest(period: september, lookback: halfYear),
        ),
      );
      final byName = {for (final a in draft.allocations) a.name: a};

      expect(byName['Bills']!.type, ExpenseType.fixed);
      expect(byName['Bills']!.allocationCents, 4500000);
      expect(byName['Bills']!.dailyAllowanceCents, 150000);
      expect(byName['Car']!.trendFactor, 1.08);
      expect(
        byName['Car']!.allocationCents,
        (byName['Car']!.baseMonthlyCents * 1.08).round(),
      );
      expect(
        draft.totalCents,
        draft.allocations.fold(0, (s, a) => s + a.allocationCents),
      );
      expect(draft.fixedCents, 4500000);
    });

    test('a quiet lookback is an empty draft, not a failure', () async {
      final draft = unwrap(
        await allocate(
          AllocationRequest(period: september, lookback: halfYear),
        ),
      );

      expect(draft.isEmpty, isTrue);
      expect(draft.totalCents, 0);
    });
  });

  group('Option A — the user sets a total', () {
    test(
      'every allocation is scaled and they sum to the total exactly',
      () async {
        seedThree();
        const total = 10000001; // odd, so rounding has to be dealt with

        final draft = unwrap(
          await allocate(
            AllocationRequest(
              period: september,
              lookback: halfYear,
              mode: const BudgetMode.total(total),
            ),
          ),
        );

        expect(draft.totalCents, total);
        // Proportions are kept: Bills is still the largest, Car the smallest.
        final cents = draft.allocations.map((a) => a.allocationCents).toList();
        expect(cents[0], greaterThan(cents[1]));
        expect(cents[1], greaterThan(cents[2]));
        // And the daily allowances follow the scaled figures.
        for (final a in draft.allocations) {
          expect(a.dailyAllowanceCents, a.allocationCents ~/ 30);
        }
      },
    );

    test('keeps the ratio between categories', () async {
      seedThree();
      final free = unwrap(
        await allocate(
          AllocationRequest(period: september, lookback: halfYear),
        ),
      );
      final scaled = unwrap(
        await allocate(
          AllocationRequest(
            period: september,
            lookback: halfYear,
            mode: BudgetMode.total(free.totalCents * 2),
          ),
        ),
      );

      for (var i = 0; i < free.allocations.length; i++) {
        expect(
          scaled.allocations[i].allocationCents,
          free.allocations[i].allocationCents * 2,
        );
      }
    });

    test('a zero total zeroes everything', () async {
      seedThree();

      final draft = unwrap(
        await allocate(
          AllocationRequest(
            period: september,
            lookback: halfYear,
            mode: const BudgetMode.total(0),
          ),
        ),
      );

      expect(draft.allocations.every((a) => a.allocationCents == 0), isTrue);
      expect(draft.totalCents, 0);
    });

    test('refuses a total with no history to share it across', () async {
      final result = await allocate(
        AllocationRequest(
          period: september,
          lookback: halfYear,
          mode: const BudgetMode.total(500000),
        ),
      );

      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('should have refused'),
      );
    });

    test('refuses a negative total before reading anything', () async {
      final result = await allocate(
        AllocationRequest(
          period: september,
          lookback: halfYear,
          mode: const BudgetMode.total(-1),
        ),
      );

      result.fold(
        (f) => expect((f as ValidationFailure).field, 'total'),
        (_) => fail('should have refused'),
      );
    });
  });

  group('Option B — the app suggests a total', () {
    test('income for the lookback, scaled to the period, less savings, less '
        'fixed costs, shared among the rest', () async {
      seedThree();
      income.income = 6 * 18000000; // Rs 180,000 a month for six months

      final draft = unwrap(
        await allocate(
          AllocationRequest(
            period: september,
            lookback: halfYear,
            mode: const BudgetMode.suggested(savingsTargetPct: 10),
          ),
        ),
      );
      final byName = {for (final a in draft.allocations) a.name: a};

      expect(income.askedFrom, halfYear.from);
      expect(income.askedTo, halfYear.to);
      expect(draft.incomeCents, 18000000);
      expect(draft.savingsTargetCents, 1800000);
      // Fixed at face value.
      expect(byName['Bills']!.allocationCents, 4500000);
      // The rest fills income − savings − fixed exactly.
      const discretionary = 18000000 - 1800000 - 4500000;
      expect(
        byName['Food']!.allocationCents + byName['Car']!.allocationCents,
        discretionary,
      );
      expect(draft.totalCents, 18000000 - 1800000);
      expect(draft.unallocatedCents, 0);
    });

    test('non-fixed categories keep their proportions to each other', () async {
      seedThree();
      income.income = 6 * 18000000;
      final free = unwrap(
        await allocate(
          AllocationRequest(period: september, lookback: halfYear),
        ),
      );
      final suggested = unwrap(
        await allocate(
          AllocationRequest(
            period: september,
            lookback: halfYear,
            mode: const BudgetMode.suggested(savingsTargetPct: 10),
          ),
        ),
      );
      int of(MoneyPlanDraft d, String name) =>
          d.allocations.firstWhere((a) => a.name == name).allocationCents;

      expect(
        of(suggested, 'Food') / of(suggested, 'Car'),
        closeTo(of(free, 'Food') / of(free, 'Car'), 0.001),
      );
    });

    test('a week is budgeted against a week of income', () async {
      seedThree();
      income.income = 6 * 18000000;
      final week = PlanPeriod(
        from: DateTime(2026, 9, 7),
        to: DateTime(2026, 9, 13),
      );

      final draft = unwrap(
        await allocate(
          AllocationRequest(
            period: week,
            lookback: halfYear,
            mode: const BudgetMode.suggested(savingsTargetPct: 0),
          ),
        ),
      );

      expect(draft.incomeCents, (18000000 * 7 / 30).round());
      expect(draft.savingsTargetCents, 0);
    });

    test('refuses when fixed costs and savings exceed income', () async {
      seedThree();
      income.income = 6 * 4000000; // less than the rent

      final result = await allocate(
        AllocationRequest(
          period: september,
          lookback: halfYear,
          mode: const BudgetMode.suggested(savingsTargetPct: 20),
        ),
      );

      result.fold(
        (f) => expect(f, isA<ValidationFailure>()),
        (_) => fail('should have refused'),
      );
    });

    test(
      'with no non-fixed category the leftover is reported, not lost',
      () async {
        reader.rows = series(1, 'Bills', List.filled(6, 4500000));
        income.income = 6 * 10000000;

        final draft = unwrap(
          await allocate(
            AllocationRequest(
              period: september,
              lookback: halfYear,
              mode: const BudgetMode.suggested(savingsTargetPct: 10),
            ),
          ),
        );

        expect(draft.totalCents, 4500000);
        expect(draft.unallocatedCents, 10000000 - 1000000 - 4500000);
      },
    );

    test('refuses a savings target outside 0–100 before reading', () async {
      final result = await allocate(
        AllocationRequest(
          period: september,
          lookback: halfYear,
          mode: const BudgetMode.suggested(savingsTargetPct: 101),
        ),
      );

      result.fold(
        (f) => expect((f as ValidationFailure).field, 'savingsTargetPct'),
        (_) => fail('should have refused'),
      );
      expect(income.askedFrom, isNull);
    });

    test('a failure reading income passes through', () async {
      seedThree();
      income.failWith = const CacheFailure('disk is full');

      final result = await allocate(
        AllocationRequest(
          period: september,
          lookback: halfYear,
          mode: const BudgetMode.suggested(savingsTargetPct: 10),
        ),
      );

      expect(
        result,
        const Left<Failure, MoneyPlanDraft>(CacheFailure('disk is full')),
      );
    });
  });

  group('validation and failures', () {
    test('refuses an inverted period', () async {
      final result = await allocate(
        AllocationRequest(
          period: PlanPeriod(
            from: DateTime(2026, 9, 30),
            to: DateTime(2026, 9),
          ),
          lookback: halfYear,
        ),
      );

      result.fold(
        (f) => expect((f as ValidationFailure).field, 'period'),
        (_) => fail('should have refused'),
      );
    });

    test('refuses a lookback the statistics stage refuses', () async {
      final result = await allocate(
        AllocationRequest(
          period: september,
          lookback: LookbackWindow(months: 0, lastMonth: DateTime(2026, 8)),
        ),
      );

      result.fold(
        (f) => expect((f as ValidationFailure).field, 'months'),
        (_) => fail('should have refused'),
      );
    });

    test('a failure from the spending read passes through', () async {
      reader.failWith = const CacheFailure('disk is full');

      final result = await allocate(
        AllocationRequest(period: september, lookback: halfYear),
      );

      expect(
        result,
        const Left<Failure, MoneyPlanDraft>(CacheFailure('disk is full')),
      );
    });
  });
}
