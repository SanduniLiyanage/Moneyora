/// The only place SQL is written for `receipt_scans` and `receipt_items`.
///
/// Throws [CacheException] on failure and returns models; the repository
/// above converts. See `docs/ARCHITECTURE.md` §3.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/errors/exceptions.dart';
import '../models/receipt_scan_model.dart';

/// Reads and writes scan records in the local encrypted database.
/// FR-RCP-009, FR-RCP-013.
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

  /// Every scan with its items, newest first — by `created_at`, then id,
  /// so two scans in the same second still come back in the order they
  /// were saved. FR-RCP-013.
  ///
  /// Two statements, not a join: the items are grouped under their scan
  /// in Dart, which costs one query and no row duplication for scans of
  /// twenty lines. No index backs the sort — the DBD's `idx_receipt_status`
  /// is not among the eleven v1 built (E-30 lists them) — and none is
  /// needed for a table that grows by one row per receipt.
  Future<List<ReceiptScanModel>> listAll();
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

  @override
  Future<List<ReceiptScanModel>> listAll() =>
      _guard('read the receipts', () async {
        final scanRows = await _db.query(
          'receipt_scans',
          orderBy: 'created_at DESC, id DESC',
        );
        final itemRows = await _db.query('receipt_items', orderBy: 'id ASC');
        final itemsByScan = <int, List<Map<String, Object?>>>{};
        for (final row in itemRows) {
          itemsByScan
              .putIfAbsent(row['receipt_scan_id']! as int, () => [])
              .add(row);
        }
        return [
          for (final row in scanRows)
            ReceiptScanModel.fromMap(row, itemsByScan[row['id']! as int] ?? []),
        ];
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
