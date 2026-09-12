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
import '../../domain/entities/trend_point.dart';
import '../models/category_total_model.dart';
import '../models/trend_point_model.dart';

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

  /// Totals expense spending per category per bucket of [granularity]
  /// between [from] and [to] inclusive, earliest bucket first, for
  /// [accountId] or — when it is null — every account. Sparse: a category
  /// with nothing spent in a bucket has no row. FR-RPT-005.
  Future<List<TrendPointModel>> spendingTrend({
    required DateTime from,
    required DateTime to,
    required TrendGranularity granularity,
    int? accountId,
  });
}

/// sqflite implementation of [AnalyticsLocalDataSource].
class AnalyticsLocalDataSourceImpl implements AnalyticsLocalDataSource {
  /// Creates a datasource over an already-open [db].
  const AnalyticsLocalDataSourceImpl(this._db);

  final Database _db;

  /// The rows that count as spending: unsplit expenses plus the parts of
  /// split ones, each with its date, category and amount.
  ///
  /// This is the one place the E-02 and E-04 invariants above are written.
  /// [_spendingByCategory] totals these rows per category and
  /// [_spendingTrend] totals them per bucket per category — both are
  /// assembled from this fragment rather than each carrying its own copy of
  /// the union, because the invariants are the hard part of either query and
  /// a second copy of them is a second place for them to drift apart.
  ///
  /// `type = 'expense'` is what excludes transfers and income both; it is
  /// stated as an equality rather than as `type <> 'transfer'` so that adding
  /// a fourth type later cannot quietly fold it into spending.
  ///
  /// FR-RPT-003's account filter is the `{account}` clause, substituted for
  /// `AND t.account_id = ?` or for nothing at all. One body with a hole in
  /// it rather than two whole statements, for the reason above. The
  /// substituted text is a constant and the account id stays a bound
  /// parameter, so nothing here is built from input.
  static const String _accountClause = 'AND t.account_id = ?';

  static const String _spendingParts = '''
        SELECT t.date AS date, t.category_id AS category_id,
               t.amount_cents AS amount_cents
          FROM transactions t
         WHERE t.type = 'expense'
           AND t.is_split = 0
           AND t.date >= ? AND t.date <= ?
           {account}
        UNION ALL
        SELECT t.date AS date, s.category_id AS category_id,
               s.amount_cents AS amount_cents
          FROM transaction_splits s
          JOIN transactions t ON t.id = s.transaction_id
         WHERE t.type = 'expense'
           AND t.date >= ? AND t.date <= ?
           {account}
''';

  /// [_spendingParts] totalled per category, largest first.
  ///
  /// One statement rather than two queries added up in Dart, because SQLite
  /// can do it at the index and NFR-PER-006 allows 100ms for the whole thing
  /// at 10,000 rows.
  static const String _spendingByCategory = '''
SELECT c.id AS category_id, c.name AS name, c.color AS color,
       SUM(part.amount_cents) AS total_cents
  FROM (
{parts}
       ) AS part
  JOIN categories c ON c.id = part.category_id
 GROUP BY c.id, c.name, c.color
 ORDER BY total_cents DESC, c.name ASC
''';

  /// [_spendingParts] totalled per bucket per category, earliest first.
  /// FR-RPT-005.
  ///
  /// One statement for the whole period rather than [_spendingByCategory]
  /// once per bucket. On the 10,000-row benchmark fixture the two are within
  /// a few milliseconds of each other on the host VM
  /// (`analytics_query_benchmark_test.dart` prints both: about 16ms against
  /// about 21ms for a 24-month line) — but the VM pays no platform-channel
  /// round trip per call, and on a device that cost is paid once here and
  /// once *per point* by the loop: 24 for a two-year monthly line, up to 92
  /// for a daily one. A chart whose query cost grows with the number of
  /// points it draws is the shape NFR-PER-006 is there to refuse.
  ///
  /// Grouped on the category id first and joined to `categories` afterwards,
  /// rather than grouping on the joined name and colour the way
  /// [_spendingByCategory] does: measured at about 30% less on the same
  /// fixture, because the join then runs once per (bucket, category) row
  /// rather than once per transaction.
  ///
  /// `{bucket}` is the expression that cuts a `YYYY-MM-DD` date down to its
  /// bucket, substituted from [_bucketExpressions] — a constant per
  /// granularity, never input. A month bucket is padded back out to its
  /// first day so the model parses one shape of string.
  static const String _spendingTrend = '''
SELECT g.bucket AS bucket, c.id AS category_id, c.name AS name,
       c.color AS color, g.total_cents AS total_cents
  FROM (
        SELECT {bucket} AS bucket, part.category_id AS category_id,
               SUM(part.amount_cents) AS total_cents
          FROM (
{parts}
               ) AS part
         GROUP BY bucket, part.category_id
       ) AS g
  JOIN categories c ON c.id = g.category_id
 ORDER BY g.bucket ASC, g.total_cents DESC, c.name ASC
''';

  static const Map<TrendGranularity, String> _bucketExpressions = {
    TrendGranularity.day: 'part.date',
    TrendGranularity.month: "substr(part.date, 1, 7) || '-01'",
  };

  /// [statement] with its `{parts}` hole filled by [_spendingParts] and the
  /// account clause substituted in or out, plus the bound arguments in the
  /// order the finished text reads them — dates for the first half of the
  /// union, then the account when one is being filtered on, then the same
  /// again for the second half.
  static (String, List<Object?>) _assemble(
    String statement, {
    required DateTime from,
    required DateTime to,
    required int? accountId,
  }) {
    // Fixed-width ISO dates, so string comparison is date comparison and the
    // `date` index applies.
    final start = encodeIsoDay(from);
    final end = encodeIsoDay(to);

    final sql = statement
        .replaceAll('{parts}', _spendingParts)
        .replaceAll('{account}', accountId == null ? '' : _accountClause);
    final args = accountId == null
        ? <Object?>[start, end, start, end]
        : <Object?>[start, end, accountId, start, end, accountId];
    return (sql, args);
  }

  @override
  Future<List<CategoryTotalModel>> spendingByCategory({
    required DateTime from,
    required DateTime to,
    int? accountId,
  }) async {
    return _guard('total spending by category', () async {
      final (sql, args) = _assemble(
        _spendingByCategory,
        from: from,
        to: to,
        accountId: accountId,
      );
      final rows = await _db.rawQuery(sql, args);

      return rows.map(CategoryTotalModel.fromMap).toList(growable: false);
    });
  }

  @override
  Future<List<TrendPointModel>> spendingTrend({
    required DateTime from,
    required DateTime to,
    required TrendGranularity granularity,
    int? accountId,
  }) async {
    return _guard('chart spending over time', () async {
      final (sql, args) = _assemble(
        _spendingTrend.replaceAll('{bucket}', _bucketExpressions[granularity]!),
        from: from,
        to: to,
        accountId: accountId,
      );
      final rows = await _db.rawQuery(sql, args);

      return rows.map(TrendPointModel.fromMap).toList(growable: false);
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
