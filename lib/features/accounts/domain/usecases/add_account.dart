import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/account.dart';
import '../repositories/account_repository.dart';

/// Creates an account. FR-ACC-001.
class AddAccount implements UseCase<int, Account> {
  /// Creates the use case.
  const AddAccount(this._repository);

  final AccountRepository _repository;

  @override
  Future<Either<Failure, int>> call(Account params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    return _repository.add(params);
  }

  /// Returns the reason [account] cannot be saved, or null if it can.
  ///
  /// Public and static so a form can check as the user types, rather than
  /// letting them fill everything in and then refusing at the end.
  static ValidationFailure? validate(Account account) {
    if (account.name.trim().isEmpty) {
      return const ValidationFailure('Give the account a name.', field: 'name');
    }

    if (account.name.trim().length > 40) {
      // Long enough for "Commercial Bank savings", short enough that the
      // account list stays readable at a phone width.
      return const ValidationFailure(
        'That name is too long - 40 characters at most.',
        field: 'name',
      );
    }

    if (account.currency.length != 3) {
      return const ValidationFailure(
        'Use a three-letter currency code, like LKR.',
        field: 'currency',
      );
    }

    if (account.initialBalanceDate.isAfter(
      DateTime.now().add(const Duration(days: 1)),
    )) {
      return const ValidationFailure(
        'An opening balance cannot be dated in the future.',
        field: 'initialBalanceDate',
      );
    }

    // initialBalanceCents is deliberately unchecked for sign. A credit card
    // opens owing money, so a negative opening balance is ordinary rather
    // than suspicious - unlike a transaction amount, which never is.
    return null;
  }
}
