/// The only place SQL is written for the analytics feature.
///
/// Throws [CacheException] on failure and returns models, per the layer
/// contract in `docs/ARCHITECTURE.md` §3.
///
/// ## Two invariants the query exists to hold
///
/// * **Transfers are not spending** (E-02). Two rows exist per transfer, so a
///   total that forgets this does not merely include them — it counts each one
///   twice, in opposite directions, and the error is invisible in the output.
/// * **A split belongs to its parts, not to its parent** (E-04). A parent row
///   carries the dominant category and the full amount; its children carry the
///   real breakdown. Summing both double-counts the transaction, and summing
///   only the parent files the whole amount under one category.
library;

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/utils/date_utils.dart';
import '../models/category_total_model.dart';

/// Reads aggregates over transaction history. Never writes.
abstract interface class AnalyticsLocalDataSource {
  /// Totals expense spending per category between [from] and [to] inclusive,
  /// largest first.
  Future<List<CategoryTotalModel>> spendingByCategory({
    required DateTime from,
    required DateTime to,
  });
}

/// sqflite implementation of [AnalyticsLocalDataSource].
class AnalyticsLocalDataSourceImpl implements AnalyticsLocalDataSource {
  /// Creates a datasource over an already-open [db].
  const AnalyticsLocalDataSourceImpl(this._db);

  final Database _db;

  /// Unsplit expenses plus the parts of split ones, totalled per category.
  ///
  /// One statement rather than two queries added up in Dart, because SQLite
  /// can do it at the index and NFR-PER-006 allows 100ms for the whole thing
  /// at 10,000 rows.
  ///
  /// `type = 'expense'` is what excludes transfers and income both; it is
  /// stated as an equality rather than as `type <> 'transfer'` so that adding
  /// a fourth type later cannot quietly fold it into spending.
  static const String _spendingByCategory = '''
SELECT c.id AS category_id, c.name AS name, c.color AS color,
       SUM(part.amount_cents) AS total_cents
  FROM (
        SELECT t.category_id AS category_id, t.amount_cents AS amount_cents
          FROM transactions t
         WHERE t.type = 'expense'
           AND t.is_split = 0
           AND t.date >= ? AND t.date <= ?
        UNION ALL
        SELECT s.category_id AS category_id, s.amount_cents AS amount_cents
          FROM transaction_splits s
          JOIN transactions t ON t.id = s.transaction_id
         WHERE t.type = 'expense'
           AND t.date >= ? AND t.date <= ?
       ) AS part
  JOIN categories c ON c.id = part.category_id
 GROUP BY c.id, c.name, c.color
 ORDER BY total_cents DESC, c.name ASC
''';

  @override
  Future<List<CategoryTotalModel>> spendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async {
    return _guard('total spending by category', () async {
      // Fixed-width ISO dates, so string comparison is date comparison and the
      // `date` index applies.
      final start = encodeIsoDay(from);
      final end = encodeIsoDay(to);

      final rows = await _db.rawQuery(_spendingByCategory, [
        start,
        end,
        start,
        end,
      ]);

      return rows.map(CategoryTotalModel.fromMap).toList(growable: false);
    });
  }

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
