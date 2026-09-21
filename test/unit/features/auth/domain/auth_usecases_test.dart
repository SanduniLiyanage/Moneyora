import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/usecases/usecase.dart';
import 'package:moneyora/features/auth/domain/entities/lockout_state.dart';
import 'package:moneyora/features/auth/domain/entities/pin_verdict.dart';
import 'package:moneyora/features/auth/domain/repositories/auth_repository.dart';
import 'package:moneyora/features/auth/domain/usecases/change_passcode.dart';
import 'package:moneyora/features/auth/domain/usecases/get_lockout_state.dart';
import 'package:moneyora/features/auth/domain/usecases/has_passcode.dart';
import 'package:moneyora/features/auth/domain/usecases/remove_passcode.dart';
import 'package:moneyora/features/auth/domain/usecases/set_passcode.dart';
import 'package:moneyora/features/auth/domain/usecases/verify_passcode.dart';

/// The auth use cases share one collaborator and one clock; one file, one
/// group per use case, as `settings_usecases_test.dart` does it.
///
/// The repository fake stores the PIN in the clear. That is fine here: what
/// is under test is the policy over the answers, not how the answer is
/// derived — the hasher has its own test.
void main() {
  late _FakeRepository repository;
  late DateTime now;

  final t0 = DateTime(2026, 9, 21, 9);

  setUp(() {
    repository = _FakeRepository();
    now = t0;
  });

  VerifyPasscode verify() => VerifyPasscode(repository, now: () => now);

  group('VerifyPasscode', () {
    test('accepts the right PIN and leaves a clean slate alone', () async {
      repository.pin = '1234';

      final result = await verify()('1234');

      expect(result, const Right<Failure, PinVerdict>(PinAccepted()));
      expect(repository.lockoutWrites, isEmpty);
    });

    test('accepts the right PIN and clears a count', () async {
      repository
        ..pin = '1234'
        ..lockout = const LockoutState(failedAttempts: 3);

      final result = await verify()('1234');

      expect(result, const Right<Failure, PinVerdict>(PinAccepted()));
      expect(repository.lockout, LockoutState.none);
    });

    test('rejects a wrong PIN and counts it', () async {
      repository.pin = '1234';

      final result = await verify()('9999');

      expect(
        result,
        const Right<Failure, PinVerdict>(
          PinRejected(LockoutState(failedAttempts: 1)),
        ),
      );
      expect(repository.lockout, const LockoutState(failedAttempts: 1));
    });

    test('the fifth wrong PIN locks the gate', () async {
      repository
        ..pin = '1234'
        ..lockout = const LockoutState(failedAttempts: 4);

      final result = await verify()('9999');

      final expected = LockoutState(
        failedAttempts: 5,
        lockedUntil: t0.add(const Duration(seconds: 30)),
      );
      expect(result, Right<Failure, PinVerdict>(PinRejected(expected)));
      expect(repository.lockout, expected);
    });

    test(
      'refuses without checking while locked, and does not count it',
      () async {
        final locked = LockoutState(
          failedAttempts: 5,
          lockedUntil: t0.add(const Duration(seconds: 30)),
        );
        repository
          ..pin = '1234'
          ..lockout = locked;

        // Even the right PIN: a locked gate is locked.
        final result = await verify()('1234');

        expect(result, Right<Failure, PinVerdict>(PinLockedOut(locked)));
        expect(repository.matchCalls, 0);
        expect(repository.lockout, locked);
      },
    );

    test('checks again once the lockout has passed', () async {
      repository
        ..pin = '1234'
        ..lockout = LockoutState(
          failedAttempts: 5,
          lockedUntil: t0.add(const Duration(seconds: 30)),
        );
      now = t0.add(const Duration(seconds: 30));

      final result = await verify()('1234');

      expect(result, const Right<Failure, PinVerdict>(PinAccepted()));
      expect(repository.lockout, LockoutState.none);
    });

    test(
      'a wrong PIN after a served lockout locks again, for longer',
      () async {
        repository
          ..pin = '1234'
          ..lockout = LockoutState(
            failedAttempts: 5,
            lockedUntil: t0.add(const Duration(seconds: 30)),
          );
        now = t0.add(const Duration(minutes: 1));

        final result = await verify()('9999');

        expect(
          result,
          Right<Failure, PinVerdict>(
            PinRejected(
              LockoutState(
                failedAttempts: 6,
                lockedUntil: now.add(const Duration(minutes: 1)),
              ),
            ),
          ),
        );
      },
    );

    test('refuses a malformed PIN as input, not as a guess', () async {
      repository.pin = '1234';

      final result = await verify()('12');

      expect(
        result,
        const Left<Failure, PinVerdict>(
          ValidationFailure('Enter a PIN of 4 to 6 digits.', field: 'pin'),
        ),
      );
      expect(repository.matchCalls, 0);
      expect(repository.lockout, LockoutState.none);
    });

    test('surfaces a store that cannot be read', () async {
      repository.failWith = const CacheFailure('keychain unavailable');

      final result = await verify()('1234');

      expect(
        result,
        const Left<Failure, PinVerdict>(CacheFailure('keychain unavailable')),
      );
    });
  });

  group('SetPasscode', () {
    test('stores a well-formed PIN when none is set', () async {
      final result = await SetPasscode(repository)('123456');

      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.pin, '123456');
    });

    test('refuses a malformed PIN in its own words', () async {
      for (final bad in ['123', '1234567', '12a4', '']) {
        final result = await SetPasscode(repository)(bad);
        expect(
          result,
          const Left<Failure, Unit>(
            ValidationFailure('Enter a PIN of 4 to 6 digits.', field: 'pin'),
          ),
          reason: bad,
        );
      }
      expect(repository.pin, isNull);
    });

    test('refuses to replace a passcode that exists', () async {
      repository.pin = '1234';

      final result = await SetPasscode(repository)('5678');

      expect(
        result,
        const Left<Failure, Unit>(
          ValidationFailure(
            'A passcode is already set. Change it instead.',
            field: 'pin',
          ),
        ),
      );
      expect(repository.pin, '1234');
    });
  });

  group('ChangePasscode', () {
    ChangePasscode change() => ChangePasscode(repository, verify());

    test('replaces the passcode on proof of the current one', () async {
      repository.pin = '1234';

      final result = await change()(
        const ChangePasscodeParams(current: '1234', next: '5678'),
      );

      expect(result, const Right<Failure, PinVerdict>(PinAccepted()));
      expect(repository.pin, '5678');
    });

    test('a wrong current PIN is counted, and nothing changes', () async {
      repository.pin = '1234';

      final result = await change()(
        const ChangePasscodeParams(current: '0000', next: '5678'),
      );

      expect(
        result,
        const Right<Failure, PinVerdict>(
          PinRejected(LockoutState(failedAttempts: 1)),
        ),
      );
      expect(repository.pin, '1234');
    });

    test('refuses the same PIN again, before checking anything', () async {
      repository.pin = '1234';

      final result = await change()(
        const ChangePasscodeParams(current: '1234', next: '1234'),
      );

      expect(
        result,
        const Left<Failure, PinVerdict>(
          ValidationFailure(
            'Choose a PIN different from the current one.',
            field: 'pin',
          ),
        ),
      );
      expect(repository.matchCalls, 0);
    });

    test('refuses when no passcode is set', () async {
      final result = await change()(
        const ChangePasscodeParams(current: '1234', next: '5678'),
      );

      expect(
        result,
        const Left<Failure, PinVerdict>(
          ValidationFailure('No passcode is set.'),
        ),
      );
    });
  });

  group('RemovePasscode', () {
    RemovePasscode remove() => RemovePasscode(repository, verify());

    test('clears the passcode on proof of it', () async {
      repository
        ..pin = '1234'
        ..lockout = const LockoutState(failedAttempts: 2);

      final result = await remove()('1234');

      expect(result, const Right<Failure, PinVerdict>(PinAccepted()));
      expect(repository.pin, isNull);
      expect(repository.lockout, LockoutState.none);
    });

    test('a wrong PIN is counted, and the passcode stays', () async {
      repository.pin = '1234';

      final result = await remove()('0000');

      expect(
        result,
        const Right<Failure, PinVerdict>(
          PinRejected(LockoutState(failedAttempts: 1)),
        ),
      );
      expect(repository.pin, '1234');
    });

    test('refuses when no passcode is set', () async {
      final result = await remove()('1234');

      expect(
        result,
        const Left<Failure, PinVerdict>(
          ValidationFailure('No passcode is set.'),
        ),
      );
    });
  });

  group('HasPasscode and GetLockoutState', () {
    test('report what is stored', () async {
      expect(
        await HasPasscode(repository)(const NoParams()),
        const Right<Failure, bool>(false),
      );
      repository
        ..pin = '1234'
        ..lockout = const LockoutState(failedAttempts: 2);
      expect(
        await HasPasscode(repository)(const NoParams()),
        const Right<Failure, bool>(true),
      );
      expect(
        await GetLockoutState(repository)(const NoParams()),
        const Right<Failure, LockoutState>(LockoutState(failedAttempts: 2)),
      );
    });
  });
}

class _FakeRepository implements AuthRepository {
  String? pin;
  LockoutState lockout = LockoutState.none;
  Failure? failWith;

  /// How many times the stored PIN was compared against.
  int matchCalls = 0;

  /// Every lockout state written, in order.
  final List<LockoutState> lockoutWrites = [];

  @override
  Future<Either<Failure, bool>> hasPasscode() async {
    if (failWith case final failure?) return Left(failure);
    return Right(pin != null);
  }

  @override
  Future<Either<Failure, Unit>> setPasscode(String pin) async {
    if (failWith case final failure?) return Left(failure);
    this.pin = pin;
    lockout = LockoutState.none;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> clearPasscode() async {
    if (failWith case final failure?) return Left(failure);
    pin = null;
    lockout = LockoutState.none;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, bool>> matchesPasscode(String pin) async {
    if (failWith case final failure?) return Left(failure);
    matchCalls++;
    return Right(this.pin != null && this.pin == pin);
  }

  @override
  Future<Either<Failure, LockoutState>> getLockout() async {
    if (failWith case final failure?) return Left(failure);
    return Right(lockout);
  }

  @override
  Future<Either<Failure, Unit>> saveLockout(LockoutState state) async {
    if (failWith case final failure?) return Left(failure);
    lockout = state;
    lockoutWrites.add(state);
    return const Right(unit);
  }
}
