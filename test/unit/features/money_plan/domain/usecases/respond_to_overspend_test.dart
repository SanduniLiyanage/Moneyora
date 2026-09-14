import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/respond_to_overspend.dart';

/// Hands back a scripted plan and records what it was asked to write.
class _FakeRepository implements MoneyPlanRepository {
  MoneyPlan? plan;
  Failure? readFails;
  Failure? writeFails;
  int? writtenPlanId;
  List<PlanAllocation>? written;

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) async {
    if (readFails case final f?) return Left(f);
    return Right(plan?.id == id ? plan : null);
  }

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  ) async {
    writtenPlanId = planId;
    written = allocations;
    if (writeFails case final f?) return Left(f);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) =>
      throw UnimplementedError();

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(DateTime day) =>
      throw UnimplementedError();

  @override
  Stream<Either<Failure, List<MoneyPlan>>> watchAll() =>
      throw UnimplementedError();
}

PlanAllocation _row(
  int categoryId,
  int allocated, {
  int spent = 0,
  bool byUser = false,
  int carry = 0,
}) => PlanAllocation(
  categoryId: categoryId,
  allocatedCents: allocated,
  spentCents: spent,
  carryOverCents: carry,
  confidence: ConfidenceLevel.medium,
  isUserModified: byUser,
);

MoneyPlan _plan(List<PlanAllocation> rows) => MoneyPlan(
  id: 7,
  name: 'September',
  period: PlanPeriod.month(2026, 9),
  totalBudgetCents: rows.fold(0, (s, a) => s + a.allocatedCents),
  isActive: true,
  allocations: rows,
);

int _sum(List<PlanAllocation> rows) =>
    rows.fold(0, (s, a) => s + a.allocatedCents);

PlanAllocation _of(List<PlanAllocation> rows, int categoryId) =>
    rows.firstWhere((a) => a.categoryId == categoryId);

OverspendRequest _request(OverspendResponse response, {int category = 1}) =>
    OverspendRequest(planId: 7, categoryId: category, response: response);

void main() {
  // Food is 5,000 over. Of the others, Bills has 10,000 left, Car 30,000,
  // Pets nothing at all.
  final plan = _plan([
    _row(1, 3000000, spent: 3500000), // Food, 5,000 over
    _row(2, 4500000, spent: 3500000), // Bills, 10,000 left
    _row(3, 3000000, spent: 0), // Car, 30,000 left
    _row(4, 1000000, spent: 1000000), // Pets, nothing left
  ]);

  group('exceeded', () {
    test('is spent past the allocation, strictly', () {
      expect(_row(1, 100, spent: 101).overspendCents, 1);
      expect(_row(1, 100, spent: 100).overspendCents, 0);
      expect(_row(1, 100, spent: 99).overspendCents, 0);
    });

    test('a category within budget has nothing to respond to', () {
      final failure = RespondToOverspend.validate(
        plan,
        _request(const OverspendResponse.autoRedistribute(), category: 2),
      );

      expect(failure?.message, 'This category is within its budget.');
    });

    test('a category not in the plan is refused', () {
      final failure = RespondToOverspend.validate(
        plan,
        _request(const OverspendResponse.carryOver(), category: 99),
      );

      expect(failure?.message, 'That category is not in this plan.');
    });
  });

  group('auto-redistribute', () {
    test('raises the category to its spend and takes the overspend from '
        'the others by what each has left', () {
      final after = RespondToOverspend.autoRedistribute(plan.allocations, 1);

      // 5,000 split 10,000 : 30,000 : 0 → 1,250 : 3,750 : 0.
      expect(_of(after, 1).allocatedCents, 3500000);
      expect(_of(after, 2).allocatedCents, 4500000 - 125000);
      expect(_of(after, 3).allocatedCents, 3000000 - 375000);
      expect(_of(after, 4).allocatedCents, 1000000, reason: 'nothing left');
      expect(_sum(after), _sum(plan.allocations), reason: 'total held');
      expect(after.map((a) => a.categoryId), [1, 2, 3, 4], reason: 'order');
    });

    test('never takes a category under what it has spent', () {
      final after = RespondToOverspend.autoRedistribute(plan.allocations, 1);

      for (final a in after) {
        expect(a.allocatedCents, greaterThanOrEqualTo(a.spentCents));
      }
    });

    test('the exceeded category then reads exactly spent, not over', () {
      final after = RespondToOverspend.autoRedistribute(plan.allocations, 1);

      expect(_of(after, 1).overspendCents, 0);
      expect(_of(after, 1).remainingCents, 0);
    });

    test('is not the user\'s change', () {
      final after = RespondToOverspend.autoRedistribute(plan.allocations, 1);

      expect(after.any((a) => a.isUserModified), isFalse);
    });

    test('is refused when the others cannot cover it', () {
      final tight = _plan([
        _row(1, 3000000, spent: 3500000),
        _row(2, 4500000, spent: 4460000), // 400 left
        _row(4, 1000000, spent: 1000000),
      ]);

      final failure = RespondToOverspend.validate(
        tight,
        _request(const OverspendResponse.autoRedistribute()),
      );

      expect(
        failure?.message,
        'The other categories do not have enough left between them to cover '
        'the overspend.',
      );
    });

    test('is refused when there is no other category', () {
      final alone = _plan([_row(1, 3000000, spent: 3500000)]);

      expect(
        RespondToOverspend.validate(
          alone,
          _request(const OverspendResponse.autoRedistribute()),
        ),
        isNotNull,
      );
    });

    test('covers it exactly when the others have exactly enough', () {
      final exact = _plan([
        _row(1, 3000000, spent: 3500000),
        _row(2, 4500000, spent: 4200000), // 3,000 left
        _row(3, 2000000, spent: 1800000), // 2,000 left
      ]);

      expect(
        RespondToOverspend.validate(
          exact,
          _request(const OverspendResponse.autoRedistribute()),
        ),
        isNull,
      );
      final after = RespondToOverspend.autoRedistribute(exact.allocations, 1);
      expect(_of(after, 2).allocatedCents, 4200000);
      expect(_of(after, 3).allocatedCents, 1800000);
    });
  });

  group('manual adjust', () {
    test('moves the whole overspend from the chosen category', () {
      final after = RespondToOverspend.manualAdjust(
        plan.allocations,
        1,
        fromCategoryId: 3,
      );

      expect(_of(after, 1).allocatedCents, 3500000);
      expect(_of(after, 3).allocatedCents, 2500000);
      expect(_of(after, 2).allocatedCents, 4500000, reason: 'untouched');
      expect(_sum(after), _sum(plan.allocations));
    });

    test('marks both rows as the user\'s', () {
      final after = RespondToOverspend.manualAdjust(
        plan.allocations,
        1,
        fromCategoryId: 3,
      );

      expect(_of(after, 1).isUserModified, isTrue);
      expect(_of(after, 3).isUserModified, isTrue);
      expect(_of(after, 2).isUserModified, isFalse);
    });

    test('refuses the exceeded category itself', () {
      final failure = RespondToOverspend.validate(
        plan,
        _request(const OverspendResponse.manualAdjust(fromCategoryId: 1)),
      );

      expect(failure?.message, 'Pick a different category to reduce.');
    });

    test('refuses a category that has not got it left', () {
      final failure = RespondToOverspend.validate(
        plan,
        _request(const OverspendResponse.manualAdjust(fromCategoryId: 4)),
      );

      expect(
        failure?.message,
        'That category does not have enough left to cover the overspend.',
      );
    });

    test('refuses a category not in the plan', () {
      final failure = RespondToOverspend.validate(
        plan,
        _request(const OverspendResponse.manualAdjust(fromCategoryId: 99)),
      );

      expect(failure?.message, 'That category is not in this plan.');
    });

    test('allows a category with exactly enough left', () {
      // Bills has 10,000 left; a 10,000 overspend fits exactly.
      final exact = _plan([
        _row(1, 3000000, spent: 4000000),
        _row(2, 4500000, spent: 3500000),
      ]);

      expect(
        RespondToOverspend.validate(
          exact,
          _request(const OverspendResponse.manualAdjust(fromCategoryId: 2)),
        ),
        isNull,
      );
    });
  });

  group('carry over', () {
    test('records the overspend on the row and changes no figure', () {
      final after = RespondToOverspend.carryOver(plan.allocations, 1);

      expect(_of(after, 1).carryOverCents, 500000);
      expect(_of(after, 1).allocatedCents, 3000000);
      expect(_of(after, 1).spentCents, 3500000);
      expect(after.where((a) => a.categoryId != 1), [
        for (final a in plan.allocations)
          if (a.categoryId != 1) a,
      ]);
    });

    test('replaces an earlier carry-over rather than adding to it', () {
      final again = [
        _row(1, 3000000, spent: 3700000, carry: 500000),
        _row(2, 4500000),
      ];

      final after = RespondToOverspend.carryOver(again, 1);

      expect(_of(after, 1).carryOverCents, 700000);
    });

    test('is never refused for an exceeded category', () {
      final alone = _plan([_row(1, 3000000, spent: 3500000)]);

      expect(
        RespondToOverspend.validate(
          alone,
          _request(const OverspendResponse.carryOver()),
        ),
        isNull,
      );
    });
  });

  group('the use case', () {
    test('reads the plan, applies the response and writes every row', () async {
      final repository = _FakeRepository()..plan = plan;

      final result = await RespondToOverspend(repository)(
        _request(const OverspendResponse.manualAdjust(fromCategoryId: 3)),
      );

      expect(repository.writtenPlanId, 7);
      expect(_of(repository.written!, 3).allocatedCents, 2500000);
      final returned = result.getOrElse((_) => fail('expected a plan'));
      expect(returned.allocations, repository.written);
      expect(returned.totalBudgetCents, plan.totalBudgetCents);
    });

    test('a refusal writes nothing', () async {
      final repository = _FakeRepository()..plan = plan;

      final result = await RespondToOverspend(repository)(
        _request(const OverspendResponse.manualAdjust(fromCategoryId: 4)),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.written, isNull);
    });

    test('a missing plan is a validation failure', () async {
      final repository = _FakeRepository();

      final result = await RespondToOverspend(repository)(
        _request(const OverspendResponse.carryOver()),
      );

      expect(
        result,
        const Left<Failure, MoneyPlan>(ValidationFailure('No plan with id 7.')),
      );
    });

    test('a failure beneath passes through', () async {
      final repository = _FakeRepository()
        ..plan = plan
        ..writeFails = const CacheFailure('disk is full');

      final result = await RespondToOverspend(repository)(
        _request(const OverspendResponse.carryOver()),
      );

      expect(
        result,
        const Left<Failure, MoneyPlan>(CacheFailure('disk is full')),
      );
    });
  });
}
