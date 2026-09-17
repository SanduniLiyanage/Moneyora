import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/account_repository.dart';

/// Re-derives every cached account balance from history. E-18.
///
/// This is the repair for drift that arrives from outside the app's own
/// write paths - a restored backup, a crash mid-write, a database edited by
/// hand. The cache cannot drift through those paths themselves, because each
/// one moves `current_balance_cents` inside the transaction that writes the
/// row; so this runs only when repair is asked for, never on launch, where a
/// full-history scan per account would sit on NFR-PER-001's cold-start path.
///
/// It delegates to the repository's sweep rather than looping over
/// [RecomputeAccountBalance] itself: the sweep re-derives every account in a
/// single database transaction and announces the change once, where a loop
/// would open one transaction and fire one notification per account.
///
/// Reached from the Settings action (Sprint 7). The restore path (Sprint 8)
/// is its other caller.
class RecomputeAllAccountBalances implements UseCase<Unit, NoParams> {
  /// Creates the use case.
  const RecomputeAllAccountBalances(this._repository);

  final AccountRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(NoParams params) =>
      _repository.recomputeAllBalances();
}
