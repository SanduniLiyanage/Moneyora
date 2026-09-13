import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/money_plan.dart';
import '../repositories/money_plan_repository.dart';

/// Watches the active plan, or the absence of one. FR-PLN-013.
///
/// A stream rather than a read, the way `WatchAccounts` is: the active plan
/// is what live tracking draws, and its spend moves whenever any
/// transaction is written. The shared change bus fires on those writes too,
/// so a tracking screen re-reads without polling.
class WatchActivePlan implements StreamUseCase<MoneyPlan?, NoParams> {
  /// Creates the use case.
  const WatchActivePlan(this._repository);

  final MoneyPlanRepository _repository;

  @override
  Stream<Either<Failure, MoneyPlan?>> call(NoParams params) =>
      _repository.watchActive();
}
