@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/activate_plan.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compare_plans.dart';
import 'package:moneyora/features/money_plan/domain/usecases/delete_plan.dart';
import 'package:moneyora/features/money_plan/domain/usecases/recompute_plan_spending.dart';
import 'package:moneyora/features/money_plan/domain/usecases/rename_plan.dart';
import 'package:moneyora/features/money_plan/domain/usecases/watch_plans.dart';
import 'package:moneyora/features/money_plan/presentation/pages/compare_plans_page.dart';
import 'package:moneyora/features/money_plan/presentation/pages/plan_list_page.dart';
import 'package:moneyora/injection.dart';

/// The plan list and the comparison over the real use cases and an
/// in-memory repository whose stream re-emits after every write — so a
/// switch of the active plan is seen the way the app sees it.
class _MemoryRepository implements MoneyPlanRepository {
  _MemoryRepository(this.plans, {this.readFails, this.writeFails});

  List<MoneyPlan> plans;
  final Failure? readFails;
  final Failure? writeFails;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  int? activated;
  int? recounted;
  int? deleted;

  @override
  Stream<Either<Failure, List<MoneyPlan>>> watchAll() async* {
    if (readFails case final f?) {
      yield Left(f);
      return;
    }
    yield Right(plans);
    await for (final _ in _changes.stream) {
      yield Right(plans);
    }
  }

  @override
  Future<Either<Failure, Unit>> activate(int id) async {
    if (writeFails case final f?) return Left(f);
    activated = id;
    plans = [
      for (final p in plans)
        MoneyPlan(
          id: p.id,
          name: p.name,
          period: p.period,
          totalBudgetCents: p.totalBudgetCents,
          isActive: p.id == id,
          allocations: p.allocations,
        ),
    ];
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) async {
    if (writeFails case final f?) return Left(f);
    recounted = planId;
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Set<int>>> recordAlertLevels(
    List<AlertLevelChange> changes,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) async {
    if (readFails case final f?) return Left(f);
    for (final p in plans) {
      if (p.id == id) return Right(p);
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(DateTime day) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> rename(int id, String name) async {
    if (writeFails case final f?) return Left(f);
    plans = [
      for (final p in plans)
        p.id == id
            ? MoneyPlan(
                id: p.id,
                name: name,
                period: p.period,
                totalBudgetCents: p.totalBudgetCents,
                isActive: p.isActive,
                allocations: p.allocations,
              )
            : p,
    ];
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    if (writeFails case final f?) return Left(f);
    deleted = id;
    plans = [
      for (final p in plans)
        if (p.id != id) p,
    ];
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations, {
    int? totalBudgetCents,
  }) => throw UnimplementedError();

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() =>
      throw UnimplementedError();
}

PlanAllocation _row(int id, String name, int cents) => PlanAllocation(
  categoryId: id,
  categoryName: name,
  allocatedCents: cents,
  confidence: ConfidenceLevel.medium,
);

final _monthly = MoneyPlan(
  id: 1,
  name: 'Regular Monthly',
  period: PlanPeriod.month(2026, 9),
  totalBudgetCents: 10000000,
  isActive: true,
  allocations: [
    _row(1, 'Bills', 4500000),
    _row(2, 'Food', 3000000),
    _row(3, 'Car', 2500000),
  ],
);

final _vacation = MoneyPlan(
  id: 2,
  name: 'June Vacation Plan',
  period: PlanPeriod.days(DateTime(2027, 6, 10), 10),
  totalBudgetCents: 8000000,
  isActive: false,
  allocations: [_row(2, 'Food', 3500000), _row(4, 'Travel', 4500000)],
);

void main() {
  Widget boot(_MemoryRepository repository, {String? at}) => ProviderScope(
    overrides: [
      watchPlansProvider.overrideWith((ref) async => WatchPlans(repository)),
      activatePlanProvider.overrideWith(
        (ref) async => ActivatePlan(repository),
      ),
      recomputePlanSpendingProvider.overrideWith(
        (ref) async => RecomputePlanSpending(repository),
      ),
      comparePlansProvider.overrideWith(
        (ref) async => ComparePlans(repository),
      ),
      renamePlanProvider.overrideWith((ref) async => RenamePlan(repository)),
      deletePlanProvider.overrideWith((ref) async => DeletePlan(repository)),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: at ?? Routes.plans,
        routes: [
          GoRoute(
            path: Routes.plans,
            builder: (context, state) => const PlanListPage(),
          ),
          GoRoute(
            path: Routes.comparePlans,
            builder: (context, state) => ComparePlansPage(
              request: ComparePlansRequest(
                leftId: int.parse(state.uri.queryParameters['a']!),
                rightId: int.parse(state.uri.queryParameters['b']!),
              ),
            ),
          ),
          GoRoute(
            path: Routes.activePlan,
            builder: (context, state) =>
                const Scaffold(body: Text('the active plan')),
          ),
          GoRoute(
            path: Routes.moneyPlan,
            builder: (context, state) => const Scaffold(body: Text('wizard')),
          ),
        ],
      ),
    ),
  );

  group('rename and delete. FR-PLN-015', () {
    // A tester on 1.0.0 had no way to remove a plan saved by mistake.
    Future<void> choose(WidgetTester tester, String plan, String item) async {
      await tester.tap(find.byTooltip('More for $plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
    }

    testWidgets('renames a plan, and the list follows', (tester) async {
      await tester.pumpWidget(boot(_MemoryRepository([_monthly, _vacation])));
      await tester.pumpAndSettle();

      await choose(tester, 'June Vacation Plan', 'Rename…');
      await tester.enterText(find.byType(TextField), 'Galle trip');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Galle trip'), findsOneWidget);
      expect(find.text('June Vacation Plan'), findsNothing);
      expect(find.text('Renamed to Galle trip.'), findsOneWidget);
    });

    testWidgets('a blank name is caught in the dialog', (tester) async {
      final repository = _MemoryRepository([_monthly]);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await choose(tester, 'Regular Monthly', 'Rename…');
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Give the plan a name.'), findsOneWidget);
      expect(repository.plans.single.name, 'Regular Monthly');
    });

    testWidgets('deleting the active plan says nothing will be tracked, and '
        'removes it', (tester) async {
      final repository = _MemoryRepository([_monthly, _vacation]);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await choose(tester, 'Regular Monthly', 'Delete…');
      expect(find.text('Delete Regular Monthly?'), findsOneWidget);
      expect(find.textContaining('Your transactions stay'), findsOneWidget);
      expect(find.textContaining('Nothing is tracked until'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Delete'));
      await tester.pumpAndSettle();

      expect(repository.deleted, 1);
      expect(find.text('Regular Monthly'), findsNothing);
      expect(find.text('Regular Monthly deleted.'), findsOneWidget);
      expect(find.text('June Vacation Plan'), findsOneWidget);
    });

    testWidgets('an inactive plan is deleted without the tracking warning', (
      tester,
    ) async {
      await tester.pumpWidget(boot(_MemoryRepository([_monthly, _vacation])));
      await tester.pumpAndSettle();

      await choose(tester, 'June Vacation Plan', 'Delete…');

      expect(find.textContaining('Nothing is tracked until'), findsNothing);
    });

    testWidgets('cancelling deletes nothing', (tester) async {
      final repository = _MemoryRepository([_monthly]);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await choose(tester, 'Regular Monthly', 'Delete…');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.deleted, isNull);
      expect(find.text('Regular Monthly'), findsOneWidget);
    });
  });

  group('the list', () {
    testWidgets('shows every plan with its period and total, and which is '
        'active', (tester) async {
      await tester.pumpWidget(boot(_MemoryRepository([_monthly, _vacation])));
      await tester.pumpAndSettle();

      expect(find.text('Regular Monthly'), findsOneWidget);
      expect(
        find.text('September 2026 · 30 days · Rs100,000.00'),
        findsOneWidget,
      );
      expect(find.text('June Vacation Plan'), findsOneWidget);
      expect(find.textContaining('10 days · Rs80,000.00'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
    });

    testWidgets('the active plan leads, with the way into it', (tester) async {
      // With no "Your plan" on the home screen, this list is how the
      // tracked plan is reached.
      final vacationActive = MoneyPlan(
        id: _vacation.id,
        name: _vacation.name,
        period: _vacation.period,
        totalBudgetCents: _vacation.totalBudgetCents,
        isActive: true,
        allocations: _vacation.allocations,
      );
      final monthlyInactive = MoneyPlan(
        id: _monthly.id,
        name: _monthly.name,
        period: _monthly.period,
        totalBudgetCents: _monthly.totalBudgetCents,
        isActive: false,
        allocations: _monthly.allocations,
      );
      await tester.pumpWidget(
        boot(_MemoryRepository([monthlyInactive, vacationActive])),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getTopLeft(find.text('June Vacation Plan')).dy,
        lessThan(tester.getTopLeft(find.text('Regular Monthly')).dy),
      );
      expect(
        find.text('Tap the active plan to see your spending against it.'),
        findsOneWidget,
      );
    });

    testWidgets('with no plans, says so and offers the wizard', (tester) async {
      await tester.pumpWidget(boot(_MemoryRepository([])));
      await tester.pumpAndSettle();

      expect(find.text('No budget plans yet'), findsOneWidget);
      await tester.tap(find.text('Create Money Plan'));
      await tester.pumpAndSettle();
      expect(find.text('wizard'), findsOneWidget);
    });

    testWidgets('a failure reading shows its message', (tester) async {
      await tester.pumpWidget(
        boot(
          _MemoryRepository([], readFails: const CacheFailure('disk is full')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('disk is full'), findsOneWidget);
    });

    testWidgets('tapping the active plan opens it', (tester) async {
      await tester.pumpWidget(boot(_MemoryRepository([_monthly, _vacation])));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Regular Monthly'));
      await tester.pumpAndSettle();

      expect(find.text('the active plan'), findsOneWidget);
    });
  });

  group('switching the active plan (FR-PLN-015)', () {
    testWidgets('tapping another plan activates it, and the list follows '
        'through the stream', (tester) async {
      final repository = _MemoryRepository([_monthly, _vacation]);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('June Vacation Plan'));
      await tester.pumpAndSettle();

      expect(repository.activated, 2);
      expect(find.text('June Vacation Plan is now active.'), findsOneWidget);
      // One "Active" chip, on the vacation plan's row now.
      expect(find.text('Active'), findsOneWidget);
      expect(
        find.descendant(
          of: find.widgetWithText(Card, 'June Vacation Plan'),
          matching: find.text('Active'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('the menu offers Activate on an inactive plan only', (
      tester,
    ) async {
      final repository = _MemoryRepository([_monthly, _vacation]);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More for Regular Monthly'));
      await tester.pumpAndSettle();
      expect(find.text('Activate'), findsNothing);
      expect(find.text('Recount spending'), findsOneWidget);
      await tester.tapAt(Offset.zero); // dismiss
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More for June Vacation Plan'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Activate'));
      await tester.pumpAndSettle();

      expect(repository.activated, 2);
    });

    testWidgets('a failure shows its message and the list is unchanged', (
      tester,
    ) async {
      final repository = _MemoryRepository([
        _monthly,
        _vacation,
      ], writeFails: const CacheFailure('database is locked'));
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('June Vacation Plan'));
      await tester.pumpAndSettle();

      expect(find.text('database is locked'), findsOneWidget);
      expect(repository.activated, isNull);
    });
  });

  testWidgets('Recount spending calls the repair (E-18)', (tester) async {
    final repository = _MemoryRepository([_monthly, _vacation]);
    await tester.pumpWidget(boot(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('More for Regular Monthly'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recount spending'));
    await tester.pumpAndSettle();

    expect(repository.recounted, 1);
    expect(
      find.text("Regular Monthly's spending was recounted."),
      findsOneWidget,
    );
  });

  group('comparing two plans (FR-PLN-015)', () {
    testWidgets('Compare with… picks the other plan and opens them side by '
        'side', (tester) async {
      await tester.pumpWidget(boot(_MemoryRepository([_monthly, _vacation])));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More for Regular Monthly'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Compare with…'));
      await tester.pumpAndSettle();
      expect(find.text('Compare Regular Monthly with'), findsOneWidget);
      await tester.tap(find.text('Compare'));
      await tester.pumpAndSettle();

      expect(find.text('Compare plans'), findsOneWidget);
      // Both headers, with their periods — a month against ten days.
      expect(find.text('Regular Monthly'), findsOneWidget);
      expect(find.text('June Vacation Plan'), findsOneWidget);
      expect(find.textContaining('30 days · active'), findsOneWidget);
      expect(find.textContaining('10 days'), findsOneWidget);
      // The totals and their difference.
      expect(find.text('Rs100,000.00'), findsOneWidget);
      expect(find.text('Rs80,000.00'), findsOneWidget);
      expect(find.text('Rs20,000.00 less'), findsOneWidget);
      // Food is in both; Bills only on the left; Travel only on the right.
      expect(find.text('Rs30,000.00'), findsOneWidget);
      expect(find.text('Rs35,000.00'), findsOneWidget);
      expect(find.text('Rs5,000.00 more'), findsOneWidget);
      expect(find.text('Rs45,000.00'), findsNWidgets(2));
      expect(find.text('—'), findsNWidgets(3));
      expect(find.text('Rs45,000.00 less'), findsOneWidget);
      expect(find.text('Rs45,000.00 more'), findsOneWidget);
    });

    testWidgets('a single plan has nothing to compare with', (tester) async {
      await tester.pumpWidget(boot(_MemoryRepository([_monthly])));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('More for Regular Monthly'));
      await tester.pumpAndSettle();

      expect(find.text('Compare with…'), findsNothing);
    });

    testWidgets("the use case's refusal is shown in its words", (tester) async {
      await tester.pumpWidget(
        boot(
          _MemoryRepository([_monthly, _vacation]),
          at: '${Routes.comparePlans}?a=1&b=1',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Pick two different plans to compare.'), findsOneWidget);
    });
  });
}
