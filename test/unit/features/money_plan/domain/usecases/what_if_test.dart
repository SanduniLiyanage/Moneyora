import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/usecases/what_if.dart';

PlanAllocation _row(int id, int cents) => PlanAllocation(
  categoryId: id,
  allocatedCents: cents,
  confidence: ConfidenceLevel.medium,
);

void main() {
  final plan = MoneyPlan(
    id: 1,
    name: 'September',
    period: PlanPeriod.month(2026, 9),
    totalBudgetCents: 1000,
    allocations: [_row(1, 500), _row(2, 300), _row(3, 200)],
  );

  test('reducing A by a fifth frees a fifth of A, all of it for B', () {
    final result = WhatIf.reduce(
      plan,
      fromCategoryId: 1,
      toCategoryId: 2,
      percent: 20,
    )!;

    expect(result.freedCents, 100);
    expect(result.reducedFromCents, 500);
    expect(result.reducedToCents, 400);
    expect(result.raisedFromCents, 300);
    expect(result.raisedToCents, 400);
  });

  test('the third category is not touched: the total is held between A and '
      'B alone', () {
    // 400 + 400 + 200 = 1000: C stayed at 200.
    final result = WhatIf.reduce(
      plan,
      fromCategoryId: 1,
      toCategoryId: 2,
      percent: 20,
    )!;

    expect(result.reducedToCents + result.raisedToCents + 200, 1000);
  });

  test('a whole reduction moves everything', () {
    final result = WhatIf.reduce(
      plan,
      fromCategoryId: 3,
      toCategoryId: 1,
      percent: 100,
    )!;

    expect(result.reducedToCents, 0);
    expect(result.raisedToCents, 700);
  });

  test('nothing reduced is nothing moved', () {
    final result = WhatIf.reduce(
      plan,
      fromCategoryId: 1,
      toCategoryId: 2,
      percent: 0,
    )!;

    expect(result.freedCents, 0);
    expect(result.raisedToCents, 300);
  });

  test('rounds the reduction to the cent', () {
    // 500 × 33% = 165.
    final result = WhatIf.reduce(
      plan,
      fromCategoryId: 1,
      toCategoryId: 2,
      percent: 33,
    )!;

    expect(result.freedCents, 165);
    expect(result.raisedToCents, 465);
  });

  test('is null for the same category twice, or one not in the plan', () {
    expect(
      WhatIf.reduce(plan, fromCategoryId: 1, toCategoryId: 1, percent: 10),
      isNull,
    );
    expect(
      WhatIf.reduce(plan, fromCategoryId: 9, toCategoryId: 1, percent: 10),
      isNull,
    );
    expect(
      WhatIf.reduce(plan, fromCategoryId: 1, toCategoryId: 9, percent: 10),
      isNull,
    );
  });

  test('does not change the plan it was asked about', () {
    WhatIf.reduce(plan, fromCategoryId: 1, toCategoryId: 2, percent: 50);

    expect(plan.allocations.map((a) => a.allocatedCents), [500, 300, 200]);
    expect(plan.allocations.every((a) => !a.isUserModified), isTrue);
  });
}
