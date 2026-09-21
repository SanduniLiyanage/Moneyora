import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/auth/data/datasources/pin_hasher.dart';
import 'package:moneyora/features/auth/data/models/passcode_record.dart';

/// The derivation, at a count small enough to run in a test but through the
/// same isolate path the app uses.
void main() {
  final hasher = Pbkdf2PinHasher(iterations: 1000, random: Random(7));

  test('a record carries its parameters and not the PIN', () async {
    final record = await hasher.hash('1234');

    expect(record.iterations, 1000);
    expect(record.salt, hasLength(Pbkdf2PinHasher.saltLength));
    expect(record.hash, hasLength(Pbkdf2PinHasher.hashLength));
    expect(record.encode(), isNot(contains('1234')));
  });

  test('the same PIN twice gives two different records', () async {
    final a = await hasher.hash('1234');
    final b = await hasher.hash('1234');

    expect(a.salt, isNot(equals(b.salt)));
    expect(a.hash, isNot(equals(b.hash)));
  });

  test('matches the PIN it was made from and nothing else', () async {
    final record = await hasher.hash('1234');

    expect(await hasher.matches('1234', record), isTrue);
    expect(await hasher.matches('1235', record), isFalse);
    expect(await hasher.matches('12345', record), isFalse);
    expect(await hasher.matches('', record), isFalse);
  });

  test('verifies under the record\'s count, not the hasher\'s', () async {
    // A record derived at one count must still verify after the default is
    // raised: the count is read from the record.
    final old = await Pbkdf2PinHasher(iterations: 500).hash('4321');
    final raised = Pbkdf2PinHasher(iterations: 2000);

    expect(await raised.matches('4321', old), isTrue);
    expect(await raised.matches('1234', old), isFalse);
  });

  test('a known vector', () async {
    // PBKDF2-HMAC-SHA256("password", "salt", 1, 32) from RFC 7914 §11 —
    // the record format round-trips the bytes of a published test vector.
    const record = PasscodeRecord(
      iterations: 1,
      salt: [0x73, 0x61, 0x6c, 0x74],
      hash: [
        0x12, 0x0f, 0xb6, 0xcf, 0xfc, 0xf8, 0xb3, 0x2c, //
        0x43, 0xe7, 0x22, 0x52, 0x56, 0xc4, 0xf8, 0x37,
        0xa8, 0x65, 0x48, 0xc9, 0x2c, 0xcc, 0x35, 0x48,
        0x08, 0x05, 0x98, 0x7c, 0xb7, 0x0b, 0xe1, 0x7b,
      ],
    );

    expect(await hasher.matches('password', record), isTrue);
  });
}
