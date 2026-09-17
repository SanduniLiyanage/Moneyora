/// The only place SQL is written for the settings feature.
///
/// Throws [CacheException] on failure and returns models; the repository above
/// converts. See `docs/ARCHITECTURE.md` §3.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/user_settings_model.dart';

/// Reads and writes the single `users` row in the local encrypted database.
abstract interface class SettingsLocalDataSource {
  /// The row as stored.
  Future<UserSettingsModel> read();

  /// Writes the preference columns of [settings] over the row.
  Future<void> write(UserSettingsModel settings);

  /// Fires after every successful write.
  Stream<void> get changes;

  /// Closes [changes].
  Future<void> dispose();
}

/// sqflite implementation of [SettingsLocalDataSource].
///
/// The `users` table has exactly one row, `id = 1`, written by the default
/// seed on first launch (DBD §3.1). Nothing here inserts: a missing row is a
/// database that was never seeded, and that is an error to surface, not a
/// state to paper over with defaults that would then be silently lost on the
/// next write.
class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  /// Creates a datasource over an already-open [db].
  ///
  /// Pass [changeBus] to share one change signal with the other datasources,
  /// which is what `injection.dart` does: FR-ACC-005's base currency lives
  /// in this row and every summed balance on screen has to follow a change
  /// to it. Omit it and this datasource gets a private bus, hearing only its
  /// own writes — how every unit test constructs one.
  SettingsLocalDataSourceImpl(this._db, {DatabaseChangeBus? changeBus})
    : _changes = changeBus ?? DatabaseChangeBus(),
      _ownsChanges = changeBus == null;

  /// The one row's id.
  static const int userId = 1;

  final Database _db;
  final DatabaseChangeBus _changes;

  /// Whether this datasource made [_changes] and must therefore close it.
  final bool _ownsChanges;

  @override
  Stream<void> get changes => _changes.changes;

  @override
  Future<void> dispose() async {
    // Never close a bus handed in: it outlives this datasource, and closing it
    // here would silence every other datasource sharing it.
    if (_ownsChanges) await _changes.close();
  }

  @override
  Future<UserSettingsModel> read() => _guard('read the settings', () async {
    final rows = await _db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const CacheException('The settings row has not been seeded.');
    }
    return UserSettingsModel.fromMap(rows.single);
  });

  @override
  Future<void> write(UserSettingsModel settings) async {
    await _guard('save the settings', () async {
      final changed = await _db.update(
        'users',
        settings.toUpdateMap(),
        where: 'id = ?',
        whereArgs: [userId],
      );
      if (changed == 0) {
        throw const CacheException('The settings row has not been seeded.');
      }
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
