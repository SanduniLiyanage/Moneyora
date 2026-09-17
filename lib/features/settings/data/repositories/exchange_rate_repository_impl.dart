/// The exchange-rates layer boundary. Exceptions become failures here and
/// nowhere else, exactly as `SettingsRepositoryImpl` does it.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/exchange_rate.dart';
import '../../domain/repositories/exchange_rate_repository.dart';
import '../datasources/exchange_rate_local_datasource.dart';
import '../models/exchange_rate_model.dart';

/// Fulfils [ExchangeRateRepository] against the local encrypted database.
class ExchangeRateRepositoryImpl implements ExchangeRateRepository {
  /// Creates a repository over [local].
  const ExchangeRateRepositoryImpl(this._local);

  final ExchangeRateLocalDataSource _local;

  Future<Either<Failure, List<ExchangeRate>>> _list() => _attempt(() async {
    final models = await _local.list();
    // Converted, not cast: Equatable compares runtimeType, so a model handed
    // upward never equals an identical entity.
    return models.map((model) => model.toEntity()).toList();
  });

  @override
  Future<Either<Failure, Unit>> set(ExchangeRate rate) => _attempt(() async {
    await _local.upsert(ExchangeRateModel.fromEntity(rate));
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> remove({
    required String fromCurrency,
    required String toCurrency,
  }) => _attempt(() async {
    await _local.remove(fromCurrency: fromCurrency, toCurrency: toCurrency);
    return unit;
  });

  @override
  Stream<Either<Failure, List<ExchangeRate>>> watch() {
    // An explicit controller rather than an async generator, for the reason
    // `AccountRepositoryImpl.watch` records: a subscription to an async*
    // suspended in `await for` over a broadcast stream cannot be cancelled.
    late final StreamController<Either<Failure, List<ExchangeRate>>> controller;
    StreamSubscription<void>? signal;
    var pending = Future<void>.value();

    Future<void> read() async {
      final result = await _list();
      if (!controller.isClosed) controller.add(result);
    }

    void schedule() => pending = pending.then((_) => read());

    controller = StreamController<Either<Failure, List<ExchangeRate>>>(
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
