import 'package:equatable/equatable.dart';

import 'lockout_state.dart';

/// What `VerifyPasscode` decided about one attempt. FR-SET-005, NFR-SEC-003.
///
/// A verdict rather than a boolean, and a value rather than a failure: a
/// wrong PIN is the gate doing its job, not something going wrong, and the
/// screen needs to say where the user now stands — attempts left, or how long
/// until the next one is accepted — which a `Left` could not carry.
sealed class PinVerdict extends Equatable {
  const PinVerdict();
}

/// The PIN was right. The lockout state has been reset.
class PinAccepted extends PinVerdict {
  /// Creates the verdict.
  const PinAccepted();

  @override
  List<Object?> get props => const [];
}

/// The PIN was checked and was wrong. [lockout] is the state after this
/// failure was counted — it may already be locked, if this was the failure
/// that tipped it.
class PinRejected extends PinVerdict {
  /// Creates the verdict.
  const PinRejected(this.lockout);

  /// Where the gate stands now.
  final LockoutState lockout;

  @override
  List<Object?> get props => [lockout];
}

/// The attempt was refused without checking the PIN, because a lockout is in
/// force. [lockout] is unchanged: an attempt during a lockout is not counted,
/// or a stuck key would double the wait.
class PinLockedOut extends PinVerdict {
  /// Creates the verdict.
  const PinLockedOut(this.lockout);

  /// The lockout in force.
  final LockoutState lockout;

  @override
  List<Object?> get props => [lockout];
}
