@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/accounts/data/datasources/account_local_datasource.dart';
import 'package:moneyora/features/accounts/data/models/account_model.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:moneyora/features/transactions/data/models/transaction_model.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// Against a real in-memory SQLite, because every claim here is about what
/// SQLite does — that a foreign key refuses, that SUM over no rows is null.
///
/// The reconciliation tests are the point of the file. E-18 called the stored
/// balance a cache and specified no way to check it; this is that check, and
/// it is driven through the *transactions* datasource so the two write paths
/// are tested against each other rather than against my own arithmetic twice.
void main() {
  sqfliteFfiInit();

  late Database db;
  late AccountLocalDataSourceImpl accounts;
  late TransactionLocalDataSourceImpl transactions;

  const cash = 1;
  const card = 2;
  const food = 1;
  const salary = 3;

  final date = DateTime(2026, 9, 2);
  final opened = DateTime(2026, 1, 1);

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

    const now = '2026-01-01T00:00:00Z';
    await db.insert('users', {'id': 1, 'created_at': now});
    for (final (id, name) in [(cash, 'Cash'), (card, 'Payment card')]) {
      await db.insert('accounts', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'wallet',
        'initial_balance_date': '2026-01-01',
        'created_at': now,
      });
    }
    for (final (id, name, type) in [
      (food, 'Food', 'expense'),
      (2, 'Transport', 'expense'),
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

    accounts = AccountLocalDataSourceImpl(db);
    transactions = TransactionLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await accounts.dispose();
    await transactions.dispose();
    await db.close();
  });

  AccountModel model({
    String name = 'Savings',
    int initialBalanceCents = 0,
    AccountType type = AccountType.bank,
    int? id,
  }) => AccountModel(
    id: id,
    name: name,
    icon: 'bank',
    type: type,
    initialBalanceCents: initialBalanceCents,
    initialBalanceDate: opened,
  );

  Future<int> balanceOf(int id) async =>
      (await db.query(
            'accounts',
            columns: ['current_balance_cents'],
            where: 'id = ?',
            whereArgs: [id],
          )).first['current_balance_cents']!
          as int;

  TransactionModel expense({int amountCents = 50000, int accountId = cash}) =>
      TransactionModel(
        accountId: accountId,
        categoryId: food,
        amountCents: amountCents,
        type: TransactionType.expense,
        date: date,
      );

  // ── CRUD ──────────────────────────────────────────────────────────────────

  group('add', () {
    test(
      'stores the account and seeds its balance from the opening figure',
      () async {
        final id = await accounts.add(model(initialBalanceCents: 250000));

        expect(await balanceOf(id), 250000);
      },
    );

    test('accepts a negative opening balance for a credit card', () async {
      // Money owed rather than held. Unlike a transaction amount, this is
      // ordinary rather than suspicious.
      final id = await accounts.add(
        model(
          name: 'Visa',
          type: AccountType.creditCard,
          initialBalanceCents: -450000,
        ),
      );

      expect(await balanceOf(id), -450000);
    });

    test('round-trips the type through its storage string', () async {
      // AccountType.creditCard.name is 'creditCard'; the CHECK accepts only
      // 'credit_card'. Using .name would pass every test that never touches
      // SQLite and fail on the first insert.
      final id = await accounts.add(
        model(name: 'Visa', type: AccountType.creditCard),
      );

      final read = (await accounts.list()).firstWhere((a) => a.id == id);
      expect(read.type, AccountType.creditCard);
    });
  });

  group('update', () {
    test('changes the editable fields', () async {
      final id = await accounts.add(model());

      await accounts.update(model(id: id, name: 'Renamed'));

      final read = (await accounts.list()).firstWhere((a) => a.id == id);
      expect(read.name, 'Renamed');
    });

    test('re-derives the balance when the opening figure moves', () async {
      final id = await accounts.add(model(initialBalanceCents: 100000));
      await transactions.add(expense(accountId: id, amountCents: 30000));
      expect(await balanceOf(id), 70000);

      await accounts.update(model(id: id, initialBalanceCents: 200000));

      // Changing the opening balance moves every total derived from it, so
      // leaving the cache alone here would strand it 100,000 too low.
      expect(await balanceOf(id), 170000);
    });

    test('refuses an id that is not there', () async {
      expect(
        () => accounts.update(model(id: 4242)),
        throwsA(isA<CacheException>()),
      );
    });
  });

  group('archive', () {
    test('hides the account without touching its transactions', () async {
      await transactions.add(expense());

      await accounts.setArchived(cash, archived: true);

      expect((await accounts.list()).map((a) => a.id), isNot(contains(cash)));
      expect(
        (await accounts.list(includeArchived: true)).map((a) => a.id),
        contains(cash),
      );
      // The history is the whole reason archiving exists rather than deleting.
      expect(await transactions.list(const TransactionFilter()), hasLength(1));
    });

    test('can be undone', () async {
      await accounts.setArchived(cash, archived: true);
      await accounts.setArchived(cash, archived: false);

      expect((await accounts.list()).map((a) => a.id), contains(cash));
    });
  });

  group('delete', () {
    test('removes an account nothing references', () async {
      final id = await accounts.add(model());

      await accounts.delete(id);

      expect((await accounts.list()).map((a) => a.id), isNot(contains(id)));
    });

    test('refuses once a transaction names it, and says how many', () async {
      await transactions.add(expense());
      await transactions.add(expense());

      await expectLater(
        accounts.delete(cash),
        throwsA(
          isA<CacheException>().having(
            (e) => e.message,
            'message',
            contains('2 transactions'),
          ),
        ),
      );
      expect((await accounts.list()).map((a) => a.id), contains(cash));
    });
  });

  // ── E-18: the reconciliation ──────────────────────────────────────────────

  group('recomputeBalance', () {
    test('is the opening balance when there is no history', () async {
      // SUM over an empty set is NULL, not zero. Without COALESCE this comes
      // back null and the cast throws on a brand-new account.
      final id = await accounts.add(model(initialBalanceCents: 75000));

      expect(await accounts.recomputeBalance(id), 75000);
    });

    test('adds income and subtracts expense', () async {
      await transactions.add(expense(amountCents: 30000));
      await transactions.add(
        TransactionModel(
          accountId: cash,
          categoryId: salary,
          amountCents: 500000,
          type: TransactionType.income,
          date: date,
        ),
      );

      expect(await accounts.recomputeBalance(cash), 470000);
    });

    test(
      'reads a transfer from the direction column, not from a join',
      () async {
        // E-16 put the direction on the transaction row precisely so balance
        // arithmetic never has to join `transfers` to discover which way the
        // money went.
        await transactions.createTransfer(
          fromAccountId: card,
          toAccountId: cash,
          amountCents: 800000,
          date: date,
        );

        expect(await accounts.recomputeBalance(card), -800000);
        expect(await accounts.recomputeBalance(cash), 800000);
      },
    );

    test('repairs a balance that was corrupted behind the app', () async {
      await transactions.add(expense(amountCents: 125000));
      // Simulate the drift E-18 warns about: a write path that forgot to
      // update the cache, or a restore that put the column back wrong.
      await db.update('accounts', {'current_balance_cents': 999999});

      final repaired = await accounts.recomputeBalance(cash);

      expect(repaired, -125000);
      expect(await balanceOf(cash), -125000);
    });

    test('recomputeAllBalances repairs every account at once', () async {
      await transactions.add(expense(amountCents: 20000));
      await transactions.add(expense(accountId: card, amountCents: 30000));
      await db.update('accounts', {'current_balance_cents': 12345});

      await accounts.recomputeAllBalances();

      expect(await balanceOf(cash), -20000);
      expect(await balanceOf(card), -30000);
    });

    test('refuses an account that does not exist', () async {
      expect(
        () => accounts.recomputeBalance(4242),
        throwsA(isA<CacheException>()),
      );
    });
  });

  group('cached equals recomputed', () {
    test('after a random sequence of writes on both accounts', () async {
      // The property E-18 asks for, now checkable rather than only asserted.
      // The transactions datasource maintains the cache incrementally; this
      // derives it from history independently. Any write path that forgets an
      // update, doubles one, or moves the wrong account fails here.
      final random = Random(20260906);
      final live = <int>[];

      for (var step = 0; step < 90; step++) {
        switch (random.nextInt(4)) {
          case 0:
            live.add(
              await transactions.add(
                expense(
                  amountCents: 1000 + random.nextInt(80000),
                  accountId: random.nextBool() ? cash : card,
                ),
              ),
            );
          case 1:
            live.add(
              await transactions.add(
                TransactionModel(
                  accountId: random.nextBool() ? cash : card,
                  categoryId: salary,
                  amountCents: 1000 + random.nextInt(80000),
                  type: TransactionType.income,
                  date: date,
                ),
              ),
            );
          case 2:
            final from = random.nextBool() ? cash : card;
            await transactions.createTransfer(
              fromAccountId: from,
              toAccountId: from == cash ? card : cash,
              amountCents: 1000 + random.nextInt(40000),
              date: date,
            );
          case 3:
            if (live.isEmpty) continue;
            await transactions.delete(
              live.removeAt(random.nextInt(live.length)),
            );
        }
      }

      for (final id in [cash, card]) {
        final cached = await balanceOf(id);
        expect(
          cached,
          await accounts.recomputeBalance(id),
          reason: 'cached balance drifted from history on account $id',
        );
      }
    });
  });

  group('changes', () {
    test('fires on every successful write', () async {
      final seen = <void>[];
      final subscription = accounts.changes.listen(seen.add);

      final id = await accounts.add(model());
      await accounts.setArchived(id, archived: true);
      await Future<void>.delayed(Duration.zero);

      expect(seen, hasLength(2));
      await subscription.cancel();
    });
  });
}
