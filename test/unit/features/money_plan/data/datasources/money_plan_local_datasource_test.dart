@TestOn('vm')
library;

import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/database_change_bus.dart';
import 'package:moneyora/core/database/migrations/v1_initial.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/money_plan/data/datasources/money_plan_local_datasource.dart';
import 'package:moneyora/features/money_plan/data/models/money_plan_model.dart';
import 'package:moneyora/features/money_plan/data/models/plan_allocation_model.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:moneyora/features/transactions/data/models/transaction_model.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Against a real in-memory SQLite: the first slice that writes rows for
/// this feature, so every claim here is about what actually lands — that a
/// save is all or nothing, that at most one plan is ever active, that an
/// update to the allocations holds the total or changes nothing.
void main() {
  sqfliteFfiInit();

  late Database db;
  late MoneyPlanLocalDataSourceImpl plans;
  late int food;
  late int bills;

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

    Future<int> idOf(String name) async =>
        (await db.query(
              'categories',
              columns: ['id'],
              where: 'name = ?',
              whereArgs: [name],
            )).single['id']!
            as int;
    food = await idOf('Food');
    bills = await idOf('Bills');

    plans = MoneyPlanLocalDataSourceImpl(db);
  });

  tearDown(() async {
    await plans.dispose();
    await db.close();
  });

  MoneyPlanModel plan(
    String name, {
    bool active = true,
    List<PlanAllocationModel>? allocations,
  }) => MoneyPlanModel(
    name: name,
    period: PlanPeriod.month(2026, 9),
    totalBudgetCents: 7500000,
    isActive: active,
    allocations:
        allocations ??
        [
          PlanAllocationModel(
            categoryId: bills,
            allocatedCents: 4500000,
            confidence: ConfidenceLevel.high,
            expenseType: ExpenseType.fixed,
          ),
          PlanAllocationModel(
            categoryId: food,
            allocatedCents: 3000000,
            confidence: ConfidenceLevel.medium,
            expenseType: ExpenseType.variable,
          ),
        ],
  );

  Future<List<int>> activeIds() async => [
    for (final row in await db.query(
      'money_plans',
      columns: ['id'],
      where: 'is_active = 1',
    ))
      row['id']! as int,
  ];

  group('insert', () {
    test('writes the plan and its allocations, and reads them back with '
        'category names', () async {
      final id = await plans.insert(plan('September'));

      final read = (await plans.getById(id))!;
      expect(read.id, id);
      expect(read.name, 'September');
      expect(read.period, PlanPeriod.month(2026, 9));
      expect(read.totalBudgetCents, 7500000);
      expect(read.isActive, isTrue);
      expect(read.allocations.length, 2);
      expect(read.allocations[0].categoryName, 'Bills');
      expect(read.allocations[0].allocatedCents, 4500000);
      expect(read.allocations[0].confidence, ConfidenceLevel.high);
      expect(read.allocations[0].expenseType, ExpenseType.fixed);
      expect(read.allocations[0].spentCents, 0);
      expect(read.allocations[0].isUserModified, isFalse);
      expect(read.allocations[1].categoryName, 'Food');
      expect(read.createdAt, isNotNull);
    });

    test(
      'is all or nothing: a bad category leaves no plan row behind',
      () async {
        final bad = plan(
          'Broken',
          allocations: [
            PlanAllocationModel(
              categoryId: bills,
              allocatedCents: 1,
              confidence: ConfidenceLevel.low,
            ),
            const PlanAllocationModel(
              categoryId: 999999, // no such category: the FK refuses
              allocatedCents: 1,
              confidence: ConfidenceLevel.low,
            ),
          ],
        );

        await expectLater(plans.insert(bad), throwsA(isA<CacheException>()));

        expect(await db.query('money_plans'), isEmpty);
        expect(await db.query('plan_allocations'), isEmpty);
      },
    );

    test('an inserted-inactive plan does not disturb the active one', () async {
      final first = await plans.insert(plan('Active'));
      final second = await plans.insert(plan('Saved for later', active: false));

      expect(await activeIds(), [first]);
      expect((await plans.getById(second))!.isActive, isFalse);
    });

    test(
      'an all-or-nothing failure also rolls back the deactivation',
      () async {
        final first = await plans.insert(plan('Active'));
        final bad = plan(
          'Broken',
          allocations: [
            const PlanAllocationModel(
              categoryId: 999999,
              allocatedCents: 1,
              confidence: ConfidenceLevel.low,
            ),
          ],
        );

        await expectLater(plans.insert(bad), throwsA(isA<CacheException>()));

        expect(await activeIds(), [first], reason: 'still active');
      },
    );
  });

  group('one active plan at a time', () {
    test('saving an active plan deactivates the previous one', () async {
      final first = await plans.insert(plan('First'));
      final second = await plans.insert(plan('Second'));

      expect(await activeIds(), [second]);
      expect((await plans.getById(first))!.isActive, isFalse);
      expect((await plans.getActive())!.id, second);
    });

    test('activate switches, leaving exactly one', () async {
      final first = await plans.insert(plan('First'));
      final second = await plans.insert(plan('Second'));

      await plans.activate(first);

      expect(await activeIds(), [first]);
      expect((await plans.getById(second))!.isActive, isFalse);
    });

    test('activating a plan that does not exist changes nothing', () async {
      final first = await plans.insert(plan('First'));

      await expectLater(plans.activate(999), throwsA(isA<CacheException>()));

      expect(await activeIds(), [first], reason: 'rolled back');
    });

    test('getActive is null when nothing is active', () async {
      await plans.insert(plan('Later', active: false));

      expect(await plans.getActive(), isNull);
    });
  });

  group('updateAllocations', () {
    test(
      'rewrites the figures and the user flag, matched by category',
      () async {
        final id = await plans.insert(plan('September'));

        await plans.updateAllocations(id, [
          PlanAllocationModel(
            categoryId: bills,
            allocatedCents: 4000000,
            confidence: ConfidenceLevel.high,
            isUserModified: true,
          ),
          PlanAllocationModel(
            categoryId: food,
            allocatedCents: 3500000,
            confidence: ConfidenceLevel.medium,
          ),
        ]);

        final read = (await plans.getById(id))!;
        expect(read.allocations[0].allocatedCents, 4000000);
        expect(read.allocations[0].isUserModified, isTrue);
        expect(read.allocations[1].allocatedCents, 3500000);
        expect(read.allocations[1].isUserModified, isFalse);
        // Untouched columns stay as they were.
        expect(read.allocations[0].confidence, ConfidenceLevel.high);
        expect(read.allocations[0].expenseType, ExpenseType.fixed);
        expect(read.totalBudgetCents, 7500000);
      },
    );

    test(
      'is all or nothing: an unknown category rolls every row back',
      () async {
        final id = await plans.insert(plan('September'));

        await expectLater(
          plans.updateAllocations(id, [
            PlanAllocationModel(
              categoryId: bills,
              allocatedCents: 1,
              confidence: ConfidenceLevel.high,
            ),
            const PlanAllocationModel(
              categoryId: 999999,
              allocatedCents: 1,
              confidence: ConfidenceLevel.high,
            ),
          ]),
          throwsA(isA<CacheException>()),
        );

        final read = (await plans.getById(id))!;
        expect(
          read.allocations[0].allocatedCents,
          4500000,
          reason: 'unchanged',
        );
      },
    );
  });

  // ── FR-PLN-013, E-18: the recount ──────────────────────────────────────────

  group('recomputeSpent', () {
    late TransactionLocalDataSourceImpl transactions;
    late int transport;
    late int wallet;
    late int card;

    TransactionModel expense(
      int categoryId,
      int amountCents, {
      DateTime? on,
      List<TransactionSplit> parts = const [],
    }) => TransactionModel(
      accountId: wallet,
      categoryId: categoryId,
      amountCents: amountCents,
      type: TransactionType.expense,
      date: on ?? DateTime(2026, 9, 14),
      splits: parts,
    );

    Future<int> spentOf(int planId, int categoryId) async =>
        (await db.query(
              'plan_allocations',
              columns: ['spent_amount_cents'],
              where: 'plan_id = ? AND category_id = ?',
              whereArgs: [planId, categoryId],
            )).single['spent_amount_cents']!
            as int;

    setUp(() async {
      transport =
          (await db.query(
                'categories',
                columns: ['id'],
                where: 'name = ?',
                whereArgs: ['Transport'],
              )).single['id']!
              as int;
      wallet =
          (await db.query('accounts', columns: ['id'])).single['id']! as int;
      card = await db.insert('accounts', {
        'user_id': 1,
        'name': 'Card',
        'icon': 'card',
        'initial_balance_date': '2026-09-01',
        'created_at': '2026-09-01T00:00:00Z',
      });
      // The writer of the cache, on the same database: what the recount is
      // checked against, exactly as the accounts datasource's test does it.
      transactions = TransactionLocalDataSourceImpl(db);
    });

    tearDown(() => transactions.dispose());

    test('is zero for a plan with no history', () async {
      // SUM over nothing is NULL; without the COALESCE the column would be
      // set to NULL and its NOT NULL constraint would refuse.
      final id = await plans.insert(plan('Empty'));

      await plans.recomputeSpent(id);

      expect(await spentOf(id, food), 0);
      expect(await spentOf(id, bills), 0);
    });

    test('counts what the transactions datasource counted', () async {
      final id = await plans.insert(plan('September'));
      await transactions.add(expense(food, 30000));
      await transactions.add(expense(food, 20000));
      await transactions.add(expense(bills, 45000));

      await plans.recomputeSpent(id);

      expect(await spentOf(id, food), 50000);
      expect(await spentOf(id, bills), 45000);
    });

    test('reads a split by its parts, not its parent', () async {
      // E-04, read the way the analytics datasource reads it: the parent's
      // dominant category is a display convenience, and its amount is the
      // sum of parts that may belong to other categories.
      final id = await plans.insert(plan('September'));
      await transactions.add(
        expense(
          food,
          100000,
          parts: [
            TransactionSplit(categoryId: food, amountCents: 60000),
            TransactionSplit(categoryId: bills, amountCents: 30000),
            TransactionSplit(categoryId: transport, amountCents: 10000),
          ],
        ),
      );

      await plans.recomputeSpent(id);

      expect(await spentOf(id, food), 60000);
      expect(await spentOf(id, bills), 30000);
    });

    test('ignores income, transfers and rows outside the period', () async {
      final id = await plans.insert(plan('September'));
      await transactions.add(expense(food, 10000, on: DateTime(2026, 8, 31)));
      await transactions.add(expense(food, 10000, on: DateTime(2026, 10, 1)));
      await transactions.add(
        TransactionModel(
          accountId: wallet,
          categoryId: food,
          amountCents: 500000,
          type: TransactionType.income,
          date: DateTime(2026, 9, 14),
        ),
      );
      await transactions.createTransfer(
        fromAccountId: wallet,
        toAccountId: card,
        amountCents: 800000,
        date: DateTime(2026, 9, 14),
      );
      await transactions.add(expense(food, 25000, on: DateTime(2026, 9, 30)));

      await plans.recomputeSpent(id);

      expect(await spentOf(id, food), 25000);
    });

    test('repairs a figure corrupted behind the app', () async {
      final id = await plans.insert(plan('September'));
      await transactions.add(expense(food, 30000));
      // The drift E-18 warns about: a restore that put the column back
      // wrong, or a hand edit.
      await db.update('plan_allocations', {'spent_amount_cents': 999999});

      await plans.recomputeSpent(id);

      expect(await spentOf(id, food), 30000);
      expect(await spentOf(id, bills), 0);
    });

    test(
      'a plan saved active counts the expenses already in its period',
      () async {
        // The gap the incremental write cannot close on its own: these rows
        // were written while no plan was active, so nothing moved them onto
        // any plan. A plan saved on the 14th over a month that began on the
        // 1st would start at zero — so the save recounts, in its own
        // transaction, and the figure is right before anything reads it.
        await transactions.add(expense(food, 30000, on: DateTime(2026, 9, 3)));
        await transactions.add(expense(bills, 45000, on: DateTime(2026, 9, 5)));

        final id = await plans.insert(plan('Mid-month'));

        expect(await spentOf(id, food), 30000);
        expect(await spentOf(id, bills), 45000);
      },
    );

    test('a plan saved for later is not counted until activated', () async {
      // Inactive plans are not tracked (the incremental write targets the
      // active one only), so the figure is "as of the last time it was
      // active" — zero for one that never was — and activation recounts.
      await transactions.add(expense(food, 30000, on: DateTime(2026, 9, 3)));
      final id = await plans.insert(plan('Later', active: false));
      expect(await spentOf(id, food), 0, reason: 'not tracked yet');
      await transactions.add(expense(food, 20000, on: DateTime(2026, 9, 6)));

      await plans.activate(id);

      expect(await spentOf(id, food), 50000);
    });

    test('re-activating a plan catches up on what it missed', () async {
      final first = await plans.insert(plan('First'));
      await transactions.add(expense(food, 30000));
      final second = await plans.insert(plan('Second'));
      // Written while `second` was active: `first` never saw it.
      await transactions.add(expense(food, 20000));
      expect(await spentOf(first, food), 30000, reason: 'as of deactivation');

      await plans.activate(first);

      expect(await spentOf(first, food), 50000);
      // `second` was saved active mid-period, so it counted the 30,000 on
      // save and the 20,000 as it was written; deactivation freezes it.
      expect(await spentOf(second, food), 50000, reason: 'left as it was');
    });

    test('refuses a plan that does not exist', () async {
      expect(() => plans.recomputeSpent(4242), throwsA(isA<CacheException>()));
    });

    test('fires the change signal', () async {
      final id = await plans.insert(plan('September'));
      final ticks = <void>[];
      final sub = plans.changes.listen(ticks.add);

      await plans.recomputeSpent(id);
      await Future<void>.delayed(Duration.zero);

      expect(ticks.length, 1);
      await sub.cancel();
    });

    test('agrees with the cache after a random sequence of writes', () async {
      // E-18's property from the other side. The transactions datasource
      // keeps the cache incrementally and its own test recounts in Dart;
      // this is the SQL recount agreeing with the incremental figure, so
      // the repair and the thing it repairs cannot disagree on what
      // spending is.
      final id = await plans.insert(plan('September'));
      final random = Random(20260914);
      final live = <int>[];
      final categories = [food, bills, transport];
      final days = [
        DateTime(2026, 8, 31),
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 15),
        DateTime(2026, 9, 30),
        DateTime(2026, 10, 1),
      ];

      TransactionModel some({int? id}) {
        final on = days[random.nextInt(days.length)];
        final category = categories[random.nextInt(categories.length)];
        if (random.nextInt(3) == 0) {
          final a = 1000 + random.nextInt(50000);
          final b = 1000 + random.nextInt(50000);
          return TransactionModel(
            id: id,
            accountId: wallet,
            categoryId: category,
            amountCents: a + b,
            type: TransactionType.expense,
            date: on,
            splits: [
              TransactionSplit(
                categoryId: categories[random.nextInt(categories.length)],
                amountCents: a,
              ),
              TransactionSplit(
                categoryId: categories[random.nextInt(categories.length)],
                amountCents: b,
              ),
            ],
          );
        }
        return TransactionModel(
          id: id,
          accountId: wallet,
          categoryId: category,
          amountCents: 1000 + random.nextInt(90000),
          type: TransactionType.expense,
          date: on,
        );
      }

      for (var step = 0; step < 120; step++) {
        switch (random.nextInt(4)) {
          case 0:
          case 1:
            live.add(await transactions.add(some()));
          case 2:
            if (live.isEmpty) continue;
            await transactions.update(
              some(id: live[random.nextInt(live.length)]),
            );
          case 3:
            if (live.isEmpty) continue;
            await transactions.delete(
              live.removeAt(random.nextInt(live.length)),
            );
        }
      }

      final cached = {
        for (final c in [food, bills]) c: await spentOf(id, c),
      };
      // A sequence that moved nothing would also pass the check below.
      expect(cached.values.any((v) => v > 0), isTrue, reason: 'exercised');

      await plans.recomputeSpent(id);

      for (final c in [food, bills]) {
        expect(
          await spentOf(id, c),
          cached[c],
          reason: 'the recount disagrees with the cache on category $c',
        );
      }
    });
  });

  group('changes', () {
    test('fires once per successful write', () async {
      final ticks = <void>[];
      final sub = plans.changes.listen(ticks.add);

      final id = await plans.insert(plan('A'));
      await plans.activate(id);
      await plans.updateAllocations(id, [
        PlanAllocationModel(
          categoryId: food,
          allocatedCents: 1,
          confidence: ConfidenceLevel.low,
        ),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(ticks.length, 3);
      await sub.cancel();
    });

    test('a failed write does not fire', () async {
      final ticks = <void>[];
      final sub = plans.changes.listen(ticks.add);

      await expectLater(plans.activate(999), throwsA(isA<CacheException>()));
      await Future<void>.delayed(Duration.zero);

      expect(ticks, isEmpty);
      await sub.cancel();
    });

    test('a shared bus is not closed on dispose', () async {
      final bus = DatabaseChangeBus();
      final shared = MoneyPlanLocalDataSourceImpl(db, changeBus: bus);

      await shared.dispose();

      expect(bus.isClosed, isFalse);
      await bus.close();
    });
  });
}
