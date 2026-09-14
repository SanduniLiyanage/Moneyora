import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/update_allocation.dart';

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

PlanAllocation _row(int categoryId, int cents, {bool byUser = false}) =>
    PlanAllocation(
      categoryId: categoryId,
      allocatedCents: cents,
      confidence: ConfidenceLevel.medium,
      isUserModified: byUser,
    );

int _sum(List<PlanAllocation> rows) =>
    rows.fold(0, (s, a) => s + a.allocatedCents);

void main() {
  group('rebalance', () {
    test('sets the one and spreads the difference over the rest, holding '
        'the total exactly', () {
      final rows = [_row(1, 500), _row(2, 300), _row(3, 200)];

      final out = UpdateAllocation.rebalance(
        rows,
        categoryId: 1,
        allocatedCents: 400,
        totalCents: 1000,
      );

      expect(out.map((a) => a.categoryId), [1, 2, 3]);
      expect(out[0].allocatedCents, 400);
      expect(out[0].isUserModified, isTrue);
      // 600 shared 3:2 → 360, 240.
      expect(out[1].allocatedCents, 360);
      expect(out[2].allocatedCents, 240);
      expect(_sum(out), 1000);
    });

    test('an odd remainder still sums exactly', () {
      final rows = [_row(1, 500), _row(2, 300), _row(3, 200)];

      final out = UpdateAllocation.rebalance(
        rows,
        categoryId: 1,
        allocatedCents: 401,
        totalCents: 1000,
      );

      expect(_sum(out), 1000);
    });

    test('a second manual change does not undo the first', () {
      // The user set category 2 to 350 earlier; now they set 1 to 400.
      final rows = [_row(1, 500), _row(2, 350, byUser: true), _row(3, 150)];

      final out = UpdateAllocation.rebalance(
        rows,
        categoryId: 1,
        allocatedCents: 400,
        totalCents: 1000,
      );

      expect(out[1].allocatedCents, 350, reason: 'held');
      expect(out[1].isUserModified, isTrue);
      expect(out[2].allocatedCents, 250, reason: 'absorbed all of it');
      expect(out[2].isUserModified, isFalse);
      expect(_sum(out), 1000);
    });

    test('when every other row is the user\'s, they all absorb it', () {
      final rows = [
        _row(1, 500),
        _row(2, 300, byUser: true),
        _row(3, 200, byUser: true),
      ];

      final out = UpdateAllocation.rebalance(
        rows,
        categoryId: 1,
        allocatedCents: 600,
        totalCents: 1000,
      );

      // 400 shared 3:2.
      expect(out[1].allocatedCents, 240);
      expect(out[2].allocatedCents, 160);
      expect(_sum(out), 1000);
    });

    test('when the untouched rows cannot absorb it, everyone does', () {
      // Held rows already take 700; setting 1 to 400 leaves −100 for the
      // untouched row, so the fallback spreads 600 across all others.
      final rows = [_row(1, 200), _row(2, 700, byUser: true), _row(3, 100)];

      final out = UpdateAllocation.rebalance(
        rows,
        categoryId: 1,
        allocatedCents: 400,
        totalCents: 1000,
      );

      expect(_sum(out), 1000);
      expect(out.every((a) => a.allocatedCents >= 0), isTrue);
      expect(out[1].allocatedCents, 525); // 600 × 7/8
      expect(out[2].allocatedCents, 75); // 600 × 1/8
    });

    test('setting a row to the whole total zeroes the rest', () {
      final rows = [_row(1, 500), _row(2, 300), _row(3, 200)];

      final out = UpdateAllocation.rebalance(
        rows,
        categoryId: 2,
        allocatedCents: 1000,
        totalCents: 1000,
      );

      expect(out.map((a) => a.allocatedCents), [0, 1000, 0]);
    });

    test('setting a row to zero hands its share to the rest', () {
      final rows = [_row(1, 500), _row(2, 300), _row(3, 200)];

      final out = UpdateAllocation.rebalance(
        rows,
        categoryId: 3,
        allocatedCents: 0,
        totalCents: 1000,
      );

      expect(out.map((a) => a.allocatedCents), [625, 375, 0]);
    });

    test('rows the user already set keep their flag; the rest stay clear', () {
      final rows = [_row(1, 500), _row(2, 300, byUser: true), _row(3, 200)];

      final out = UpdateAllocation.rebalance(
        rows,
        categoryId: 3,
        allocatedCents: 100,
        totalCents: 1000,
      );

      expect(out.map((a) => a.isUserModified), [false, true, true]);
    });
  });

  group('the use case', () {
    late _FakeRepository repository;
    late UpdateAllocation update;

    final plan = MoneyPlan(
      id: 7,
      name: 'September',
      period: PlanPeriod.month(2026, 9),
      totalBudgetCents: 1000,
      isActive: true,
      allocations: [_row(1, 500), _row(2, 300), _row(3, 200)],
    );

    setUp(() {
      repository = _FakeRepository()..plan = plan;
      update = UpdateAllocation(repository);
    });

    test(
      'reads the plan, rebalances, writes every row, returns the plan',
      () async {
        final result = await update(
          const UpdateAllocationRequest(
            planId: 7,
            categoryId: 1,
            allocatedCents: 400,
          ),
        );

        result.fold((f) => fail('unexpected failure: $f'), (updated) {
          expect(updated.id, 7);
          expect(updated.totalBudgetCents, 1000);
          expect(updated.allocatedCents, 1000);
          expect(updated.allocations[0].allocatedCents, 400);
        });
        expect(repository.writtenPlanId, 7);
        expect(_sum(repository.written!), 1000);
      },
    );

    test('refuses a negative amount before reading', () async {
      final result = await update(
        const UpdateAllocationRequest(
          planId: 7,
          categoryId: 1,
          allocatedCents: -1,
        ),
      );

      result.fold(
        (f) => expect((f as ValidationFailure).field, 'allocatedCents'),
        (_) => fail('should have refused'),
      );
      expect(repository.written, isNull);
    });

    test('refuses an amount over the total', () async {
      final result = await update(
        const UpdateAllocationRequest(
          planId: 7,
          categoryId: 1,
          allocatedCents: 1001,
        ),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.written, isNull);
    });

    test('refuses a category that is not in the plan', () async {
      final result = await update(
        const UpdateAllocationRequest(
          planId: 7,
          categoryId: 99,
          allocatedCents: 100,
        ),
      );

      result.fold(
        (f) => expect((f as ValidationFailure).field, 'categoryId'),
        (_) => fail('should have refused'),
      );
    });

    test('refuses a plan that does not exist', () async {
      final result = await update(
        const UpdateAllocationRequest(
          planId: 8,
          categoryId: 1,
          allocatedCents: 100,
        ),
      );

      expect(result.isLeft(), isTrue);
    });

    test('refuses the only allocation in a plan', () async {
      repository.plan = MoneyPlan(
        id: 7,
        name: 'One',
        period: PlanPeriod.month(2026, 9),
        totalBudgetCents: 500,
        allocations: [_row(1, 500)],
      );

      final result = await update(
        const UpdateAllocationRequest(
          planId: 7,
          categoryId: 1,
          allocatedCents: 100,
        ),
      );

      expect(result.isLeft(), isTrue);
    });

    test('a failure reading or writing passes through', () async {
      repository.readFails = const CacheFailure('disk is full');
      final read = await update(
        const UpdateAllocationRequest(
          planId: 7,
          categoryId: 1,
          allocatedCents: 100,
        ),
      );
      expect(
        read,
        const Left<Failure, MoneyPlan>(CacheFailure('disk is full')),
      );

      repository
        ..readFails = null
        ..writeFails = const CacheFailure('locked');
      final write = await update(
        const UpdateAllocationRequest(
          planId: 7,
          categoryId: 1,
          allocatedCents: 100,
        ),
      );
      expect(write, const Left<Failure, MoneyPlan>(CacheFailure('locked')));
    });
  });
}
