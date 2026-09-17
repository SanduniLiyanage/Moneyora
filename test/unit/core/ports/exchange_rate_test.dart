import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/ports/exchange_rate.dart';

/// The arithmetic FR-ACC-005's totals depend on. E-34 fixes the scale at
/// 10⁶ and the rounding at nearest-cent, halves away from zero; these are
/// the cases where getting either wrong would still look plausible.
void main() {
  final when = DateTime(2026, 9, 17);

  ExchangeRate rate(int micros, {String from = 'USD', String to = 'LKR'}) =>
      ExchangeRate(
        fromCurrency: from,
        toCurrency: to,
        rateMicros: micros,
        updatedAt: when,
      );

  group('convert', () {
    test('multiplies at the scaled rate', () {
      // USD 10.00 at 300.25 LKR/USD.
      expect(rate(300250000).convert(1000), 300250);
    });

    test('rounds to the nearest cent', () {
      // 1 cent at 0.5 → 0.5 cents → rounds away from zero, to 1.
      expect(rate(500000).convert(1), 1);
      // 1 cent at 0.4 → 0.
      expect(rate(400000).convert(1), 0);
      // 3 cents at 0.5 → 1.5 → 2.
      expect(rate(500000).convert(3), 2);
    });

    test('keeps the sign, halves away from zero either way', () {
      // A card owing dollars owes rupees.
      expect(rate(300000000).convert(-1000), -300000);
      expect(rate(500000).convert(-1), -1);
      expect(rate(500000).convert(-3), -2);
    });

    test('a tiny rate does not vanish', () {
      // LKR → USD at 0.003331: Rs 1,000,000.00 → $3,331.00.
      expect(rate(3331, from: 'LKR', to: 'USD').convert(100000000), 333100);
    });

    test('does not overflow a large balance at a large rate', () {
      // Rs 90 trillion in cents at a rate of 300 would overflow a 64-bit
      // multiply; the product is taken over BigInt.
      const cents = 9000000000000000;
      expect(rate(300000000).convert(cents), cents * 300);
    });

    test('zero is zero', () {
      expect(rate(300000000).convert(0), 0);
    });
  });

  test('rate is the scaled value, for display', () {
    expect(rate(300250000).rate, 300.25);
  });

  test('is a value', () {
    expect(rate(1), rate(1));
    expect(rate(1), isNot(rate(2)));
  });
}
