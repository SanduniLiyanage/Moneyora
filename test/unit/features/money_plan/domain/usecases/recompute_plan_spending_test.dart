import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/recompute_plan_spending.dart';

/// Records the plan id it was asked to recount, or fails on request.
class _FakeRepository implements MoneyPlanRepository {
  int? recomputed;
  Failure? failWith;

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) async {
    recomputed = planId;
    if (failWith case final f?) return Left(f);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> activate(int id) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) =>
      throw UnimplementedError();

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

void main() {
  test('recounts the plan it is given', () async {
    final repository = _FakeRepository();

    final result = await RecomputePlanSpending(repository)(7);

    expect(result, const Right<Failure, Unit>(unit));
    expect(repository.recomputed, 7);
  });

  test('surfaces a failure rather than throwing', () async {
    final repository = _FakeRepository()
      ..failWith = const CacheFailure('database is locked');

    final result = await RecomputePlanSpending(repository)(7);

    expect(
      result,
      const Left<Failure, Unit>(CacheFailure('database is locked')),
    );
  });
}
