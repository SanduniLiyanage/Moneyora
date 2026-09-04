/// The only place SQL is written for the transactions feature.
///
/// Everything here throws [CacheException] on failure and returns models, per
/// the layer contract in `docs/ARCHITECTURE.md` §3. The repository above
/// catches and converts; nothing further up ever sees a sqflite error.
///
/// ## Three invariants this file exists to hold
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
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../models/transaction_model.dart';

/// Reads and writes transactions in the local encrypted database.
abstract interface class TransactionLocalDataSource {
  /// Inserts [transaction] and returns its new id.
  ///
  /// Rejects transfers — they go through [createTransfer], because writing one
  /// half on its own leaves the other account short.
  Future<int> add(TransactionModel transaction);

  /// Replaces the stored row for [transaction], which must carry an id.
  Future<void> update(TransactionModel transaction);

  /// Deletes by id.
  ///
  /// Deleting either half of a transfer removes **both** halves and the header
  /// row, because half a transfer is not a thing the rest of the app can read.
  Future<void> delete(int id);

  /// Reads rows matching [filter], newest first, with their split parts.
  Future<List<TransactionModel>> list(TransactionFilter filter);

  /// Moves money between two accounts as one atomic unit. FR-TRF-002, E-15.
  ///
  /// Returns the `transfers` row id, not either transaction id — the header is
  /// what the UI edits and deletes.
  Future<int> createTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
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
  TransactionLocalDataSourceImpl(this._db);

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> dispose() => _changes.close();

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Future<int> add(TransactionModel transaction) async {
    if (transaction.type == TransactionType.transfer) {
      throw const CacheException(
        'A transfer cannot be added as a single row. Use createTransfer, '
        'which writes both halves and the header together (E-15).',
      );
    }

    final id = await _guard('add a transaction', () async {
      return _db.transaction((txn) async {
        final rowId = await txn.insert('transactions', transaction.toMap());
        await _writeSplits(txn, transaction, rowId);
        await _applyBalance(txn, transaction.accountId, _delta(transaction));
        return rowId;
      });
    });

    _notify();
    return id;
  }

  @override
  Future<void> update(TransactionModel transaction) async {
    final id = transaction.id;
    if (id == null) {
      throw const CacheException('Cannot update a transaction with no id.');
    }

    await _guard('update transaction $id', () async {
      await _db.transaction((txn) async {
        final existing = await _requireRow(txn, id);

        // Reverse the old row's effect before applying the new one. The two
        // may sit on different accounts, and they may be different amounts, so
        // there is no shortcut that adjusts a single balance by a difference.
        await _applyBalance(txn, existing.accountId, -_delta(existing));

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
        await _writeSplits(txn, transaction, id);

        await _applyBalance(txn, transaction.accountId, _delta(transaction));
      });
    });

    _notify();
  }

  @override
  Future<void> delete(int id) async {
    await _guard('delete transaction $id', () async {
      await _db.transaction((txn) async {
        final existing = await _requireRow(txn, id);

        if (existing.type == TransactionType.transfer) {
          await _deleteTransferAround(txn, id);
          return;
        }

        await _applyBalance(txn, existing.accountId, -_delta(existing));
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

        final toTxId = await txn.insert(
          'transactions',
          TransactionModel(
            accountId: toAccountId,
            amountCents: amountCents,
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
          'date': TransactionModel.encodeDate(date),
          'note': note,
          'from_tx_id': fromTxId,
          'to_tx_id': toTxId,
          'created_at': now.toIso8601String(),
        });

        await _applyBalance(txn, fromAccountId, -amountCents);
        await _applyBalance(txn, toAccountId, amountCents);

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

      return rows
          .map(
            (row) => TransactionModel.fromMap(
              row,
              splitRows: splitsById[row['id']] ?? const [],
            ),
          )
          .toList();
    });
  }

  // ── writes shared by several paths ────────────────────────────────────────

  Future<void> _writeSplits(
    DatabaseExecutor txn,
    TransactionModel transaction,
    int parentId,
  ) async {
    // The common case is unsplit, and it must stay a single insert (E-04).
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
  Future<void> _applyBalance(
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
      final orphan = await _requireRow(txn, halfId);
      await _applyBalance(txn, orphan.accountId, -_delta(orphan));
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
      final half = await _requireRow(txn, txId);
      await _applyBalance(txn, half.accountId, -_delta(half));
      await txn.delete('transactions', where: 'id = ?', whereArgs: [txId]);
    }
  }

  // ── reads ─────────────────────────────────────────────────────────────────

  Future<TransactionModel> _requireRow(DatabaseExecutor txn, int id) async {
    final rows = await txn.query(
      'transactions',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw CacheException('No transaction with id $id.');
    }
    return TransactionModel.fromMap(rows.first);
  }

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

  /// How much [transaction] moves its own account's balance, signed.
  ///
  /// Amounts are always positive on the row, so the direction has to come from
  /// somewhere: [TransactionType] for ordinary rows, and [TransferDirection]
  /// for the two halves of a transfer, which are otherwise identical (E-16).
  static int _delta(TransactionModel transaction) => switch (transaction.type) {
    TransactionType.income => transaction.amountCents,
    TransactionType.expense => -transaction.amountCents,
    TransactionType.transfer =>
      transaction.transferDirection == TransferDirection.incoming
          ? transaction.amountCents
          : -transaction.amountCents,
  };

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
