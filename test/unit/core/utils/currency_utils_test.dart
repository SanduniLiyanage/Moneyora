import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/utils/currency_utils.dart';

/// This is the only file allowed to turn integer cents into text, so it is the
/// only place a formatting bug can live — and a formatting bug in a finance
/// app means someone reads the wrong number and acts on it.
void main() {
  group('formatCents', () {
    test('formats a plain amount', () {
      expect(formatCents(125050), 'Rs1,250.50');
    });

    test('always shows two decimal places', () {
      // Rs5 and Rs5.00 in the same list read as different precisions and
      // invite a second look at nothing.
      expect(formatCents(50000), 'Rs500.00');
      expect(formatCents(500), 'Rs5.00');
    });

    test('pads a fraction below ten', () {
      // The bug this catches: 5 cents rendering as ".5", so Rs1.05 becomes
      // Rs1.5 — a tenfold error that looks entirely plausible.
      expect(formatCents(105), 'Rs1.05');
      expect(formatCents(100), 'Rs1.00');
    });

    test('groups thousands', () {
      expect(formatCents(100000), 'Rs1,000.00');
      expect(formatCents(100000000), 'Rs1,000,000.00');
      expect(formatCents(99999), 'Rs999.99');
    });

    test('puts the sign before the symbol', () {
      // 'Rs-500.00' reads as a typo.
      expect(formatCents(-50000), '-Rs500.00');
    });

    test('handles zero', () {
      expect(formatCents(0), 'Rs0.00');
    });

    test('omits the symbol on request', () {
      // For the keypad and chart labels, where the currency is already stated.
      expect(formatCents(125050, showSymbol: false), '1,250.50');
    });

    test('handles amounts past the scalability ceiling without overflow', () {
      // SRS §5.6 tolerates 100,000 transactions. Dart ints are 64-bit, so the
      // real ceiling is far higher — worth asserting, because a currency with
      // no minor unit and a large balance is where naive code overflows.
      expect(formatCents(999999999999), 'Rs9,999,999,999.99');
    });
  });

  group('parseToCents', () {
    test('parses a decimal amount', () {
      expect(parseToCents('1250.50'), 125050);
    });

    test('parses a whole number', () {
      expect(parseToCents('500'), 50000);
    });

    test('tolerates grouping, symbol and spaces', () {
      // People paste amounts. All three of these should mean the same thing.
      expect(parseToCents('Rs1,250.50'), 125050);
      expect(parseToCents('1,250.50'), 125050);
      expect(parseToCents(' Rs 1250.50 '), 125050);
    });

    test('rounds rather than truncating a third decimal', () {
      // Truncation loses a cent on every such entry, always downward, which
      // is exactly the kind of one-way drift nobody notices for months.
      expect(parseToCents('10.005'), 1001);
      expect(parseToCents('10.004'), 1000);
    });

    test('returns null for text that is not a number', () {
      // Deliberately not zero. An unparseable amount silently becoming 0 is a
      // transaction that looks saved and is wrong.
      expect(parseToCents('abc'), isNull);
      expect(parseToCents(''), isNull);
      expect(parseToCents('   '), isNull);
    });

    test('round-trips through formatCents', () {
      for (final cents in [0, 1, 99, 100, 12345, 999999999]) {
        expect(
          parseToCents(formatCents(cents)),
          cents,
          reason: 'round trip failed for $cents',
        );
      }
    });
  });

  group('CurrencyFormat', () {
    test('LKR has two decimal places', () {
      expect(CurrencyFormat.lkr.code, 'LKR');
      expect(CurrencyFormat.lkr.minorUnitsPerMajor, 100);
    });

    test('supports a zero-decimal currency', () {
      // FR-ACC-005 requires multi-currency accounts, and not every currency
      // has minor units — JPY does not.
      const yen = CurrencyFormat(code: 'JPY', symbol: '¥', decimalDigits: 0);
      expect(formatCents(1250, currency: yen), '¥1,250');
      expect(parseToCents('1250', currency: yen), 1250);
    });
  });
}
