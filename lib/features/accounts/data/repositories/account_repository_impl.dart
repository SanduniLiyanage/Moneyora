/// The accounts layer boundary. Exceptions become failures here and nowhere
/// else, exactly as `TransactionRepositoryImpl` does it.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/ports/account_reader.dart';
import '../../domain/entities/account.dart';
import '../../domain/repositories/account_repository.dart';
import '../datasources/account_local_datasource.dart';
import '../models/account_model.dart';

/// Fulfils [AccountRepository] against the local encrypted database.
///
/// Also fulfils [AccountReader], the narrow contract in `core/` that lets
/// `features/transactions/` read the account list without importing this
/// feature (E-27) — the same shape `AnalyticsRepositoryImpl` uses for
/// [AccountRepository]/`SpendingByCategoryReader`.
class AccountRepositoryImpl implements AccountRepository, AccountReader {
  /// Creates a repository over [local].
  const AccountRepositoryImpl(this._local);

  final AccountLocalDataSource _local;

  @override
  Future<Either<Failure, int>> add(Account account) =>
      _attempt(() => _local.add(AccountModel.fromEntity(account)));

  @override
  Future<Either<Failure, Unit>> update(Account account) => _attempt(() async {
    await _local.update(AccountModel.fromEntity(account));
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> setArchived(int id, {required bool archived}) =>
      _attempt(() async {
        await _local.setArchived(id, archived: archived);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> delete(int id) => _attempt(() async {
    await _local.delete(id);
    return unit;
  });

  @override
  Future<Either<Failure, int>> transactionCount(int id) =>
      _attempt(() => _local.transactionCount(id));

  @override
  Future<Either<Failure, List<Account>>> list({
    bool includeArchived = false,
  }) => _attempt(() async {
    final models = await _local.list(includeArchived: includeArchived);
    // Converted, not cast: Equatable compares runtimeType, so a model handed
    // upward never equals an identical entity.
    return models.map((model) => model.toEntity()).toList();
  });

  @override
  Future<Either<Failure, int>> recomputeBalance(int id) =>
      _attempt(() => _local.recomputeBalance(id));

  @override
  Future<Either<Failure, Unit>> recomputeAllBalances() => _attempt(() async {
    await _local.recomputeAllBalances();
    return unit;
  });

  @override
  Stream<Either<Failure, List<Account>>> watch({bool includeArchived = false}) {
    // Built on an explicit controller rather than an async generator, for the
    // reason `TransactionRepositoryImpl.watch` records: a subscription to an
    // async* suspended in `await for` over a broadcast stream cannot be
    // cancelled, so a screen that navigates away keeps listening for the life
    // of the process.
    late final StreamController<Either<Failure, List<Account>>> controller;
    StreamSubscription<void>? signal;
    var pending = Future<void>.value();

    Future<void> read() async {
      final result = await list(includeArchived: includeArchived);
      if (!controller.isClosed) controller.add(result);
    }

    void schedule() => pending = pending.then((_) => read());

    controller = StreamController<Either<Failure, List<Account>>>(
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

  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() => watch().map(
    (either) => either.map(
      (accounts) => [
        for (final account in accounts)
          AccountOption(
            id: account.id!,
            name: account.name,
            balanceCents: account.currentBalanceCents,
            icon: account.icon,
            currency: account.currency,
          ),
      ],
    ),
  );

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
