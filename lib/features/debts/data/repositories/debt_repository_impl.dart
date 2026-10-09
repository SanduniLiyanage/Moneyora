/// The debts layer boundary. Exceptions become failures here and nowhere
/// else, exactly as `ExchangeRateRepositoryImpl` does it.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/debt.dart';
import '../../domain/repositories/debt_repository.dart';
import '../datasources/debt_local_datasource.dart';
import '../models/debt_model.dart';

/// Fulfils [DebtRepository] against the local encrypted database.
class DebtRepositoryImpl implements DebtRepository {
  /// Creates a repository over [local].
  const DebtRepositoryImpl(this._local);

  final DebtLocalDataSource _local;

  Future<Either<Failure, List<Debt>>> _list() => _attempt(() async {
    final models = await _local.list();
    // Converted, not cast: Equatable compares runtimeType, so a model handed
    // upward never equals an identical entity.
    return models.map((model) => model.toEntity()).toList();
  });

  @override
  Future<Either<Failure, int>> add(Debt debt) =>
      _attempt(() => _local.add(DebtModel.fromEntity(debt)));

  @override
  Future<Either<Failure, List<int>>> addAll(List<Debt> debts) => _attempt(
    () => _local.addAll([for (final debt in debts) DebtModel.fromEntity(debt)]),
  );

  @override
  Future<Either<Failure, Unit>> update(Debt debt) => _attempt(() async {
    await _local.update(DebtModel.fromEntity(debt));
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> delete(int id) => _attempt(() async {
    await _local.delete(id);
    return unit;
  });

  @override
  Stream<Either<Failure, List<Debt>>> watch() {
    // An explicit controller rather than an async generator, for the reason
    // `AccountRepositoryImpl.watch` records: a subscription to an async*
    // suspended in `await for` over a broadcast stream cannot be cancelled.
    late final StreamController<Either<Failure, List<Debt>>> controller;
    StreamSubscription<void>? signal;
    var pending = Future<void>.value();

    Future<void> read() async {
      final result = await _list();
      if (!controller.isClosed) controller.add(result);
    }

    void schedule() => pending = pending.then((_) => read());

    controller = StreamController<Either<Failure, List<Debt>>>(
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
    _ => CacheFailure(e.message),
  };
}
