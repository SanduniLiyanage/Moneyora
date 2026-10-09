/// The only place SQL is written for debts. E-42.
///
/// Throws [CacheException] on failure and returns models; the repository above
/// converts. See `docs/ARCHITECTURE.md` §3.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/debt_model.dart';

/// Reads and writes `debts` in the local encrypted database.
abstract interface class DebtLocalDataSource {
  /// Every debt: open ones first, by due day (none last), then paid ones,
  /// most recently paid first.
  Future<List<DebtModel>> list();

  /// Inserts [debt] and returns its new id.
  Future<int> add(DebtModel debt);

  /// Replaces the row with [debt]'s id.
  Future<void> update(DebtModel debt);

  /// Deletes the row with [id].
  Future<void> delete(int id);

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
  Future<int> add(DebtModel debt) async {
    final now = _clock();
    final id = await _guard(
      'save the debt',
      () => _db.insert('debts', {
        ...debt.toMap(now: now),
        'created_at': now.toUtc().toIso8601String(),
      }),
    );
    _changes.notify();
    return id;
  }

  @override
  Future<void> update(DebtModel debt) async {
    final id = debt.id;
    if (id == null) {
      throw const CacheException('Cannot update a debt with no id.');
    }
    await _guard('save the debt', () async {
      final changed = await _db.update(
        'debts',
        debt.toMap(now: _clock()),
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed == 0) throw CacheException('No debt with id $id.');
    });
    _changes.notify();
  }

  @override
  Future<void> delete(int id) async {
    await _guard('delete the debt', () async {
      final removed = await _db.delete(
        'debts',
        where: 'id = ?',
        whereArgs: [id],
      );
      if (removed == 0) throw CacheException('No debt with id $id.');
    });
    _changes.notify();
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
