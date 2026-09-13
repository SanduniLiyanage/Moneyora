import 'package:equatable/equatable.dart';

/// How a plan's total is decided. FR-PLN-008.
///
/// Three, not two: the SRS's Phase 3 and the DBD's nullable
/// `money_plans.total_budget` both name the unconstrained case — "no
/// constraint: sum of allocations" — and both of FR-PLN-008's options build
/// on it.
sealed class BudgetMode extends Equatable {
  const BudgetMode();

  /// No total: the plan is what the history says, added up.
  const factory BudgetMode.unconstrained() = UnconstrainedBudget;

  /// Option A: the user sets [totalCents] and every allocation is scaled
  /// proportionally so they add up to it exactly.
  const factory BudgetMode.total(int totalCents) = UserTotalBudget;

  /// Option B: the app suggests a total — historical income, less fixed
  /// expenses, less a savings target of [savingsTargetPct] percent of
  /// income (FR-SET-008) — and the non-fixed categories share what is
  /// left.
  const factory BudgetMode.suggested({required double savingsTargetPct}) =
      SuggestedBudget;
}

/// See [BudgetMode.unconstrained].
class UnconstrainedBudget extends BudgetMode {
  /// Creates the mode.
  const UnconstrainedBudget();

  @override
  List<Object?> get props => const [];
}

/// See [BudgetMode.total].
class UserTotalBudget extends BudgetMode {
  /// Creates the mode.
  const UserTotalBudget(this.totalCents);

  /// The total every allocation must add up to.
  final int totalCents;

  @override
  List<Object?> get props => [totalCents];
}

/// See [BudgetMode.suggested].
class SuggestedBudget extends BudgetMode {
  /// Creates the mode.
  const SuggestedBudget({required this.savingsTargetPct});

  /// Percent of income to hold back, 0–100.
  final double savingsTargetPct;

  @override
  List<Object?> get props => [savingsTargetPct];
}
