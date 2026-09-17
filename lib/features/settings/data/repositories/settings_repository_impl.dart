/// The settings layer boundary. Exceptions become failures here and nowhere
/// else, exactly as `AccountRepositoryImpl` does it.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/user_settings.dart';
import '../../domain/repositories/settings_repository.dart';
import '../datasources/settings_local_datasource.dart';
import '../models/user_settings_model.dart';

/// Fulfils [SettingsRepository] against the local encrypted database.
class SettingsRepositoryImpl implements SettingsRepository {
  /// Creates a repository over [local].
  const SettingsRepositoryImpl(this._local);

  final SettingsLocalDataSource _local;

  @override
  Future<Either<Failure, UserSettings>> get() => _attempt(() async {
    final model = await _local.read();
    // Converted, not cast: Equatable compares runtimeType, so a model handed
    // upward never equals an identical entity.
    return model.toEntity();
  });

  @override
  Future<Either<Failure, Unit>> save(UserSettings settings) =>
      _attempt(() async {
        await _local.write(UserSettingsModel.fromEntity(settings));
        return unit;
      });

  @override
  Stream<Either<Failure, UserSettings>> watch() {
    // An explicit controller rather than an async generator, for the reason
    // `AccountRepositoryImpl.watch` records: a subscription to an async*
    // suspended in `await for` over a broadcast stream cannot be cancelled.
    late final StreamController<Either<Failure, UserSettings>> controller;
    StreamSubscription<void>? signal;
    var pending = Future<void>.value();

    Future<void> read() async {
      final result = await get();
      if (!controller.isClosed) controller.add(result);
    }

    void schedule() => pending = pending.then((_) => read());

    controller = StreamController<Either<Failure, UserSettings>>(
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
