/// The only place SQL is written for `receipt_scans` and `receipt_items`.
///
/// Throws [CacheException] on failure and returns models; the repository
/// above converts. See `docs/ARCHITECTURE.md` §3.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/receipt_scan_model.dart';

/// Writes scan records to the local encrypted database. FR-RCP-009.
abstract interface class ReceiptScanLocalDataSource {
  /// Inserts [scan] and its items in one database transaction and returns
  /// the scan's id.
  ///
  /// All or none: a scan row without its items is a receipt the history
  /// cannot show, and items without their scan cannot exist (the foreign
  /// key cascades). Nothing is notified — no screen watches scans yet,
  /// and the expenses written beside a scan notify through the
  /// transactions datasource.
  Future<int> insert(ReceiptScanModel scan);
}

/// sqflite implementation of [ReceiptScanLocalDataSource].
class ReceiptScanLocalDataSourceImpl implements ReceiptScanLocalDataSource {
  /// Creates a datasource over an already-open [db].
  const ReceiptScanLocalDataSourceImpl(this._db);

  final Database _db;

  @override
  Future<int> insert(ReceiptScanModel scan) => _guard('save the receipt', () {
    return _db.transaction((txn) async {
      final now = DateTime.now();
      final scanId = await txn.insert('receipt_scans', scan.toMap(now: now));
      for (final item in scan.itemModels) {
        await txn.insert('receipt_items', item.toMap(scanId: scanId));
      }
      return scanId;
    });
  });

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
