/// The only place SQL is written for the accounts feature.
///
/// Throws [CacheException] on failure and returns models; the repository above
/// converts. See `docs/ARCHITECTURE.md` §3.
///
/// The interesting method here is [recomputeBalance], which is E-18's
/// reconciliation. Everything else is ordinary CRUD.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/account_model.dart';

/// Reads and writes accounts in the local encrypted database.
abstract interface class AccountLocalDataSource {
  /// Inserts [account] and returns its new id.
  Future<int> add(AccountModel account);

  /// Updates the editable columns of [account]. Leaves the balance cache be.
  Future<void> update(AccountModel account);

  /// Sets or clears the archived flag.
  Future<void> setArchived(int id, {required bool archived});

  /// Removes the row. Fails if anything still references it.
  Future<void> delete(int id);

  /// How many `transactions` rows name [id], on either side of a transfer.
  Future<int> transactionCount(int id);

  /// Reads accounts, archived ones excluded unless asked for.
  Future<List<AccountModel>> list({bool includeArchived = false});

  /// Re-derives the cached balance for [id], writes it, and returns it. E-18.
  Future<int> recomputeBalance(int id);

  /// Re-derives every account's balance in one database transaction.
  Future<void> recomputeAllBalances();

  /// Fires after every successful write.
  Stream<void> get changes;

  /// Closes [changes].
  Future<void> dispose();
}

/// sqflite implementation of [AccountLocalDataSource].
class AccountLocalDataSourceImpl implements AccountLocalDataSource {
  /// Creates a datasource over an already-open [db].
  AccountLocalDataSourceImpl(this._db);

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
  Future<int> add(AccountModel account) async {
    final id = await _guard(
      'add an account',
      () => _db.transaction((txn) async {
        final rowId = await txn.insert('accounts', account.toMap());
        // A new account's balance is its opening balance and nothing else,
        // because no transaction can reference it yet.
        await txn.rawUpdate(
          'UPDATE accounts SET current_balance_cents = initial_balance_cents '
          'WHERE id = ?',
          [rowId],
        );
        return rowId;
      }),
    );

    _notify();
    return id;
  }

  @override
  Future<void> update(AccountModel account) async {
    final id = account.id;
    if (id == null) {
      throw const CacheException('Cannot update an account with no id.');
    }

    await _guard('update account $id', () async {
      await _db.transaction((txn) async {
        final changed = await txn.update(
          'accounts',
          account.toUpdateMap(),
          where: 'id = ?',
          whereArgs: [id],
        );
        if (changed == 0) throw CacheException('No account with id $id.');

        // Editing the opening balance moves every total derived from it, so
        // the cache is re-derived in the same transaction rather than left to
        // drift until something else happens to recompute it.
        await _recomputeWithin(txn, id);
      });
    });

    _notify();
  }

  @override
  Future<void> setArchived(int id, {required bool archived}) async {
    await _guard('archive account $id', () async {
      final changed = await _db.update(
        'accounts',
        {'is_archived': archived ? 1 : 0},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed == 0) throw CacheException('No account with id $id.');
    });

    _notify();
  }

  @override
  Future<void> delete(int id) async {
    await _guard('delete account $id', () async {
      // The foreign key from transactions would refuse anyway, but failing
      // here says which account and how many rows, rather than quoting a
      // constraint name at whoever reads the log.
      final count = await transactionCount(id);
      if (count > 0) {
        throw CacheException('Account $id still has $count transactions.');
      }
      final removed = await _db.delete(
        'accounts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (removed == 0) throw CacheException('No account with id $id.');
    });

    _notify();
  }

  @override
  Future<int> transactionCount(int id) => _guard(
    'count transactions for account $id',
    () async =>
        (await _db.rawQuery(
              'SELECT COUNT(*) AS c FROM transactions WHERE account_id = ?',
              [id],
            )).first['c']!
            as int,
  );

  @override
  Future<List<AccountModel>> list({bool includeArchived = false}) =>
      _guard('read accounts', () async {
        final rows = await _db.query(
          'accounts',
          where: includeArchived ? null : 'is_archived = 0',
          orderBy: 'is_archived ASC, id ASC',
        );
        return rows.map(AccountModel.fromMap).toList();
      });

  @override
  Future<int> recomputeBalance(int id) async {
    final balance = await _guard(
      'recompute the balance for account $id',
      () => _db.transaction((txn) => _recomputeWithin(txn, id)),
    );

    _notify();
    return balance;
  }

  @override
  Future<void> recomputeAllBalances() async {
    await _guard('recompute every balance', () async {
      await _db.transaction((txn) async {
        final rows = await txn.query('accounts', columns: ['id']);
        for (final row in rows) {
          await _recomputeWithin(txn, row['id']! as int);
        }
      });
    });

    _notify();
  }

  /// Derives the balance for [id] from history and writes it.
  ///
  /// The arithmetic is E-02's, corrected for E-16: each half of a transfer
  /// carries its own `account_id` and its own direction, so this reads from
  /// `transactions` alone and never joins `transfers`. That is exactly what
  /// the direction column was added to buy.
  ///
  /// `SUM` over an empty set is `NULL`, not zero, which is why every term is
  /// wrapped in `COALESCE` — without it a brand-new account's balance comes
  /// back null and the cast throws.
  ///
  /// Placeholders are positional `?`, not named `:id`. sqflite binds its
  /// argument list by position, so a named parameter repeated twice would take
  /// the arguments in an order nobody intended.
  Future<int> _recomputeWithin(DatabaseExecutor txn, int id) async {
    final rows = await txn.rawQuery(
      '''
SELECT
  (SELECT initial_balance_cents FROM accounts WHERE id = ?)
  + COALESCE(SUM(CASE WHEN type = 'income'  THEN amount_cents END), 0)
  - COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_cents END), 0)
  + COALESCE(SUM(CASE WHEN type = 'transfer' AND transfer_direction = 'in'
                      THEN amount_cents END), 0)
  - COALESCE(SUM(CASE WHEN type = 'transfer' AND transfer_direction = 'out'
                      THEN amount_cents END), 0)
  AS balance
FROM transactions
WHERE account_id = ?
''',
      [id, id],
    );

    final balance = rows.first['balance'];
    if (balance == null) throw CacheException('No account with id $id.');

    await txn.update(
      'accounts',
      {'current_balance_cents': balance},
      where: 'id = ?',
      whereArgs: [id],
    );
    return balance as int;
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
