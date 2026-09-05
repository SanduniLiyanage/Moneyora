import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/account_repository.dart';

/// Permanently removes an account that has never been used. FR-ACC-003.
///
/// Refuses once anything references it, and says how many. Deleting an account
/// with history would either orphan those rows or take them with it, and both
/// silently change totals the user has already seen - so the answer is to
/// archive instead, which is what the message says.
///
/// The check lives here rather than in the repository because it is a
/// judgement about what the app should permit, not a fact about storage.
class DeleteAccount implements UseCase<Unit, int> {
  /// Creates the use case.
  const DeleteAccount(this._repository);

  final AccountRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(int params) async {
    final counted = await _repository.transactionCount(params);

    return counted.match(Left.new, (count) async {
      if (count > 0) {
        return Left(
          ValidationFailure(
            count == 1
                ? 'This account has one transaction. Archive it instead, so '
                      'the record is kept.'
                : 'This account has $count transactions. Archive it instead, '
                      'so the records are kept.',
          ),
        );
      }
      return _repository.delete(params);
    });
  }
}
