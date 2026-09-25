/// The ledger's shared write path: one row in, its parts, and the caches it
/// moves.
///
/// Two datasources write transactions — `TransactionLocalDataSourceImpl`
/// for the entries a user types, `RecurringRuleLocalDataSourceImpl` for the
/// ones a rule posts — and both must move `accounts.current_balance_cents`
/// (E-18) and `plan_allocations.spent_amount_cents` (FR-PLN-013) exactly the
/// same way, inside whatever database transaction they are writing in. A
/// second copy of this arithmetic would be a second place for a balance to
/// drift, so there is one, here, and every method takes the transaction it
/// runs in rather than opening its own.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/transaction.dart';
import '../models/transaction_model.dart';

/// Writes and reads single ledger rows inside a caller's transaction.
abstract final class LedgerWriter {
  /// Writes one non-transfer row with its parts and cache moves, returning
  /// its id. Always inside a transaction — the caller's.
  static Future<int> insert(
    DatabaseExecutor txn,
    TransactionModel transaction,
  ) async {
    final rowId = await txn.insert('transactions', transaction.toMap());
    await writeSplits(txn, transaction, rowId);
    await applyBalance(txn, transaction.accountId, delta(transaction));
    await applyPlanSpend(txn, transaction, sign: 1);
    return rowId;
  }

  /// Writes [transaction]'s split parts under [parentId]. A no-op for the
  /// unsplit case, which must stay a single insert (E-04).
  static Future<void> writeSplits(
    DatabaseExecutor txn,
    TransactionModel transaction,
    int parentId,
  ) async {
    if (transaction.splits.isEmpty) return;

    for (final row in transaction.splitMaps(parentId)) {
      await txn.insert('transaction_splits', row);
    }
  }

  /// Moves the cached balance on [accountId] by [deltaCents].
  ///
  /// Always called from inside a transaction, never on its own (E-18). The
  /// arithmetic is exact because the column is `INTEGER` cents (E-06);
  /// repeated increment of a `REAL` would drift.
  static Future<void> applyBalance(
    DatabaseExecutor txn,
    int accountId,
    int deltaCents,
  ) async {
    if (deltaCents == 0) return;
    await txn.rawUpdate(
      'UPDATE accounts SET current_balance_cents = current_balance_cents + ? '
      'WHERE id = ?',
      [deltaCents, accountId],
    );
  }

  /// Moves the active plan's `spent_amount_cents` by what [transaction]
  /// spends, times [sign] (`1` to apply, `-1` to reverse). FR-PLN-013.
  ///
  /// Always called from inside the transaction that writes the row, never on
  /// its own — the same rule as [applyBalance] and for the same reason
  /// (E-18): a second call is a call something can skip, and eventual
  /// consistency here is a plan screen that says "on track" over an expense
  /// the list screen already shows.
  ///
  /// **What counts as spending.** Only `expense` rows. FR-PLN-013 tracks
  /// "actual spending vs. the active plan"; income is not spending, a
  /// transfer is neither (E-02), and a plan allocates expense categories. A
  /// split parent contributes nothing and each of its parts contributes its
  /// own amount to its own category (E-04) — the rows the analytics
  /// datasource's `_spendingParts` counts, so the plan and the reports agree
  /// on what was spent on Food.
  ///
  /// **What is a no-op, not an error.** No active plan; the date outside the
  /// active plan's period; a category the plan has no row for. All three
  /// come out of the one statement below: the subquery yields `NULL` when no
  /// active plan holds the date, `plan_id = NULL` matches nothing, and a
  /// category with no allocation row matches nothing. An expense the plan
  /// does not cover is simply not tracked, which is what "tracking against
  /// the plan" means; refusing the expense would let the plan veto the
  /// ledger.
  ///
  /// **Active plan only, as of the write.** The reversal on edit and delete
  /// targets the plan that is active *now*, holding the *old* row's date. A
  /// plan that was active when a row was written and is not any more keeps
  /// the figure it had, and a plan activated after rows in its period were
  /// written starts from whatever `spent_amount_cents` says. Both are
  /// repaired by `MoneyPlanLocalDataSource.recomputeSpent`, the recount E-18
  /// asks for; activation is where that recount belongs.
  static Future<void> applyPlanSpend(
    DatabaseExecutor txn,
    TransactionModel transaction, {
    required int sign,
  }) async {
    if (transaction.type != TransactionType.expense) return;

    final parts = transaction.splits.isEmpty
        ? [(transaction.categoryId, transaction.amountCents)]
        : [for (final s in transaction.splits) (s.categoryId, s.amountCents)];
    final date = TransactionModel.encodeDate(transaction.date);

    for (final (categoryId, amountCents) in parts) {
      if (categoryId == null || amountCents == 0) continue;
      await txn.rawUpdate(
        'UPDATE plan_allocations '
        'SET spent_amount_cents = spent_amount_cents + ? '
        'WHERE category_id = ? AND plan_id = ('
        'SELECT id FROM money_plans '
        'WHERE is_active = 1 AND start_date <= ? AND end_date >= ? '
        'ORDER BY id DESC LIMIT 1)',
        [sign * amountCents, categoryId, date, date],
      );
    }
  }

  /// The stored row, with its split parts when it has any.
  ///
  /// The parts are needed by whoever reverses the row's effect (E-04: they,
  /// not the parent, are what moved the plan), and an unsplit row costs no
  /// second query.
  static Future<TransactionModel> requireRow(
    DatabaseExecutor txn,
    int id,
  ) async {
    final rows = await txn.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw CacheException('No transaction with id $id.');
    }
    return withSplits(txn, rows.first);
  }

  /// [row] as a model, with its split parts read when `is_split` says it
  /// has some.
  static Future<TransactionModel> withSplits(
    DatabaseExecutor txn,
    Map<String, Object?> row,
  ) async {
    final splitRows = row['is_split'] == 1
        ? await txn.query(
            'transaction_splits',
            where: 'transaction_id = ?',
            whereArgs: [row['id']],
            orderBy: 'id ASC',
          )
        : const <Map<String, Object?>>[];
    return TransactionModel.fromMap(row, splitRows: splitRows);
  }

  /// How much [transaction] moves its own account's balance, signed.
  ///
  /// Amounts are always positive on the row, so the direction has to come from
  /// somewhere: [TransactionType] for ordinary rows, and [TransferDirection]
  /// for the two halves of a transfer, which are otherwise identical (E-16).
  static int delta(TransactionModel transaction) => switch (transaction.type) {
    TransactionType.income => transaction.amountCents,
    TransactionType.expense => -transaction.amountCents,
    TransactionType.transfer =>
      transaction.transferDirection == TransferDirection.incoming
          ? transaction.amountCents
          : -transaction.amountCents,
  };
}
