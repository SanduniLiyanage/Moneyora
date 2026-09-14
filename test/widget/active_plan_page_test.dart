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
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/update_allocation.dart';
import 'package:moneyora/features/money_plan/domain/usecases/watch_active_plan.dart';
import 'package:moneyora/features/money_plan/presentation/pages/active_plan_page.dart';
import 'package:moneyora/injection.dart';

/// The saved-plan screen over the real use cases and an in-memory
/// repository whose stream re-emits after every write — so an adjustment is
/// seen the way the screen will see it in the app: through the stream, not
/// through local state.
class _MemoryRepository implements MoneyPlanRepository {
  _MemoryRepository({this.plan, this.hold, this.readFails});

  MoneyPlan? plan;
  final Completer<void>? hold;
  final Failure? readFails;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  List<PlanAllocation>? written;

  /// What the transactions datasource does after an expense write: the
  /// plan's rows change beneath the screen and the shared bus ticks.
  void spend(MoneyPlan updated) {
    plan = updated;
    _changes.add(null);
  }

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() async* {
    if (hold != null) await hold!.future;
    if (readFails case final f?) {
      yield Left(f);
      return;
    }
    yield Right(plan);
    await for (final _ in _changes.stream) {
      yield Right(plan);
    }
  }

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) async =>
      Right(plan?.id == id ? plan : null);

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  ) async {
    written = allocations;
    final p = plan!;
    plan = MoneyPlan(
      id: p.id,
      name: p.name,
      period: p.period,
      totalBudgetCents: p.totalBudgetCents,
      isActive: p.isActive,
      allocations: allocations,
    );
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) =>
      throw UnimplementedError();
}

PlanAllocation _row(
  int id,
  String name,
  int cents, {
  ExpenseType? type,
  ConfidenceLevel confidence = ConfidenceLevel.medium,
  int spent = 0,
}) => PlanAllocation(
  categoryId: id,
  categoryName: name,
  allocatedCents: cents,
  spentCents: spent,
  confidence: confidence,
  expenseType: type,
);

final _september = MoneyPlan(
  id: 7,
  name: 'September',
  period: PlanPeriod.month(2026, 9),
  totalBudgetCents: 10000000,
  isActive: true,
  allocations: [
    _row(
      1,
      'Bills',
      4500000,
      type: ExpenseType.fixed,
      confidence: ConfidenceLevel.high,
    ),
    _row(2, 'Food', 3000000, type: ExpenseType.variable),
    _row(3, 'Car', 2500000, type: ExpenseType.variable),
  ],
);

/// [_september] with spend against it: Bills a third through, Food at
/// exactly 80%, Car exactly spent.
MoneyPlan _tracked({int billsSpent = 1500000}) => MoneyPlan(
  id: 7,
  name: 'September',
  period: PlanPeriod.month(2026, 9),
  totalBudgetCents: 10000000,
  isActive: true,
  allocations: [
    _row(
      1,
      'Bills',
      4500000,
      type: ExpenseType.fixed,
      confidence: ConfidenceLevel.high,
      spent: billsSpent,
    ),
    _row(2, 'Food', 3000000, type: ExpenseType.variable, spent: 2400000),
    _row(3, 'Car', 2500000, type: ExpenseType.variable, spent: 2500000),
  ],
);

void main() {
  Widget boot(_MemoryRepository repository, {DateTime? now}) => ProviderScope(
    overrides: [
      watchActivePlanProvider.overrideWith(
        (ref) async => WatchActivePlan(repository),
      ),
      updateAllocationProvider.overrideWith(
        (ref) async => UpdateAllocation(repository),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.activePlan,
        routes: [
          GoRoute(
            path: Routes.activePlan,
            builder: (context, state) => ActivePlanPage(now: now),
          ),
          GoRoute(
            path: Routes.moneyPlan,
            builder: (context, state) => const Scaffold(body: Text('wizard')),
          ),
        ],
      ),
    ),
  );

  testWidgets('spins until the plan arrives', (tester) async {
    final hold = Completer<void>();
    await tester.pumpWidget(
      boot(_MemoryRepository(plan: _september, hold: hold)),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    hold.complete();
    await tester.pumpAndSettle();
    expect(find.text('September'), findsOneWidget);
  });

  testWidgets('with no active plan, says so and offers the wizard', (
    tester,
  ) async {
    await tester.pumpWidget(boot(_MemoryRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No active plan'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsNothing);

    await tester.tap(find.text('Create Money Plan'));
    await tester.pumpAndSettle();
    expect(find.text('wizard'), findsOneWidget);
  });

  testWidgets('shows the plan: name, period, total, one row per category '
      'with its figure, class and confidence', (tester) async {
    await tester.pumpWidget(boot(_MemoryRepository(plan: _september)));
    await tester.pumpAndSettle();

    expect(find.text('September'), findsOneWidget);
    expect(find.text('September 2026 · 30 days'), findsOneWidget);
    expect(find.text('Rs100,000.00'), findsOneWidget);
    expect(find.text('Bills'), findsOneWidget);
    expect(find.text('Rs45,000.00'), findsOneWidget);
    expect(
      find.text('Rs1,500.00 a day · Fixed · High confidence'),
      findsOneWidget,
    );
    expect(find.text('Food'), findsOneWidget);
    expect(find.text('Car'), findsOneWidget);
  });

  testWidgets('a failure reading shows its message', (tester) async {
    await tester.pumpWidget(
      boot(_MemoryRepository(readFails: const CacheFailure('disk is full'))),
    );
    await tester.pumpAndSettle();

    expect(find.text('disk is full'), findsOneWidget);
  });

  group('adjusting an allocation (FR-PLN-011)', () {
    testWidgets('writes the new figure and shows the others recalculated '
        'to hold the total', (tester) async {
      final repository = _MemoryRepository(plan: _september);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      expect(find.text('Name your plan'), findsNothing);
      expect(find.text('Budget for the period'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '40000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      // Food is 40,000; Bills and Car share the remaining 60,000 in their
      // 45:25 ratio; the total is still 100,000.
      final rows = repository.written!;
      expect(rows.map((a) => a.allocatedCents), [3857143, 4000000, 2142857]);
      expect(rows.fold(0, (s, a) => s + a.allocatedCents), 10000000);

      expect(find.text('Rs40,000.00'), findsOneWidget);
      expect(find.text('Rs38,571.43'), findsOneWidget);
      expect(find.text('Rs21,428.57'), findsOneWidget);
      expect(find.textContaining('set by you'), findsOneWidget);
      expect(find.text('Rs100,000.00'), findsOneWidget);
    });

    testWidgets("a refused amount shows the use case's own sentence and "
        'changes nothing', (tester) async {
      final repository = _MemoryRepository(plan: _september);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '250000');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(
        find.text("An allocation cannot exceed the plan's total."),
        findsOneWidget,
      );
      expect(repository.written, isNull);
      expect(find.text('Rs30,000.00'), findsOneWidget);
    });

    testWidgets('an unparseable amount is caught in the dialog', (
      tester,
    ) async {
      final repository = _MemoryRepository(plan: _september);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'lots');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount.'), findsOneWidget);
      expect(repository.written, isNull);
    });

    testWidgets('cancelling writes nothing', (tester) async {
      final repository = _MemoryRepository(plan: _september);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(repository.written, isNull);
    });
  });

  group('what if (FR-PLN-012)', () {
    testWidgets('answers the question without writing', (tester) async {
      final repository = _MemoryRepository(plan: _september);
      await tester.pumpWidget(boot(repository));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();

      // Defaults: reduce the first category (Bills) by 10%, give it to the
      // second (Food). 10% of 45,000 is 4,500.
      expect(find.text('What if…'), findsOneWidget);
      expect(find.text('Bills: Rs45,000.00 → Rs40,500.00'), findsOneWidget);
      expect(
        find.text('Food could take Rs4,500.00 more: Rs30,000.00 → Rs34,500.00'),
        findsOneWidget,
      );
      expect(find.textContaining('A preview'), findsOneWidget);
      expect(repository.written, isNull);
    });

    testWidgets('follows the percentage as it is typed', (tester) async {
      await tester.pumpWidget(boot(_MemoryRepository(plan: _september)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'By'), '50');
      await tester.pumpAndSettle();

      expect(find.text('Bills: Rs45,000.00 → Rs22,500.00'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'By'), '150');
      await tester.pumpAndSettle();
      expect(find.text('A percentage from 0 to 100.'), findsOneWidget);
    });

    testWidgets('the same category twice is refused', (tester) async {
      await tester.pumpWidget(boot(_MemoryRepository(plan: _september)));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.help_outline));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Bills').last);
      await tester.pumpAndSettle();

      expect(find.text('Pick two different categories.'), findsOneWidget);
    });
  });

  group('tracking (FR-PLN-013)', () {
    final midMonth = DateTime(2026, 9, 15, 10, 30);

    Color barColour(WidgetTester tester, int index) => tester
        .widgetList<LinearProgressIndicator>(
          find.byType(LinearProgressIndicator),
        )
        .elementAt(index)
        .color!;

    testWidgets('each row shows spent, percentage and the projection to '
        'the period\'s end', (tester) async {
      await tester.pumpWidget(
        boot(_MemoryRepository(plan: _tracked()), now: midMonth),
      );
      await tester.pumpAndSettle();

      // Bills: 15,000 of 45,000 halfway through — 33%, heading for 30,000,
      // 15,000 under. Food: 24,000 of 30,000 — 80%, heading for 48,000,
      // 18,000 over. Car: 25,000 of 25,000 — 100%, heading for 50,000,
      // 25,000 over.
      expect(
        find.text('Rs15,000.00 spent · 33% · heading Rs15,000.00 under'),
        findsOneWidget,
      );
      expect(
        find.text('Rs24,000.00 spent · 80% · heading Rs18,000.00 over'),
        findsOneWidget,
      );
      expect(
        find.text('Rs25,000.00 spent · 100% · heading Rs25,000.00 over'),
        findsOneWidget,
      );
      // The budget figures and provenance are still there beside them.
      expect(find.text('Rs45,000.00'), findsOneWidget);
      expect(
        find.text('Rs1,500.00 a day · Fixed · High confidence'),
        findsOneWidget,
      );
    });

    testWidgets('the three colours: green under 80%, yellow from 80%, red '
        'at 100%', (tester) async {
      await tester.pumpWidget(
        boot(_MemoryRepository(plan: _tracked()), now: midMonth),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
      expect(barColour(tester, 0), AppColors.light.income);
      expect(barColour(tester, 1), AppColors.light.accent);
      expect(barColour(tester, 2), AppColors.light.expense);
    });

    testWidgets('the header totals the spend and names the day', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(_MemoryRepository(plan: _tracked()), now: midMonth),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rs64,000.00 spent · day 15 of 30'), findsOneWidget);
    });

    testWidgets('before the period starts there is nothing to project', (
      tester,
    ) async {
      await tester.pumpWidget(
        boot(_MemoryRepository(plan: _tracked()), now: DateTime(2026, 8, 20)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Rs15,000.00 spent · 33%'), findsOneWidget);
      expect(find.textContaining('heading'), findsNothing);
      expect(find.text('Rs64,000.00 spent · not started'), findsOneWidget);
    });

    testWidgets('an expense saved elsewhere moves the row through the '
        'stream', (tester) async {
      // No local state: the transactions datasource writes the cache and
      // ticks the shared bus; the screen only re-reads.
      final repository = _MemoryRepository(plan: _tracked());
      await tester.pumpWidget(boot(repository, now: midMonth));
      await tester.pumpAndSettle();
      expect(barColour(tester, 0), AppColors.light.income);

      repository.spend(_tracked(billsSpent: 4600000));
      await tester.pumpAndSettle();

      expect(
        find.text('Rs46,000.00 spent · 102% · heading Rs47,000.00 over'),
        findsOneWidget,
      );
      expect(barColour(tester, 0), AppColors.light.expense);
      expect(find.text('Rs95,000.00 spent · day 15 of 30'), findsOneWidget);
    });
  });
}
