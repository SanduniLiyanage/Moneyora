@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/debts/data/datasources/debt_local_datasource.dart';
import 'package:moneyora/features/debts/data/models/debt_model.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The datasource against real SQLite at the latest schema. E-42.
void main() {
  sqfliteFfiInit();

  late Database db;
  late DebtLocalDataSourceImpl source;
  final now = DateTime.utc(2026, 10, 9, 8);

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
    source = DebtLocalDataSourceImpl(db, clock: () => now);
  });

  tearDown(() async {
    await source.dispose();
    await db.close();
  });

  DebtModel debt({
    String person = 'Nimal',
    DebtDirection direction = DebtDirection.owedToMe,
    int cents = 250000,
    DateTime? due,
    DateTime? paid,
    String? note,
  }) => DebtModel(
    direction: direction,
    person: person,
    amountCents: cents,
    incurredOn: DateTime(2026, 10, 1),
    dueOn: due,
    paidOn: paid,
    note: note,
  );

  test('a debt is written and read back as it was', () async {
    final id = await source.add(
      debt(due: DateTime(2026, 11, 1), note: 'Train tickets'),
    );

    final read = (await source.list()).single;
    expect(
      read.toEntity(),
      Debt(
        id: id,
        direction: DebtDirection.owedToMe,
        person: 'Nimal',
        amountCents: 250000,
        incurredOn: DateTime(2026, 10, 1),
        dueOn: DateTime(2026, 11, 1),
        note: 'Train tickets',
      ),
    );
    final row = (await db.query('debts')).single;
    expect(row['incurred_on'], '2026-10-01');
    expect(row['due_on'], '2026-11-01');
    expect(row['paid_on'], isNull);
    expect(row['created_at'], now.toIso8601String());
  });

  test('open first, soonest due first and none last, then paid, latest '
      'paid first', () async {
    await source.add(debt(person: 'No due'));
    await source.add(debt(person: 'Paid early', paid: DateTime(2026, 10, 2)));
    await source.add(debt(person: 'Due later', due: DateTime(2026, 12, 1)));
    await source.add(debt(person: 'Paid late', paid: DateTime(2026, 10, 8)));
    await source.add(debt(person: 'Due soon', due: DateTime(2026, 10, 20)));

    expect((await source.list()).map((d) => d.person), [
      'Due soon',
      'Due later',
      'No due',
      'Paid late',
      'Paid early',
    ]);
  });

  test('an update replaces the row, paid day included', () async {
    final id = await source.add(debt());

    await source.update(
      DebtModel.fromEntity(
        Debt(
          id: id,
          direction: DebtDirection.iOwe,
          person: 'Saman',
          amountCents: 1000,
          incurredOn: DateTime(2026, 10, 1),
          paidOn: DateTime(2026, 10, 9),
        ),
      ),
    );

    final read = (await source.list()).single;
    expect(read.person, 'Saman');
    expect(read.direction, DebtDirection.iOwe);
    expect(read.paidOn, DateTime(2026, 10, 9));
  });

  test('a delete removes it, and a missing row is an error', () async {
    final id = await source.add(debt());

    await source.delete(id);

    expect(await source.list(), isEmpty);
    await expectLater(source.delete(id), throwsA(isA<CacheException>()));
  });

  test('every write is announced', () async {
    var heard = 0;
    final listening = source.changes.listen((_) => heard++);
    addTearDown(listening.cancel);

    final id = await source.add(debt());
    await source.update(
      DebtModel(
        id: id,
        direction: DebtDirection.owedToMe,
        person: 'Nimal',
        amountCents: 100,
        incurredOn: DateTime(2026, 10, 1),
      ),
    );
    await source.delete(id);
    await Future<void>.delayed(Duration.zero);

    expect(heard, 3);
  });

  test('several are written together, in order, and announced once', () async {
    var heard = 0;
    final listening = source.changes.listen((_) => heard++);
    addTearDown(listening.cancel);

    final ids = await source.addAll([
      debt(person: 'Nimal'),
      debt(person: 'Saman'),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(ids, hasLength(2));
    expect((await source.list()).map((d) => (d.id, d.person)).toSet(), {
      (ids[0], 'Nimal'),
      (ids[1], 'Saman'),
    });
    expect(heard, 1);
  });

  test('all or none: one row refused writes none of them', () async {
    await expectLater(
      source.addAll([debt(person: 'Nimal'), debt(person: 'Saman', cents: 0)]),
      throwsA(isA<CacheException>()),
    );

    expect(await source.list(), isEmpty);
  });

  group('several changed together. FR-DBT-006', () {
    test('every row is rewritten, and announced once', () async {
      final ids = await source.addAll([
        debt(person: 'Nimal P.'),
        debt(person: 'nimal p.'),
      ]);
      var heard = 0;
      final listening = source.changes.listen((_) => heard++);
      addTearDown(listening.cancel);

      await source.updateAll([
        for (final model in await source.list())
          DebtModel.fromEntity(model.toEntity().withPerson('Nimal')),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect((await source.list()).map((d) => (d.id, d.person)).toSet(), {
        (ids[0], 'Nimal'),
        (ids[1], 'Nimal'),
      });
      expect(heard, 1);
    });

    test('all or none: a row that is not there changes none of them', () async {
      final id = await source.add(debt(person: 'Nimal P.'));
      final kept = (await source.list()).single.toEntity();

      await expectLater(
        source.updateAll([
          DebtModel.fromEntity(kept.withPerson('Nimal')),
          DebtModel.fromEntity(
            Debt(
              id: id + 99,
              direction: DebtDirection.owedToMe,
              person: 'Nimal',
              amountCents: 100,
              incurredOn: DateTime(2026, 10, 1),
            ),
          ),
        ]),
        throwsA(isA<CacheException>()),
      );

      expect((await source.list()).single.person, 'Nimal P.');
    });
  });

  group('a settlement and its undo, as one write. FR-DBT-007', () {
    test('adds, changes and removes together, and says so once', () async {
      final keep = await source.add(debt(person: 'Nimal'));
      final gone = await source.add(debt(person: 'Saman'));
      final kept = (await source.list())
          .firstWhere((d) => d.id == keep)
          .toEntity();
      var heard = 0;
      final listening = source.changes.listen((_) => heard++);
      addTearDown(listening.cancel);

      final ids = await source.batch(
        add: [
          DebtModel.fromEntity(
            Debt(
              direction: DebtDirection.iOwe,
              person: 'Nimal',
              amountCents: 250000,
              incurredOn: DateTime(2026, 10, 20),
              paidOn: DateTime(2026, 10, 20),
              note: 'Settled up',
              isPayment: true,
            ),
          ),
        ],
        update: [DebtModel.fromEntity(kept.withPaidOn(DateTime(2026, 10, 20)))],
        delete: [gone],
      );
      await Future<void>.delayed(Duration.zero);

      final rows = await source.list();
      expect(rows, hasLength(2));
      final payment = rows.firstWhere((d) => d.id == ids.single);
      expect(payment.isPayment, isTrue, reason: 'read back as a payment');
      expect(payment.paidOn, DateTime(2026, 10, 20));
      expect(
        rows.firstWhere((d) => d.id == keep).paidOn,
        DateTime(2026, 10, 20),
      );
      final stored = await db.query(
        'debts',
        where: 'id = ?',
        whereArgs: [ids.single],
      );
      expect(stored.single['is_payment'], 1);
      expect(heard, 1);
    });

    test('all or none: a row that is not there writes nothing', () async {
      final id = await source.add(debt(person: 'Nimal'));

      await expectLater(
        source.batch(
          add: [debt(person: 'Saman')],
          delete: [id + 99],
        ),
        throwsA(isA<CacheException>()),
      );

      expect((await source.list()).single.id, id);
    });
  });

  test('a row the CHECKs refuse is a CacheException', () async {
    await expectLater(
      source.add(debt(cents: 0)),
      throwsA(isA<CacheException>()),
    );
  });
}
