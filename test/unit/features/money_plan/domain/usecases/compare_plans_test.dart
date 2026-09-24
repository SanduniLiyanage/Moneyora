import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/usecases/usecase.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_comparison.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/compare_plans.dart';
import 'package:moneyora/features/money_plan/domain/usecases/watch_plans.dart';

/// Hands back scripted plans by id, and a scripted list.
class _FakeRepository implements MoneyPlanRepository {
  final Map<int, MoneyPlan> plans = {};
  Failure? failWith;
  final List<int> asked = [];

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) async {
    asked.add(id);
    if (failWith case final f?) return Left(f);
    return Right(plans[id]);
  }

  @override
  Stream<Either<Failure, List<MoneyPlan>>> watchAll() =>
      Stream.value(Right(plans.values.toList()));

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(DateTime day) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Set<int>>> recordAlertLevels(
    List<AlertLevelChange> changes,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  ) => throw UnimplementedError();

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() =>
      throw UnimplementedError();
}

PlanAllocation _row(int id, String name, int cents, {int spent = 0}) =>
    PlanAllocation(
      categoryId: id,
      categoryName: name,
      allocatedCents: cents,
      spentCents: spent,
      confidence: ConfidenceLevel.medium,
    );

final _monthly = MoneyPlan(
  id: 1,
  name: 'Regular Monthly',
  period: PlanPeriod.month(2026, 9),
  totalBudgetCents: 10000000,
  isActive: true,
  allocations: [
    _row(1, 'Bills', 4500000, spent: 4500000),
    _row(2, 'Food', 3000000, spent: 1200000),
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
  group('PlanComparison.of', () {
    final comparison = PlanComparison.of(_monthly, _vacation);

    test('lists the union of categories, left order first', () {
      expect(comparison.rows.map((r) => r.categoryName), [
        'Bills',
        'Food',
        'Car',
        'Travel',
      ]);
    });

    test('a category in both has both sides', () {
      final food = comparison.rows[1];

      expect(food.left!.allocatedCents, 3000000);
      expect(food.right!.allocatedCents, 3500000);
      expect(food.differenceCents, 500000);
    });

    test('a category in one plan only keeps its side and a blank', () {
      final bills = comparison.rows[0];
      final travel = comparison.rows[3];

      expect(bills.left, isNotNull);
      expect(bills.right, isNull);
      expect(bills.differenceCents, -4500000);
      expect(travel.left, isNull);
      expect(travel.right!.allocatedCents, 4500000);
      expect(travel.differenceCents, 4500000);
    });

    test('nothing is scaled to a common period', () {
      // A ten-day plan against a month: the figures are what each plan
      // allots, and the header carries the periods.
      expect(comparison.left.period.days, 30);
      expect(comparison.right.period.days, 10);
      expect(comparison.rows[1].right!.allocatedCents, 3500000);
    });

    test('the total difference is right less left', () {
      expect(comparison.totalDifferenceCents, -2000000);
    });

    test('carries the spend, so a past plan can be read against what '
        'happened', () {
      expect(comparison.rows[0].left!.spentCents, 4500000);
    });
  });

  group('ComparePlans', () {
    test('reads both plans and compares them', () async {
      final repository = _FakeRepository()
        ..plans[1] = _monthly
        ..plans[2] = _vacation;

      final result = await ComparePlans(repository)(
        const ComparePlansRequest(leftId: 1, rightId: 2),
      );

      expect(repository.asked, [1, 2]);
      expect(
        result.getOrElse((_) => fail('expected a comparison')).rows,
        hasLength(4),
      );
    });

    test('refuses the same plan twice, without reading', () async {
      final repository = _FakeRepository()..plans[1] = _monthly;

      final result = await ComparePlans(repository)(
        const ComparePlansRequest(leftId: 1, rightId: 1),
      );

      expect(
        result,
        const Left<Failure, PlanComparison>(
          ValidationFailure('Pick two different plans to compare.'),
        ),
      );
      expect(repository.asked, isEmpty);
    });

    test('names a plan that is not there', () async {
      final repository = _FakeRepository()..plans[1] = _monthly;

      final result = await ComparePlans(repository)(
        const ComparePlansRequest(leftId: 1, rightId: 9),
      );

      expect(
        result,
        const Left<Failure, PlanComparison>(
          ValidationFailure('No plan with id 9.'),
        ),
      );
    });

    test('a failure beneath passes through', () async {
      final repository = _FakeRepository()
        ..failWith = const CacheFailure('disk is full');

      final result = await ComparePlans(repository)(
        const ComparePlansRequest(leftId: 1, rightId: 2),
      );

      expect(
        result,
        const Left<Failure, PlanComparison>(CacheFailure('disk is full')),
      );
    });
  });

  test('WatchPlans forwards what the repository emits', () async {
    final repository = _FakeRepository()
      ..plans[1] = _monthly
      ..plans[2] = _vacation;

    final emitted = await WatchPlans(repository)(const NoParams()).first;

    expect(emitted.getOrElse((_) => []).map((p) => p.name), [
      'Regular Monthly',
      'June Vacation Plan',
    ]);
  });
}
