import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/money_plan_repository.dart';

/// Re-derives a plan's spend per category from history. FR-PLN-013, E-18.
///
/// `plan_allocations.spent_amount_cents` is a cache, kept by the
/// transactions datasource inside the same database transaction as every
/// expense that moves it — the rule E-18 sets for account balances, and the
/// reason the figure on the plan screen can be trusted. This is the repair
/// for drift that arrives from outside those writes: a plan activated after
/// expenses in its period were already recorded, a restored backup, a
/// database edited by hand.
///
/// The data layer already recounts on its own when a plan becomes active,
/// so a plan saved mid-period counts what was already in it. This use case
/// is the reachable repair for everything else, called from the plan list
/// (FR-PLN-015) and, once Sprint 8 builds one, the restore path — the same
/// two places `RecomputeAllAccountBalances` is reached from, for the same
/// reason. Not on launch: a recount is `O(expenses in the period)`, and
/// NFR-PER-001 is why nothing scans history on the cold-start path.
class RecomputePlanSpending implements UseCase<Unit, int> {
  /// Creates the use case.
  const RecomputePlanSpending(this._repository);

  final MoneyPlanRepository _repository;

  /// [params] is the plan id.
  @override
  Future<Either<Failure, Unit>> call(int params) =>
      _repository.recomputeSpent(params);
}
