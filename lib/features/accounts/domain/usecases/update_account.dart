import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/account.dart';
import '../repositories/account_repository.dart';
import 'add_account.dart';

/// Edits an existing account. FR-ACC-002.
///
/// Runs [AddAccount.validate] by calling it rather than restating it, for the
/// same reason `UpdateTransaction` does: two copies of a rule set drift, and
/// the copy that drifts is always the one on the path nobody is testing.
class UpdateAccount implements UseCase<Unit, Account> {
  /// Creates the use case.
  const UpdateAccount(this._repository);

  final AccountRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(Account params) async {
    if (params.id == null) {
      return const Left(
        ValidationFailure('This account has not been saved yet.'),
      );
    }

    final failure = AddAccount.validate(params);
    if (failure != null) return Left(failure);

    return _repository.update(params);
  }
}
