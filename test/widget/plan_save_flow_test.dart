@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/income_reader.dart';
import 'package:moneyora/core/ports/monthly_spending_reader.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/money_plan/domain/entities/allocation_request.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/allocate_budget.dart';
import 'package:moneyora/features/money_plan/domain/usecases/classify_categories.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compute_category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/usecases/save_plan.dart';
import 'package:moneyora/features/money_plan/domain/usecases/watch_active_plan.dart';
import 'package:moneyora/features/money_plan/presentation/pages/active_plan_page.dart';
import 'package:moneyora/features/money_plan/presentation/pages/plan_review_page.dart';
import 'package:moneyora/injection.dart';

/// Review → name → save → the saved plan, over the real engine and use
/// cases with scripted ports and an in-memory repository.

class _ScriptedSpending implements MonthlySpendingReader {
  _ScriptedSpending(this.rows);

  final List<MonthlySpending> rows;

  @override
  Future<Either<Failure, List<MonthlySpending>>> monthlySpendingByCategory({
    required DateTime from,
    required DateTime to,
  }) async => Right(rows);
}

class _NoIncome implements IncomeReader {
  @override
  Future<Either<Failure, int>> totalIncome({
    required DateTime from,
    required DateTime to,
  }) async => const Right(0);
}

class _MemoryRepository implements MoneyPlanRepository {
  _MemoryRepository({this.saveFails});

  final Failure? saveFails;
  MoneyPlan? saved;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) async {
    if (saveFails case final f?) return Left(f);
    saved = MoneyPlan(
      id: 1,
      name: plan.name,
      period: plan.period,
      totalBudgetCents: plan.totalBudgetCents,
      isActive: plan.isActive,
      allocations: [
        for (final (i, a) in plan.allocations.indexed)
          PlanAllocation(
            id: i + 1,
            categoryId: a.categoryId,
            categoryName: a.categoryName,
            allocatedCents: a.allocatedCents,
            confidence: a.confidence,
            expenseType: a.expenseType,
          ),
      ],
    );
    _changes.add(null);
    return const Right(1);
  }

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() async* {
    yield Right(saved);
    await for (final _ in _changes.stream) {
      yield Right(saved);
    }
  }

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(DateTime day) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  ) => throw UnimplementedError();
}

void main() {
  final now = DateTime(2026, 9, 13);
  final halfYear = LookbackWindow.before(now);
  final request = AllocationRequest(
    period: PlanPeriod.month(2026, 10),
    lookback: halfYear,
  );

  List<MonthlySpending> shaped() => [
    for (final start in halfYear.monthStarts) ...[
      MonthlySpending(
        categoryId: 1,
        name: 'Bills',
        month: start,
        amountCents: 4500000,
        transactionCount: 1,
      ),
      MonthlySpending(
        categoryId: 2,
        name: 'Food',
        month: start,
        amountCents: 2000000 + (start.month.isEven ? 500000 : 0),
        transactionCount: 20,
      ),
    ],
  ];

  Widget boot(_MemoryRepository repository) => ProviderScope(
    overrides: [
      allocateBudgetProvider.overrideWith(
        (ref) async => AllocateBudget(
          ClassifyCategories(
            ComputeCategoryStatistics(_ScriptedSpending(shaped())),
          ),
          _NoIncome(),
        ),
      ),
      savePlanProvider.overrideWith((ref) async => SavePlan(repository)),
      watchActivePlanProvider.overrideWith(
        (ref) async => WatchActivePlan(repository),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.moneyPlanReview,
        routes: [
          GoRoute(
            path: Routes.home,
            builder: (context, state) => const Scaffold(body: Text('home')),
          ),
          GoRoute(
            path: Routes.moneyPlanReview,
            builder: (context, state) => PlanReviewPage(request: request),
          ),
          GoRoute(
            path: Routes.activePlan,
            builder: (context, state) => const ActivePlanPage(),
          ),
        ],
      ),
    ),
  );

  testWidgets('saves the draft under the chosen name, activated, and lands '
      'on the saved plan with home beneath it', (tester) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(boot(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();

    // The dialog proposes the period as the name; the user can change it.
    expect(find.text('Name your plan'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'October 2026'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Holiday month');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final saved = repository.saved!;
    expect(saved.name, 'Holiday month');
    expect(saved.isActive, isTrue);
    expect(saved.period, PlanPeriod.month(2026, 10));
    expect(saved.allocations.map((a) => a.categoryName), ['Bills', 'Food']);
    expect(saved.allocatedCents, saved.totalBudgetCents);

    // On the saved plan now — and back goes home, not to the review.
    expect(find.text('Holiday month'), findsOneWidget);
    expect(
      find.text(
        'Tap a category to change its budget; the others adjust '
        'to keep the total.',
      ),
      findsOneWidget,
    );
    expect(find.byType(BackButton), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('home'), findsOneWidget);
  });

  testWidgets('a blank name is refused in the use case\'s words, and nothing '
      'is saved', (tester) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(boot(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Give the plan a name.'), findsOneWidget);
    expect(repository.saved, isNull);
    expect(find.text('Save plan'), findsOneWidget, reason: 'still reviewing');
  });

  testWidgets('a failure beneath shows its message and stays on the review', (
    tester,
  ) async {
    final repository = _MemoryRepository(
      saveFails: const CacheFailure('disk is full'),
    );
    await tester.pumpWidget(boot(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('disk is full'), findsOneWidget);
    expect(find.text('Save plan'), findsOneWidget);
  });

  testWidgets('cancelling the name dialog saves nothing', (tester) async {
    final repository = _MemoryRepository();
    await tester.pumpWidget(boot(repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Save plan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(repository.saved, isNull);
  });
}
