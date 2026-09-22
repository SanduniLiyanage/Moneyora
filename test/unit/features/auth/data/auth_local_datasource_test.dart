import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/auth/data/datasources/auth_local_datasource.dart';
import 'package:moneyora/features/auth/data/models/passcode_record.dart';
import 'package:moneyora/features/auth/domain/entities/lockout_state.dart';

/// The keychain datasource over `flutter_secure_storage`'s own in-memory
/// test platform, which is the closest a unit test gets to the keychain.
void main() {
  late SecureStorageAuthDataSource source;

  const record = PasscodeRecord(
    iterations: 1000,
    salt: [1, 2, 3, 4],
    hash: [5, 6, 7, 8],
  );

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    source = SecureStorageAuthDataSource();
  });

  group('passcode', () {
    test('is absent until written, then reads back', () async {
      expect(await source.readPasscode(), isNull);

      await source.writePasscode(record);

      expect(await source.readPasscode(), record);
    });

    test('is written under its named entry, as a PHC string', () async {
      await source.writePasscode(record);

      expect(
        await const FlutterSecureStorage().read(
          key: SecureStorageAuthDataSource.passcodeKey,
        ),
        record.encode(),
      );
    });

    test('deletes, and deleting again is harmless', () async {
      await source.writePasscode(record);
      await source.deletePasscode();
      await source.deletePasscode();

      expect(await source.readPasscode(), isNull);
    });

    test('a damaged entry is an error, not "no passcode"', () async {
      FlutterSecureStorage.setMockInitialValues({
        SecureStorageAuthDataSource.passcodeKey: 'garbage',
      });

      expect(
        () => SecureStorageAuthDataSource().readPasscode(),
        throwsA(isA<CacheException>()),
      );
    });
  });

  group('lockout', () {
    test('is absent until written, then reads back', () async {
      expect(await source.readLockout(), isNull);

      final state = LockoutState(
        failedAttempts: 5,
        lockedUntil: DateTime.utc(2026, 9, 21, 9, 0, 30),
      );
      await source.writeLockout(state);

      expect(await source.readLockout(), state);
    });

    test('deletes', () async {
      await source.writeLockout(const LockoutState(failedAttempts: 2));
      await source.deleteLockout();

      expect(await source.readLockout(), isNull);
    });
  });

  group('InMemoryAuthDataSource', () {
    test('behaves the same', () async {
      final memory = InMemoryAuthDataSource();
      expect(await memory.readPasscode(), isNull);
      expect(await memory.readLockout(), isNull);

      await memory.writePasscode(record);
      await memory.writeLockout(const LockoutState(failedAttempts: 1));
      expect(await memory.readPasscode(), record);
      expect(await memory.readLockout(), const LockoutState(failedAttempts: 1));

      await memory.deletePasscode();
      await memory.deleteLockout();
      expect(await memory.readPasscode(), isNull);
      expect(await memory.readLockout(), isNull);
    });
  });

  group('biometrics', () {
    test('is off until written, then reads back', () async {
      expect(await source.readBiometricsEnabled(), isFalse);

      await source.writeBiometricsEnabled(enabled: true);

      expect(await source.readBiometricsEnabled(), isTrue);
    });

    test('is stored as "1" under its named entry', () async {
      await source.writeBiometricsEnabled(enabled: true);

      expect(
        await const FlutterSecureStorage().read(
          key: SecureStorageAuthDataSource.biometricsKey,
        ),
        '1',
      );
    });

    test('turning it off removes the entry rather than storing "0"', () async {
      await source.writeBiometricsEnabled(enabled: true);

      await source.writeBiometricsEnabled(enabled: false);

      expect(
        await const FlutterSecureStorage().read(
          key: SecureStorageAuthDataSource.biometricsKey,
        ),
        isNull,
      );
      expect(await source.readBiometricsEnabled(), isFalse);
    });

    test('InMemoryAuthDataSource behaves the same', () async {
      final memory = InMemoryAuthDataSource();
      expect(await memory.readBiometricsEnabled(), isFalse);

      await memory.writeBiometricsEnabled(enabled: true);
      expect(await memory.readBiometricsEnabled(), isTrue);

      await memory.writeBiometricsEnabled(enabled: false);
      expect(await memory.readBiometricsEnabled(), isFalse);
    });
  });
}
