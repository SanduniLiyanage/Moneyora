import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
import 'package:moneyora/core/errors/exceptions.dart';

/// The key the database opens with, kept across updates and never
/// replaced over data already on the phone. NFR-SEC-001, NFR-REL-002.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const name = SecureStorageKeyStore.keyName;

  group('the keychain is read so a failure never erases it', () {
    test('a read that fails is an error, not a wiped keychain', () {
      // The plugin's Android default deletes every stored value when one
      // cannot be decrypted, the database key with them.
      final options = SecureStorageKeyStore.defaultStorage.aOptions.toMap();

      expect(options['resetOnError'], 'false');
    });

    test('and every other option is the default, so a key stored by an '
        'earlier version is found where it was', () {
      final ours = {...SecureStorageKeyStore.defaultStorage.aOptions.toMap()}
        ..remove('resetOnError');
      final theirs = {...AndroidOptions.defaultOptions.toMap()}
        ..remove('resetOnError');

      expect(ours, theirs);
    });
  });

  group('SecureStorageKeyStore', () {
    test('a first launch makes a key, and keeps returning it', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final store = SecureStorageKeyStore();

      final first = await store.getOrCreateKey();
      final second = await store.getOrCreateKey(mustExist: true);

      expect(first, isNotEmpty);
      expect(second, first);
      expect(await const FlutterSecureStorage().read(key: name), first);
    });

    test('a key already there is the one returned, data or not', () async {
      FlutterSecureStorage.setMockInitialValues({name: 'kept since 1.0.0'});

      expect(
        await SecureStorageKeyStore().getOrCreateKey(mustExist: true),
        'kept since 1.0.0',
      );
    });

    test('with data on the phone and no key, refuses, and writes no new '
        'one', () async {
      FlutterSecureStorage.setMockInitialValues({});

      await expectLater(
        SecureStorageKeyStore().getOrCreateKey(mustExist: true),
        throwsA(
          isA<EncryptionException>().having(
            (e) => e.message,
            'message',
            missingDatabaseKeyMessage,
          ),
        ),
      );
      expect(await const FlutterSecureStorage().read(key: name), isNull);
    });
  });

  test('the in-memory store refuses the same way', () async {
    await expectLater(
      InMemoryKeyStore().getOrCreateKey(mustExist: true),
      throwsA(isA<EncryptionException>()),
    );
  });
}
