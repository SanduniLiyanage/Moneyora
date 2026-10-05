import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/money_plan/domain/entities/budget_alert_evaluation.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/repositories/money_plan_repository.dart';
import 'package:moneyora/features/money_plan/domain/usecases/delete_plan.dart';
import 'package:moneyora/features/money_plan/domain/usecases/rename_plan.dart';

/// Records the delete and rename it was asked for.
class _FakeRepository implements MoneyPlanRepository {
  Failure? fails;
  int? deleted;
  (int, String)? renamed;

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    if (fails case final f?) return Left(f);
    deleted = id;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> rename(int id, String name) async {
    if (fails case final f?) return Left(f);
    renamed = (id, name);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations, {
    int? totalBudgetCents,
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) =>
      throw UnimplementedError();

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

/// FR-PLN-015's housekeeping: a plan can be renamed and deleted.
void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  group('DeletePlan', () {
    test('deletes the plan it is given', () async {
      final result = await DeletePlan(repository)(7);

      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.deleted, 7);
    });

    test('a failure passes through', () async {
      repository.fails = const CacheFailure('locked');

      expect(
        await DeletePlan(repository)(7),
        const Left<Failure, Unit>(CacheFailure('locked')),
      );
    });
  });

  group('RenamePlan', () {
    test('writes the name, trimmed', () async {
      final result = await RenamePlan(repository)(
        const RenamePlanRequest(planId: 7, name: '  October  '),
      );

      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.renamed, (7, 'October'));
    });

    test('refuses a blank name, as saving does, and writes nothing', () async {
      final result = await RenamePlan(repository)(
        const RenamePlanRequest(planId: 7, name: '   '),
      );

      result.fold((f) {
        expect(f, isA<ValidationFailure>());
        expect(f.message, 'Give the plan a name.');
        expect((f as ValidationFailure).field, 'name');
      }, (_) => fail('should have refused'));
      expect(repository.renamed, isNull);
    });

    test('a failure passes through', () async {
      repository.fails = const CacheFailure('locked');

      expect(
        await RenamePlan(repository)(
          const RenamePlanRequest(planId: 7, name: 'October'),
        ),
        const Left<Failure, Unit>(CacheFailure('locked')),
      );
    });
  });
}
