import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'gemini_remote_datasource.dart';

/// The Copilot's API key, in the platform keychain and nowhere else.
///
/// Non-negotiable #3: the key is never a Dart constant, never an asset, never
/// a committed `.env`. It reaches the device once, typed by the person who
/// owns it, and lives in the same hardware-backed store as the database key.
///
/// Deleting the key disables the Copilot and nothing else — which is the point
/// of it being optional (NFR-REL-004).
class SecureLlmApiKeyStore implements LlmApiKeyStore {
  /// Creates a store over [storage], defaulting to platform secure storage.
  SecureLlmApiKeyStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// Keychain / Keystore entry name.
  static const String keyName = 'gemini_api_key';

  @override
  Future<String?> read() => _storage.read(key: keyName);

  @override
  Future<void> write(String key) =>
      _storage.write(key: keyName, value: key.trim());

  @override
  Future<void> clear() => _storage.delete(key: keyName);
}

/// In-memory key store for tests and for a debug build with no keychain.
class InMemoryLlmApiKeyStore implements LlmApiKeyStore {
  /// Creates a store, optionally pre-loaded with [key].
  InMemoryLlmApiKeyStore([this._key]);

  String? _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String key) async => _key = key.trim();

  @override
  Future<void> clear() async => _key = null;
}
