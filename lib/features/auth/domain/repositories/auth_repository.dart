import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/lockout_state.dart';

/// The passcode and its lockout state. FR-SET-005, NFR-SEC-003.
///
/// Six methods and no policy: whether an attempt is allowed, what a failure
/// costs and when the count resets are `VerifyPasscode`'s decisions, made
/// over what this repository stores. The repository knows how a PIN is
/// hashed and where the result lives; the use cases know what a wrong PIN
/// means.
///
/// The PIN itself never comes back out. [matchesPasscode] answers yes or no
/// against a stored derivation; there is nothing stored from which the PIN
/// could be read.
abstract class AuthRepository {
  /// Whether a passcode is set.
  Future<Either<Failure, bool>> hasPasscode();

  /// Stores [pin], replacing any passcode already set, and clears the
  /// lockout state — a fresh PIN starts a fresh run.
  ///
  /// [pin] has already passed `PasscodeFormat.validate`; this does not check
  /// it again.
  Future<Either<Failure, Unit>> setPasscode(String pin);

  /// Removes the passcode and the lockout state with it.
  Future<Either<Failure, Unit>> clearPasscode();

  /// Whether [pin] is the stored passcode. False when none is set.
  ///
  /// Checks only. It does not touch the lockout state, which is the use
  /// case's to update once it has decided what this answer means.
  Future<Either<Failure, bool>> matchesPasscode(String pin);

  /// The lockout state; [LockoutState.none] when nothing is stored.
  Future<Either<Failure, LockoutState>> getLockout();

  /// Stores [state]. Storing [LockoutState.none] may remove the entry.
  Future<Either<Failure, Unit>> saveLockout(LockoutState state);

  /// Whether biometric unlock is turned on. False until
  /// [setBiometricsEnabled] turns it on. NFR-SEC-004.
  Future<Either<Failure, bool>> isBiometricsEnabled();

  /// Turns biometric unlock on or off. NFR-SEC-004.
  ///
  /// Storage only — whether a PIN exists and whether the sensor agrees are
  /// `EnableBiometrics`'s decisions, made before this is called.
  Future<Either<Failure, Unit>> setBiometricsEnabled({required bool enabled});
}
