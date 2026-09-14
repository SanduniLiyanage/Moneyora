import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/money_plan.dart';
import '../repositories/money_plan_repository.dart';

/// Watches every saved plan, newest first. FR-PLN-015.
///
/// A stream, like [WatchActivePlan] and for the same reason: the list says
/// which plan is active, and activation is a write on the shared bus, so a
/// list that re-reads on it shows the switch without being told to.
class WatchPlans implements StreamUseCase<List<MoneyPlan>, NoParams> {
  /// Creates the use case.
  const WatchPlans(this._repository);

  final MoneyPlanRepository _repository;

  @override
  Stream<Either<Failure, List<MoneyPlan>>> call(NoParams params) =>
      _repository.watchAll();
}
