import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/expense_writer.dart';
import '../entities/transaction.dart';
import '../repositories/transaction_repository.dart';
import 'add_transaction.dart';

/// Fulfils [ExpenseWriter] for the receipt scanner. FR-RCP-009.
///
/// Every expense goes through [AddTransaction.validate] — the same rules a
/// typed expense meets, which is the reason that method is static — and
/// then to the repository as one batch. Validation runs over the whole
/// list before anything is written: a receipt with one bad line is
/// refused whole, so the user fixes the line and confirms again rather
/// than finding the other lines already saved.
///
/// The failure names the line, because "Enter an amount greater than
/// zero" over a twelve-item receipt does not say which one.
class AddExpenses implements ExpenseWriter {
  /// Creates the use case.
  const AddExpenses(this._repository);

  final TransactionRepository _repository;

  @override
  Future<Either<Failure, List<int>>> call(
    List<ExpenseToRecord> expenses,
  ) async {
    if (expenses.isEmpty) {
      return const Left(ValidationFailure('There is nothing to record.'));
    }

    final transactions = <Transaction>[];
    for (final (index, expense) in expenses.indexed) {
      final transaction = toTransaction(expense);
      if (AddTransaction.validate(transaction) case final failure?) {
        return Left(ValidationFailure('Item ${index + 1}: ${failure.message}'));
      }
      transactions.add(transaction);
    }

    return _repository.addAll(transactions);
  }

  /// The entity for [expense]: always an expense, never split, never
  /// recurring.
  static Transaction toTransaction(ExpenseToRecord expense) => Transaction(
    accountId: expense.accountId,
    categoryId: expense.categoryId,
    amountCents: expense.amountCents,
    type: TransactionType.expense,
    date: expense.date,
    time: expense.time,
    note: expense.note,
    receiptScanId: expense.receiptScanId,
    receiptImagePath: expense.receiptImagePath,
  );
}
