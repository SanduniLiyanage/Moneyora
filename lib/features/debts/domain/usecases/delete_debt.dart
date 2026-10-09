import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/debt_repository.dart';

/// Removes a debt for good. FR-DBT-003.
///
/// For one recorded by mistake. A debt that was settled is marked paid
/// instead, which keeps it in the list's history.
class DeleteDebt implements UseCase<Unit, int> {
  /// Creates the use case.
  const DeleteDebt(this._repository);

  final DebtRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(int params) => _repository.delete(params);
}
