import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/auth/domain/entities/lockout_policy.dart';
import 'package:moneyora/features/auth/domain/entities/lockout_state.dart';

/// NFR-SEC-003's ladder, walked end to end without waiting on a clock.
void main() {
  const policy = LockoutPolicy.standard;
  final t0 = DateTime(2026, 9, 21, 9);

  group('lockoutAfter', () {
    test('the first four failures cost nothing', () {
      for (var failed = 0; failed < 5; failed++) {
        expect(policy.lockoutAfter(failed), isNull, reason: 'failure $failed');
      }
    });

    test('the fifth failure locks for 30 seconds, and each one after '
        'doubles it', () {
      expect(policy.lockoutAfter(5), const Duration(seconds: 30));
      expect(policy.lockoutAfter(6), const Duration(minutes: 1));
      expect(policy.lockoutAfter(7), const Duration(minutes: 2));
      expect(policy.lockoutAfter(8), const Duration(minutes: 4));
      expect(policy.lockoutAfter(11), const Duration(minutes: 32));
    });

    test('caps at an hour, however long the run', () {
      expect(policy.lockoutAfter(12), const Duration(hours: 1));
      expect(policy.lockoutAfter(13), const Duration(hours: 1));
      // Far past where a shift would overflow.
      expect(policy.lockoutAfter(1000), const Duration(hours: 1));
    });
  });

  group('recordFailure', () {
    test('counts, and locks on the fifth', () {
      var state = LockoutState.none;
      for (var i = 1; i <= 4; i++) {
        state = policy.recordFailure(state, t0);
        expect(state, LockoutState(failedAttempts: i));
      }
      state = policy.recordFailure(state, t0);
      expect(
        state,
        LockoutState(
          failedAttempts: 5,
          lockedUntil: t0.add(const Duration(seconds: 30)),
        ),
      );
    });

    test(
      'a failure after a served lockout locks again at once, for longer',
      () {
        const served = LockoutState(failedAttempts: 5);
        final later = t0.add(const Duration(minutes: 5));

        final state = policy.recordFailure(served, later);

        expect(state.failedAttempts, 6);
        expect(state.lockedUntil, later.add(const Duration(minutes: 1)));
      },
    );
  });

  group('attemptsBeforeLockout', () {
    test('counts down the free attempts, then is always one', () {
      expect(policy.attemptsBeforeLockout(LockoutState.none), 5);
      expect(
        policy.attemptsBeforeLockout(const LockoutState(failedAttempts: 4)),
        1,
      );
      expect(
        policy.attemptsBeforeLockout(const LockoutState(failedAttempts: 5)),
        1,
      );
      expect(
        policy.attemptsBeforeLockout(const LockoutState(failedAttempts: 9)),
        1,
      );
    });
  });

  group('LockoutState', () {
    test('is locked strictly before lockedUntil', () {
      final state = LockoutState(
        failedAttempts: 5,
        lockedUntil: t0.add(const Duration(seconds: 30)),
      );

      expect(state.isLockedAt(t0), isTrue);
      expect(state.remainingAt(t0), const Duration(seconds: 30));
      expect(state.isLockedAt(t0.add(const Duration(seconds: 29))), isTrue);
      expect(state.isLockedAt(t0.add(const Duration(seconds: 30))), isFalse);
      expect(
        state.remainingAt(t0.add(const Duration(seconds: 30))),
        Duration.zero,
      );
    });

    test('with no lockout is never locked', () {
      expect(LockoutState.none.isLockedAt(t0), isFalse);
      expect(const LockoutState(failedAttempts: 3).isLockedAt(t0), isFalse);
    });
  });
}
