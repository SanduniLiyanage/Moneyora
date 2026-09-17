import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/ports/conversion_table.dart';
import 'package:moneyora/core/ports/exchange_rate.dart';

/// The lookup every total goes through. E-34 fixes the fallback: no rate to
/// the base is null, not zero and not an error.
void main() {
  final when = DateTime(2026, 9, 17);

  ExchangeRate rate(String from, String to, int micros) => ExchangeRate(
    fromCurrency: from,
    toCurrency: to,
    rateMicros: micros,
    updatedAt: when,
  );

  final table = ConversionTable(
    baseCurrency: 'LKR',
    rates: [rate('USD', 'LKR', 300000000), rate('LKR', 'USD', 3333)],
  );

  group('toBase', () {
    test('a base-currency balance needs no rate', () {
      expect(table.toBase(12345, 'LKR'), 12345);
      expect(table.toBase(12345, ' lkr '), 12345);
      expect(const ConversionTable(baseCurrency: 'LKR').toBase(5, 'LKR'), 5);
    });

    test('converts at the rate to the base', () {
      expect(table.toBase(1000, 'USD'), 300000);
      expect(table.toBase(1000, 'usd'), 300000);
    });

    test('null when there is no rate to the base', () {
      // A rate *from* the base is not a rate *to* it; E-34 keys by pair and
      // does not invert, because the bank's two rates are not reciprocals.
      final onlyAway = ConversionTable(
        baseCurrency: 'USD',
        rates: [rate('USD', 'LKR', 300000000)],
      );
      expect(onlyAway.toBase(1000, 'LKR'), isNull);
      expect(table.toBase(1000, 'EUR'), isNull);
    });
  });

  test('rateFor finds the ordered pair only', () {
    expect(
      table.rateFor(fromCurrency: 'USD', toCurrency: 'LKR')?.rateMicros,
      300000000,
    );
    expect(
      table.rateFor(fromCurrency: 'lkr', toCurrency: 'usd')?.rateMicros,
      3333,
    );
    expect(table.rateFor(fromCurrency: 'EUR', toCurrency: 'LKR'), isNull);
  });

  test('is a value', () {
    expect(
      const ConversionTable(baseCurrency: 'LKR'),
      const ConversionTable(baseCurrency: 'LKR'),
    );
    expect(
      const ConversionTable(baseCurrency: 'LKR'),
      isNot(const ConversionTable(baseCurrency: 'USD')),
    );
  });
}
