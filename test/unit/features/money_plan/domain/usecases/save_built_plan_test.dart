import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_classification.dart';
import 'package:moneyora/features/money_plan/domain/entities/category_statistics.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_line.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/save_built_plan.dart';

class _FakeRepository implements MoneyPlanRepository {
  MoneyPlan? saved;
  Failure? failWith;

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) async {
    saved = plan;
    if (failWith case final f?) return Left(f);
    return const Right(7);
  }

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> rename(int id, String name) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> delete(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations, {
    int? totalBudgetCents,
  }) => throw UnimplementedError();

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

CategoryAllocation _generated(int id, String name, int cents) =>
    CategoryAllocation(
      classification: CategoryClassification(
        statistics: CategoryStatistics.of(
          categoryId: id,
          name: name,
          monthlyTotalsCents: List.filled(6, cents),
          transactionCount: 6,
        ),
        type: ExpenseType.fixed,
      ),
      baseMonthlyCents: cents,
      seasonalFactor: 1.0,
      trendFactor: 1.0,
      allocationCents: cents,
      dailyAllowanceCents: cents ~/ 30,
      confidence: const ConfidenceScore(
        level: ConfidenceLevel.high,
        uncappedLevel: ConfidenceLevel.high,
        dataPoints: 6,
        coefficientOfVariation: 0,
        lookbackMonths: 6,
      ),
    );

void main() {
  late _FakeRepository repository;
  late SaveBuiltPlan save;
  final october = PlanPeriod.month(2026, 10);

  BuiltPlanRequest request(List<PlanLine> lines, {String name = 'October'}) =>
      BuiltPlanRequest(name: name, period: october, lines: lines);

  const food = PlanLine(
    categoryId: 1,
    categoryName: 'Food',
    amountCents: 3000000,
  );

  setUp(() {
    repository = _FakeRepository();
    save = SaveBuiltPlan(repository);
  });

  group('a plan built by hand', () {
    test('saves every line with an amount; the total is their sum', () async {
      final result = await save(
        request([
          food,
          const PlanLine(
            categoryId: 2,
            categoryName: 'Transport',
            amountCents: 1000000,
          ),
          const PlanLine(categoryId: 3, categoryName: 'Gifts', amountCents: 0),
        ]),
      );

      expect(result, const Right<Failure, int>(7));
      final plan = repository.saved!;
      expect(plan.name, 'October');
      expect(plan.period, october);
      expect(plan.isActive, isTrue);
      expect(plan.totalBudgetCents, 4000000);
      expect(plan.allocations.map((a) => a.categoryId), [1, 2]);
    });

    test('a line of the user own is Low confidence, unclassed, and set by '
        'the user', () async {
      await save(request([food]));

      final row = repository.saved!.allocations.single;
      expect(row.confidence, ConfidenceLevel.low);
      expect(row.expenseType, isNull);
      expect(row.isUserModified, isTrue);
      expect(row.categoryName, 'Food');
    });

    test('can be kept for later rather than tracked', () async {
      await save(
        BuiltPlanRequest(
          name: 'Holiday',
          period: october,
          lines: const [food],
          activate: false,
        ),
      );

      expect(repository.saved!.isActive, isFalse);
    });

    test('the name is trimmed', () async {
      await save(request([food], name: '  October  '));

      expect(repository.saved!.name, 'October');
    });
  });

  group('a generated plan, edited', () {
    test('an untouched line keeps its class and confidence, and is not '
        'set by the user', () async {
      await save(request([PlanLine.suggested(_generated(4, 'Rent', 4500000))]));

      final row = repository.saved!.allocations.single;
      expect(row.allocatedCents, 4500000);
      expect(row.confidence, ConfidenceLevel.high);
      expect(row.expenseType, ExpenseType.fixed);
      expect(row.isUserModified, isFalse);
    });

    test(
      'a changed line keeps its provenance and is set by the user',
      () async {
        final line = PlanLine.suggested(_generated(4, 'Rent', 4500000))
            .withAmount(5000000);

        await save(request([line]));

        final row = repository.saved!.allocations.single;
        expect(row.allocatedCents, 5000000);
        expect(row.expenseType, ExpenseType.fixed);
        expect(row.isUserModified, isTrue);
      },
    );

    test('a line set to nothing leaves the plan', () async {
      await save(
        request([
          PlanLine.suggested(_generated(4, 'Rent', 4500000)).withAmount(0),
          food,
        ]),
      );

      expect(repository.saved!.allocations.map((a) => a.categoryId), [1]);
      expect(repository.saved!.totalBudgetCents, 3000000);
    });
  });

  group('refuses, without writing', () {
    Future<void> refuses(BuiltPlanRequest r, String message) async {
      final result = await save(r);

      expect(result.getLeft().toNullable()?.message, message);
      expect(repository.saved, isNull);
    }

    test(
      'no line with an amount',
      () => refuses(
        request([
          const PlanLine(categoryId: 1, categoryName: 'Food', amountCents: 0),
        ]),
        'Give at least one category an amount.',
      ),
    );

    test(
      'no lines at all',
      () => refuses(request(const []), 'Give at least one category an amount.'),
    );

    test(
      'a negative amount',
      () => refuses(
        request([
          food,
          const PlanLine(categoryId: 2, categoryName: 'Fuel', amountCents: -1),
        ]),
        'A budget cannot be less than nothing.',
      ),
    );

    test(
      'the same category twice',
      () => refuses(
        request([food, food.withAmount(5)]),
        'A category can appear only once in a plan.',
      ),
    );

    test(
      'a blank name',
      () => refuses(request([food], name: '   '), 'Give the plan a name.'),
    );

    test('an inverted period', () async {
      final result = await save(
        BuiltPlanRequest(
          name: 'Backwards',
          period: PlanPeriod(
            from: DateTime(2026, 10, 10),
            to: DateTime(2026, 10, 1),
          ),
          lines: const [food],
        ),
      );

      expect(result.getLeft().toNullable(), isA<ValidationFailure>());
      expect(repository.saved, isNull);
    });
  });

  test('a failure from the repository passes through', () async {
    repository.failWith = const CacheFailure();

    final result = await save(request([food]));

    expect(result, const Left<Failure, int>(CacheFailure()));
  });
}
