@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/features/accounts/data/datasources/account_local_datasource.dart';
import 'package:moneyora/features/debts/data/datasources/debt_local_datasource.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A database as a released version leaves it, updated in place to this
/// one: every row of every table as it was, every balance where it was.
/// NFR-REL-002, NFR-REL-005, E-47.
///
/// A tester asked that old data never disappear on an update. Each
/// migration has its own test (`v7_debts_test.dart`, `v8_…`, `v9_…`);
/// this one starts from what a phone actually has — 1.2.0's schema v8 and
/// 1.1.0's v6, filled the way the app fills them — opens it through the
/// app's own [DatabaseHelper], from a file, as an update does, and reads
/// it back through the datasources the screens use.
void main() {
  sqfliteFfiInit();

  late Directory dir;
  late String databases;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('moneyora-upgrade-');
    // The app opens `moneyora.db` in the platform's databases folder.
    databases = await databaseFactoryFfi.getDatabasesPath();
    await databaseFactoryFfi.setDatabasesPath(dir.path);
  });

  tearDown(() async {
    await databaseFactoryFfi.setDatabasesPath(databases);
    await dir.delete(recursive: true);
  });

  const now = '2026-10-11T08:00:00Z';

  /// A database at every version up to [upTo], as that release left it.
  Future<String> released(int upTo) async {
    final path = '${dir.path}/moneyora.db';
    final db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute(createSchemaMigrations);
    for (final version
        in schemaMigrations.keys.where((v) => v <= upTo).toList()..sort()) {
      for (final statement in schemaMigrations[version]!) {
        await db.execute(statement);
      }
      await db.insert('schema_migrations', {
        'version': version,
        'applied_at': now,
      });
    }

    await db.insert('users', {'id': 1, 'created_at': now});
    await db.insert('accounts', {
      'id': 1,
      'user_id': 1,
      'name': 'Cash',
      'icon': 'wallet',
      'initial_balance_cents': 500000,
      // 5,000 + 2,500 income - 1,250 - 300 - 999.99 - 200 transferred out.
      'current_balance_cents': 500000 + 250000 - 125000 - 30000 - 99999 - 20000,
      'initial_balance_date': '2026-09-01',
      'created_at': now,
    });
    await db.insert('accounts', {
      'id': 2,
      'user_id': 1,
      'name': 'Visa',
      'icon': 'card',
      'type': 'credit_card',
      'initial_balance_cents': 0,
      'current_balance_cents': 20000,
      'initial_balance_date': '2026-09-01',
      'created_at': now,
      if (upTo >= 8) ...{
        'credit_limit_cents': 5000000,
        'statement_day': 25,
        'payment_due_day': 10,
        'apr_basis_points': 2450,
      },
    });
    for (final (id, name, type) in [
      (1, 'Food', 'expense'),
      (2, 'Transport', 'expense'),
      (3, 'Salary', 'income'),
    ]) {
      await db.insert('categories', {
        'id': id,
        'user_id': 1,
        'name': name,
        'icon': 'dot',
        'color': '#3F51B5',
        'type': type,
        'is_default': 1,
      });
    }
    await db.insert('receipt_scans', {
      'id': 1,
      'user_id': 1,
      'image_path': '/data/receipts/1.jpg.enc',
      'merchant_name': 'Keells',
      'receipt_date': '2026-10-02',
      'total_amount_cents': 99999,
      'confidence_score': 80,
      'status': 'confirmed',
      'created_at': now,
    });
    await db.insert('receipt_items', {
      'id': 1,
      'receipt_scan_id': 1,
      'name': 'Rice 5kg',
      'quantity': 1.0,
      'total_price_cents': 99999,
      'suggested_category_id': 1,
      'confirmed_category_id': 1,
      'confidence_score': 90,
    });

    Map<String, Object?> row(
      int id,
      String type,
      int cents, {
      int account = 1,
      int? category,
      String? time,
      String? direction,
      int? scan,
      int split = 0,
    }) => {
      'id': id,
      'account_id': account,
      'category_id': category,
      'amount_cents': cents,
      'type': type,
      'transfer_direction': direction,
      'date': '2026-10-0$id',
      'time': time,
      'note': 'Row $id',
      'receipt_scan_id': scan,
      'is_split': split,
      'created_at': now,
      'updated_at': now,
    };
    await db.insert(
      'transactions',
      row(1, 'expense', 125000, category: 1, time: '12:58'),
    );
    await db.insert('transactions', row(2, 'expense', 30000, category: 2));
    await db.insert(
      'transactions',
      row(3, 'income', 250000, category: 3, time: '09:00'),
    );
    await db.insert(
      'transactions',
      row(4, 'expense', 99999, category: 1, scan: 1, split: 1),
    );
    await db.insert('transaction_splits', {
      'transaction_id': 4,
      'category_id': 1,
      'amount_cents': 69999,
    });
    await db.insert('transaction_splits', {
      'transaction_id': 4,
      'category_id': 2,
      'amount_cents': 30000,
    });
    await db.insert(
      'transactions',
      row(5, 'transfer', 20000, direction: 'out'),
    );
    await db.insert(
      'transactions',
      row(6, 'transfer', 20000, account: 2, direction: 'in'),
    );
    await db.insert('transfers', {
      'from_account_id': 1,
      'to_account_id': 2,
      'amount_cents': 20000,
      'credited_amount_cents': 20000,
      'date': '2026-10-05',
      'from_tx_id': 5,
      'to_tx_id': 6,
      'created_at': now,
    });
    if (upTo >= 7) {
      for (final (id, direction, person, cents, due, paid) in [
        (1, 'owed_to_me', 'Nimal', 100000, '2026-11-01', null),
        (2, 'i_owe', 'Saman', 40000, null, null),
        (3, 'owed_to_me', 'Kamala', 25000, null, '2026-10-08'),
      ]) {
        await db.insert('debts', {
          'id': id,
          'direction': direction,
          'person': person,
          'amount_cents': cents,
          'note': 'Debt $id',
          'incurred_on': '2026-10-01',
          'due_on': due,
          'paid_on': paid,
          'created_at': now,
          'updated_at': now,
        });
      }
    }
    await db.close();
    return path;
  }

  /// Every row of every table, by table, in row order.
  Future<Map<String, List<Map<String, Object?>>>> everything(
    Database db,
  ) async {
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name <> 'schema_migrations'",
    );
    return {
      for (final t in tables)
        t['name']! as String: await db.rawQuery(
          'SELECT * FROM "${t['name']}" ORDER BY rowid',
        ),
    };
  }

  /// The app as it starts after an update, over the database at [path].
  DatabaseHelper launch(String path) {
    final helper = DatabaseHelper(
      dbFactory: databaseFactoryFfi,
      keyStore: _KeptKey(),
    );
    expect(path, '${dir.path}/moneyora.db', reason: 'where the app looks');
    addTearDown(helper.close);
    return helper;
  }

  /// Updates the database at [path] as the app does on its first launch
  /// after an update, and returns it open.
  Future<Database> update(String path) => launch(path).database;

  for (final (release, version) in [('1.2.0', 8), ('1.1.0', 6)]) {
    group('from $release (schema v$version)', () {
      test(
        'every row of every table is as it was, new columns aside',
        () async {
          final path = await released(version);
          final before = await () async {
            final db = await databaseFactoryFfi.openDatabase(path);
            final rows = await everything(db);
            await db.close();
            return rows;
          }();

          final db = await update(path);

          expect(await DatabaseHelper.appliedVersions(db), {
            for (final v in schemaMigrations.keys) v,
          });
          final after = await everything(db);
          for (final MapEntry(key: table, value: rows) in before.entries) {
            expect(after[table], hasLength(rows.length), reason: table);
            for (final (i, old) in rows.indexed) {
              final now = after[table]![i];
              for (final MapEntry(:key, :value) in old.entries) {
                expect(now[key], value, reason: '$table row $i, $key');
              }
            }
          }
          expect(before['transactions'], hasLength(6));
          expect(before['receipt_items'], hasLength(1));
        },
      );

      test('no balance moves, and each one is what its history says', () async {
        final db = await update(await released(version));
        final cached = {
          for (final a in await db.query('accounts'))
            a['id']: a['current_balance_cents'],
        };

        await AccountLocalDataSourceImpl(db).recomputeAllBalances();

        expect({
          for (final a in await db.query('accounts'))
            a['id']: a['current_balance_cents'],
        }, cached);
      });

      test('the screens read it back: times, splits, the receipt, the '
          'transfer', () async {
        final db = await update(await released(version));

        final rows = await TransactionLocalDataSourceImpl(db)
            .list(const TransactionFilter());

        expect(rows, hasLength(6));
        expect(rows.firstWhere((t) => t.id == 1).time, '12:58');
        expect(rows.firstWhere((t) => t.id == 2).time, isNull);
        expect(rows.firstWhere((t) => t.id == 4).splits, hasLength(2));
        expect(rows.firstWhere((t) => t.id == 4).receiptScanId, 1);
        expect(rows.firstWhere((t) => t.id == 5).counterpartyAccountId, 2);
        expect(rows.every((t) => t.debtId == null), isTrue);
      });
    });
  }

  test('from 1.2.0, the debts and the card are as they were', () async {
    final db = await update(await released(8));

    final debts = await DebtLocalDataSourceImpl(db).list();
    expect(debts.map((d) => (d.id, d.person, d.amountCents, d.isOpen)), [
      (1, 'Nimal', 100000, true),
      (2, 'Saman', 40000, true),
      (3, 'Kamala', 25000, false),
    ]);
    expect(debts.first.dueOn, DateTime(2026, 11, 1));
    expect(debts.first.direction, DebtDirection.owedToMe);
    // Debts, not payments, through no account: nothing moved.
    expect(debts.every((d) => !d.isPayment && d.accountId == null), isTrue);
    final card = (await db.query('accounts', where: 'id = 2')).single;
    expect(card['credit_limit_cents'], 5000000);
    expect(card['payment_due_day'], 10);
    expect(card['apr_basis_points'], 2450);
  });

  test('a second launch after the update changes nothing more', () async {
    final path = await released(8);
    final first = launch(path);
    final once = await everything(await first.database);
    await first.close();

    final again = await update(path);

    expect(await everything(again), once);
  });
}

/// The keychain as an update leaves it: holding the key the database was
/// made with. (The test database is not encrypted; what is under test is
/// that the update asks for the existing key and never makes a new one.)
class _KeptKey implements EncryptionKeyStore {
  @override
  Future<String> getOrCreateKey({bool mustExist = false}) async =>
      'the key this phone kept';
}
