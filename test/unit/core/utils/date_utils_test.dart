import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/utils/date_utils.dart';

void main() {
  group('encodeIsoDay', () {
    test('writes a fixed-width local date with no time', () {
      expect(encodeIsoDay(DateTime(2026, 9, 3, 23, 59)), '2026-09-03');
    });

    test('pads every field', () {
      expect(encodeIsoDay(DateTime(999, 1, 1)), '0999-01-01');
    });
  });

  group('decodeIsoDay', () {
    test('reads back what encodeIsoDay wrote, at local midnight', () {
      final day = DateTime(2026, 9, 3);

      expect(decodeIsoDay(encodeIsoDay(day)), day);
      expect(decodeIsoDay('2026-09-03').isUtc, isFalse);
    });

    test('round-trips every day of a leap year', () {
      for (
        var d = DateTime(2024);
        d.year == 2024;
        d = d.add(const Duration(days: 1))
      ) {
        final day = DateTime(d.year, d.month, d.day);
        expect(decodeIsoDay(encodeIsoDay(day)), day);
      }
    });

    test('refuses anything that is not YYYY-MM-DD', () {
      expect(() => decodeIsoDay('2026-09'), throwsFormatException);
      expect(() => decodeIsoDay('2026/09/03'), throwsFormatException);
      expect(() => decodeIsoDay('2026-09-03T00:00:00Z'), throwsFormatException);
      expect(() => decodeIsoDay('yyyy-mm-dd'), throwsFormatException);
    });
  });
}
