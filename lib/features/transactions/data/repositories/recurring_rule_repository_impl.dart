/// The layer boundary for recurring rules: exceptions become failures and
/// models become entities here, and nothing else happens. See
/// `transaction_repository_impl.dart` for why it stays that thin.
library;

import 'dart:async';

import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/exceptions.dart';
import '../../../../core/errors/failures.dart';
import '../../domain/entities/recurring_rule.dart';
import '../../domain/entities/transaction.dart';
import '../../domain/repositories/recurring_rule_repository.dart';
import '../datasources/recurring_rule_local_datasource.dart';
import '../models/recurring_rule_model.dart';
import '../models/transaction_model.dart';

/// Fulfils [RecurringRuleRepository] against the local encrypted database.
class RecurringRuleRepositoryImpl implements RecurringRuleRepository {
  /// Creates a repository over [local].
  const RecurringRuleRepositoryImpl(this._local);

  final RecurringRuleLocalDataSource _local;

  @override
  Future<Either<Failure, int>> create({
    required Transaction first,
    required RecurringRule rule,
  }) => _attempt(
    () => _local.create(
      first: TransactionModel.fromEntity(first),
      rule: RecurringRuleModel.fromEntity(rule),
    ),
  );

  @override
  Future<Either<Failure, List<RecurringSeries>>> due(DateTime today) =>
      _attempt(() async => _toSeries(await _local.due(today)));

  @override
  Stream<Either<Failure, List<RecurringSeries>>> watchAll() {
    // The shape `TransactionRepositoryImpl.watch` uses, for its reasons: an
    // explicit controller so cancelling actually cancels, and reads chained
    // so an older one can never land after a newer one.
    late final StreamController<Either<Failure, List<RecurringSeries>>>
    controller;
    StreamSubscription<void>? signal;
    var pending = Future<void>.value();

    Future<void> read() async {
      final result = await _attempt(() async => _toSeries(await _local.all()));
      if (!controller.isClosed) controller.add(result);
    }

    void schedule() => pending = pending.then((_) => read());

    controller = StreamController<Either<Failure, List<RecurringSeries>>>(
      onListen: () {
        // The shared bus, so a transaction write — a template edited, a
        // template handed on (E-36) — re-reads the list as a rule write does.
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
  Future<Either<Failure, Unit>> pause(int ruleId) => _attempt(() async {
    await _local.pause(ruleId);
    return unit;
  });

  @override
  Future<Either<Failure, Unit>> resume(int ruleId, DateTime nextDueDate) =>
      _attempt(() async {
        await _local.resume(ruleId, nextDueDate);
        return unit;
      });

  @override
  Future<Either<Failure, Unit>> delete(int ruleId) => _attempt(() async {
    await _local.delete(ruleId);
    return unit;
  });

  static List<RecurringSeries> _toSeries(List<RecurringSeriesRow> rows) => [
    for (final row in rows)
      RecurringSeries(
        rule: row.rule.toEntity(),
        template: row.template?.toEntity(),
      ),
  ];

  @override
  Future<Either<Failure, List<int>>> post({
    required int ruleId,
    required DateTime expectedNextDueDate,
    required List<Transaction> entries,
    required DateTime nextDueDate,
    required bool ended,
    required DateTime postedAt,
  }) => _attempt(
    () => _local.post(
      ruleId: ruleId,
      expectedNextDueDate: expectedNextDueDate,
      entries: [for (final e in entries) TransactionModel.fromEntity(e)],
      nextDueDate: nextDueDate,
      ended: ended,
      postedAt: postedAt,
    ),
  );

  /// Runs [body], converting any data-layer exception into a [Failure].
  Future<Either<Failure, T>> _attempt<T>(Future<T> Function() body) async {
    try {
      return Right(await body());
    } on AppException catch (e) {
      return Left(_toFailure(e));
    }
  }

  /// Exhaustive over the sealed [AppException], as the transaction
  /// repository's is.
  static Failure _toFailure(AppException e) => switch (e) {
    CacheException() => CacheFailure(e.message),
    EncryptionException() => EncryptionFailure(e.message),
    ServerException() => ServerFailure(e.message),
    NetworkException() => const NetworkFailure(),
    OcrException() => OcrFailure(e.message),
    PermissionException() => PermissionFailure(e.message),
  };
}
