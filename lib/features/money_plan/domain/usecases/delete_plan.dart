import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/money_plan_repository.dart';

/// Deletes a saved plan. FR-PLN-015.
///
/// Its allocations go with it; the transactions it tracked stay, because
/// they are the user's record and the plan only measured them. Deleting
/// the active plan leaves none active, which the plan screen already
/// answers with its way to make one (E-22).
class DeletePlan implements UseCase<Unit, int> {
  /// Creates the use case.
  const DeletePlan(this._repository);

  final MoneyPlanRepository _repository;

  /// [params] is the plan id.
  @override
  Future<Either<Failure, Unit>> call(int params) => _repository.delete(params);
}
