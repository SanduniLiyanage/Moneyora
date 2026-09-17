/// The only place SQL is written for exchange rates. E-34.
///
/// Throws [CacheException] on failure and returns models; the repository above
/// converts. See `docs/ARCHITECTURE.md` §3.
library;

import 'dart:async';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/database/database_change_bus.dart';
import '../../../../core/errors/exceptions.dart';
import '../models/exchange_rate_model.dart';

/// Reads and writes `exchange_rates` in the local encrypted database.
abstract interface class ExchangeRateLocalDataSource {
  /// Every stored rate, ordered by pair.
  Future<List<ExchangeRateModel>> list();

  /// Inserts [rate], or replaces the row already held for its pair.
  Future<void> upsert(ExchangeRateModel rate);

  /// Deletes the pair's row. Not an error if there was none.
  Future<void> remove({
    required String fromCurrency,
    required String toCurrency,
  });

  /// Fires after every successful write.
  Stream<void> get changes;

  /// Closes [changes].
  Future<void> dispose();
}

/// sqflite implementation of [ExchangeRateLocalDataSource].
class ExchangeRateLocalDataSourceImpl implements ExchangeRateLocalDataSource {
  /// Creates a datasource over an already-open [db].
  ///
  /// Pass [changeBus] to share one change signal with the other datasources,
  /// which is what `injection.dart` does: a rate is what converts every
  /// foreign balance on screen (FR-ACC-005), so a total has to follow a rate
  /// change the way it follows a transaction write. Omit it and this
  /// datasource gets a private bus, hearing only its own writes.
  ExchangeRateLocalDataSourceImpl(this._db, {DatabaseChangeBus? changeBus})
    : _changes = changeBus ?? DatabaseChangeBus(),
      _ownsChanges = changeBus == null;

  final Database _db;
  final DatabaseChangeBus _changes;
  final bool _ownsChanges;

  @override
  Stream<void> get changes => _changes.changes;

  @override
  Future<void> dispose() async {
    if (_ownsChanges) await _changes.close();
  }

  @override
  Future<List<ExchangeRateModel>> list() => _guard('read the rates', () async {
    final rows = await _db.query(
      'exchange_rates',
      orderBy: 'from_currency, to_currency',
    );
    return rows.map(ExchangeRateModel.fromMap).toList();
  });

  @override
  Future<void> upsert(ExchangeRateModel rate) async {
    await _guard('save the rate', () async {
      // One rate per pair is the primary key; replacing is the whole point
      // of entering a newer one.
      await _db.insert(
        'exchange_rates',
        rate.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    _changes.notify();
  }

  @override
  Future<void> remove({
    required String fromCurrency,
    required String toCurrency,
  }) async {
    final deleted = await _guard(
      'remove the rate',
      () => _db.delete(
        'exchange_rates',
        where: 'from_currency = ? AND to_currency = ?',
        whereArgs: [fromCurrency, toCurrency],
      ),
    );

    if (deleted > 0) _changes.notify();
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
