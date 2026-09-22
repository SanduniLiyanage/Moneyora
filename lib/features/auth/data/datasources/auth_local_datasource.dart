import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../../core/errors/exceptions.dart';
import '../../domain/entities/lockout_state.dart';
import '../models/lockout_state_model.dart';
import '../models/passcode_record.dart';

/// Where the passcode record and the lockout state live. FR-SET-005,
/// NFR-SEC-003.
///
/// **Not the `users` row.** The DBD gives it `passcode_hash` and
/// `biometric_enabled`, and both columns stay in the schema, unused — E-31 §1
/// records why the hash column as specified would secure nothing, and the
/// lockout state has no column at all. Rather than migrate two columns into
/// four, the gate keeps its state in the platform keychain beside the
/// database key `SecureStorageKeyStore` already holds there: the same
/// hardware-backed store, the same fake in tests, and a store that is
/// readable before the database is open — which the lock screen, drawn
/// during the launch, needs. Decided 2026-09-17.
///
/// Three entries, by name. `auth.passcode` and `auth.lockout` are the
/// passcode gate's; `auth.biometrics` is NFR-SEC-004's toggle, "1" when on
/// and absent otherwise — there is no third value to store, so there is
/// nothing a malformed entry could mean and no [CacheException] case for it.
abstract class AuthLocalDataSource {
  /// The stored passcode record, or null when no passcode is set.
  Future<PasscodeRecord?> readPasscode();

  /// Stores [record], replacing any.
  Future<void> writePasscode(PasscodeRecord record);

  /// Removes the passcode record. A no-op when there is none.
  Future<void> deletePasscode();

  /// The stored lockout state, or null when nothing is stored.
  Future<LockoutState?> readLockout();

  /// Stores [state], replacing any.
  Future<void> writeLockout(LockoutState state);

  /// Removes the lockout state. A no-op when there is none.
  Future<void> deleteLockout();

  /// Whether the biometrics entry is set. NFR-SEC-004.
  Future<bool> readBiometricsEnabled();

  /// Writes the entry when [enabled], deletes it otherwise — the same
  /// present-or-absent shape [deleteLockout] keeps for a clean store.
  Future<void> writeBiometricsEnabled({required bool enabled});
}

/// The production datasource, over the platform keychain / keystore.
///
/// Every platform error becomes a [CacheException], and so does a stored
/// value this app could not have written: a record that will not parse is
/// reported, not treated as "no passcode", because silently unlocking on a
/// corrupt entry is the wrong way to fail for a lock.
class SecureStorageAuthDataSource implements AuthLocalDataSource {
  /// Creates a datasource over [storage], defaulting to the platform's.
  SecureStorageAuthDataSource({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Keychain entry holding the [PasscodeRecord]. Permanent: renaming it
  /// silently turns every passcode off.
  static const String passcodeKey = 'auth.passcode';

  /// Keychain entry holding the [LockoutState].
  static const String lockoutKey = 'auth.lockout';

  /// Keychain entry holding the biometrics toggle. NFR-SEC-004.
  static const String biometricsKey = 'auth.biometrics';

  @override
  Future<PasscodeRecord?> readPasscode() => _attempt(() async {
    final stored = await _storage.read(key: passcodeKey);
    if (stored == null || stored.isEmpty) return null;
    return PasscodeRecord.decode(stored);
  });

  @override
  Future<void> writePasscode(PasscodeRecord record) =>
      _attempt(() => _storage.write(key: passcodeKey, value: record.encode()));

  @override
  Future<void> deletePasscode() =>
      _attempt(() => _storage.delete(key: passcodeKey));

  @override
  Future<LockoutState?> readLockout() => _attempt(() async {
    final stored = await _storage.read(key: lockoutKey);
    if (stored == null || stored.isEmpty) return null;
    return LockoutStateModel.decode(stored);
  });

  @override
  Future<void> writeLockout(LockoutState state) => _attempt(
    () =>
        _storage.write(key: lockoutKey, value: LockoutStateModel.encode(state)),
  );

  @override
  Future<void> deleteLockout() =>
      _attempt(() => _storage.delete(key: lockoutKey));

  @override
  Future<bool> readBiometricsEnabled() =>
      _attempt(() async => await _storage.read(key: biometricsKey) == '1');

  @override
  Future<void> writeBiometricsEnabled({required bool enabled}) => _attempt(
    () => enabled
        ? _storage.write(key: biometricsKey, value: '1')
        : _storage.delete(key: biometricsKey),
  );

  Future<T> _attempt<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on FormatException catch (e) {
      throw CacheException('The passcode store is damaged.', cause: e);
    } on Exception catch (e) {
      throw CacheException('Could not reach the passcode store.', cause: e);
    }
  }
}

/// In-memory datasource for tests and widget tests.
///
/// The platform keychain is a method channel, which never answers in a
/// widget test; this is what `authLocalDataSourceProvider` is overridden
/// with, the way `InMemoryKeyStore` stands in for the database key.
class InMemoryAuthDataSource implements AuthLocalDataSource {
  PasscodeRecord? _passcode;
  LockoutState? _lockout;
  bool _biometricsEnabled = false;

  @override
  Future<PasscodeRecord?> readPasscode() async => _passcode;

  @override
  Future<void> writePasscode(PasscodeRecord record) async => _passcode = record;

  @override
  Future<void> deletePasscode() async => _passcode = null;

  @override
  Future<LockoutState?> readLockout() async => _lockout;

  @override
  Future<void> writeLockout(LockoutState state) async => _lockout = state;

  @override
  Future<void> deleteLockout() async => _lockout = null;

  @override
  Future<bool> readBiometricsEnabled() async => _biometricsEnabled;

  @override
  Future<void> writeBiometricsEnabled({required bool enabled}) async =>
      _biometricsEnabled = enabled;
}
