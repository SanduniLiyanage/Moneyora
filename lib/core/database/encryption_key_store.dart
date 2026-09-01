import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Supplies the AES-256 key that SQLCipher opens the database with.
///
/// This is an interface rather than a concrete class for one reason: the
/// production implementation talks to the iOS Keychain and Android Keystore
/// over a platform channel, which cannot run in a unit test. Every test that
/// needs a database injects a fake instead, which is what makes the migration
/// runner testable at all.
///
/// Satisfies NFR-SEC-001 (AES-256 at rest) and SDD §5.4.
abstract class EncryptionKeyStore {
  /// Returns the database key, generating and persisting one on first call.
  ///
  /// Must return the *same* key on every subsequent call for the life of the
  /// installation. A key that changes makes every existing row unreadable —
  /// there is no recovery, because the ciphertext is all that remains.
  Future<String> getOrCreateKey();
}

/// Production key store, backed by the platform's hardware-backed keychain.
///
/// The key is generated once on first launch and never leaves the device.
/// It is not derived from a passcode: the passcode (FR-SET-005) gates access
/// to the *app*, and users change or remove it. Deriving the database key from
/// something the user can change would mean re-encrypting the entire database
/// on every passcode change, and losing all data if they forget it.
class SecureStorageKeyStore implements EncryptionKeyStore {
  /// Creates a key store over [storage], defaulting to platform secure storage.
  SecureStorageKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Keychain / Keystore entry name. Changing this orphans every existing
  /// database, so treat it as permanent.
  static const String keyName = 'db_encryption_key';

  /// 256 bits, per NFR-SEC-001.
  static const int _keyLengthBytes = 32;

  @override
  Future<String> getOrCreateKey() async {
    final existing = await _storage.read(key: keyName);
    if (existing != null && existing.isNotEmpty) return existing;

    // Random.secure() draws from the platform CSPRNG. The default Random()
    // is a deterministic PRNG seeded from the clock, which would make the
    // key guessable from the install time — a real and frequently made
    // mistake, and one no test would catch.
    final random = Random.secure();
    final bytes = List<int>.generate(
      _keyLengthBytes,
      (_) => random.nextInt(256),
    );
    final key = base64UrlEncode(bytes);

    await _storage.write(key: keyName, value: key);
    return key;
  }
}

/// In-memory key store for tests and the development seed path.
///
/// Deliberately not const-constructible with a caller-supplied key: a fixed
/// key that leaked into production would silently make every database
/// readable by anyone holding this source.
class InMemoryKeyStore implements EncryptionKeyStore {
  String? _key;

  @override
  Future<String> getOrCreateKey() async => _key ??= base64UrlEncode(
    List<int>.generate(32, (_) => Random.secure().nextInt(256)),
  );
}
