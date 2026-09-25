/// The layer boundary for recurring rules: exceptions become failures and
/// models become entities here, and nothing else happens. See
/// `transaction_repository_impl.dart` for why it stays that thin.
library;

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
  Future<Either<Failure, List<DueRecurringRule>>> due(DateTime today) =>
      _attempt(() async {
        final rows = await _local.due(today);
        return [
          for (final row in rows)
            DueRecurringRule(
              rule: row.rule.toEntity(),
              template: row.template?.toEntity(),
            ),
        ];
      });

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
