import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/money_plan/data/datasources/money_plan_local_datasource.dart';
import 'package:moneyora/features/money_plan/data/models/money_plan_model.dart';
import 'package:moneyora/features/money_plan/data/models/plan_allocation_model.dart';
import 'package:moneyora/features/money_plan/data/repositories/money_plan_repository_impl.dart';
import 'package:moneyora/features/money_plan/domain/entities/confidence_score.dart';
import 'package:moneyora/features/money_plan/domain/entities/money_plan.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_allocation.dart';
import 'package:moneyora/features/money_plan/domain/entities/plan_period.dart';

/// Returns canned rows, or throws whatever it is handed, and lets a test
/// fire the change signal by hand.
class _FakeDataSource implements MoneyPlanLocalDataSource {
  _FakeDataSource({this.throws});

  final AppException? throws;
  final StreamController<void> _changes = StreamController<void>.broadcast();
  MoneyPlanModel? active;
  MoneyPlanModel? inserted;
  int? activated;
  List<PlanAllocationModel>? updated;
  int? recomputed;
  MoneyPlanModel? previous;
  String? askedBefore;
  int reads = 0;

  void tick() => _changes.add(null);

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<void> dispose() => _changes.close();

  @override
  Future<int> insert(MoneyPlanModel plan) async {
    if (throws case final e?) throw e;
    inserted = plan;
    return 5;
  }

  @override
  Future<void> activate(int id) async {
    if (throws case final e?) throw e;
    activated = id;
  }

  @override
  Future<MoneyPlanModel?> getById(int id) async {
    if (throws case final e?) throw e;
    return active?.id == id ? active : null;
  }

  @override
  Future<MoneyPlanModel?> getLatestEndingBefore(String isoDay) async {
    if (throws case final e?) throw e;
    askedBefore = isoDay;
    return previous;
  }

  @override
  Future<List<MoneyPlanModel>> listAll() async {
    reads += 1;
    if (throws case final e?) throw e;
    return [?active];
  }

  @override
  Future<MoneyPlanModel?> getActive() async {
    reads += 1;
    if (throws case final e?) throw e;
    return active;
  }

  @override
  Future<void> updateAllocations(
    int planId,
    List<PlanAllocationModel> allocations,
  ) async {
    if (throws case final e?) throw e;
    updated = allocations;
  }

  @override
  Future<void> recomputeSpent(int planId) async {
    if (throws case final e?) throw e;
    recomputed = planId;
  }
}

final _plan = MoneyPlan(
  id: 5,
  name: 'September',
  period: PlanPeriod.month(2026, 9),
  totalBudgetCents: 100,
  isActive: true,
  allocations: const [
    PlanAllocation(
      id: 1,
      categoryId: 1,
      categoryName: 'Bills',
      allocatedCents: 100,
      confidence: ConfidenceLevel.high,
    ),
  ],
);

void main() {
  test('save hands the datasource a model and returns the id', () async {
    final source = _FakeDataSource();
    final repository = MoneyPlanRepositoryImpl(source);

    final result = await repository.save(_plan);

    expect(result, const Right<Failure, int>(5));
    expect(source.inserted!.name, 'September');
    expect(source.inserted!.allocationModels.single.categoryId, 1);
  });

  test('getById converts the model back to an entity', () async {
    final source = _FakeDataSource()..active = MoneyPlanModel.fromEntity(_plan);
    final repository = MoneyPlanRepositoryImpl(source);

    final result = await repository.getById(5);

    expect(result, Right<Failure, MoneyPlan?>(_plan));
    expect(await repository.getById(6), const Right<Failure, MoneyPlan?>(null));
  });

  test('getLatestEndingBefore encodes the day and converts back', () async {
    final source = _FakeDataSource()
      ..previous = MoneyPlanModel.fromEntity(_plan);
    final repository = MoneyPlanRepositoryImpl(source);

    final result = await repository.getLatestEndingBefore(DateTime(2026, 10));

    expect(source.askedBefore, '2026-10-01');
    expect(result, Right<Failure, MoneyPlan?>(_plan));
  });

  test('activate and updateAllocations pass through', () async {
    final source = _FakeDataSource();
    final repository = MoneyPlanRepositoryImpl(source);

    expect(await repository.activate(5), const Right<Failure, Unit>(unit));
    expect(source.activated, 5);

    expect(
      await repository.updateAllocations(5, _plan.allocations),
      const Right<Failure, Unit>(unit),
    );
    expect(source.updated!.single.allocatedCents, 100);
  });

  test('recomputeSpent passes the plan id through', () async {
    final source = _FakeDataSource();
    final repository = MoneyPlanRepositoryImpl(source);

    expect(
      await repository.recomputeSpent(5),
      const Right<Failure, Unit>(unit),
    );
    expect(source.recomputed, 5);
  });

  test('turns a cache exception into a failure at this boundary', () async {
    final repository = MoneyPlanRepositoryImpl(
      _FakeDataSource(throws: const CacheException('disk is full')),
    );

    expect(
      await repository.save(_plan),
      const Left<Failure, int>(CacheFailure('disk is full')),
    );
    expect(
      await repository.activate(5),
      const Left<Failure, Unit>(CacheFailure('disk is full')),
    );
    expect(
      await repository.getById(5),
      const Left<Failure, MoneyPlan?>(CacheFailure('disk is full')),
    );
    expect(
      await repository.recomputeSpent(5),
      const Left<Failure, Unit>(CacheFailure('disk is full')),
    );
  });

  group('watchAll', () {
    test('emits every plan on listen and again on every change', () async {
      final source = _FakeDataSource()
        ..active = MoneyPlanModel.fromEntity(_plan);
      final repository = MoneyPlanRepositoryImpl(source);
      final seen = <Either<Failure, List<MoneyPlan>>>[];

      final sub = repository.watchAll().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      source.active = null;
      source.tick();
      await Future<void>.delayed(Duration.zero);

      // Unwrapped: a List inside an Either compares by identity.
      expect(seen.map((e) => e.getOrElse((_) => fail('left'))), [
        [_plan],
        <MoneyPlan>[],
      ]);
      await sub.cancel();
      await source.dispose();
    });

    test('a failed read is a Left on the stream', () async {
      final repository = MoneyPlanRepositoryImpl(
        _FakeDataSource(throws: const CacheException('disk is full')),
      );

      final first = await repository.watchAll().first;

      expect(
        first,
        const Left<Failure, List<MoneyPlan>>(CacheFailure('disk is full')),
      );
    });
  });

  group('watchActive', () {
    test('emits the active plan on listen and again on every change', () async {
      final source = _FakeDataSource()
        ..active = MoneyPlanModel.fromEntity(_plan);
      final repository = MoneyPlanRepositoryImpl(source);
      final seen = <Either<Failure, MoneyPlan?>>[];

      final sub = repository.watchActive().listen(seen.add);
      await Future<void>.delayed(Duration.zero);
      source.active = null;
      source.tick();
      await Future<void>.delayed(Duration.zero);

      expect(seen, [
        Right<Failure, MoneyPlan?>(_plan),
        const Right<Failure, MoneyPlan?>(null),
      ]);
      await sub.cancel();
      await source.dispose();
    });

    test(
      'a failed read is a Left on the stream, not a broken stream',
      () async {
        final source = _FakeDataSource(throws: const CacheException('locked'));
        final repository = MoneyPlanRepositoryImpl(source);

        final first = await repository.watchActive().first;

        expect(first, const Left<Failure, MoneyPlan?>(CacheFailure('locked')));
        await source.dispose();
      },
    );

    test('stops reading once cancelled', () async {
      final source = _FakeDataSource();
      final repository = MoneyPlanRepositoryImpl(source);

      final sub = repository.watchActive().listen((_) {});
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      final before = source.reads;
      source.tick();
      await Future<void>.delayed(Duration.zero);

      expect(source.reads, before);
      await source.dispose();
    });
  });
}
