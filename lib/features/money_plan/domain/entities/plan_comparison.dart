import 'package:equatable/equatable.dart';

import 'money_plan.dart';
import 'plan_allocation.dart';

/// One category across two plans. FR-PLN-015.
class ComparisonRow extends Equatable {
  /// Creates a row.
  const ComparisonRow({
    required this.categoryId,
    required this.categoryName,
    required this.left,
    required this.right,
  });

  /// The category.
  final int categoryId;

  /// Its display name, from whichever plan has it.
  final String? categoryName;

  /// The first plan's row, or null when it does not budget this category.
  final PlanAllocation? left;

  /// The second plan's row, or null when it does not budget this category.
  final PlanAllocation? right;

  /// [right]'s allocation less [left]'s, a missing side counting as zero:
  /// positive when the second plan gives the category more.
  int get differenceCents =>
      (right?.allocatedCents ?? 0) - (left?.allocatedCents ?? 0);

  @override
  List<Object?> get props => [categoryId, categoryName, left, right];
}

/// Two plans side by side: every category either budgets, in one list.
/// FR-PLN-015.
///
/// The rows are the union of both plans' categories, in the first plan's
/// order and then the second's additions, so a category the left plan has
/// and the right does not still appears — with nothing on the right —
/// rather than silently dropping out of the comparison. Every figure is
/// what the plans hold; nothing is scaled to a common period, because the
/// SRS's own example compares "June Vacation Plan" with "Regular Monthly",
/// which are not the same length, and a reader wants to see what each
/// plan actually allots. The periods are on the header for that reason.
class PlanComparison extends Equatable {
  /// Creates a comparison by hand. Prefer [PlanComparison.of].
  const PlanComparison({
    required this.left,
    required this.right,
    required this.rows,
  });

  /// [left] against [right].
  factory PlanComparison.of(MoneyPlan left, MoneyPlan right) {
    final byId = <int, ComparisonRow>{};
    for (final a in left.allocations) {
      byId[a.categoryId] = ComparisonRow(
        categoryId: a.categoryId,
        categoryName: a.categoryName,
        left: a,
        right: null,
      );
    }
    for (final a in right.allocations) {
      final existing = byId[a.categoryId];
      byId[a.categoryId] = ComparisonRow(
        categoryId: a.categoryId,
        categoryName: existing?.categoryName ?? a.categoryName,
        left: existing?.left,
        right: a,
      );
    }
    return PlanComparison(left: left, right: right, rows: byId.values.toList());
  }

  /// The first plan.
  final MoneyPlan left;

  /// The second plan.
  final MoneyPlan right;

  /// One per category either plan budgets.
  final List<ComparisonRow> rows;

  /// [right]'s total less [left]'s.
  int get totalDifferenceCents =>
      right.totalBudgetCents - left.totalBudgetCents;

  @override
  List<Object?> get props => [left, right, rows];
}
