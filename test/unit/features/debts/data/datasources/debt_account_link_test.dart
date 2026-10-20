@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/accounts/data/datasources/account_local_datasource.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/debts/data/datasources/debt_local_datasource.dart';
import 'package:moneyora/features/debts/data/models/debt_model.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/usecases/split_bill.dart';
import 'package:moneyora/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A debt carried through an account, against real SQLite at the latest
/// schema. FR-DBT-009, E-47, E-18.
///
/// Every case ends on the same two checks: the accounts' cached balances
/// are what recalculating them from history gives (E-18's oracle), and no
/// debt's money is income or spending (E-02).
void main() {
  sqfliteFfiInit();

  late Database db;
  late DebtLocalDataSourceImpl debts;
  late AccountLocalDataSourceImpl accounts;

  const cash = 1;
  const bank = 2;
  const cashOpening = 1000000;
  const bankOpening = 5000000;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          for (final version in schemaMigrations.keys.toList()..sort()) {
            for (final statement in schemaMigrations[version]!) {
              await d.execute(statement);
            }
          }
        },
        version: latestSchemaVersion,
      ),
    );
    const now = '2026-10-01T00:00:00Z';
    await db.insert('users', {'id': 1, 'created_at': now});
    for (final (id, name, opening) in [
      (cash, 'Cash', cashOpening),
      (bank, 'Bank', bankOpening),
    ]) {
      await db.insert('accounts', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'wallet',
        'initial_balance_cents': opening,
        'current_balance_cents': opening,
        'initial_balance_date': '2026-10-01',
        'created_at': now,
      });
    }
    debts = DebtLocalDataSourceImpl(
      db,
      clock: () => DateTime.utc(2026, 10, 20),
    );
    accounts = AccountLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await debts.dispose();
    await accounts.dispose();
    await db.close();
  });

  Future<int> balanceOf(int id) async =>
      (await db.query(
            'accounts',
            columns: ['current_balance_cents'],
            where: 'id = ?',
            whereArgs: [id],
          )).single['current_balance_cents']!
          as int;

  Future<List<Map<String, Object?>>> movements() =>
      db.query('transactions', where: 'debt_id IS NOT NULL', orderBy: 'id');

  /// E-18's oracle and E-02's rule, after every case.
  Future<void> holds() async {
    final cached = {
      for (final id in [cash, bank]) id: await balanceOf(id),
    };
    await accounts.recomputeAllBalances();
    for (final id in [cash, bank]) {
      expect(await balanceOf(id), cached[id], reason: 'account $id recomputed');
    }
    final spending = await db.rawQuery(
      "SELECT COUNT(*) AS n FROM transactions WHERE type IN ('income', "
      "'expense')",
    );
    expect(spending.single['n'], 0, reason: 'never income or spending');
  }

  DebtModel lent({
    int? id,
    int cents = 250000,
    int? account = cash,
    DateTime? paid,
    int? paidThrough,
    String person = 'Nimal',
  }) => DebtModel(
    id: id,
    direction: DebtDirection.owedToMe,
    person: person,
    amountCents: cents,
    incurredOn: DateTime(2026, 10, 5),
    accountId: account,
    paidOn: paid,
    paidAccountId: paidThrough,
  );

  test('created through an account, the money leaves it, as a balance '
      'movement of its own', () async {
    final id = await debts.add(lent());

    expect(await balanceOf(cash), cashOpening - 250000);
    final row = (await movements()).single;
    expect(row['debt_id'], id);
    expect(row['account_id'], cash);
    expect(row['type'], 'transfer');
    expect(row['transfer_direction'], 'out');
    expect(row['category_id'], isNull);
    expect(row['amount_cents'], 250000);
    expect(row['date'], '2026-10-05');
    expect(row['note'], 'Lent to Nimal');
    await holds();
  });

  test('borrowed into an account, the money arrives', () async {
    await debts.add(
      DebtModel(
        direction: DebtDirection.iOwe,
        person: 'Saman',
        amountCents: 120000,
        incurredOn: DateTime(2026, 10, 6),
        accountId: bank,
      ),
    );

    expect(await balanceOf(bank), bankOpening + 120000);
    expect((await movements()).single['note'], 'Borrowed from Saman');
    await holds();
  });

  test('without an account, nothing moves, as before', () async {
    await debts.add(lent(account: null));

    expect(await balanceOf(cash), cashOpening);
    expect(await movements(), isEmpty);
    await holds();
  });

  test('its amount changed, the account moves by the difference', () async {
    final id = await debts.add(lent());

    await debts.update(lent(id: id, cents: 400000));

    expect(await balanceOf(cash), cashOpening - 400000);
    expect((await movements()).single['amount_cents'], 400000);
    await holds();
  });

  test('its account changed, the first is made whole and the second '
      'moves', () async {
    final id = await debts.add(lent());

    await debts.update(lent(id: id, account: bank));

    expect(await balanceOf(cash), cashOpening);
    expect(await balanceOf(bank), bankOpening - 250000);
    expect((await movements()).single['account_id'], bank);
    await holds();
  });

  test('marked paid back through an account, the money comes back into '
      'it', () async {
    final id = await debts.add(lent());

    await debts.update(
      lent(id: id, paid: DateTime(2026, 10, 18), paidThrough: bank),
    );

    expect(await balanceOf(cash), cashOpening - 250000);
    expect(await balanceOf(bank), bankOpening + 250000);
    final rows = await movements();
    expect(rows, hasLength(2));
    expect(rows.last['transfer_direction'], 'in');
    expect(rows.last['date'], '2026-10-18');
    expect(rows.last['note'], 'Nimal paid back');
    await holds();
  });

  test('marked not paid after all, the money goes back out', () async {
    final id = await debts.add(lent());
    await debts.update(
      lent(id: id, paid: DateTime(2026, 10, 18), paidThrough: cash),
    );
    expect(await balanceOf(cash), cashOpening);

    await debts.update(lent(id: id));

    expect(await balanceOf(cash), cashOpening - 250000);
    expect(await movements(), hasLength(1));
    await holds();
  });

  test('deleted, every account is as it was before it', () async {
    final id = await debts.add(lent());
    await debts.update(
      lent(id: id, paid: DateTime(2026, 10, 18), paidThrough: bank),
    );

    await debts.delete(id);

    expect(await balanceOf(cash), cashOpening);
    expect(await balanceOf(bank), bankOpening);
    expect(await movements(), isEmpty);
    expect(await db.query('debts'), isEmpty);
    await holds();
  });

  test('a split bill names no account, so moves none', () async {
    await debts.addAll([
      for (final debt in SplitBill.debtsFor(
        SplitRequest(
          totalCents: 300000,
          others: const ['Nimal', 'Saman'],
          on: DateTime(2026, 10, 7),
        ),
      ))
        DebtModel.fromEntity(debt),
    ]);

    expect(await db.query('debts'), hasLength(2));
    expect(await movements(), isEmpty);
    expect(await balanceOf(cash), cashOpening);
    await holds();
  });

  test('a payment moves its account once, and closing it moves nothing '
      'more', () async {
    final payment = DebtModel(
      direction: DebtDirection.iOwe,
      person: 'Nimal',
      amountCents: 60000,
      incurredOn: DateTime(2026, 10, 20),
      paidOn: DateTime(2026, 10, 20),
      note: 'Settled up',
      isPayment: true,
      accountId: cash,
      // Ignored: a payment is the money moving.
      paidAccountId: bank,
    );

    await debts.add(payment);

    expect(await balanceOf(cash), cashOpening + 60000);
    expect(await balanceOf(bank), bankOpening);
    expect((await movements()).single['note'], 'Nimal paid back · Settled up');
    await holds();
  });

  test('settled up through an account, as one write: the net moves once, the '
      'records closed move nothing', () async {
    final loan = await debts.add(lent(cents: 100000));
    final lunch = await debts.add(
      DebtModel(
        direction: DebtDirection.iOwe,
        person: 'Nimal',
        amountCents: 40000,
        incurredOn: DateTime(2026, 10, 6),
        accountId: bank,
      ),
    );
    final settledOn = DateTime(2026, 10, 20);
    final open = await debts.list();

    await debts.batch(
      add: [
        DebtModel(
          direction: DebtDirection.iOwe,
          person: 'Nimal',
          amountCents: 60000,
          incurredOn: settledOn,
          paidOn: settledOn,
          isPayment: true,
          accountId: cash,
        ),
      ],
      update: [
        for (final d in open)
          DebtModel.fromEntity(d.toEntity().withPaidOn(settledOn)),
      ],
    );

    // Lent 1,000 from cash, borrowed 400 into the bank, 600 back in cash.
    expect(await balanceOf(cash), cashOpening - 100000 + 60000);
    expect(await balanceOf(bank), bankOpening + 40000);
    expect(
      (await movements()).where((m) => m['debt_id'] == loan),
      hasLength(1),
    );
    expect(
      (await movements()).where((m) => m['debt_id'] == lunch),
      hasLength(1),
    );
    await holds();
  });

  test('renamed, the history says the new name', () async {
    final id = await debts.add(lent(person: 'Nimal P'));

    await debts.updateAll([lent(id: id, person: 'Nimal Perera')]);

    expect((await movements()).single['note'], 'Lent to Nimal Perera');
    await holds();
  });

  test('all or none: a write that fails moves no account', () async {
    final id = await debts.add(lent());

    await expectLater(
      debts.batch(
        update: [lent(id: id, cents: 999999)],
        delete: [id + 99],
      ),
      throwsA(isA<CacheException>()),
    );

    expect(await balanceOf(cash), cashOpening - 250000);
    expect((await movements()).single['amount_cents'], 250000);
    await holds();
  });

  test('the account\'s history has it, and the ledger will not delete it '
      'from under its debt', () async {
    await debts.add(lent());
    final ledger = TransactionLocalDataSourceImpl(db);
    addTearDown(ledger.dispose);
    final row = (await movements()).single;

    await expectLater(
      ledger.delete(row['id']! as int),
      throwsA(
        isA<CacheException>().having(
          (e) => e.message,
          'message',
          "That is a debt's money. Change or delete it under Debts.",
        ),
      ),
    );
    expect(await movements(), hasLength(1));
    expect(await balanceOf(cash), cashOpening - 250000);
  });

  test(
    'one account\'s period counts it as money out, never as spending',
    () async {
      await debts.add(lent());
      final analytics = AnalyticsLocalDataSourceImpl(db);
      final from = DateTime(2026, 10, 1);
      final to = DateTime(2026, 10, 31);

      final moved = await analytics.transfersForPeriod(
        from: from,
        to: to,
        accountId: cash,
      );
      final spent = await analytics.spendingByCategory(from: from, to: to);
      final earned = await analytics.incomeForPeriod(from: from, to: to);

      expect(moved.outCents, 250000);
      expect(spent, isEmpty);
      expect(earned, 0);
    },
  );
}
