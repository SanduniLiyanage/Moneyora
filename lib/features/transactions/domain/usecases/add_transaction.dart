import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';

/// Records a new expense or income. FR-EXP-001, FR-INC-001.
///
/// Validation lives here rather than in the widget or the datasource, and it
/// is worth saying why, because both alternatives are tempting.
///
/// In a widget it would run only on the path a user happens to take: a
/// transaction arriving from a receipt scan (FR-RCP-009) or a recurring rule
/// (FR-EXP-008) would skip every check. In the datasource it would be
/// unreachable without a database.
///
/// Here it runs for every caller and is testable with a fake repository.
///
/// The schema enforces the same invariants with `CHECK` constraints, which is
/// not duplication — that is the last line of defence and produces a SQLite
/// error. This produces a [ValidationFailure] a screen can render.
class AddTransaction implements UseCase<int, Transaction> {
  /// Creates the use case.
  const AddTransaction(this._repository);

  final TransactionRepository _repository;

  @override
  Future<Either<Failure, int>> call(Transaction params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    return _repository.add(params);
  }

  /// Returns the reason [transaction] is invalid, or null if it is fine.
  ///
  /// Public and static so the entry screen can check as the user types without
  /// attempting a save — the same rules, one implementation.
  static ValidationFailure? validate(Transaction transaction) {
    if (transaction.amountCents <= 0) {
      // Zero is rejected as well as negative. A zero-amount transaction is
      // almost always a half-finished entry, and silently storing one leaves
      // a row that pollutes averages while looking harmless.
      return const ValidationFailure('Enter an amount greater than zero.');
    }

    // E-17: a transfer has no category; everything else must have one.
    if (transaction.type == TransactionType.transfer) {
      if (transaction.categoryId != null) {
        return const ValidationFailure(
          'A transfer moves money between your own accounts, so it has no '
          'category.',
        );
      }
      if (transaction.transferDirection == null) {
        // E-16: without this nothing on the row says which way money moved.
        return const ValidationFailure(
          'A transfer must record whether money left or arrived.',
        );
      }
    } else {
      if (transaction.categoryId == null) {
        return const ValidationFailure('Choose a category.');
      }
      if (transaction.transferDirection != null) {
        return const ValidationFailure('Only transfers carry a direction.');
      }
    }

    // E-04: SQLite cannot express "children must sum to parent", so this is
    // the only place the invariant is enforced.
    if (transaction.isSplit) {
      if (transaction.splits.any((s) => s.amountCents <= 0)) {
        return const ValidationFailure(
          'Every part of a split must be greater than zero.',
        );
      }
      if (transaction.splitTotalCents != transaction.amountCents) {
        final difference =
            transaction.amountCents - transaction.splitTotalCents;
        return ValidationFailure(
          difference > 0
              ? 'The split is short by $difference cents.'
              : 'The split exceeds the total by ${-difference} cents.',
        );
      }
      if (transaction.type == TransactionType.transfer) {
        return const ValidationFailure('A transfer cannot be split.');
      }
    }

    if (transaction.date.isAfter(DateTime.now().add(const Duration(days: 1)))) {
      // A day of slack, because a device clock in another time zone is a
      // legitimate reason for a date to look like tomorrow. A month ahead is
      // a typo.
      return const ValidationFailure('That date is in the future.');
    }

    return null;
  }
}
