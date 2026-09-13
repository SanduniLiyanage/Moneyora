@TestOn('vm')
library;

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
