import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/money_plan.dart';
import '../entities/money_plan_draft.dart';
import '../repositories/money_plan_repository.dart';

/// A draft the user accepted, and what to call it. FR-PLN-001, FR-PLN-015.
class SavePlanRequest extends Equatable {
  /// Creates a request.
  const SavePlanRequest({
    required this.draft,
    required this.name,
    this.activate = true,
  });

  /// The generator's proposal, as reviewed.
  final MoneyPlanDraft draft;

  /// The plan's name.
  final String name;

  /// Whether to start tracking it now. True by default: the SDD's last step
  /// is "plan saved & activated — real-time tracking begins", and a plan
  /// the user just built is the one they mean to follow. False keeps
  /// whichever plan is active as it is — FR-PLN-015's "save for later".
  final bool activate;

  @override
  List<Object?> get props => [draft, name, activate];
}

/// Saves a draft as a plan — the first write the feature makes.
/// FR-PLN-001, FR-PLN-015.
///
/// Activation is the repository's job, in the same transaction as the
/// insert: with [SavePlanRequest.activate] the previously active plan is
/// deactivated as this one is written, so there is no moment with none or
/// two. See [MoneyPlanRepository.save].
class SavePlan implements UseCase<int, SavePlanRequest> {
  /// Creates the use case.
  const SavePlan(this._repository);

  final MoneyPlanRepository _repository;

  @override
  Future<Either<Failure, int>> call(SavePlanRequest params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    return _repository.save(
      MoneyPlan.fromDraft(
        params.draft,
        name: params.name.trim(),
        isActive: params.activate,
      ),
    );
  }

  /// Why [request] cannot be saved, or null when it can.
  static ValidationFailure? validate(SavePlanRequest request) {
    if (request.name.trim().isEmpty) {
      return const ValidationFailure('Give the plan a name.', field: 'name');
    }
    if (request.draft.isEmpty) {
      return const ValidationFailure(
        'There is nothing to save: the plan has no allocations.',
        field: 'draft',
      );
    }
    return null;
  }
}
