@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/database/database_change_bus.dart';
import 'package:moneyora/core/database/database_helper.dart';
import 'package:moneyora/core/database/seed/default_seed.dart';
import 'package:moneyora/core/database/seed/dev_seed.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/usecases/usecase.dart';
import 'package:moneyora/features/analytics/data/datasources/analytics_local_datasource.dart';
import 'package:moneyora/features/analytics/data/repositories/analytics_repository_impl.dart';
import 'package:moneyora/features/money_plan/data/datasources/money_plan_local_datasource.dart';
import 'package:moneyora/features/money_plan/data/repositories/money_plan_repository_impl.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_request.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_mode.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan_draft.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/usecases/activate_plan.dart';
import 'package:moneyora/features/money_plan/domain/usecases/allocate_budget.dart';
import 'package:moneyora/features/money_plan/domain/usecases/classify_categories.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/usecases/save_plan.dart';
import 'package:moneyora/features/money_plan/domain/usecases/update_allocation.dart';
import 'package:moneyora/features/money_plan/domain/usecases/watch_active_plan.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The whole feature end to end on `dev_seed`: generate a draft, save it,
/// read it back, adjust one allocation, watch the active plan follow.
void main() {
  sqfliteFfiInit();

  late Database db;
  late DatabaseChangeBus bus;
  late MoneyPlanLocalDataSourceImpl planSource;
  late AllocateBudget allocate;
  late SavePlan save;
  late ActivatePlan activatePlan;
  late UpdateAllocation update;
  late WatchActivePlan watchActive;

  final twoYears = LookbackWindow(months: 24, lastMonth: DateTime(2026, 8));

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        onConfigure: (d) => d.execute('PRAGMA foreign_keys = ON'),
        onCreate: (d, _) async {
          final batch = d.batch();
          // Every version, not v1 alone: the plan tables read
          // carry_over_cents, which v2 adds (E-33).
          for (final version in schemaMigrations.keys.toList()..sort()) {
            for (final statement in schemaMigrations[version]!) {
              batch.execute(statement);
            }
          }
          await batch.commit(noResult: true);
        },
        version: latestSchemaVersion,
      ),
    );
    await applyDefaultSeed(db);
    await DevSeed.populate(db, endDate: DateTime(2026, 8, 31));

    bus = DatabaseChangeBus();
    final analytics = AnalyticsRepositoryImpl(AnalyticsLocalDataSourceImpl(db));
    planSource = MoneyPlanLocalDataSourceImpl(db, changeBus: bus);
    final plans = MoneyPlanRepositoryImpl(planSource);

    allocate = AllocateBudget(
      ClassifyCategories(ComputeCategoryStatistics(analytics)),
      analytics,
    );
    save = SavePlan(plans);
    activatePlan = ActivatePlan(plans);
    update = UpdateAllocation(plans);
    watchActive = WatchActivePlan(plans);
  });

  tearDown(() async {
    await planSource.dispose();
    await bus.close();
    await db.close();
  });

  Future<MoneyPlanDraft> draft({
    BudgetMode mode = const BudgetMode.unconstrained(),
  }) async {
    final result = await allocate(
      AllocationRequest(
        period: PlanPeriod.month(2026, 9),
        lookback: twoYears,
        mode: mode,
      ),
    );
    return result.fold((f) => fail('unexpected failure: $f'), (d) => d);
  }

  T unwrap<T>(Either<Failure, T> r) =>
      r.fold((f) => fail('unexpected failure: $f'), (v) => v);

  test('a generated draft saves and reads back as the active plan', () async {
    final d = await draft(mode: const BudgetMode.total(10000000));

    final id = unwrap(await save(SavePlanRequest(draft: d, name: 'September')));
    final plan = unwrap(await watchActive(const NoParams()).first)!;

    expect(plan.id, id);
    expect(plan.name, 'September');
    expect(plan.period, PlanPeriod.month(2026, 9));
    expect(plan.isActive, isTrue);
    expect(plan.totalBudgetCents, 10000000);
    expect(plan.allocatedCents, 10000000);
    expect(plan.allocations.length, d.allocations.length);

    final byName = {for (final a in plan.allocations) a.categoryName: a};
    final bills = byName['Bills']!;
    expect(bills.allocatedCents, d.allocations.first.allocationCents);
    expect(bills.expenseType, ExpenseType.fixed);
    expect(bills.confidence, ConfidenceLevel.high);
    expect(byName['Gifts']!.expenseType, ExpenseType.seasonal);
    expect(byName['Pets']!.confidence, ConfidenceLevel.low);
    // The save recounts spend from history (FR-PLN-013); the seed ends on
    // 31 August, so a September plan has nothing to count.
    expect(plan.allocations.every((a) => a.spentCents == 0), isTrue);
  });

  test('saving a second plan makes it the active one; activating the '
      'first switches back', () async {
    final d = await draft();
    final first = unwrap(await save(SavePlanRequest(draft: d, name: 'One')));
    final second = unwrap(await save(SavePlanRequest(draft: d, name: 'Two')));

    expect(unwrap(await watchActive(const NoParams()).first)!.id, second);

    unwrap(await activatePlan(first));

    expect(unwrap(await watchActive(const NoParams()).first)!.id, first);
  });

  test('a manual adjustment holds the total and marks the row', () async {
    final d = await draft(mode: const BudgetMode.total(10000000));
    final id = unwrap(await save(SavePlanRequest(draft: d, name: 'September')));
    final before = unwrap(await watchActive(const NoParams()).first)!;
    final food = before.allocations.firstWhere((a) => a.categoryName == 'Food');

    final updated = unwrap(
      await update(
        UpdateAllocationRequest(
          planId: id,
          categoryId: food.categoryId,
          allocatedCents: food.allocatedCents + 500000,
        ),
      ),
    );

    expect(updated.allocatedCents, 10000000);
    final after = unwrap(await watchActive(const NoParams()).first)!;
    expect(after.allocatedCents, 10000000, reason: 'as written');
    final foodAfter = after.allocations.firstWhere(
      (a) => a.categoryName == 'Food',
    );
    expect(foodAfter.allocatedCents, food.allocatedCents + 500000);
    expect(foodAfter.isUserModified, isTrue);
    expect(
      after.allocations.where((a) => a.isUserModified).length,
      1,
      reason: 'only the row the user touched',
    );
  });

  test('the active-plan stream follows a write on the shared bus', () async {
    final d = await draft();
    final seen = <MoneyPlan?>[];
    final sub = watchActive(const NoParams())
        .listen((e) => seen.add(unwrap(e)));
    Future<void> untilSeen(int count) async {
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (seen.length < count) {
        if (DateTime.now().isAfter(deadline)) fail('saw only $seen');
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    }

    await untilSeen(1);
    expect(seen.single, isNull, reason: 'nothing active yet');

    unwrap(await save(SavePlanRequest(draft: d, name: 'Now')));
    await untilSeen(2);

    expect(seen.last!.name, 'Now');
    await sub.cancel();
  });
}
