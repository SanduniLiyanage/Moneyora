@TestOn('vm')
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/features/backup/data/datasources/backup_codec.dart';

/// The `.mora` envelope against the real cipher and the real KDF, at a
/// work factor the VM can afford.
void main() {
  const codec = BackupCodec(iterations: 1000);
  const contents = <String, Object?>{
    'app': 'moneyora',
    'tables': {
      'users': [
        {'id': 1, 'currency': 'LKR'},
      ],
    },
  };

  test('opens what it sealed, with the same password', () async {
    final sealed = await codec.seal(contents, 'a long password');

    expect(await codec.open(sealed, 'a long password'), contents);
  });

  test(
    'carries its work factor, so a file outlives a raised default',
    () async {
      final sealed = await codec.seal(contents, 'a long password');

      expect(ByteData.sublistView(sealed, 5, 9).getUint32(0), 1000);
      // A codec with a different default still opens it.
      expect(
        await const BackupCodec(iterations: 5).open(sealed, 'a long password'),
        contents,
      );
    },
  );

  test('two seals of the same contents differ', () async {
    // A fresh salt and nonce each time: nothing about one backup says
    // anything about another made from the same data.
    final a = await codec.seal(contents, 'a long password');
    final b = await codec.seal(contents, 'a long password');

    expect(a, isNot(b));
  });

  test('refuses the wrong password in a sentence', () async {
    final sealed = await codec.seal(contents, 'a long password');

    await expectLater(
      codec.open(sealed, 'another password'),
      throwsA(
        isA<EncryptionException>().having(
          (e) => e.message,
          'message',
          'That password does not open this backup.',
        ),
      ),
    );
  });

  test('refuses a file altered after sealing', () async {
    final sealed = await codec.seal(contents, 'a long password');
    sealed[sealed.length - 20] ^= 0x01;

    await expectLater(
      codec.open(sealed, 'a long password'),
      throwsA(isA<EncryptionException>()),
    );
  });

  test('refuses what is not a backup, and a format it does not know', () async {
    await expectLater(
      codec.open(Uint8List.fromList(List.filled(80, 7)), 'x'),
      throwsA(
        isA<CacheException>().having(
          (e) => e.message,
          'message',
          'That file is not a Moneyora backup.',
        ),
      ),
    );

    final future = await codec.seal(contents, 'a long password');
    future[4] = BackupCodec.formatVersion + 1;
    await expectLater(
      codec.open(future, 'a long password'),
      throwsA(
        isA<CacheException>().having(
          (e) => e.message,
          'message',
          contains('newer version of Moneyora'),
        ),
      ),
    );
  });
}
