import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:moneyora/features/auth/data/datasources/pin_hasher.dart';
import 'package:moneyora/features/auth/data/models/passcode_record.dart';
import 'package:moneyora/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:moneyora/features/auth/domain/entities/lockout_state.dart';

/// The boundary: exceptions become failures, and the two stores are kept
/// consistent with each other.
void main() {
  late _Store store;
  late AuthRepositoryImpl repository;

  setUp(() {
    store = _Store();
    repository = AuthRepositoryImpl(store, _InstantHasher());
  });

  test('has no passcode until one is set', () async {
    expect(await repository.hasPasscode(), const Right<Failure, bool>(false));

    await repository.setPasscode('1234');

    expect(await repository.hasPasscode(), const Right<Failure, bool>(true));
  });

  test('matches through the hasher', () async {
    await repository.setPasscode('1234');

    expect(
      await repository.matchesPasscode('1234'),
      const Right<Failure, bool>(true),
    );
    expect(
      await repository.matchesPasscode('4321'),
      const Right<Failure, bool>(false),
    );
  });

  test('nothing matches when no passcode is set', () async {
    expect(
      await repository.matchesPasscode('1234'),
      const Right<Failure, bool>(false),
    );
  });

  test('setting a passcode clears the lockout', () async {
    await repository.saveLockout(const LockoutState(failedAttempts: 4));

    await repository.setPasscode('1234');

    expect(
      await repository.getLockout(),
      const Right<Failure, LockoutState>(LockoutState.none),
    );
  });

  test('clearing the passcode clears the lockout', () async {
    await repository.setPasscode('1234');
    await repository.saveLockout(const LockoutState(failedAttempts: 4));

    await repository.clearPasscode();

    expect(await repository.hasPasscode(), const Right<Failure, bool>(false));
    expect(store.lockout, isNull);
  });

  test(
    'saving no lockout removes the entry rather than storing zeros',
    () async {
      await repository.saveLockout(const LockoutState(failedAttempts: 4));
      await repository.saveLockout(LockoutState.none);

      expect(store.lockout, isNull);
      expect(
        await repository.getLockout(),
        const Right<Failure, LockoutState>(LockoutState.none),
      );
    },
  );

  test('a store that throws is a CacheFailure in its own words', () async {
    store.failWith = const CacheException('keychain unavailable');

    expect(
      await repository.hasPasscode(),
      const Left<Failure, bool>(CacheFailure('keychain unavailable')),
    );
    expect(
      await repository.getLockout(),
      const Left<Failure, LockoutState>(CacheFailure('keychain unavailable')),
    );
    expect(
      await repository.setPasscode('1234'),
      const Left<Failure, Unit>(CacheFailure('keychain unavailable')),
    );
  });
}

/// The in-memory datasource, made to fail on demand.
class _Store extends InMemoryAuthDataSource {
  CacheException? failWith;
  LockoutState? lockout;

  void _check() {
    if (failWith case final e?) throw e;
  }

  @override
  Future<PasscodeRecord?> readPasscode() async {
    _check();
    return super.readPasscode();
  }

  @override
  Future<void> writePasscode(PasscodeRecord record) async {
    _check();
    return super.writePasscode(record);
  }

  @override
  Future<LockoutState?> readLockout() async {
    _check();
    return lockout;
  }

  @override
  Future<void> writeLockout(LockoutState state) async {
    _check();
    lockout = state;
  }

  @override
  Future<void> deleteLockout() async {
    _check();
    lockout = null;
  }
}

/// A "hash" that is the PIN's bytes, so the test never waits on a KDF.
class _InstantHasher implements PinHasher {
  @override
  Future<PasscodeRecord> hash(String pin) async =>
      PasscodeRecord(iterations: 1, salt: const [0], hash: pin.codeUnits);

  @override
  Future<bool> matches(String pin, PasscodeRecord record) async =>
      pin.codeUnits.join(',') == record.hash.join(',');
}
