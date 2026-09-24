import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/budget_alert_evaluation.dart';
import '../entities/money_plan.dart';
import '../entities/plan_allocation.dart';

/// What the app can do with saved plans. FR-PLN-011, FR-PLN-013, FR-PLN-015,
/// FR-SET-007.
///
/// Declared here and implemented in `data/`, so the use cases depend on this
/// and not on sqflite. Every method returns `Either<Failure, T>`; none
/// throws.
abstract interface class MoneyPlanRepository {
  /// Writes [plan] and its allocations as one transaction, returning the
  /// new plan id.
  ///
  /// When [plan.isActive], any plan that was active is deactivated in the
  /// same transaction: at most one plan is active at a time, and the data
  /// layer holds that rather than asking each caller to remember it.
  Future<Either<Failure, int>> save(MoneyPlan plan);

  /// Makes [id] the active plan, deactivating whichever was. Same invariant
  /// as [save], same transaction.
  Future<Either<Failure, Unit>> activate(int id);

  /// Reads one plan with its allocations, or null when there is none.
  Future<Either<Failure, MoneyPlan?>> getById(int id);

  /// The plan whose period ended most recently before [day], or null when
  /// none has. The plan a new one starting on [day] follows — where
  /// FR-PLN-014's carried-over overspend is read from.
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(DateTime day);

  /// The active plan, or null when there is none — re-read after every
  /// database write, since FR-PLN-013's spend against it moves with every
  /// transaction.
  Stream<Either<Failure, MoneyPlan?>> watchActive();

  /// Every saved plan with its allocations, newest first — re-read after
  /// every database write, as [watchActive] is. FR-PLN-015.
  Stream<Either<Failure, List<MoneyPlan>>> watchAll();

  /// Rewrites the allocation figures of [planId]'s rows from [allocations],
  /// matched by category, as one transaction. FR-PLN-011.
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  );

  /// Re-derives every allocation's `spentCents` of [planId] from the
  /// expenses in its period and stores the result. FR-PLN-013, E-18.
  Future<Either<Failure, Unit>> recomputeSpent(int planId);

  /// Stores each of [changes]' levels, as one transaction, on the rows that
  /// still hold the level the change was read from; returns the allocation
  /// ids that moved. FR-SET-007, E-35.
  ///
  /// Compare-and-set, because the plan a change was computed from may be a
  /// stale read: the active plan is re-read after every write, and two
  /// quick expenses can each be evaluated against a read taken before the
  /// other's store. The row moves once; only the caller whose change moved
  /// it may announce the crossing. A row that no longer exists moves
  /// nowhere and is simply not in the answer.
  ///
  /// No change signal: nothing on screen draws this column, and signalling
  /// would re-read every plan watcher for a value none of them shows.
  Future<Either<Failure, Set<int>>> recordAlertLevels(
    List<AlertLevelChange> changes,
  );
}
