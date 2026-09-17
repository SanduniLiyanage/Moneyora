import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/account_repository.dart';

/// Re-derives a cached account balance from history. E-18.
///
/// `accounts.current_balance_cents` is a cache. It is maintained inside the
/// same database transaction as every row that moves it, which is what makes
/// it trustworthy - but "maintained correctly by every write path that will
/// ever exist" is a claim, and this is the thing that checks it.
///
/// The DBD specified the stored column and no reconciliation at all, which is
/// the defect E-18 records: any path that forgets the update desynchronises
/// the balance from the transactions that produced it, with nothing in the
/// schema able to notice.
///
/// The same arithmetic already serves as the oracle in the transactions
/// datasource's property test: after a random sequence of writes, cached must
/// equal recomputed.
///
/// This is the single-account form. The sweep every account needs after a
/// restore, or from the Settings action, is [RecomputeAllAccountBalances] -
/// one use case per operation, rather than a nullable parameter meaning two
/// different things.
class RecomputeAccountBalance implements UseCase<int, int> {
  /// Creates the use case.
  const RecomputeAccountBalance(this._repository);

  final AccountRepository _repository;

  /// Recomputes the account [params] and returns its new balance.
  @override
  Future<Either<Failure, int>> call(int params) =>
      _repository.recomputeBalance(params);
}
