import 'package:equatable/equatable.dart';

import 'allocation_progress.dart';
import 'budget_alert_level.dart';
import 'money_plan.dart';
import 'plan_allocation.dart';

/// One category that has just crossed a threshold. FR-SET-007.
class BudgetAlert extends Equatable {
  /// Creates an alert.
  const BudgetAlert({
    required this.allocationId,
    required this.categoryName,
    required this.level,
    required this.percentUsed,
  });

  /// The `plan_allocations` row it is about.
  final int allocationId;

  /// The category's name, as the row was read with it.
  final String categoryName;

  /// The threshold crossed — the higher one, when a single expense crossed
  /// both.
  final BudgetAlertLevel level;

  /// Whole percent spent, floored, as the tracking bar shows it.
  final int percentUsed;

  @override
  List<Object?> get props => [allocationId, categoryName, level, percentUsed];
}

/// One allocation's stored level moving from [from] to [to]. FR-SET-007,
/// E-35.
///
/// Carries what the evaluation *read* as well as what it decided, so the
/// store can refuse a change made from a stale read: the row moves only if
/// it still holds [from]. Two evaluations of the same crossing — two quick
/// expenses whose plan reads both land before either store — then move the
/// row once, and only the one that moved it announces anything.
class AlertLevelChange extends Equatable {
  /// Creates a change.
  const AlertLevelChange({
    required this.allocationId,
    required this.from,
    required this.to,
  });

  /// The `plan_allocations` row.
  final int allocationId;

  /// The level the evaluation read on the row.
  final BudgetAlertLevel from;

  /// The level to store.
  final BudgetAlertLevel to;

  @override
  List<Object?> get props => [allocationId, from, to];
}

/// What FR-SET-007 has to say about a plan, and what to remember having
/// said. Pure: no clock, no database, no platform.
///
/// Every allocation's current level is read from FR-PLN-013's own bands
/// ([AllocationProgress.statusOf]), so an alert and the row's colour cannot
/// disagree: 80% is yellow and a warning, 100% is red and an alert.
///
/// Compared with [PlanAllocation.alertedLevel], the level last announced:
///
/// - **Higher** — the row has crossed a threshold since it was last
///   announced. One alert, at the level it is now: a single expense that
///   takes a row from 70% to 110% is one alert that it is over, not a
///   warning followed a moment later by the thing it warned of.
/// - **Lower** — an edit or a delete took the row back under a threshold.
///   Nothing is said, and the stored level follows it down, so crossing the
///   threshold again is announced again. It is a new crossing.
/// - **The same** — nothing.
///
/// A plan activated while already past a threshold has nothing announced
/// yet, so its first evaluation announces it — once, which is what the
/// stored level is for.
class BudgetAlertEvaluation extends Equatable {
  /// Creates an evaluation by hand. Prefer [BudgetAlertEvaluation.of].
  const BudgetAlertEvaluation({required this.alerts, required this.changes});

  /// Evaluates every saved allocation of [plan].
  ///
  /// An allocation with no id has never been written, has no stored level
  /// to compare against and no row to store one on, and is skipped; the
  /// data layer never hands one back from a saved plan.
  factory BudgetAlertEvaluation.of(MoneyPlan plan) {
    final alerts = <BudgetAlert>[];
    final changes = <AlertLevelChange>[];

    for (final allocation in plan.allocations) {
      final id = allocation.id;
      if (id == null) continue;

      final current = levelOf(allocation);
      if (current == allocation.alertedLevel) continue;

      changes.add(
        AlertLevelChange(
          allocationId: id,
          from: allocation.alertedLevel,
          to: current,
        ),
      );
      if (current.isAbove(allocation.alertedLevel)) {
        alerts.add(
          BudgetAlert(
            allocationId: id,
            categoryName: allocation.categoryName ?? 'A category',
            level: current,
            percentUsed: AllocationProgress.percentOf(
              spentCents: allocation.spentCents,
              allocatedCents: allocation.allocatedCents,
            ),
          ),
        );
      }
    }

    return BudgetAlertEvaluation(alerts: alerts, changes: changes);
  }

  /// The level [allocation]'s spend is at now, from FR-PLN-013's bands.
  static BudgetAlertLevel levelOf(PlanAllocation allocation) =>
      switch (AllocationProgress.statusOf(
        spentCents: allocation.spentCents,
        allocatedCents: allocation.allocatedCents,
      )) {
        TrackingStatus.onTrack => BudgetAlertLevel.none,
        TrackingStatus.warning => BudgetAlertLevel.warning,
        TrackingStatus.exceeded => BudgetAlertLevel.exceeded,
      };

  /// The thresholds crossed upward, in the plan's row order.
  final List<BudgetAlert> alerts;

  /// Every allocation whose stored level is out of date — upward crossings
  /// and falls alike — in the plan's row order. Empty when nothing moved,
  /// which is most evaluations: every transaction write re-reads the plan.
  final List<AlertLevelChange> changes;

  /// [changes] as the level to store, by allocation id.
  Map<int, BudgetAlertLevel> get levels => {
    for (final c in changes) c.allocationId: c.to,
  };

  /// Whether there is anything to store.
  bool get isUnchanged => changes.isEmpty;

  @override
  List<Object?> get props => [alerts, changes];
}
