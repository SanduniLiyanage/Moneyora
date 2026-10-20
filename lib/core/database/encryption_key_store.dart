import 'dart:convert';
import 'dart:math';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../errors/exceptions.dart';

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
  ///
  /// [mustExist] says data made with the key is already on the phone: a
  /// database file the caller found. Then a key that cannot be found is
  /// never replaced. The call throws [EncryptionException] and writes
  /// nothing, so the data stays as it is rather than being locked away for
  /// good under a new key. NFR-REL-002.
  Future<String> getOrCreateKey({bool mustExist = false});
}

/// What the app says when the key to data already on the phone cannot be
/// read. Shown on home, where a database that will not open is explained.
const String missingDatabaseKeyMessage =
    'Moneyora could not read the key that unlocks your data on this phone, '
    'so it has left your data as it is rather than start again without it. '
    'Restart the phone and open Moneyora again.';

/// Production key store, backed by the platform's hardware-backed keychain.
///
/// The key is generated once on first launch and never leaves the device.
/// It is not derived from a passcode: the passcode (FR-SET-005) gates access
/// to the *app*, and users change or remove it. Deriving the database key from
/// something the user can change would mean re-encrypting the entire database
/// on every passcode change, and losing all data if they forget it.
class SecureStorageKeyStore implements EncryptionKeyStore {
  /// Creates a key store over [storage], defaulting to [defaultStorage].
  SecureStorageKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? defaultStorage;

  final FlutterSecureStorage _storage;

  /// The platform keychain, read so that a failure to read never erases it.
  ///
  /// flutter_secure_storage's Android default, `resetOnError: true`,
  /// deletes **every** stored value the moment one cannot be decrypted —
  /// a Keystore hiccup after an OS update is enough. The database key
  /// would go with them, and nothing could open the database again. With
  /// it off, a failed read is an error, the key stays where it is, and the
  /// next launch can read it. Every other option is the plugin's default,
  /// so a key stored by an earlier version is found where it was.
  static const FlutterSecureStorage defaultStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(resetOnError: false),
  );

  /// Keychain / Keystore entry name. Changing this orphans every existing
  /// database, so treat it as permanent.
  static const String keyName = 'db_encryption_key';

  /// 256 bits, per NFR-SEC-001.
  static const int _keyLengthBytes = 32;

  @override
  Future<String> getOrCreateKey({bool mustExist = false}) async {
    final String? existing;
    try {
      existing = await _storage.read(key: keyName);
    } on PlatformException catch (e) {
      throw EncryptionException(missingDatabaseKeyMessage, cause: e);
    }
    if (existing != null && existing.isNotEmpty) return existing;
    // Data made with a key is on the phone and the key is not: a new one
    // would lock that data away for good (NFR-REL-002).
    if (mustExist) throw const EncryptionException(missingDatabaseKeyMessage);

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
  Future<String> getOrCreateKey({bool mustExist = false}) async {
    if (_key == null && mustExist) {
      throw const EncryptionException(missingDatabaseKeyMessage);
    }
    return _key ??= base64UrlEncode(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );
  }
}
