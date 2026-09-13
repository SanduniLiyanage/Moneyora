import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/money_plan.dart';
import '../entities/plan_allocation.dart';

/// What the app can do with saved plans. FR-PLN-011, FR-PLN-013, FR-PLN-015.
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

  /// The active plan, or null when there is none — re-read after every
  /// database write, since FR-PLN-013's spend against it moves with every
  /// transaction.
  Stream<Either<Failure, MoneyPlan?>> watchActive();

  /// Rewrites the allocation figures of [planId]'s rows from [allocations],
  /// matched by category, as one transaction. FR-PLN-011.
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  );
}
