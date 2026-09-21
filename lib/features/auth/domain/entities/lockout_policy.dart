import 'lockout_state.dart';

/// NFR-SEC-003's "5-attempt lockout with exponential backoff", as arithmetic.
///
/// The first [freeAttempts] failures are refused and counted, nothing more.
/// The failure that reaches the count locks the gate for [firstLockout]; every
/// failure after it doubles the previous lockout, up to [maxLockout]. A correct
/// PIN resets the count to zero (see `VerifyPasscode`), so the run starts
/// again from the free attempts.
///
/// With the standard numbers: 30 s after the fifth failure, then 1, 2, 4, 8,
/// 16, 32 minutes, then an hour for every failure after that. A 6-digit PIN
/// has a million values; at an hour per guess the search is not one a person
/// holding the phone finishes, which is all the backoff is for. The passcode
/// never protects the data — the database key is not derived from it
/// (E-31 §1) — so there is no reason to be crueller to the owner who has
/// mistyped.
///
/// Pure: given the same state and clock it always answers the same, which is
/// what lets the unit test walk the whole ladder without waiting an hour.
class LockoutPolicy {
  /// Creates a policy. The defaults are NFR-SEC-003's.
  const LockoutPolicy({
    this.freeAttempts = 5,
    this.firstLockout = const Duration(seconds: 30),
    this.maxLockout = const Duration(hours: 1),
  });

  /// The policy the app ships with.
  static const LockoutPolicy standard = LockoutPolicy();

  /// How many consecutive failures are allowed before the first lockout.
  final int freeAttempts;

  /// The lockout the [freeAttempts]th failure triggers.
  final Duration firstLockout;

  /// The longest a single lockout can be, however many failures precede it.
  final Duration maxLockout;

  /// The lockout a run of [failedAttempts] consecutive failures ends in, or
  /// null while the run is still within the free attempts.
  Duration? lockoutAfter(int failedAttempts) {
    if (failedAttempts < freeAttempts) return null;
    final doublings = failedAttempts - freeAttempts;
    // Past this many doublings the shift would overflow long before the
    // duration compares; every one of them is over the cap anyway.
    if (doublings >= 30) return maxLockout;
    final lockout = firstLockout * (1 << doublings);
    return lockout > maxLockout ? maxLockout : lockout;
  }

  /// How many more wrong PINs [state] can absorb before the gate locks.
  ///
  /// After a lockout has been served, every further failure locks again at
  /// once — so past the free attempts the answer is always one.
  int attemptsBeforeLockout(LockoutState state) {
    final left = freeAttempts - state.failedAttempts;
    return left > 0 ? left : 1;
  }

  /// [state] after one more wrong PIN entered at [now].
  LockoutState recordFailure(LockoutState state, DateTime now) {
    final failed = state.failedAttempts + 1;
    final lockout = lockoutAfter(failed);
    return LockoutState(
      failedAttempts: failed,
      lockedUntil: lockout == null ? null : now.add(lockout),
    );
  }
}
