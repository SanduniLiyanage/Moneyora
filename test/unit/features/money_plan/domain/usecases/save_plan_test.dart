import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_mode.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/lookback_window.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan_draft.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/save_plan.dart';

class _FakeRepository implements MoneyPlanRepository {
  MoneyPlan? saved;
  Failure? failWith;

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) async {
    saved = plan;
    if (failWith case final f?) return Left(f);
    return const Right(42);
  }

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  ) => throw UnimplementedError();

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Set<int>>> recordAlertLevels(
    List<AlertLevelChange> changes,
  ) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(DateTime day) =>
      throw UnimplementedError();

  @override
  Stream<Either<Failure, List<MoneyPlan>>> watchAll() =>
      throw UnimplementedError();
}

CategoryAllocation _allocation({
  required int categoryId,
  required String name,
  required int cents,
  ExpenseType type = ExpenseType.variable,
  ConfidenceLevel confidence = ConfidenceLevel.medium,
}) {
  final statistics = CategoryStatistics.of(
    categoryId: categoryId,
    name: name,
    monthlyTotalsCents: List.filled(6, cents),
    transactionCount: 6,
  );
  return CategoryAllocation(
    classification: CategoryClassification(statistics: statistics, type: type),
    baseMonthlyCents: cents,
    seasonalFactor: 1.0,
    trendFactor: 1.0,
    allocationCents: cents,
    dailyAllowanceCents: cents ~/ 30,
    confidence: ConfidenceScore(
      level: confidence,
      uncappedLevel: confidence,
      dataPoints: 6,
      coefficientOfVariation: 0,
      lookbackMonths: 6,
    ),
  );
}

final _draft = MoneyPlanDraft(
  period: PlanPeriod.month(2026, 9),
  lookback: LookbackWindow(months: 6, lastMonth: DateTime(2026, 8)),
  mode: const BudgetMode.total(7500000),
  allocations: [
    _allocation(
      categoryId: 1,
      name: 'Bills',
      cents: 4500000,
      type: ExpenseType.fixed,
      confidence: ConfidenceLevel.high,
    ),
    _allocation(categoryId: 2, name: 'Food', cents: 3000000),
  ],
);

void main() {
  late _FakeRepository repository;
  late SavePlan save;

  setUp(() {
    repository = _FakeRepository();
    save = SavePlan(repository);
  });

  test(
    'maps the draft to a plan: name, period, total, one row per category',
    () async {
      final result = await save(
        SavePlanRequest(draft: _draft, name: '  September  '),
      );

      expect(result, const Right<Failure, int>(42));
      final plan = repository.saved!;
      expect(plan.name, 'September');
      expect(plan.period, PlanPeriod.month(2026, 9));
      expect(plan.totalBudgetCents, 7500000);
      expect(plan.isActive, isTrue);
      expect(plan.allocations.length, 2);
      expect(plan.allocations[0].categoryId, 1);
      expect(plan.allocations[0].categoryName, 'Bills');
      expect(plan.allocations[0].allocatedCents, 4500000);
      expect(plan.allocations[0].expenseType, ExpenseType.fixed);
      expect(plan.allocations[0].confidence, ConfidenceLevel.high);
      expect(plan.allocations[0].isUserModified, isFalse);
      expect(plan.allocations[0].spentCents, 0);
      expect(plan.allocations[1].categoryName, 'Food');
    },
  );

  test('activates by default, and not when asked not to', () async {
    await save(SavePlanRequest(draft: _draft, name: 'A'));
    expect(repository.saved!.isActive, isTrue);

    await save(SavePlanRequest(draft: _draft, name: 'B', activate: false));
    expect(repository.saved!.isActive, isFalse);
  });

  test('refuses a blank name without writing', () async {
    final result = await save(SavePlanRequest(draft: _draft, name: '   '));

    result.fold(
      (f) => expect((f as ValidationFailure).field, 'name'),
      (_) => fail('should have refused'),
    );
    expect(repository.saved, isNull);
  });

  test('refuses an empty draft without writing', () async {
    final empty = MoneyPlanDraft(
      period: _draft.period,
      lookback: _draft.lookback,
      mode: _draft.mode,
      allocations: const [],
    );

    final result = await save(SavePlanRequest(draft: empty, name: 'Nothing'));

    result.fold(
      (f) => expect((f as ValidationFailure).field, 'draft'),
      (_) => fail('should have refused'),
    );
    expect(repository.saved, isNull);
  });

  test('a failure from the repository passes through', () async {
    repository.failWith = const CacheFailure('disk is full');

    final result = await save(SavePlanRequest(draft: _draft, name: 'X'));

    expect(result, const Left<Failure, int>(CacheFailure('disk is full')));
  });
}
