import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/money_plan_repository.dart';

/// A plan and the name it should have. FR-PLN-015.
class RenamePlanRequest extends Equatable {
  /// Creates a request.
  const RenamePlanRequest({required this.planId, required this.name});

  /// The saved plan.
  final int planId;

  /// Its new name, as typed.
  final String name;

  @override
  List<Object?> get props => [planId, name];
}

/// Renames a saved plan, by the rule a new one is named by. FR-PLN-015.
class RenamePlan implements UseCase<Unit, RenamePlanRequest> {
  /// Creates the use case.
  const RenamePlan(this._repository);

  final MoneyPlanRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(RenamePlanRequest params) async {
    final name = params.name.trim();
    if (name.isEmpty) {
      return const Left(
        ValidationFailure('Give the plan a name.', field: 'name'),
      );
    }
    return _repository.rename(params.planId, name);
  }
}
