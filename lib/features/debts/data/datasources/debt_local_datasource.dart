/// The only place SQL is written for debts. E-42.
///
/// Throws [CacheException] on failure and returns models; the repository above
/// converts. See `docs/ARCHITECTURE.md` §3.
///
/// ## A debt's money movements (FR-DBT-009, E-47)
///
/// A debt naming an account moves it ([DebtMovement]). Each movement is a
/// row in `transactions` of its own — `type = 'transfer'`, one side, no
/// `transfers` header, and `debt_id` naming the debt — so the account's
/// history shows it, `RecomputeAccountBalance` counts it, and everything
/// that leaves transfers out of income and spending (E-02) leaves it out
/// too. It moves `accounts.current_balance_cents` inside the same database
/// transaction as the debt (E-18), through [moveCachedBalance], the write
/// the ledger shares.
///
/// Every write of a debt takes its movements back out and writes them
/// again from what the debt now says, the way a transaction's split parts
/// are replaced wholesale: a debt whose amount, account, day or person
/// changed moves its accounts by exactly the difference, and one deleted
/// leaves them as they were before it.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/balance_cache.dart';
import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/debt_movement.dart';
import '../models/debt_model.dart';

/// Reads and writes `debts` in the local encrypted database.
abstract interface class DebtLocalDataSource {
  /// Every debt: open ones first, by due day (none last), then paid ones,
  /// most recently paid first.
  Future<List<DebtModel>> list();

  /// Inserts [debt] and returns its new id.
  Future<int> add(DebtModel debt);

  /// Inserts every one of [debts] in one database transaction, all or
  /// none, and returns their ids in order. FR-DBT-004.
  Future<List<int>> addAll(List<DebtModel> debts);

  /// Replaces the row with [debt]'s id.
  Future<void> update(DebtModel debt);

  /// Replaces the row of every one of [debts] in one database transaction,
  /// all or none. FR-DBT-006.
  Future<void> updateAll(List<DebtModel> debts);

  /// Deletes the row with [id].
  Future<void> delete(int id);

  /// Inserts [add], replaces [update] and deletes the rows with the ids in
  /// [delete], in one database transaction, all or none, and returns the
  /// new ids of [add] in order. FR-DBT-007.
  Future<List<int>> batch({
    List<DebtModel> add = const [],
    List<DebtModel> update = const [],
    List<int> delete = const [],
  });

  /// Fires after every successful write.
  Stream<void> get changes;

  /// Closes [changes] when this datasource made it.
  Future<void> dispose();
}

/// sqflite implementation of [DebtLocalDataSource].
class DebtLocalDataSourceImpl implements DebtLocalDataSource {
  /// Creates a datasource over an already-open [db].
  ///
  /// Pass [changeBus] to share the one change signal, which is what
  /// `injection.dart` does; omit it and this datasource gets a private
  /// one, hearing only its own writes, which is how its test builds it.
  /// Shared, a debt that moves an account is heard by the accounts and
  /// the transaction list as well.
  DebtLocalDataSourceImpl(
    this._db, {
    DatabaseChangeBus? changeBus,
    DateTime Function()? clock,
  }) : _changes = changeBus ?? DatabaseChangeBus(),
       _ownsChanges = changeBus == null,
       _clock = clock ?? DateTime.now;

  final Database _db;
  final DatabaseChangeBus _changes;
  final bool _ownsChanges;
  final DateTime Function() _clock;

  @override
  Stream<void> get changes => _changes.changes;

  @override
  Future<void> dispose() async {
    if (_ownsChanges) await _changes.close();
  }

  @override
  Future<List<DebtModel>> list() => _guard('read your debts', () async {
    final rows = await _db.query(
      'debts',
      orderBy:
          'paid_on IS NOT NULL, '
          "CASE WHEN paid_on IS NULL THEN COALESCE(due_on, '9999-12-31') END, "
          'paid_on DESC, incurred_on DESC, id DESC',
    );
    return rows.map(DebtModel.fromMap).toList();
  });

  @override
  Future<int> add(DebtModel debt) async => (await batch(add: [debt])).single;

  @override
  Future<List<int>> addAll(List<DebtModel> debts) => batch(add: debts);

  @override
  Future<void> update(DebtModel debt) async {
    if (debt.id == null) {
      throw const CacheException('Cannot update a debt with no id.');
    }
    await batch(update: [debt]);
  }

  @override
  Future<void> updateAll(List<DebtModel> debts) => batch(update: debts);

  @override
  Future<void> delete(int id) => batch(delete: [id]);

  @override
  Future<List<int>> batch({
    List<DebtModel> add = const [],
    List<DebtModel> update = const [],
    List<int> delete = const [],
  }) async {
    if (update.any((d) => d.id == null)) {
      throw const CacheException('Cannot update a debt with no id.');
    }
    final now = _clock();
    final stamp = now.toUtc().toIso8601String();
    final ids = await _guard(
      add.isEmpty && update.isEmpty ? 'delete the debt' : 'save the debts',
      () {
        return _db.transaction((txn) async {
          for (final debt in update) {
            final id = debt.id!;
            await _unmove(txn, id);
            final changed = await txn.update(
              'debts',
              debt.toMap(now: now),
              where: 'id = ?',
              whereArgs: [id],
            );
            if (changed == 0) throw CacheException('No debt with id $id.');
            await _move(txn, id, debt, stamp);
          }
          for (final id in delete) {
            // The movements first: they name the debt (FR-DBT-009).
            await _unmove(txn, id);
            final removed = await txn.delete(
              'debts',
              where: 'id = ?',
              whereArgs: [id],
            );
            if (removed == 0) throw CacheException('No debt with id $id.');
          }
          final added = <int>[];
          for (final debt in add) {
            final id = await txn.insert('debts', {
              ...debt.toMap(now: now),
              'created_at': stamp,
            });
            await _move(txn, id, debt, stamp);
            added.add(id);
          }
          return added;
        });
      },
    );
    _changes.notify();
    return ids;
  }

  /// Takes the money movements of the debt with [id] back out of their
  /// accounts, and deletes them.
  Future<void> _unmove(DatabaseExecutor txn, int id) async {
    final rows = await txn.query(
      'transactions',
      columns: ['account_id', 'amount_cents', 'transfer_direction'],
      where: 'debt_id = ?',
      whereArgs: [id],
    );
    for (final row in rows) {
      final cents = row['amount_cents']! as int;
      await moveCachedBalance(
        txn,
        row['account_id']! as int,
        row['transfer_direction'] == 'in' ? -cents : cents,
      );
    }
    await txn.delete('transactions', where: 'debt_id = ?', whereArgs: [id]);
  }

  /// Writes [debt]'s money movements as ledger rows naming [id], and moves
  /// their accounts.
  Future<void> _move(
    DatabaseExecutor txn,
    int id,
    DebtModel debt,
    String stamp,
  ) async {
    for (final movement in DebtMovement.of(debt)) {
      await txn.insert('transactions', {
        'account_id': movement.accountId,
        'amount_cents': movement.amountCents,
        // One side of a transfer, with no other side: a balance movement,
        // never income or spending (E-02), and no category (E-17).
        'type': 'transfer',
        'transfer_direction': movement.incoming ? 'in' : 'out',
        'date': encodeIsoDay(movement.on),
        'note': movement.label,
        'debt_id': id,
        'created_at': stamp,
        'updated_at': stamp,
      });
      await moveCachedBalance(txn, movement.accountId, movement.deltaCents);
    }
  }

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
