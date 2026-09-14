import 'package:equatable/equatable.dart';

import 'budget_mode.dart';
import 'category_allocation.dart';
import 'category_classification.dart';
import 'lookback_window.dart';
import 'plan_period.dart';

/// What the generator proposes: a plan not yet reviewed or saved.
/// FR-PLN-007, FR-PLN-008.
class MoneyPlanDraft extends Equatable {
  /// Creates a draft.
  const MoneyPlanDraft({
    required this.period,
    required this.lookback,
    required this.mode,
    required this.allocations,
    this.incomeCents,
    this.savingsTargetCents,
    this.carriedFromPlan,
  });

  /// The days the plan is for.
  final PlanPeriod period;

  /// The history it was built from.
  final LookbackWindow lookback;

  /// How the total was decided.
  final BudgetMode mode;

  /// One per category with any spending in the lookback, in the statistics'
  /// order: largest mean first.
  final List<CategoryAllocation> allocations;

  /// Historical income scaled to the period — set under
  /// [BudgetMode.suggested] only, since only that mode reads it.
  final int? incomeCents;

  /// The savings held back from [incomeCents] — under
  /// [BudgetMode.suggested] only.
  final int? savingsTargetCents;

  /// The name of the plan whose carried-over overspend was deducted from
  /// these allocations (FR-PLN-014), or null when none was.
  final String? carriedFromPlan;

  /// Every carried-over deduction added up.
  int get carryOverCents =>
      allocations.fold(0, (sum, a) => sum + a.carryOverCents);

  /// This draft with [allocations] replaced and [carriedFromPlan] set.
  MoneyPlanDraft withCarryOvers(
    List<CategoryAllocation> allocations, {
    required String carriedFromPlan,
  }) => MoneyPlanDraft(
    period: period,
    lookback: lookback,
    mode: mode,
    allocations: allocations,
    incomeCents: incomeCents,
    savingsTargetCents: savingsTargetCents,
    carriedFromPlan: carriedFromPlan,
  );

  /// What the allocations add up to. Under [BudgetMode.total] this is the
  /// user's total exactly.
  int get totalCents =>
      allocations.fold(0, (sum, a) => sum + a.allocationCents);

  /// The Fixed allocations added up.
  int get fixedCents => allocations
      .where((a) => a.type == ExpenseType.fixed)
      .fold(0, (sum, a) => sum + a.allocationCents);

  /// Under [BudgetMode.suggested], what income leaves after savings and the
  /// allocations — non-zero only when there was no non-fixed category to
  /// give it to. Null under the other modes.
  int? get unallocatedCents => incomeCents == null
      ? null
      : incomeCents! - savingsTargetCents! - totalCents;

  /// True when the lookback held no spending at all.
  bool get isEmpty => allocations.isEmpty;

  @override
  List<Object?> get props => [
    period,
    lookback,
    mode,
    allocations,
    incomeCents,
    savingsTargetCents,
    carriedFromPlan,
  ];
}
