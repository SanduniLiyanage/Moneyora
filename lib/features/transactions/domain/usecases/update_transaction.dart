import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';
import 'add_transaction.dart';

/// Edits an existing transaction. FR-EXP-006.
///
/// Runs exactly the same validation as [AddTransaction], by calling it rather
/// than restating it. Two copies of a rule set drift, and the copy that drifts
/// is always the one on the path you are not currently testing — an edit
/// screen that accepted a zero amount an entry screen rejects would be a bug
/// nobody thinks to look for.
class UpdateTransaction implements UseCase<Unit, Transaction> {
  /// Creates the use case.
  const UpdateTransaction(this._repository);

  final TransactionRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(Transaction params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    return _repository.update(params);
  }

  /// Returns the reason [transaction] cannot be saved, or null if it can.
  static ValidationFailure? validate(Transaction transaction) {
    if (transaction.id == null) {
      return const ValidationFailure(
        'This transaction has not been saved yet, so there is nothing to '
        'update.',
      );
    }

    // Editing one half of a transfer independently would leave the other half
    // and the header row describing a movement that no longer happened. A
    // transfer is edited as a transfer, through its own screen, or deleted and
    // re-entered — see E-15 on why the three rows move together.
    if (transaction.type == TransactionType.transfer) {
      return const ValidationFailure(
        'A transfer is edited from the transfer itself, not from one side '
        'of it.',
      );
    }

    return AddTransaction.validate(transaction);
  }
}
