@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/receipt_scanner/data/datasources/receipt_image_vault.dart';
import 'package:path/path.dart' as p;

/// A key store that can be made to fail, for the one path where the
/// vault cannot even start.
class _KeyStore implements EncryptionKeyStore {
  _KeyStore([this.key = 'the-database-key']);

  String key;
  bool fail = false;

  @override
  Future<String> getOrCreateKey() async {
    if (fail) throw Exception('keychain unavailable');
    return key;
  }
}

void main() {
  late Directory root;
  late Directory documents;
  late Directory temporary;
  late Directory cache;
  late _KeyStore keyStore;
  late EncryptedReceiptImageVault vault;

  /// A "photo": any bytes, since nothing here decodes an image.
  final photo = Uint8List.fromList([
    0xFF, 0xD8, 0xFF, 0xE0, //
    for (var i = 0; i < 5000; i++) i % 251,
    0xFF, 0xD9,
  ]);

  setUp(() {
    root = Directory.systemTemp.createTempSync('moneyora_vault');
    documents = Directory(p.join(root.path, 'Documents'))..createSync();
    temporary = Directory(p.join(root.path, 'tmp'))..createSync();
    cache = Directory(p.join(root.path, 'picker'))..createSync();
    keyStore = _KeyStore();
    vault = EncryptedReceiptImageVault(
      keyStore: keyStore,
      documents: () async => documents,
      temporary: () async => temporary,
    );
  });

  tearDown(() => root.deleteSync(recursive: true));

  File picked([String name = 'receipt.jpg']) =>
      File(p.join(cache.path, name))..writeAsBytesSync(photo);

  group('keep', () {
    test('writes an encrypted copy under Documents/receipts and leaves '
        'the source alone', () async {
      final source = picked();

      final kept = await vault.keep(source.path);

      expect(p.dirname(kept), p.join(documents.path, 'receipts'));
      expect(p.basename(kept), endsWith('.jpg.enc'));
      expect(vault.holds(kept), isTrue);
      expect(source.existsSync(), isTrue);

      final sealed = File(kept).readAsBytesSync();
      expect(sealed.sublist(0, 4), EncryptedReceiptImageVault.magic);
      // Not the photo, and not the photo somewhere inside either.
      expect(sealed, isNot(equals(photo)));
      expect(_contains(sealed, photo.sublist(100, 200)), isFalse);
    });

    test('two keeps of the same photo are two files with different '
        'bytes', () async {
      final source = picked();

      final first = await vault.keep(source.path);
      final second = await vault.keep(source.path);

      expect(first, isNot(second));
      expect(
        File(first).readAsBytesSync(),
        isNot(equals(File(second).readAsBytesSync())),
      );
    });

    test('a source that is gone is a CacheException in the history\'s '
        'words', () async {
      expect(
        () => vault.keep(p.join(cache.path, 'gone.jpg')),
        throwsA(
          isA<CacheException>().having(
            (e) => e.message,
            'message',
            'The photo is no longer on this phone.',
          ),
        ),
      );
    });

    test('a key store that fails is an EncryptionException, and the next '
        'attempt asks again', () async {
      keyStore.fail = true;
      await expectLater(
        () => vault.keep(picked().path),
        throwsA(isA<EncryptionException>()),
      );

      keyStore.fail = false;
      final kept = await vault.keep(picked().path);
      expect(await vault.read(kept), photo);
    });
  });

  group('read', () {
    test('gives the photo back from a kept file', () async {
      final kept = await vault.keep(picked().path);

      expect(await vault.read(kept), photo);
    });

    test('gives a file the vault did not write back as it is', () async {
      final source = picked();

      expect(vault.holds(source.path), isFalse);
      expect(await vault.read(source.path), photo);
    });

    test('a file that is gone is null', () async {
      expect(await vault.read(p.join(documents.path, 'x.jpg.enc')), isNull);
    });

    test('a kept file read under another key will not open', () async {
      final kept = await vault.keep(picked().path);

      final other = EncryptedReceiptImageVault(
        keyStore: _KeyStore('a-different-key'),
        documents: () async => documents,
        temporary: () async => temporary,
      );
      expect(
        () => other.read(kept),
        throwsA(
          isA<EncryptionException>().having(
            (e) => e.message,
            'message',
            'The receipt photo could not be unlocked.',
          ),
        ),
      );
    });

    test('a kept file with one byte altered will not open', () async {
      final kept = await vault.keep(picked().path);
      final file = File(kept);
      final bytes = file.readAsBytesSync();
      bytes[bytes.length ~/ 2] ^= 0x01;
      file.writeAsBytesSync(bytes);

      expect(() => vault.read(kept), throwsA(isA<EncryptionException>()));
    });

    test('a .enc file that is not the vault\'s format is refused, not '
        'decoded', () async {
      final stray = File(p.join(documents.path, 'stray.jpg.enc'))
        ..writeAsBytesSync([1, 2, 3]);

      expect(
        () => vault.read(stray.path),
        throwsA(
          isA<EncryptionException>().having(
            (e) => e.message,
            'message',
            'That is not a kept receipt photo.',
          ),
        ),
      );
    });
  });

  group('withPlainCopy', () {
    test('hands the body a plain file in the temporary directory with the '
        'photo\'s own extension, and deletes it after', () async {
      final kept = await vault.keep(picked().path);
      String? seen;

      final result = await vault.withPlainCopy(kept, (plain) async {
        seen = plain;
        expect(p.dirname(plain), temporary.path);
        expect(p.extension(plain), '.jpg');
        expect(File(plain).readAsBytesSync(), photo);
        return 'read';
      });

      expect(result, 'read');
      expect(File(seen!).existsSync(), isFalse);
    });

    test('deletes the copy even when the body throws', () async {
      final kept = await vault.keep(picked().path);
      String? seen;

      await expectLater(
        () => vault.withPlainCopy(kept, (plain) async {
          seen = plain;
          throw const OcrException('nothing legible');
        }),
        throwsA(isA<OcrException>()),
      );

      expect(File(seen!).existsSync(), isFalse);
      expect(temporary.listSync(), isEmpty);
    });

    test('a kept file that is gone is a CacheException', () async {
      expect(
        () => vault.withPlainCopy(
          p.join(documents.path, 'gone.jpg.enc'),
          (_) async => 'never',
        ),
        throwsA(isA<CacheException>()),
      );
    });
  });
}

/// Whether [needle] occurs anywhere in [haystack].
bool _contains(List<int> haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}
