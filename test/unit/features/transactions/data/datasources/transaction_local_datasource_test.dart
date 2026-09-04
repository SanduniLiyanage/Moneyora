@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:moneyora/features/transactions/data/models/transaction_model.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// These run against a real SQLite database, in memory.
///
/// A mocked datasource would prove nothing here: every claim worth making is
/// about what SQLite does — that a failed statement rolls its whole
/// transaction back, that a cascade fires, that a foreign key refuses. Mocking
/// the database would mean asserting that the mock behaves as I imagined it.
void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  late Database db;
  late TransactionLocalDataSourceImpl source;

  const cash = 1;
  const card = 2;
  const food = 1;
  const transport = 2;
  const salary = 3;
  const missingCategory = 999;
  const missingAccount = 999;

  final date = DateTime(2026, 9, 2);

  setUp(() async {
    db = await factory.openDatabase(
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

    const now = '2026-09-01T00:00:00Z';
    await db.insert('users', {'id': 1, 'created_at': now});
    for (final (id, name) in [(cash, 'Cash'), (card, 'Payment card')]) {
      await db.insert('accounts', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'wallet',
        'initial_balance_cents': 0,
        'current_balance_cents': 0,
        'initial_balance_date': '2026-09-01',
        'created_at': now,
      });
    }
    for (final (id, name, type) in [
      (food, 'Food', 'expense'),
      (transport, 'Transport', 'expense'),
      (salary, 'Salary', 'income'),
    ]) {
      await db.insert('categories', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'dot',
        'color': '#3F51B5',
        'type': type,
      });
    }

    source = TransactionLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await source.dispose();
    await db.close();
  });

  // ── helpers ───────────────────────────────────────────────────────────────

  TransactionModel expense({
    int amountCents = 50000,
    int accountId = cash,
    int categoryId = food,
    DateTime? on,
    String? note,
    List<TransactionSplit> parts = const [],
    int? id,
  }) => TransactionModel(
    id: id,
    accountId: accountId,
    categoryId: categoryId,
    amountCents: amountCents,
    type: TransactionType.expense,
    date: on ?? date,
    note: note,
    splits: parts,
  );

  TransactionModel income({int amountCents = 300000, int accountId = cash}) =>
      TransactionModel(
        accountId: accountId,
        categoryId: salary,
        amountCents: amountCents,
        type: TransactionType.income,
        date: date,
      );

  Future<int> balanceOf(int accountId) async {
    final rows = await db.query(
      'accounts',
      columns: ['current_balance_cents'],
      where: 'id = ?',
      whereArgs: [accountId],
    );
    return rows.first['current_balance_cents']! as int;
  }

  Future<int> countOf(String table) async =>
      (await db.rawQuery('SELECT COUNT(*) AS c FROM $table')).first['c']!
          as int;

  /// The balance re-derived from history, which the cached column must match.
  ///
  /// This is the reconciliation E-18 asks for, written as a test oracle: it
  /// knows nothing about how the datasource maintains the cache, only what the
  /// answer has to be.
  Future<int> recomputeBalance(int accountId) async {
    final rows = await db.query(
      'transactions',
      where: 'account_id = ?',
      whereArgs: [accountId],
    );
    var total = 0;
    for (final row in rows) {
      final model = TransactionModel.fromMap(row);
      total += switch (model.type) {
        TransactionType.income => model.amountCents,
        TransactionType.expense => -model.amountCents,
        TransactionType.transfer =>
          model.transferDirection == TransferDirection.incoming
              ? model.amountCents
              : -model.amountCents,
      };
    }
    return total;
  }

  // ── add ───────────────────────────────────────────────────────────────────

  group('add', () {
    test('inserts the row and returns its id', () async {
      final id = await source.add(expense());

      expect(id, greaterThan(0));
      expect(await countOf('transactions'), 1);
    });

    test('moves the cached balance down for an expense', () async {
      await source.add(expense(amountCents: 125000));

      expect(await balanceOf(cash), -125000);
    });

    test('moves the cached balance up for income', () async {
      await source.add(income(amountCents: 450000));

      expect(await balanceOf(cash), 450000);
    });

    test('touches only the account the row belongs to', () async {
      await source.add(expense(accountId: card));

      expect(await balanceOf(card), -50000);
      expect(await balanceOf(cash), 0);
    });

    test('writes split parts with the parent', () async {
      final id = await source.add(
        expense(
          amountCents: 125000,
          parts: const [
            TransactionSplit(categoryId: food, amountCents: 75000),
            TransactionSplit(categoryId: transport, amountCents: 50000),
          ],
        ),
      );

      final splits = await db.query(
        'transaction_splits',
        where: 'transaction_id = ?',
        whereArgs: [id],
      );
      expect(splits, hasLength(2));

      final parent = await db.query(
        'transactions',
        where: 'id = ?',
        whereArgs: [id],
      );
      expect(parent.first['is_split'], 1);
    });

    test('refuses a transfer, which must go through createTransfer', () async {
      // E-15: writing one half on its own leaves the other account short, and
      // nothing downstream can tell that it happened.
      final half = TransactionModel(
        accountId: cash,
        amountCents: 50000,
        type: TransactionType.transfer,
        transferDirection: TransferDirection.out,
        date: date,
      );

      expect(() => source.add(half), throwsA(isA<CacheException>()));
      expect(await countOf('transactions'), 0);
    });

    test('rolls the parent and the balance back when a split fails', () async {
      // The parent inserts, the balance moves, and then a split with an
      // unknown category violates its foreign key. If the write were not one
      // transaction, this would leave a transaction whose parts are missing
      // and an account permanently out by its amount.
      final doomed = expense(
        amountCents: 125000,
        parts: const [
          TransactionSplit(categoryId: food, amountCents: 75000),
          TransactionSplit(categoryId: missingCategory, amountCents: 50000),
        ],
      );

      await expectLater(source.add(doomed), throwsA(isA<CacheException>()));

      expect(await countOf('transactions'), 0, reason: 'parent rolled back');
      expect(await countOf('transaction_splits'), 0);
      expect(await balanceOf(cash), 0, reason: 'balance rolled back');
    });
  });

  // ── update ────────────────────────────────────────────────────────────────

  group('update', () {
    test('reverses the old amount and applies the new one', () async {
      final id = await source.add(expense(amountCents: 50000));

      await source.update(expense(id: id, amountCents: 80000));

      expect(await balanceOf(cash), -80000);
    });

    test(
      'moves the balance between accounts when the account changes',
      () async {
        final id = await source.add(expense(amountCents: 50000));

        await source.update(expense(id: id, accountId: card));

        expect(await balanceOf(cash), 0, reason: 'old account restored');
        expect(await balanceOf(card), -50000, reason: 'new account charged');
      },
    );

    test('replaces split parts rather than accumulating them', () async {
      final id = await source.add(
        expense(
          amountCents: 100000,
          parts: const [
            TransactionSplit(categoryId: food, amountCents: 60000),
            TransactionSplit(categoryId: transport, amountCents: 40000),
          ],
        ),
      );

      await source.update(
        expense(
          id: id,
          amountCents: 100000,
          parts: const [
            TransactionSplit(categoryId: food, amountCents: 100000),
          ],
        ),
      );

      expect(await countOf('transaction_splits'), 1);
    });

    test('refuses a model with no id', () async {
      expect(() => source.update(expense()), throwsA(isA<CacheException>()));
    });

    test('refuses an id that is not there', () async {
      expect(
        () => source.update(expense(id: 4242)),
        throwsA(isA<CacheException>()),
      );
    });
  });

  // ── delete ────────────────────────────────────────────────────────────────

  group('delete', () {
    test('removes the row and restores the balance', () async {
      final id = await source.add(expense(amountCents: 50000));

      await source.delete(id);

      expect(await countOf('transactions'), 0);
      expect(await balanceOf(cash), 0);
    });

    test('takes the split parts with it', () async {
      final id = await source.add(
        expense(
          amountCents: 100000,
          parts: const [
            TransactionSplit(categoryId: food, amountCents: 100000),
          ],
        ),
      );

      await source.delete(id);

      expect(await countOf('transaction_splits'), 0);
    });
  });

  // ── transfers ─────────────────────────────────────────────────────────────

  group('createTransfer', () {
    test('writes two transaction rows and one header', () async {
      await source.createTransfer(
        fromAccountId: card,
        toAccountId: cash,
        amountCents: 800000,
        date: date,
      );

      expect(await countOf('transactions'), 2);
      expect(await countOf('transfers'), 1);
    });

    test('marks the halves out and in, with no category', () async {
      await source.createTransfer(
        fromAccountId: card,
        toAccountId: cash,
        amountCents: 800000,
        date: date,
      );

      final rows = await db.query('transactions', orderBy: 'id ASC');
      expect(rows[0]['transfer_direction'], 'out');
      expect(rows[0]['account_id'], card);
      expect(rows[1]['transfer_direction'], 'in');
      expect(rows[1]['account_id'], cash);
      // E-17: a transfer is not spending, so it carries no category.
      expect(rows.every((r) => r['category_id'] == null), isTrue);
    });

    test('the header points at both halves', () async {
      final transferId = await source.createTransfer(
        fromAccountId: card,
        toAccountId: cash,
        amountCents: 800000,
        date: date,
      );

      final header = (await db.query(
        'transfers',
        where: 'id = ?',
        whereArgs: [transferId],
      )).first;
      final halves = await db.query('transactions', orderBy: 'id ASC');

      expect(header['from_tx_id'], halves[0]['id']);
      expect(header['to_tx_id'], halves[1]['id']);
    });

    test('moves both balances, source down and destination up', () async {
      // Withdrawing 8,000 from the card and holding it as cash: the card falls
      // and the cash rises by the same amount, and nothing is income or spend.
      await source.createTransfer(
        fromAccountId: card,
        toAccountId: cash,
        amountCents: 800000,
        date: date,
      );

      expect(await balanceOf(card), -800000);
      expect(await balanceOf(cash), 800000);
    });

    test('leaves nothing behind when the destination does not exist', () async {
      // The first half inserts, then the second violates its foreign key. A
      // partial write here is money that left one account without arriving in
      // the other — the failure E-15 exists to prevent.
      await expectLater(
        source.createTransfer(
          fromAccountId: card,
          toAccountId: missingAccount,
          amountCents: 800000,
          date: date,
        ),
        throwsA(isA<CacheException>()),
      );

      expect(await countOf('transactions'), 0);
      expect(await countOf('transfers'), 0);
      expect(await balanceOf(card), 0);
    });

    test('deleting either half removes the whole transfer', () async {
      await source.createTransfer(
        fromAccountId: card,
        toAccountId: cash,
        amountCents: 800000,
        date: date,
      );
      final halves = await db.query('transactions', orderBy: 'id ASC');

      // Delete the incoming half — the one a user is least likely to think of
      // as "the transfer".
      await source.delete(halves[1]['id']! as int);

      expect(await countOf('transactions'), 0);
      expect(await countOf('transfers'), 0);
      expect(await balanceOf(card), 0);
      expect(await balanceOf(cash), 0);
    });
  });

  // ── list ──────────────────────────────────────────────────────────────────

  group('list', () {
    setUp(() async {
      await source.add(expense(amountCents: 10000, on: DateTime(2026, 9, 1)));
      await source.add(
        expense(
          amountCents: 20000,
          on: DateTime(2026, 9, 3),
          categoryId: transport,
          note: 'Bus to Kandy',
        ),
      );
      await source.add(income(amountCents: 500000));
      await source.createTransfer(
        fromAccountId: card,
        toAccountId: cash,
        amountCents: 800000,
        date: DateTime(2026, 9, 4),
      );
    });

    test('returns everything, newest first', () async {
      final rows = await source.list(const TransactionFilter());

      expect(rows, hasLength(5));
      expect(rows.first.date, DateTime(2026, 9, 4));
      expect(rows.last.date, DateTime(2026, 9, 1));
    });

    test('excludes transfers for analytics', () async {
      // E-02: two rows exist per transfer, so a query that forgets this
      // inflates both income and expense by the transferred amount.
      final rows = await source.list(const TransactionFilter.forAnalytics());

      expect(rows, hasLength(3));
      expect(rows.every((r) => r.type != TransactionType.transfer), isTrue);
    });

    test('filters by account, catching both sides of a transfer', () async {
      final rows = await source.list(const TransactionFilter(accountId: card));

      expect(rows, hasLength(1));
      expect(rows.single.transferDirection, TransferDirection.out);
    });

    test('filters by category', () async {
      final rows = await source.list(
        const TransactionFilter(categoryId: transport),
      );

      expect(rows, hasLength(1));
      expect(rows.single.amountCents, 20000);
    });

    test('filters by type', () async {
      final rows = await source.list(
        const TransactionFilter(type: TransactionType.income),
      );

      expect(rows, hasLength(1));
      expect(rows.single.amountCents, 500000);
    });

    test('filters by an inclusive date range', () async {
      final rows = await source.list(
        TransactionFilter(from: DateTime(2026, 9, 3), to: DateTime(2026, 9, 3)),
      );

      expect(rows, hasLength(1));
      expect(rows.single.amountCents, 20000);
    });

    test('filters by amount', () async {
      final rows = await source.list(
        const TransactionFilter(minAmountCents: 500000),
      );

      expect(rows, hasLength(3));
    });

    test('searches the note, case-insensitively', () async {
      final rows = await source.list(
        const TransactionFilter(noteContains: 'kandy'),
      );

      expect(rows, hasLength(1));
    });

    test('treats a wildcard in the search text literally', () async {
      // Without escaping, '%' would match every note that exists.
      final rows = await source.list(
        const TransactionFilter(noteContains: '%'),
      );

      expect(rows, isEmpty);
    });

    test('loads split parts with their parent', () async {
      await source.add(
        expense(
          amountCents: 90000,
          on: DateTime(2026, 9, 5),
          parts: const [
            TransactionSplit(categoryId: food, amountCents: 60000),
            TransactionSplit(categoryId: transport, amountCents: 30000),
          ],
        ),
      );

      final rows = await source.list(const TransactionFilter());

      expect(rows.first.splits, hasLength(2));
      expect(rows.first.splitTotalCents, 90000);
      // Unsplit rows are not asked about at all.
      expect(rows[1].splits, isEmpty);
    });
  });

  // ── the E-18 reconciliation oracle ────────────────────────────────────────

  group('the cached balance survives a random sequence of writes', () {
    test('cached == recomputed for every account', () async {
      // E-18 calls the cached column a cache and asks for a reconciliation.
      // This is that reconciliation used as an oracle: any write path that
      // forgets to move the balance, moves it twice, or moves the wrong
      // account fails here, and no amount of hand-testing finds those
      // reliably.
      //
      // Seeded so a failure is reproducible. A fixture whose sequence changes
      // between runs reports a different bug each time it is run.
      final random = Random(20260904);
      final liveIds = <int>[];

      for (var step = 0; step < 120; step++) {
        switch (random.nextInt(5)) {
          case 0:
            liveIds.add(
              await source.add(
                expense(
                  amountCents: 1000 + random.nextInt(90000),
                  accountId: random.nextBool() ? cash : card,
                ),
              ),
            );
          case 1:
            liveIds.add(
              await source.add(
                income(
                  amountCents: 1000 + random.nextInt(90000),
                  accountId: random.nextBool() ? cash : card,
                ),
              ),
            );
          case 2:
            // Two independent coin flips would sometimes pick the same account
            // on both sides, which CHECK(from_account_id <> to_account_id)
            // rightly refuses. One flip, and the other side is whatever is
            // left.
            final fromAccount = random.nextBool() ? cash : card;
            await source.createTransfer(
              fromAccountId: fromAccount,
              toAccountId: fromAccount == cash ? card : cash,
              amountCents: 1000 + random.nextInt(50000),
              date: date,
            );
          case 3:
            if (liveIds.isEmpty) continue;
            final id = liveIds[random.nextInt(liveIds.length)];
            await source.update(
              expense(
                id: id,
                amountCents: 1000 + random.nextInt(90000),
                accountId: random.nextBool() ? cash : card,
              ),
            );
          case 4:
            if (liveIds.isEmpty) continue;
            final id = liveIds.removeAt(random.nextInt(liveIds.length));
            await source.delete(id);
        }
      }

      for (final accountId in [cash, card]) {
        expect(
          await balanceOf(accountId),
          await recomputeBalance(accountId),
          reason: 'cached balance drifted from history on account $accountId',
        );
      }
      // A test that did nothing would also pass the assertion above.
      expect(await countOf('transactions'), greaterThan(10));
    });
  });

  // ── change notification ───────────────────────────────────────────────────

  group('changes', () {
    test('fires once per successful write', () async {
      final seen = <void>[];
      final subscription = source.changes.listen(seen.add);

      final id = await source.add(expense());
      await source.update(expense(id: id, amountCents: 60000));
      await source.delete(id);
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(3));
      await subscription.cancel();
    });

    test('stays quiet when a write fails', () async {
      final seen = <void>[];
      final subscription = source.changes.listen(seen.add);

      await expectLater(
        source.add(expense(categoryId: missingCategory)),
        throwsA(isA<CacheException>()),
      );
      await Future<void>.delayed(Duration.zero);

      expect(seen, isEmpty);
      await subscription.cancel();
    });
  });
}
