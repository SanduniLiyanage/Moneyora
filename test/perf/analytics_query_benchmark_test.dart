@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/domain/entities/trend_point.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// NFR-PER-006's benchmark: 10,000 transactions, query time, not frame time.
///
/// Per [E-28](../../docs/SPEC_ERRATA.md), no number produced here may be cited
/// as satisfying the 100ms/10,000-row target — that confirmation is
/// device-only, on the batched checklist in `docs/HANDOFF.md`. What a VM run
/// *can* catch, cheaply and on every CI run, is the failure mode the roadmap
/// actually warns about: a missing or dropped index turns this query from an
/// indexed lookup into a table scan, and that shows up as a multiple, not a
/// margin, even on a host machine's own timing.
void main() {
  sqfliteFfiInit();

  const rowCount = 10000;
  const randomSeed = 20260901; // fixed, so a failure is reproducible

  late Database db;
  late AnalyticsLocalDataSourceImpl analytics;
  late DateTime start;
  late DateTime end;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          for (final statement in v1Statements) {
            batch.execute(statement);
          }
          await batch.commit(noResult: true);
        },
        version: v1SchemaVersion,
      ),
    );
    await applyDefaultSeed(db);
    analytics = AnalyticsLocalDataSourceImpl(db);

    final categoryRows = await db.query(
      'categories',
      columns: ['id'],
      where: 'type = ?',
      whereArgs: ['expense'],
    );
    final categoryIds = categoryRows.map((r) => r['id']! as int).toList();

    end = DateTime(2026, 8, 31);
    start = DateTime(end.year - 2, end.month, end.day);
    final spanDays = end.difference(start).inDays;
    final rng = Random(randomSeed);

    // 9,500 ordinary expenses plus 500 split parents (each with two parts),
    // so both branches of the query's UNION run against real volume rather
    // than the handful of rows the correctness tests use.
    const splitCount = 500;
    const plainCount = rowCount - splitCount;

    final txnBatch = db.batch();
    for (var i = 0; i < plainCount; i++) {
      final date = start.add(Duration(days: rng.nextInt(spanDays)));
      final iso = date.toIso8601String().substring(0, 10);
      txnBatch.insert('transactions', {
        'account_id': 1,
        'category_id': categoryIds[rng.nextInt(categoryIds.length)],
        'amount_cents': 100 + rng.nextInt(500000),
        'type': 'expense',
        'date': iso,
        'created_at': '${iso}T00:00:00Z',
        'updated_at': '${iso}T00:00:00Z',
      });
    }
    await txnBatch.commit(noResult: true);

    for (var i = 0; i < splitCount; i++) {
      final date = start.add(Duration(days: rng.nextInt(spanDays)));
      final iso = date.toIso8601String().substring(0, 10);
      final parentId = await db.insert('transactions', {
        'account_id': 1,
        'category_id': categoryIds[rng.nextInt(categoryIds.length)],
        'amount_cents': 300000,
        'type': 'expense',
        'date': iso,
        'is_split': 1,
        'created_at': '${iso}T00:00:00Z',
        'updated_at': '${iso}T00:00:00Z',
      });
      final splitBatch = db.batch();
      splitBatch.insert('transaction_splits', {
        'transaction_id': parentId,
        'category_id': categoryIds[rng.nextInt(categoryIds.length)],
        'amount_cents': 150000,
      });
      splitBatch.insert('transaction_splits', {
        'transaction_id': parentId,
        'category_id': categoryIds[rng.nextInt(categoryIds.length)],
        'amount_cents': 150000,
      });
      await splitBatch.commit(noResult: true);
    }
  });

  tearDown(() => db.close());

  test(
    'spendingByCategory over 10,000 transactions — host VM, comparative only',
    () async {
      final rows = await db.rawQuery('SELECT COUNT(*) AS n FROM transactions');
      expect(rows.single['n'], rowCount);

      // One untimed warm-up run: the first execution against a fresh
      // in-memory database pays for query planning that every later run
      // reuses, and that cost is not what this benchmark is measuring.
      await analytics.spendingByCategory(from: start, to: end);

      const runs = 5;
      final durations = <Duration>[];
      for (var i = 0; i < runs; i++) {
        final stopwatch = Stopwatch()..start();
        final totals = await analytics.spendingByCategory(from: start, to: end);
        stopwatch.stop();
        durations.add(stopwatch.elapsed);
        expect(totals, isNotEmpty);
      }

      final micros = durations.map((d) => d.inMicroseconds).toList();
      final minMs = micros.reduce(min) / 1000;
      final avgMs = micros.reduce((a, b) => a + b) / runs / 1000;

      // ignore: avoid_print
      print(
        'spendingByCategory @ $rowCount transactions: '
        'min ${minMs.toStringAsFixed(1)}ms, avg ${avgMs.toStringAsFixed(1)}ms '
        '(host machine VM, comparative — not NFR-PER-006 evidence; see '
        'docs/HANDOFF.md\'s device checklist for the confirmed figure).',
      );

      // Not the NFR itself — a generous sanity ceiling to catch the failure
      // this benchmark exists for. An indexed lookup over 10,000 rows takes
      // low tens of milliseconds even on a slow CI runner; a dropped index
      // turning this into a table scan plus sort is a multiple of that, not
      // a margin, so a wide bound still catches the regression that matters.
      expect(minMs, lessThan(1000));
    },
  );

  test('spendingTrend by month over 10,000 transactions — one statement against '
      'one query per point, host VM, comparative only', () async {
    // FR-RPT-005's decision, kept measurable: the trend is one bucketed
    // statement rather than `spendingByCategory` once per point. Both are
    // timed here so a change that makes the single statement slower than
    // the loop it replaced is visible, and so the reasoning in
    // `GetSpendingTrend`'s doc comment stays a number rather than a memory.
    // The VM pays no platform-channel round trip per call, so the per-point
    // loop is *flattered* here relative to a device — the comparison is
    // conservative in the single statement's favour.
    final months = <DateTime>[];
    for (
      var m = DateTime(start.year, start.month + 1);
      !m.isAfter(end);
      m = DateTime(m.year, m.month + 1)
    ) {
      months.add(m);
    }

    await analytics.spendingTrend(
      from: start,
      to: end,
      granularity: TrendGranularity.month,
    );

    const runs = 5;
    var oneStatementMicros = double.infinity;
    var perPointMicros = double.infinity;
    for (var i = 0; i < runs; i++) {
      final one = Stopwatch()..start();
      final points = await analytics.spendingTrend(
        from: start,
        to: end,
        granularity: TrendGranularity.month,
      );
      one.stop();
      expect(points, isNotEmpty);
      oneStatementMicros = min(
        oneStatementMicros,
        one.elapsedMicroseconds.toDouble(),
      );

      final loop = Stopwatch()..start();
      for (final month in months) {
        await analytics.spendingByCategory(
          from: month,
          to: DateTime(month.year, month.month + 1, 0),
        );
      }
      loop.stop();
      perPointMicros = min(perPointMicros, loop.elapsedMicroseconds.toDouble());
    }

    // ignore: avoid_print
    print(
      'spendingTrend (month) @ $rowCount transactions: '
      'one statement min ${(oneStatementMicros / 1000).toStringAsFixed(1)}ms, '
      '${months.length} x spendingByCategory min '
      '${(perPointMicros / 1000).toStringAsFixed(1)}ms '
      '(host machine VM, comparative — not NFR-PER-006 evidence).',
    );

    // The same generous ceiling as above, for the same reason: this exists
    // to catch an index going missing, not to certify the NFR.
    expect(oneStatementMicros / 1000, lessThan(1000));
  });
}
