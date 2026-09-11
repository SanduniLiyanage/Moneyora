/// The categories layer boundary. Exceptions become failures here and
/// nowhere else, exactly as `AccountRepositoryImpl` does it.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../datasources/category_local_datasource.dart';
import '../models/category_model.dart';

/// Fulfils [CategoryRepository] against the local encrypted database.
class CategoryRepositoryImpl implements CategoryRepository {
  /// Creates a repository over [local].
  const CategoryRepositoryImpl(this._local);

  final CategoryLocalDataSource _local;

  @override
  Future<Either<Failure, int>> add(Category category) =>
      _attempt(() => _local.add(CategoryModel.fromEntity(category)));

  @override
  Future<Either<Failure, Unit>> update(Category category) => _attempt(() async {
    await _local.update(CategoryModel.fromEntity(category));
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> delete(int id) => _attempt(() async {
    await _local.delete(id);
    return unit;
  });

  @override
  Future<Either<Failure, Category?>> find(int id) =>
      _attempt(() async => (await _local.find(id))?.toEntity());

  @override
  Future<Either<Failure, int>> usageCount(int id) =>
      _attempt(() => _local.usageCount(id));

  @override
  Future<Either<Failure, int>> childCount(int id) =>
      _attempt(() => _local.childCount(id));

  @override
  Future<Either<Failure, List<Category>>> list({CategoryType? type}) =>
      _attempt(() async {
        final models = await _local.list(type: type);
        // Converted, not cast: Equatable compares runtimeType, so a model
        // handed upward never equals an identical entity.
        return models.map((model) => model.toEntity()).toList();
      });

  @override
  Stream<Either<Failure, List<Category>>> watch({CategoryType? type}) {
    // Built on an explicit controller, not an async generator - the same
    // reason `AccountRepositoryImpl.watch` is: a subscription suspended in
    // `await for` over a broadcast stream cannot be cancelled, so a screen
    // that navigates away would keep listening for the life of the process.
    late final StreamController<Either<Failure, List<Category>>> controller;
    StreamSubscription<void>? signal;
    var pending = Future<void>.value();

    Future<void> read() async {
      final result = await list(type: type);
      if (!controller.isClosed) controller.add(result);
    }

    void schedule() => pending = pending.then((_) => read());

    controller = StreamController<Either<Failure, List<Category>>>(
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
