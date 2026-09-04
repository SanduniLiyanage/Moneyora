import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/transaction_repository.dart';

/// Removes a transaction. FR-EXP-006.
///
/// Deleting either half of a transfer removes the whole transfer — both halves
/// and the header — because half a transfer is not something the rest of the
/// app can read. That rule lives in the datasource, where the three rows are,
/// rather than being reimplemented here.
///
/// **Undo is not implemented yet.** E-23 records the gap and specifies the
/// answer: a five-second snackbar, implemented by *deferring* the write rather
/// than deleting and re-inserting, since a re-inserted row takes a new id and
/// orphans the split parts that cascaded away with it. The undo window belongs
/// in the presentation layer, above this use case, so this stays the operation
/// that actually commits.
class DeleteTransaction implements UseCase<Unit, int> {
  /// Creates the use case.
  const DeleteTransaction(this._repository);

  final TransactionRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(int params) async {
    if (params <= 0) {
      // Ids come from the database and are always positive, so a zero or
      // negative one means a caller passed a placeholder rather than a row.
      return const Left(ValidationFailure('That is not a saved transaction.'));
    }
    return _repository.delete(params);
  }
}
