import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/lockout_state.dart';
import '../repositories/auth_repository.dart';

/// Where the gate stands before any attempt is made. NFR-SEC-003.
///
/// The lock screen reads this when it opens, so a lockout that was running
/// when the app was closed is still shown counting down when it is opened
/// again — the state survives the process because it is stored, not held.
class GetLockoutState implements UseCase<LockoutState, NoParams> {
  /// Creates the use case.
  const GetLockoutState(this._repository);

  final AuthRepository _repository;

  @override
  Future<Either<Failure, LockoutState>> call(NoParams params) =>
      _repository.getLockout();
}
