import 'package:equatable/equatable.dart';

import 'money_plan_draft.dart';
import 'plan_allocation.dart';
import 'plan_period.dart';

/// A saved plan. FR-PLN-001, FR-PLN-013, FR-PLN-015.
///
/// What `money_plans` holds, with its `plan_allocations`. A
/// [MoneyPlanDraft] becomes one of these on save ([fromDraft]) and loses
/// its statistics on the way: the plan is the decision the user accepted,
/// and the evidence behind it is re-derived from history whenever a new one
/// is generated.
class MoneyPlan extends Equatable {
  /// Creates a plan.
  const MoneyPlan({
    required this.name,
    required this.period,
    required this.totalBudgetCents,
    required this.allocations,
    this.id,
    this.isActive = false,
  });

  /// The draft the user accepted, named and ready to save.
  ///
  /// The total is what the allocations add up to — under Option A the user's
  /// total exactly, under Option B income less savings, otherwise the sum —
  /// so `money_plans.total_budget_cents` is never out of step with its rows.
  factory MoneyPlan.fromDraft(
    MoneyPlanDraft draft, {
    required String name,
    bool isActive = false,
  }) => MoneyPlan(
    name: name,
    period: draft.period,
    totalBudgetCents: draft.totalCents,
    isActive: isActive,
    allocations: [
      for (final a in draft.allocations)
        PlanAllocation(
          categoryId: a.categoryId,
          categoryName: a.name,
          allocatedCents: a.allocationCents,
          confidence: a.confidence.level,
          expenseType: a.type,
        ),
    ],
  );

  /// Row id, null until saved.
  final int? id;

  /// What the user called it — "October", "Holiday month".
  final String name;

  /// The days it covers, and which of FR-PLN-002's shapes it was chosen as.
  final PlanPeriod period;

  /// What the allocations add up to.
  final int totalBudgetCents;

  /// True for the one plan being tracked (FR-PLN-013). At most one plan is
  /// active at a time; the data layer holds that invariant on every write.
  final bool isActive;

  /// One row per category, in the order they were saved.
  final List<PlanAllocation> allocations;

  /// The allocations added up — equal to [totalBudgetCents] on any plan the
  /// data layer has written, since every write holds the total.
  int get allocatedCents =>
      allocations.fold(0, (sum, a) => sum + a.allocatedCents);

  @override
  List<Object?> get props => [
    id,
    name,
    period,
    totalBudgetCents,
    isActive,
    allocations,
  ];
}
