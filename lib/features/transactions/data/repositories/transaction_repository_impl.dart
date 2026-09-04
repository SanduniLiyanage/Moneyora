/// The layer boundary, and the only place exceptions become failures.
///
/// Below this file, `data/` throws. Above it, everything returns
/// `Either<Failure, T>` and no `try`/`catch` appears anywhere
/// (`docs/ARCHITECTURE.md` §3). This file is where those two worlds meet, and
/// it is deliberately thin: it translates, it converts models to entities, and
/// it composes the watch stream. It makes no decisions of its own — a
/// repository that starts validating is a use case that ended up in `data/`.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/transaction_repository.dart';
import '../datasources/transaction_local_datasource.dart';
import '../models/transaction_model.dart';

/// Fulfils [TransactionRepository] against the local encrypted database.
class TransactionRepositoryImpl implements TransactionRepository {
  /// Creates a repository over [local].
  const TransactionRepositoryImpl(this._local);

  final TransactionLocalDataSource _local;

  @override
  Future<Either<Failure, int>> add(Transaction transaction) =>
      _attempt(() => _local.add(TransactionModel.fromEntity(transaction)));

  @override
  Future<Either<Failure, Unit>> update(Transaction transaction) =>
      _attempt(() async {
        await _local.update(TransactionModel.fromEntity(transaction));
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> delete(int id) => _attempt(() async {
    await _local.delete(id);
    return unit;
  });

  @override
  Future<Either<Failure, List<Transaction>>> list(TransactionFilter filter) =>
      _attempt(() async {
        final models = await _local.list(filter);
        // Converted, not cast. `Equatable` compares `runtimeType`, so a
        // `TransactionModel` never equals an otherwise identical
        // `Transaction` — handing models upward would produce comparisons
        // that fail between objects which print the same.
        return models.map((model) => model.toEntity()).toList();
      });

  @override
  Future<Either<Failure, int>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String? note,
  }) => _attempt(
    () => _local.createTransfer(
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amountCents: amountCents,
      date: date,
      note: note,
    ),
  );

  @override
  Stream<Either<Failure, List<Transaction>>> watch(TransactionFilter filter) {
    // SQLite has no change notification, so this is a re-query on a signal
    // rather than a true change feed: the datasource says *that* something was
    // written, and each watcher asks again for whatever its own filter
    // matches. Cheap because every query here is index-served, and it cannot
    // drift the way an incrementally-patched list can.
    //
    // Written with an explicit controller rather than the obvious
    // `async* { yield ...; await for (_ in changes) yield ...; }`. That
    // version works until something stops watching: cancelling a subscription
    // to an async generator suspended in `await for` over a **broadcast**
    // stream never completes, because the generator cannot be resumed to run
    // its own cleanup. In a widget that is a screen which navigates away and
    // silently keeps its subscription for the life of the process. Here the
    // inner subscription is held directly, so `onCancel` can cancel it.
    late final StreamController<Either<Failure, List<Transaction>>> controller;
    StreamSubscription<void>? signal;

    // Reads are chained rather than fired in parallel. Two writes landing
    // together would otherwise start two queries whose results can arrive in
    // either order, and a watcher that renders the older one shows data that
    // was already stale when it arrived.
    var pending = Future<void>.value();

    Future<void> read() async {
      final result = await list(filter);
      if (!controller.isClosed) controller.add(result);
    }

    void schedule() => pending = pending.then((_) => read());

    controller = StreamController<Either<Failure, List<Transaction>>>(
      onListen: () {
        signal = _local.changes.listen((_) => schedule());
        // Emit once up front so a screen renders from its first frame instead
        // of sitting empty until something happens to change.
        schedule();
      },
      onCancel: () async {
        // Cancel the signal before closing, or a change arriving in between
        // schedules a read against a controller that is on its way out.
        await signal?.cancel();
        signal = null;
        await controller.close();
      },
    );

    return controller.stream;
  }

  /// Runs [body], converting any data-layer exception into a [Failure].
  Future<Either<Failure, T>> _attempt<T>(Future<T> Function() body) async {
    try {
      return Right(await body());
    } on AppException catch (e) {
      return Left(_toFailure(e));
    }
  }

  /// Maps a data-layer exception onto the domain's vocabulary.
  ///
  /// Exhaustive because [AppException] is sealed: adding a new exception type
  /// breaks this switch at compile time rather than falling through to a
  /// generic failure at runtime, which is the whole reason the base class is
  /// sealed.
  static Failure _toFailure(AppException e) => switch (e) {
    CacheException() => CacheFailure(e.message),
    EncryptionException() => EncryptionFailure(e.message),
    ServerException() => ServerFailure(e.message),
    NetworkException() => const NetworkFailure(),
    OcrException() => OcrFailure(e.message),
    PermissionException() => PermissionFailure(e.message),
  };
}
