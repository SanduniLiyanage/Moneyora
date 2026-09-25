/// Where SQL is written for the transactions a user enters.
///
/// Recurring rules have their own datasource beside this one, and both
/// write ledger rows through `ledger_writer.dart`, so a balance moves by
/// one arithmetic however the row arrived.
///
/// Everything here throws [CacheException] on failure and returns models, per
/// the layer contract in `docs/ARCHITECTURE.md` §3. The repository above
/// catches and converts; nothing further up ever sees a sqflite error.
///
/// ## Four invariants this file exists to hold
///
/// Each is an errata resolution, and each is impossible to enforce from any
/// other layer:
///
/// * **A transfer is three rows across two tables** with foreign keys pointing
///   both ways, so it is written in one `BEGIN … COMMIT` in a fixed order
///   (E-15). A partial write is money that left one account without arriving
///   in the other — the worst failure this application can produce.
/// * **A split's parts are written inside the parent's transaction** (E-04).
///   A parent whose children are missing is a transaction whose category
///   breakdown silently disagrees with its own amount.
/// * **`accounts.current_balance_cents` is a cache** (E-18), written only
///   inside the same transaction as the row that moves it. Never as a second
///   call, because a second call is a call something can skip.
/// * **`plan_allocations.spent_amount_cents` is a cache with the same rules**
///   (FR-PLN-013, E-18): an expense moves the active plan's figure for its
///   category inside the transaction that writes the expense. See
///   [LedgerWriter.applyPlanSpend] for what counts as spending and what is
///   a no-op.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../models/transaction_model.dart';
import 'ledger_writer.dart';

/// Reads and writes transactions in the local encrypted database.
abstract interface class TransactionLocalDataSource {
  /// Inserts [transaction] and returns its new id.
  ///
  /// Rejects transfers — they go through [createTransfer], because writing one
  /// half on its own leaves the other account short.
  Future<int> add(TransactionModel transaction);

  /// Inserts every row of [transactions] in one database transaction and
  /// returns their ids in order. FR-RCP-009.
  ///
  /// All or none: a receipt's items are one purchase, and a failure on the
  /// fourth line must not leave three in the ledger. Rejects transfers as
  /// [add] does, and fires [changes] once for the whole batch.
  Future<List<int>> addAll(List<TransactionModel> transactions);

  /// Replaces the stored row for [transaction], which must carry an id.
  Future<void> update(TransactionModel transaction);

  /// Deletes by id.
  ///
  /// Deleting either half of a transfer removes **both** halves and the header
  /// row, because half a transfer is not a thing the rest of the app can read.
  ///
  /// Deleting the entry a recurring rule copies hands that role to the
  /// series' latest remaining entry, or stops the rule when there is none
  /// (E-36).
  Future<void> delete(int id);

  /// Reads rows matching [filter], newest first, with their split parts.
  Future<List<TransactionModel>> list(TransactionFilter filter);

  /// Moves money between two accounts as one atomic unit. FR-TRF-002, E-15.
  ///
  /// Returns the `transfers` row id, not either transaction id — the header is
  /// what the UI edits and deletes.
  ///
  /// [amountCents] leaves the source in its currency; [creditedAmountCents]
  /// arrives at the destination in its own (E-34). The same number for a
  /// same-currency transfer.
  Future<int> createTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required int creditedAmountCents,
    required DateTime date,
    String? note,
  });

  /// Fires after every successful write.
  ///
  /// SQLite has no change notification, so a watching screen cannot be told
  /// what changed — only that something did. Callers re-run their own query;
  /// see `TransactionRepositoryImpl.watch`.
  Stream<void> get changes;

  /// Closes [changes]. Call from the provider's dispose.
  Future<void> dispose();
}

/// sqflite implementation of [TransactionLocalDataSource].
class TransactionLocalDataSourceImpl implements TransactionLocalDataSource {
  /// Creates a datasource over an already-open [db].
  ///
  /// Takes the database rather than `DatabaseHelper` because opening, keying
  /// and migrating are somebody else's job — done once in `injection.dart` —
  /// and a datasource that could also open a connection is a datasource that
  /// will eventually open a second one.
  /// Pass [changeBus] to share one change signal with the accounts datasource,
  /// which is what `injection.dart` does. Every write here can move
  /// `accounts.current_balance_cents` (E-18), and an accounts watcher that
  /// cannot hear those writes shows a stale balance. Omit it and this
  /// datasource gets a private bus, hearing only its own writes.
  TransactionLocalDataSourceImpl(this._db, {DatabaseChangeBus? changeBus})
    : _changes = changeBus ?? DatabaseChangeBus(),
      _ownsChanges = changeBus == null;

  final Database _db;
  final DatabaseChangeBus _changes;

  /// Whether this datasource made [_changes] and must therefore close it.
  final bool _ownsChanges;

  @override
  Stream<void> get changes => _changes.changes;

  @override
  Future<void> dispose() async {
    // Never close a bus handed in — see AccountLocalDataSourceImpl.dispose.
    if (_ownsChanges) await _changes.close();
  }

  void _notify() => _changes.notify();

  @override
  Future<int> add(TransactionModel transaction) async {
    if (transaction.type == TransactionType.transfer) {
      throw const CacheException(
        'A transfer cannot be added as a single row. Use createTransfer, '
        'which writes both halves and the header together (E-15).',
      );
    }

    final id = await _guard('add a transaction', () async {
      return _db.transaction((txn) => LedgerWriter.insert(txn, transaction));
    });

    _notify();
    return id;
  }

  @override
  Future<List<int>> addAll(List<TransactionModel> transactions) async {
    if (transactions.any((t) => t.type == TransactionType.transfer)) {
      throw const CacheException(
        'A transfer cannot be added as a single row. Use createTransfer, '
        'which writes both halves and the header together (E-15).',
      );
    }

    final ids = await _guard('add ${transactions.length} transactions', () {
      // One transaction around every row: SQLite rolls the lot back if any
      // insert fails, which is the whole reason this is not a loop over
      // [add]. The balance and plan caches move per row, inside it, as
      // always (E-18).
      return _db.transaction((txn) async {
        final ids = <int>[];
        for (final transaction in transactions) {
          ids.add(await LedgerWriter.insert(txn, transaction));
        }
        return ids;
      });
    });

    if (ids.isNotEmpty) _notify();
    return ids;
  }

  @override
  Future<void> update(TransactionModel transaction) async {
    final id = transaction.id;
    if (id == null) {
      throw const CacheException('Cannot update a transaction with no id.');
    }

    await _guard('update transaction $id', () async {
      await _db.transaction((txn) async {
        final existing = await LedgerWriter.requireRow(txn, id);

        // Reverse the old row's effect before applying the new one. The two
        // may sit on different accounts, and they may be different amounts, so
        // there is no shortcut that adjusts a single balance by a difference.
        // The same goes for the plan: the category, the date or the split
        // parts may all have changed, so the old row is taken out in full and
        // the new one put in — which is also what moves spend between two
        // categories when the category changes.
        await LedgerWriter.applyBalance(
          txn,
          existing.accountId,
          -LedgerWriter.delta(existing),
        );
        await LedgerWriter.applyPlanSpend(txn, existing, sign: -1);

        await txn.update(
          'transactions',
          transaction.toMap(),
          where: 'id = ?',
          whereArgs: [id],
        );

        // Splits are replaced wholesale rather than diffed. The parts of a
        // split have no identity a user would recognise, so matching them up
        // to preserve ids buys nothing and can only go wrong.
        await txn.delete(
          'transaction_splits',
          where: 'transaction_id = ?',
          whereArgs: [id],
        );
        await LedgerWriter.writeSplits(txn, transaction, id);

        await LedgerWriter.applyBalance(
          txn,
          transaction.accountId,
          LedgerWriter.delta(transaction),
        );
        await LedgerWriter.applyPlanSpend(txn, transaction, sign: 1);
      });
    });

    _notify();
  }

  @override
  Future<void> delete(int id) async {
    await _guard('delete transaction $id', () async {
      await _db.transaction((txn) async {
        final existing = await LedgerWriter.requireRow(txn, id);

        if (existing.type == TransactionType.transfer) {
          await _deleteTransferAround(txn, id);
          return;
        }

        await LedgerWriter.applyBalance(
          txn,
          existing.accountId,
          -LedgerWriter.delta(existing),
        );
        // Before the row goes: a split's parts are what moved the plan, and
        // they cascade away with the parent (E-04).
        await LedgerWriter.applyPlanSpend(txn, existing, sign: -1);
        // And before it goes: a recurring rule naming it as its template
        // would refuse the delete on its foreign key (E-36).
        await _handOnTemplate(txn, id);
        // transaction_splits cascades on delete (E-04), so the parts go with
        // the parent without a second statement.
        await txn.delete('transactions', where: 'id = ?', whereArgs: [id]);
      });
    });

    _notify();
  }

  @override
  Future<int> createTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required int creditedAmountCents,
    required DateTime date,
    String? note,
  }) async {
    final id = await _guard('record a transfer', () async {
      return _db.transaction((txn) async {
        final now = DateTime.now();

        // E-15: the order is forced. transfers.from_tx_id and to_tx_id are
        // foreign keys into rows that do not exist yet, so both halves are
        // written first and their ids read back. All three writes are in this
        // one transaction; there is no state in which one exists without the
        // others.
        final fromTxId = await txn.insert(
          'transactions',
          TransactionModel(
            accountId: fromAccountId,
            amountCents: amountCents,
            type: TransactionType.transfer,
            transferDirection: TransferDirection.out,
            date: date,
            note: note,
          ).toMap(now: now),
        );

        // The credit half carries the credited figure (E-34): E-16 made each
        // half's amount its own, so a balance recomputed from history reads
        // the right number on each side without joining the header.
        final toTxId = await txn.insert(
          'transactions',
          TransactionModel(
            accountId: toAccountId,
            amountCents: creditedAmountCents,
            type: TransactionType.transfer,
            transferDirection: TransferDirection.incoming,
            date: date,
            note: note,
          ).toMap(now: now),
        );

        final transferId = await txn.insert('transfers', {
          'from_account_id': fromAccountId,
          'to_account_id': toAccountId,
          'amount_cents': amountCents,
          'credited_amount_cents': creditedAmountCents,
          'date': TransactionModel.encodeDate(date),
          'note': note,
          'from_tx_id': fromTxId,
          'to_tx_id': toTxId,
          'created_at': now.toIso8601String(),
        });

        await LedgerWriter.applyBalance(txn, fromAccountId, -amountCents);
        await LedgerWriter.applyBalance(txn, toAccountId, creditedAmountCents);

        return transferId;
      });
    });

    _notify();
    return id;
  }

  @override
  Future<List<TransactionModel>> list(TransactionFilter filter) async {
    return _guard('read transactions', () async {
      final (where, args) = _buildWhere(filter);

      final rows = await _db.query(
        'transactions',
        where: where.isEmpty ? null : where,
        whereArgs: args.isEmpty ? null : args,
        // Newest first. `time` is optional, so a null must sort as the start
        // of the day rather than dragging the row to the wrong end; the id
        // breaks ties so the order is stable between identical rows.
        orderBy: "date DESC, COALESCE(time, '') DESC, id DESC",
      );

      final splitsById = await _readSplits(rows);
      final counterpartyById = await _readTransferCounterparties(rows);

      return rows
          .map(
            (row) => TransactionModel.fromMap(
              row,
              splitRows: splitsById[row['id']] ?? const [],
              counterpartyAccountId: counterpartyById[row['id']],
            ),
          )
          .toList();
    });
  }

  // ── writes shared by several paths ────────────────────────────────────────
  //
  // The single-row insert and the balance and plan caches it moves live in
  // `LedgerWriter`, shared with the recurring rules' datasource, so a rule's
  // entries move a balance by exactly the arithmetic a typed entry does.

  /// Hands the template role of any recurring rule copying [id] to another
  /// entry of the same series, before [id] is deleted. E-36.
  ///
  /// `recurring_rules.template_tx_id` has no `ON DELETE` action (DBD §2.2
  /// asks for a cascade; v1 built none), so with foreign keys on, deleting
  /// a template would fail. A cascade would be worse than the failure:
  /// deleting last month's rent, one wrong entry, would delete the rent.
  ///
  /// So the **latest remaining entry** of the series becomes the template
  /// — every entry is a copy of the template as it was when posted, and the
  /// latest is the nearest to what is repeating now — and the series goes
  /// on. When the template was the only entry there is nothing left to copy:
  /// the rule keeps its row, with no template, and stops. Both in the
  /// delete's own transaction, so an undone delete (E-23), which never
  /// reaches here, changes nothing.
  Future<void> _handOnTemplate(DatabaseExecutor txn, int id) async {
    final rules = await txn.query(
      'recurring_rules',
      columns: ['id'],
      where: 'template_tx_id = ?',
      whereArgs: [id],
    );
    for (final rule in rules) {
      final ruleId = rule['id']! as int;
      final heirs = await txn.query(
        'transactions',
        columns: ['id'],
        where: 'recurring_rule_id = ? AND id <> ?',
        whereArgs: [ruleId, id],
        orderBy: 'date DESC, id DESC',
        limit: 1,
      );
      await txn.update(
        'recurring_rules',
        heirs.isEmpty
            ? {'template_tx_id': null, 'is_active': 0}
            : {'template_tx_id': heirs.first['id']},
        where: 'id = ?',
        whereArgs: [ruleId],
      );
    }
  }

  /// Deletes both halves of a transfer and its header row.
  ///
  /// Deleting one half alone would leave `transfers` pointing at a row that no
  /// longer exists and one account permanently out by the amount, so the whole
  /// transfer goes or none of it does.
  Future<void> _deleteTransferAround(DatabaseExecutor txn, int halfId) async {
    final headers = await txn.query(
      'transfers',
      where: 'from_tx_id = ? OR to_tx_id = ?',
      whereArgs: [halfId, halfId],
      limit: 1,
    );

    if (headers.isEmpty) {
      // A transfer half with no header is already corrupt. Removing the row
      // and its balance effect is the best available repair, and it is better
      // than refusing to let the user delete something they can see.
      final orphan = await LedgerWriter.requireRow(txn, halfId);
      await LedgerWriter.applyBalance(
        txn,
        orphan.accountId,
        -LedgerWriter.delta(orphan),
      );
      await txn.delete('transactions', where: 'id = ?', whereArgs: [halfId]);
      return;
    }

    final header = headers.first;
    final fromTxId = header['from_tx_id']! as int;
    final toTxId = header['to_tx_id']! as int;

    // The header goes first. `from_tx_id` and `to_tx_id` are foreign keys into
    // the two halves, so deleting a half while the header still references it
    // fails the constraint — the teardown has to be the exact mirror of the
    // build-up in createTransfer, which writes the halves before the header.
    await txn.delete('transfers', where: 'id = ?', whereArgs: [header['id']]);

    for (final txId in {fromTxId, toTxId}) {
      final half = await LedgerWriter.requireRow(txn, txId);
      await LedgerWriter.applyBalance(
        txn,
        half.accountId,
        -LedgerWriter.delta(half),
      );
      await txn.delete('transactions', where: 'id = ?', whereArgs: [txId]);
    }
  }

  // ── reads ─────────────────────────────────────────────────────────────────

  /// Split parts for [rows], keyed by parent id.
  ///
  /// One extra query rather than one per row: a list of 500 transactions
  /// should cost two reads, not 501. Rows with no split are not asked about at
  /// all, which is why `is_split` is on the parent (E-04).
  Future<Map<Object?, List<Map<String, Object?>>>> _readSplits(
    List<Map<String, Object?>> rows,
  ) async {
    final parentIds = [
      for (final row in rows)
        if (row['is_split'] == 1) row['id'],
    ];
    if (parentIds.isEmpty) return const {};

    final placeholders = List.filled(parentIds.length, '?').join(', ');
    final splitRows = await _db.query(
      'transaction_splits',
      where: 'transaction_id IN ($placeholders)',
      whereArgs: parentIds,
      orderBy: 'id ASC',
    );

    final grouped = <Object?, List<Map<String, Object?>>>{};
    for (final split in splitRows) {
      (grouped[split['transaction_id']] ??= []).add(split);
    }
    return grouped;
  }

  /// The other account for each transfer row in [rows], keyed by transaction
  /// id. FR-TRF-004.
  ///
  /// A transfer half's own `account_id` names only the side it belongs to
  /// (E-16); the account it moved with lives in `transfers`, the header row
  /// that links both halves (E-15). One extra query covering every transfer
  /// in the page, not one per row, matching [_readSplits].
  Future<Map<Object?, int>> _readTransferCounterparties(
    List<Map<String, Object?>> rows,
  ) async {
    final transferTxIds = [
      for (final row in rows)
        if (row['type'] == 'transfer') row['id'],
    ];
    if (transferTxIds.isEmpty) return const {};

    final placeholders = List.filled(transferTxIds.length, '?').join(', ');
    final headers = await _db.query(
      'transfers',
      where: 'from_tx_id IN ($placeholders) OR to_tx_id IN ($placeholders)',
      whereArgs: [...transferTxIds, ...transferTxIds],
    );

    final counterpartyById = <Object?, int>{};
    for (final header in headers) {
      counterpartyById[header['from_tx_id']] = header['to_account_id']! as int;
      counterpartyById[header['to_tx_id']] = header['from_account_id']! as int;
    }
    return counterpartyById;
  }

  /// Builds the `WHERE` clause for [filter] and its bound arguments.
  (String, List<Object?>) _buildWhere(TransactionFilter filter) {
    final clauses = <String>[];
    final args = <Object?>[];

    void add(String clause, [Object? arg]) {
      clauses.add(clause);
      if (arg != null) args.add(arg);
    }

    if (filter.accountId != null) {
      // Each half of a transfer carries its own account_id, so this catches
      // the outgoing and incoming sides from the right account without a join
      // back to `transfers` — which is what E-16's direction column bought.
      add('account_id = ?', filter.accountId);
    }
    if (filter.categoryId != null) add('category_id = ?', filter.categoryId);
    if (filter.type != null) {
      add('type = ?', switch (filter.type!) {
        TransactionType.expense => 'expense',
        TransactionType.income => 'income',
        TransactionType.transfer => 'transfer',
      });
    }
    if (filter.excludeTransfers) {
      // E-02: a transfer is neither income nor expense, and counting it
      // inflates both. Two rows exist per transfer, so a query that forgets
      // this double-counts every one of them.
      add("type <> 'transfer'");
    }
    if (filter.from != null) {
      // Dates are fixed-width ISO-8601 TEXT, so string comparison is date
      // comparison and the date indexes apply.
      add('date >= ?', TransactionModel.encodeDate(filter.from!));
    }
    if (filter.to != null) {
      add('date <= ?', TransactionModel.encodeDate(filter.to!));
    }
    if (filter.minAmountCents != null) {
      add('amount_cents >= ?', filter.minAmountCents);
    }
    if (filter.maxAmountCents != null) {
      add('amount_cents <= ?', filter.maxAmountCents);
    }
    final note = filter.noteContains;
    if (note != null && note.isNotEmpty) {
      // LIKE is already case-insensitive for ASCII in SQLite. FR-RPT-008.
      add('note LIKE ?', '%${_escapeLike(note)}%');
    }

    return (clauses.join(' AND '), args);
  }

  /// Neutralises `%` and `_` so a note containing one is searched literally.
  static String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  /// Runs [body], turning any database error into a [CacheException].
  ///
  /// [action] is phrased to complete "Could not …" so the message a user
  /// eventually reads says what failed rather than quoting SQLite.
  Future<T> _guard<T>(String action, Future<T> Function() body) async {
    try {
      return await body();
    } on CacheException {
      rethrow;
    } on DatabaseException catch (e) {
      throw CacheException('Could not $action.', cause: e);
    }
  }
}
