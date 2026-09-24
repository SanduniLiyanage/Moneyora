/// The money_plan layer boundary. Exceptions become failures here and
/// nowhere else, exactly as `AccountRepositoryImpl` does it.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/budget_alert_evaluation.dart';
import '../../domain/entities/money_plan.dart';
import '../../domain/entities/plan_allocation.dart';
import '../../domain/repositories/money_plan_repository.dart';
import '../datasources/money_plan_local_datasource.dart';
import '../models/money_plan_model.dart';
import '../models/plan_allocation_model.dart';

/// Fulfils [MoneyPlanRepository] against the local encrypted database.
class MoneyPlanRepositoryImpl implements MoneyPlanRepository {
  /// Creates a repository over [local].
  const MoneyPlanRepositoryImpl(this._local);

  final MoneyPlanLocalDataSource _local;

  @override
  Future<Either<Failure, int>> save(MoneyPlan plan) =>
      _attempt(() => _local.insert(MoneyPlanModel.fromEntity(plan)));

  @override
  Future<Either<Failure, Unit>> activate(int id) => _attempt(() async {
    await _local.activate(id);
    return unit;
  });

  @override
  Future<Either<Failure, MoneyPlan?>> getById(int id) =>
      _attempt(() async => (await _local.getById(id))?.toEntity());

  @override
  Future<Either<Failure, MoneyPlan?>> getLatestEndingBefore(DateTime day) =>
      _attempt(
        () async =>
            (await _local.getLatestEndingBefore(encodeIsoDay(day)))?.toEntity(),
      );

  @override
  Future<Either<Failure, Unit>> updateAllocations(
    int planId,
    List<PlanAllocation> allocations,
  ) => _attempt(() async {
    await _local.updateAllocations(planId, [
      for (final a in allocations) PlanAllocationModel.fromEntity(a),
    ]);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> recomputeSpent(int planId) =>
      _attempt(() async {
        await _local.recomputeSpent(planId);
        return unit;
      });

  @override
  Future<Either<Failure, Set<int>>> recordAlertLevels(
    List<AlertLevelChange> changes,
  ) => changes.isEmpty
      // Nothing to move: no transaction opened for it.
      ? Future.value(const Right(<int>{}))
      : _attempt(() => _local.recordAlertLevels(changes));

  @override
  Stream<Either<Failure, MoneyPlan?>> watchActive() =>
      _watch(() async => (await _local.getActive())?.toEntity());

  @override
  Stream<Either<Failure, List<MoneyPlan>>> watchAll() => _watch(
    () async => [for (final p in await _local.listAll()) p.toEntity()],
  );

  /// [read] on listen and again after every change signal.
  ///
  /// The controller shape `AccountRepositoryImpl.watch` uses, for the
  /// reason it records: an async generator suspended over a broadcast
  /// stream cannot be cancelled, so a screen that leaves keeps listening.
  Stream<Either<Failure, T>> _watch<T>(Future<T> Function() read) {
    late final StreamController<Either<Failure, T>> controller;
    StreamSubscription<void>? signal;
    var pending = Future<void>.value();

    Future<void> emit() async {
      final result = await _attempt(read);
      if (!controller.isClosed) controller.add(result);
    }

    void schedule() => pending = pending.then((_) => emit());

    controller = StreamController<Either<Failure, T>>(
      onListen: () {
        signal = _local.changes.listen((_) => schedule());
        schedule();
      },
      onCancel: () async {
        await signal?.cancel();
        signal = null;
        await controller.close();
      },
    );

    return controller.stream;
  }

  Future<Either<Failure, T>> _attempt<T>(Future<T> Function() body) async {
    try {
      return Right(await body());
    } on AppException catch (e) {
      return Left(_toFailure(e));
    }
  }

  static Failure _toFailure(AppException e) => switch (e) {
    CacheException() => CacheFailure(e.message),
    EncryptionException() => EncryptionFailure(e.message),
    ServerException() => ServerFailure(e.message),
    NetworkException() => const NetworkFailure(),
    OcrException() => OcrFailure(e.message),
    PermissionException() => PermissionFailure(e.message),
  };
}
