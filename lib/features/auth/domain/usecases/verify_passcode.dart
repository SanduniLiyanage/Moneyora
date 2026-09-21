import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/lockout_policy.dart';
import '../entities/lockout_state.dart';
import '../entities/passcode_format.dart';
import '../entities/pin_verdict.dart';
import '../repositories/auth_repository.dart';

/// Checks one PIN against the gate and keeps the lockout honest.
/// FR-SET-005, NFR-SEC-003.
///
/// The one place the lockout policy is applied. Every attempt — from the lock
/// screen, from the change-PIN flow, from the remove-PIN flow — comes through
/// here, so a wrong PIN costs the same wherever it is typed and there is no
/// screen through which the five attempts can be had twice.
///
/// The order matters: the lockout is read *before* the PIN is checked, and a
/// locked gate refuses without checking, so no work is done and nothing is
/// learned from an attempt made too soon. A correct PIN clears the lockout
/// state; a wrong one records the failure through [LockoutPolicy]. Both are
/// written back before the verdict is returned, so a crash after the answer
/// cannot lose the count.
///
/// The clock is injected so the tests can serve a lockout in no time at all.
class VerifyPasscode implements UseCase<PinVerdict, String> {
  /// Creates the use case. [now] defaults to the wall clock.
  const VerifyPasscode(
    this._repository, {
    this._now = DateTime.now,
    this._policy = LockoutPolicy.standard,
  });

  final AuthRepository _repository;
  final DateTime Function() _now;
  final LockoutPolicy _policy;

  @override
  Future<Either<Failure, PinVerdict>> call(String params) async {
    // A PIN that could not have been set cannot match, and a screen only
    // ever sends digits — so a malformed one is refused as input, not
    // counted as a guess.
    if (PasscodeFormat.validate(params) case final failure?) {
      return Left(failure);
    }

    final lockoutResult = await _repository.getLockout();
    return lockoutResult.fold(Left.new, (lockout) async {
      final now = _now();
      if (lockout.isLockedAt(now)) return Right(PinLockedOut(lockout));

      final matches = await _repository.matchesPasscode(params);
      return matches.fold(Left.new, (matched) async {
        if (matched) {
          if (lockout == LockoutState.none) return const Right(PinAccepted());
          final cleared = await _repository.saveLockout(LockoutState.none);
          return cleared.map((_) => const PinAccepted());
        }
        final next = _policy.recordFailure(lockout, now);
        final saved = await _repository.saveLockout(next);
        return saved.map((_) => PinRejected(next));
      });
    });
  }
}
