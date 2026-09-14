import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/plan_comparison.dart';
import '../repositories/money_plan_repository.dart';

/// Which two plans to put side by side. FR-PLN-015.
class ComparePlansRequest extends Equatable {
  /// Creates a request.
  const ComparePlansRequest({required this.leftId, required this.rightId});

  /// The first plan.
  final int leftId;

  /// The second plan.
  final int rightId;

  @override
  List<Object?> get props => [leftId, rightId];
}

/// Reads two saved plans and lays them side by side. FR-PLN-015.
///
/// The arithmetic is [PlanComparison.of]; this reads the two plans and
/// refuses the cases that are not a comparison — the same plan twice, or a
/// plan that is not there — in its own words, so the screen shows those
/// rather than an empty table.
class ComparePlans implements UseCase<PlanComparison, ComparePlansRequest> {
  /// Creates the use case.
  const ComparePlans(this._repository);

  final MoneyPlanRepository _repository;

  @override
  Future<Either<Failure, PlanComparison>> call(
    ComparePlansRequest params,
  ) async {
    if (params.leftId == params.rightId) {
      return const Left(
        ValidationFailure('Pick two different plans to compare.'),
      );
    }
    final left = await _repository.getById(params.leftId);
    return left.fold(Left.new, (a) async {
      if (a == null) {
        return Left(ValidationFailure('No plan with id ${params.leftId}.'));
      }
      final right = await _repository.getById(params.rightId);
      return right.fold(Left.new, (b) {
        if (b == null) {
          return Left(ValidationFailure('No plan with id ${params.rightId}.'));
        }
        return Right(PlanComparison.of(a, b));
      });
    });
  }
}
