import 'package:equatable/equatable.dart';

import '../entities/money_plan.dart';
import '../entities/plan_allocation.dart';
import 'update_allocation.dart';

/// The answer to "if I reduce A by X%, how much more can go to B?".
/// FR-PLN-012.
class WhatIfResult extends Equatable {
  /// Creates a result.
  const WhatIfResult({
    required this.freedCents,
    required this.reducedFromCents,
    required this.reducedToCents,
    required this.raisedFromCents,
    required this.raisedToCents,
  });

  /// What the reduction frees — all of which B could take.
  final int freedCents;

  /// A before.
  final int reducedFromCents;

  /// A after.
  final int reducedToCents;

  /// B before.
  final int raisedFromCents;

  /// B after, with all of [freedCents].
  final int raisedToCents;

  @override
  List<Object?> get props => [
    freedCents,
    reducedFromCents,
    reducedToCents,
    raisedFromCents,
    raisedToCents,
  ];
}

/// A scenario over a saved plan, answered without writing it. FR-PLN-012.
///
/// Preview only, on purpose. The requirement is a question — how much
/// *can* go to B — and answering it is not the same as doing it: moving the
/// freed cents from A to B while holding every other row is not a single
/// `UpdateAllocation` (which spreads a change proportionally across the
/// untouched rows). The user acts on the answer through FR-PLN-011.
///
/// The arithmetic is [UpdateAllocation.rebalance]'s, with every row but B
/// treated as held — so B is the only row that can absorb A's reduction,
/// and the total is held exactly.
class WhatIf {
  WhatIf._();

  /// A's allocation cut by [percent] (0–100), with B taking the difference.
  /// Null when either category is not in [plan], or the two are the same.
  static WhatIfResult? reduce(
    MoneyPlan plan, {
    required int fromCategoryId,
    required int toCategoryId,
    required double percent,
  }) {
    if (fromCategoryId == toCategoryId) return null;
    final from = _find(plan.allocations, fromCategoryId);
    final to = _find(plan.allocations, toCategoryId);
    if (from == null || to == null) return null;

    final reducedTo = (from.allocatedCents * (100 - percent) / 100).round();
    final held = [
      for (final a in plan.allocations)
        a.categoryId == toCategoryId
            ? a
            : a.withAllocated(a.allocatedCents, byUser: true),
    ];
    final after = UpdateAllocation.rebalance(
      held,
      categoryId: fromCategoryId,
      allocatedCents: reducedTo,
      totalCents: plan.totalBudgetCents,
    );
    final raisedTo = _find(after, toCategoryId)!.allocatedCents;

    return WhatIfResult(
      freedCents: from.allocatedCents - reducedTo,
      reducedFromCents: from.allocatedCents,
      reducedToCents: reducedTo,
      raisedFromCents: to.allocatedCents,
      raisedToCents: raisedTo,
    );
  }

  static PlanAllocation? _find(List<PlanAllocation> rows, int categoryId) {
    for (final a in rows) {
      if (a.categoryId == categoryId) return a;
    }
    return null;
  }
}
