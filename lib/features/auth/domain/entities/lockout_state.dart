import 'package:equatable/equatable.dart';

/// Where the passcode gate stands after the attempts made so far.
/// NFR-SEC-003.
///
/// Two facts, and nothing derived from a clock: how many attempts in a row
/// have failed, and — once there have been enough — the moment before which
/// no further attempt is accepted. Whether that moment has passed is a
/// question for whoever holds the current time, which is why [isLockedAt]
/// takes it rather than reading `DateTime.now()`; a use case or a screen
/// can then be tested against a clock it controls.
///
/// This is stored in the platform keychain beside the passcode itself, not in
/// the `users` row: see `AuthLocalDataSource` for why the DBD's columns stay
/// unused (E-31 §1).
class LockoutState extends Equatable {
  /// Creates a lockout state.
  const LockoutState({this.failedAttempts = 0, this.lockedUntil});

  /// No failed attempts, no lockout — the state after a correct PIN.
  static const LockoutState none = LockoutState();

  /// Consecutive failed attempts since the last correct PIN.
  final int failedAttempts;

  /// The moment the current lockout ends, or null when there is none.
  ///
  /// May be in the past: a lockout that has expired is left in place until
  /// the next attempt, which either clears it (correct) or extends it
  /// (wrong) — so an attempt made after a lockout is still counted against
  /// the run that caused it.
  final DateTime? lockedUntil;

  /// Whether an attempt at [now] would be refused without being checked.
  bool isLockedAt(DateTime now) =>
      lockedUntil != null && now.isBefore(lockedUntil!);

  /// How long the lockout has left at [now]; zero when there is none.
  Duration remainingAt(DateTime now) =>
      isLockedAt(now) ? lockedUntil!.difference(now) : Duration.zero;

  @override
  List<Object?> get props => [failedAttempts, lockedUntil];
}
