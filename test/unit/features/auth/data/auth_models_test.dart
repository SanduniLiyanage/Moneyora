import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/auth/data/models/lockout_state_model.dart';
import 'package:moneyora/features/auth/data/models/passcode_record.dart';
import 'package:moneyora/features/auth/domain/entities/lockout_state.dart';

void main() {
  group('PasscodeRecord', () {
    const record = PasscodeRecord(
      iterations: 100000,
      salt: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15],
      hash: [255, 254, 253, 252],
    );

    test('encodes as a PHC string with the parameters in it', () {
      expect(
        record.encode(),
        r'$pbkdf2-sha256$i=100000$AAECAwQFBgcICQoLDA0ODw==$//79/A==',
      );
    });

    test('round-trips', () {
      expect(PasscodeRecord.decode(record.encode()), record);
    });

    test('refuses what this app would not have written', () {
      for (final bad in [
        '',
        'plain',
        r'$sha256$i=1$AAAA$AAAA',
        r'$pbkdf2-sha256$AAAA$AAAA',
        r'$pbkdf2-sha256$i=x$AAAA$AAAA',
        r'$pbkdf2-sha256$i=0$AAAA$AAAA',
        r'$pbkdf2-sha256$i=1$AAAA',
        r'$pbkdf2-sha256$i=1$not base64!$AAAA',
      ]) {
        expect(
          () => PasscodeRecord.decode(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });

  group('LockoutStateModel', () {
    test('round-trips a count with no lockout', () {
      const state = LockoutState(failedAttempts: 3);
      expect(LockoutStateModel.encode(state), '{"failed":3,"until":null}');
      expect(LockoutStateModel.decode(LockoutStateModel.encode(state)), state);
    });

    test('round-trips a lockout, in UTC', () {
      final state = LockoutState(
        failedAttempts: 5,
        lockedUntil: DateTime.utc(2026, 9, 21, 9, 0, 30),
      );
      final back = LockoutStateModel.decode(LockoutStateModel.encode(state));
      expect(back, state);
      expect(back.lockedUntil!.isUtc, isTrue);
    });

    test('a local expiry comes back as the same instant', () {
      final local = DateTime(2026, 9, 21, 9, 0, 30);
      final back = LockoutStateModel.decode(
        LockoutStateModel.encode(
          LockoutState(failedAttempts: 5, lockedUntil: local),
        ),
      );
      expect(back.lockedUntil!.isAtSameMomentAs(local), isTrue);
    });

    test('refuses what this app would not have written', () {
      for (final bad in ['', '[]', '{"failed":"3"}', '{"failed":-1}', '{}']) {
        expect(
          () => LockoutStateModel.decode(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });
}
