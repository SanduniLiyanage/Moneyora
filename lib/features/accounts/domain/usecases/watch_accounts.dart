import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/account.dart';
import '../repositories/account_repository.dart';

/// Watches the account list, and the balances on it. FR-ACC-003.
///
/// A stream because a balance is the most derived thing on screen: it moves
/// whenever any transaction anywhere is written, and a screen that read it
/// once would be wrong by the time the user looked back at it.
class WatchAccounts implements StreamUseCase<List<Account>, bool> {
  /// Creates the use case.
  const WatchAccounts(this._repository);

  final AccountRepository _repository;

  /// [params] is whether to include archived accounts.
  @override
  Stream<Either<Failure, List<Account>>> call(bool params) =>
      _repository.watch(includeArchived: params);
}
