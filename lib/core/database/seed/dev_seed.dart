import 'dart:math';

import 'package:sqflite_sqlcipher/sqflite.dart';

/// Generates synthetic transaction history for development and testing.
///
/// **Never ships.** Callers must gate this behind `kDebugMode`; it is not
/// gated internally so that tests, which run in a non-debug context, can still
/// use it.
///
/// ## Why this exists in Sprint 1 rather than Sprint 5
///
/// The Money Plan Generator analyses months of history. Without a generator
/// you arrive at Sprint 5 with an app containing a dozen hand-typed expenses,
/// no way to exercise the algorithm, and a strong temptation to ship an
/// untested engine. This fixture is simultaneously the dev dataset, the
/// algorithm's test oracle, and the demo data.
///
/// ## The shapes are deliberate
///
/// Each category is generated to a known statistical shape, so a test can
/// assert the classifier reaches the right verdict rather than merely running
/// without crashing:
///
/// | Category | Shape | The classifier should say |
/// |---|---|---|
/// | Bills | identical monthly amount | **Fixed** (CV < 0.15) |
/// | Food | noisy near-daily spend | **Variable**, HIGH confidence |
/// | Gifts | spikes each April and December | **Seasonal** — but only with a >= 24-month lookback |
/// | Car | rising ~8% per month | **Variable**, trend positive, +8% buffer |
/// | Pets | 3 transactions in total | **LOW** confidence, whatever the class |
///
/// ## 24 months, not 6
///
/// The roadmap originally said six. E-07 then established that seasonal
/// detection needs at least 24 months — two full cycles — and that below that
/// threshold the classifier must not assign Seasonal at all. Generating 24
/// months lets you test *both* halves of that rule: run the engine at the
/// 6-month default and Gifts must come back Variable; run it at 24 and the
/// same data must come back Seasonal. Six months of data could only ever test
/// the first.
class DevSeed {
  DevSeed._();

  /// Default history length. See the class doc on why this is not 6.
  static const int defaultMonths = 24;

  /// Fixed by default so runs are reproducible.
  ///
  /// A generator whose output changes per run cannot be a test oracle: a
  /// failing assertion would be unreproducible, and the first response to any
  /// failure would be to re-run it and hope.
  static const int defaultRandomSeed = 20260901;

  /// Inserts synthetic history, returning how many transactions were written.
  ///
  /// [endDate] defaults to today; history runs backwards from it.
  static Future<int> populate(
    Database db, {
    int months = defaultMonths,
    int randomSeed = defaultRandomSeed,
    DateTime? endDate,
  }) async {
    final rng = Random(randomSeed);
    final end = endDate ?? DateTime.now();
    final start = DateTime(end.year, end.month - months, end.day);

    final accountId = await _firstAccountId(db);
    final categories = await _categoryIdsByName(db);

    var written = 0;
    await db.transaction((txn) async {
      written += await _fixed(txn, rng, accountId, categories, start, end);
      written += await _variable(txn, rng, accountId, categories, start, end);
      written += await _seasonal(txn, rng, accountId, categories, start, end);
      written += await _trending(txn, rng, accountId, categories, start, end);
      written += await _sparse(txn, rng, accountId, categories, end);
      written += await _income(txn, rng, accountId, categories, start, end);
    });
    return written;
  }

  // ── shapes ────────────────────────────────────────────────────────────

  /// Rent: the same amount every month. Coefficient of variation ~0.01.
  static Future<int> _fixed(
    DatabaseExecutor txn,
    Random rng,
    int accountId,
    Map<String, int> categories,
    DateTime start,
    DateTime end,
  ) async {
    const baseCents = 4500000; // Rs 45,000
    var count = 0;
    for (
      var d = DateTime(start.year, start.month, 1);
      d.isBefore(end);
      d = DateTime(d.year, d.month + 1, 1)
    ) {
      // A little jitter, because a perfectly constant series is not realistic
      // and would let a classifier pass by accident on an equality check.
      final amount = baseCents + rng.nextInt(20000) - 10000;
      await _insert(txn, accountId, categories['Bills']!, amount, d, 'Rent');
      count++;
    }
    return count;
  }

  /// Groceries: most days, widely varying amounts.
  static Future<int> _variable(
    DatabaseExecutor txn,
    Random rng,
    int accountId,
    Map<String, int> categories,
    DateTime start,
    DateTime end,
  ) async {
    var count = 0;
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      if (rng.nextDouble() > 0.72) continue; // roughly 5 days in 7
      // Log-normal-ish: a long right tail, which is how real grocery spend
      // behaves. A uniform distribution would make the standard deviation
      // unrealistically small and the confidence score unrealistically high.
      final amount = (20000 + pow(rng.nextDouble(), 2) * 250000).round();
      await _insert(
        txn,
        accountId,
        categories['Food']!,
        amount,
        d,
        'Groceries',
      );
      count++;
    }
    return count;
  }

  /// Gifts: quiet most of the year, spiking in April and December.
  static Future<int> _seasonal(
    DatabaseExecutor txn,
    Random rng,
    int accountId,
    Map<String, int> categories,
    DateTime start,
    DateTime end,
  ) async {
    const spikeMonths = {4, 12}; // Sinhala/Tamil New Year, and Christmas
    var count = 0;
    for (var d = start; d.isBefore(end); d = d.add(const Duration(days: 1))) {
      final spiking = spikeMonths.contains(d.month);
      final chance = spiking ? 0.30 : 0.02;
      if (rng.nextDouble() > chance) continue;
      final amount = spiking
          ? 500000 +
                rng.nextInt(1000000) // Rs 5,000–15,000
          : 100000 + rng.nextInt(200000); // Rs 1,000–3,000
      await _insert(txn, accountId, categories['Gifts']!, amount, d, 'Gift');
      count++;
    }
    return count;
  }

  /// Fuel: a steady climb of roughly 8% a month.
  static Future<int> _trending(
    DatabaseExecutor txn,
    Random rng,
    int accountId,
    Map<String, int> categories,
    DateTime start,
    DateTime end,
  ) async {
    var count = 0;
    var monthIndex = 0;
    for (
      var d = DateTime(start.year, start.month, 1);
      d.isBefore(end);
      d = DateTime(d.year, d.month + 1, 1)
    ) {
      final growth = pow(1.08, monthIndex).toDouble();
      // Three fills a month, so the trend is visible within a month as well
      // as across them.
      for (var fill = 0; fill < 3; fill++) {
        final day = d.add(Duration(days: fill * 9 + rng.nextInt(4)));
        if (!day.isBefore(end)) continue;
        final amount = (300000 * growth + rng.nextInt(40000)).round();
        await _insert(txn, accountId, categories['Car']!, amount, day, 'Fuel');
        count++;
      }
      monthIndex++;
    }
    return count;
  }

  /// Pets: three transactions across the whole span.
  ///
  /// Exists to prove the confidence scorer says LOW rather than confidently
  /// budgeting from almost no evidence — the failure mode SRS Appendix C rates
  /// as the most likely risk on the project (R6).
  static Future<int> _sparse(
    DatabaseExecutor txn,
    Random rng,
    int accountId,
    Map<String, int> categories,
    DateTime end,
  ) async {
    for (final monthsBack in [2, 9, 17]) {
      final d = DateTime(end.year, end.month - monthsBack, 1 + rng.nextInt(27));
      await _insert(
        txn,
        accountId,
        categories['Pets']!,
        150000 + rng.nextInt(100000),
        d,
        'Vet',
      );
    }
    return 3;
  }

  /// Salary: monthly income, so the plan generator has a budget to work from.
  static Future<int> _income(
    DatabaseExecutor txn,
    Random rng,
    int accountId,
    Map<String, int> categories,
    DateTime start,
    DateTime end,
  ) async {
    var count = 0;
    for (
      var d = DateTime(start.year, start.month, 25);
      d.isBefore(end);
      d = DateTime(d.year, d.month + 1, 25)
    ) {
      await _insert(
        txn,
        accountId,
        categories['Salary']!,
        18000000 + rng.nextInt(200000), // Rs 180,000
        d,
        'Salary',
        type: 'income',
      );
      count++;
    }
    return count;
  }

  // ── plumbing ──────────────────────────────────────────────────────────

  static Future<void> _insert(
    DatabaseExecutor txn,
    int accountId,
    int categoryId,
    int amountCents,
    DateTime date,
    String note, {
    String type = 'expense',
  }) async {
    final iso = date.toIso8601String();
    await txn.insert('transactions', {
      'account_id': accountId,
      'category_id': categoryId,
      'amount_cents': amountCents,
      'type': type,
      'date': iso.substring(0, 10),
      'time': iso.substring(11, 16),
      'note': note,
      'created_at': iso,
      'updated_at': iso,
    });
  }

  static Future<int> _firstAccountId(DatabaseExecutor db) async {
    final rows = await db.query('accounts', columns: ['id'], limit: 1);
    if (rows.isEmpty) {
      throw StateError('Seed the default account before generating history.');
    }
    return rows.first['id']! as int;
  }

  static Future<Map<String, int>> _categoryIdsByName(
    DatabaseExecutor db,
  ) async {
    final rows = await db.query('categories', columns: ['id', 'name']);
    return {for (final r in rows) r['name']! as String: r['id']! as int};
  }
}
