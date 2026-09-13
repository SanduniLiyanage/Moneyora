import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/money_plan_repository.dart';

/// Makes a saved plan the one being tracked. FR-PLN-013, FR-PLN-015.
///
/// Whichever plan was active is deactivated in the same transaction, so at
/// most one is ever active — the invariant `money_plans.is_active` states
/// and the repository holds. There is no "deactivate" use case on purpose:
/// a user with no active plan has nothing to track, and choosing another
/// plan is how they stop tracking this one.
class ActivatePlan implements UseCase<Unit, int> {
  /// Creates the use case.
  const ActivatePlan(this._repository);

  final MoneyPlanRepository _repository;

  /// [params] is the plan id.
  @override
  Future<Either<Failure, Unit>> call(int params) =>
      _repository.activate(params);
}
