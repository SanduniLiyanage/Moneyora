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
  /// largest first, for [accountId] or — when it is null — every account.
  /// FR-RPT-003.
  Future<List<CategoryTotalModel>> spendingByCategory({
    required DateTime from,
    required DateTime to,
    int? accountId,
  });

  /// Totals income between [from] and [to] inclusive, for [accountId] or —
  /// when it is null — every account. FR-RPT-003.
  Future<int> incomeForPeriod({
    required DateTime from,
    required DateTime to,
    int? accountId,
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
  ///
  /// FR-RPT-003's account filter is the `{account}` clause below, substituted
  /// for `AND t.account_id = ?` or for nothing at all. One body with a hole in
  /// it rather than two whole statements: the E-02 and E-04 invariants above
  /// are the hard part of this query, and a second copy of them is a second
  /// place for them to drift apart. The substituted text is a constant and the
  /// account id stays a bound parameter, so nothing here is built from input.
  static const String _accountClause = 'AND t.account_id = ?';

  static const String _spendingByCategory = '''
SELECT c.id AS category_id, c.name AS name, c.color AS color,
       SUM(part.amount_cents) AS total_cents
  FROM (
        SELECT t.category_id AS category_id, t.amount_cents AS amount_cents
          FROM transactions t
         WHERE t.type = 'expense'
           AND t.is_split = 0
           AND t.date >= ? AND t.date <= ?
           {account}
        UNION ALL
        SELECT s.category_id AS category_id, s.amount_cents AS amount_cents
          FROM transaction_splits s
          JOIN transactions t ON t.id = s.transaction_id
         WHERE t.type = 'expense'
           AND t.date >= ? AND t.date <= ?
           {account}
       ) AS part
  JOIN categories c ON c.id = part.category_id
 GROUP BY c.id, c.name, c.color
 ORDER BY total_cents DESC, c.name ASC
''';

  @override
  Future<List<CategoryTotalModel>> spendingByCategory({
    required DateTime from,
    required DateTime to,
    int? accountId,
  }) async {
    return _guard('total spending by category', () async {
      // Fixed-width ISO dates, so string comparison is date comparison and the
      // `date` index applies.
      final start = encodeIsoDay(from);
      final end = encodeIsoDay(to);

      final sql = _spendingByCategory.replaceAll(
        '{account}',
        accountId == null ? '' : _accountClause,
      );
      // Both halves of the union carry the same three arguments, in the order
      // the statement reads them — dates first, then the account when one is
      // being filtered on.
      final args = accountId == null
          ? [start, end, start, end]
          : [start, end, accountId, start, end, accountId];

      final rows = await _db.rawQuery(sql, args);

      return rows.map(CategoryTotalModel.fromMap).toList(growable: false);
    });
  }

  /// Income has no split table to union against (E-04's applies to FR-EXP-010's
  /// expenses only), so this is a plain sum. `COALESCE` turns SQLite's `NULL`
  /// for "no matching rows" into 0, since there is no `GROUP BY` here to make
  /// an empty period simply vanish the way `spendingByCategory` does.
  ///
  /// The `{account}` hole is FR-RPT-003's filter, the same substitution
  /// `_spendingByCategory` uses above — the two aggregates are filtered by the
  /// same rule because FR-RPT-004 puts their results side by side, and a
  /// filter applied to one bar and not the other compares two different things
  /// and calls the difference savings. The alias is spelled out here so the
  /// clause is identical in both statements.
  static const String _incomeForPeriod = '''
SELECT COALESCE(SUM(t.amount_cents), 0) AS total_cents
  FROM transactions t
 WHERE t.type = 'income'
   AND t.date >= ? AND t.date <= ?
   {account}
''';

  @override
  Future<int> incomeForPeriod({
    required DateTime from,
    required DateTime to,
    int? accountId,
  }) async {
    return _guard('total income for period', () async {
      final sql = _incomeForPeriod.replaceAll(
        '{account}',
        accountId == null ? '' : _accountClause,
      );
      final args = <Object?>[encodeIsoDay(from), encodeIsoDay(to)];
      if (accountId != null) args.add(accountId);

      final rows = await _db.rawQuery(sql, args);
      return (rows.single['total_cents']! as num).toInt();
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
