import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/ports/conversion_table.dart';
import 'package:moneyora/core/ports/exchange_rate.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/domain/entities/account_totals.dart';

/// The arithmetic behind the one number at the top of the account list.
///
/// Worth its own file because two different exclusions meet here and mean
/// opposite things: an account the *user* left out (FR-ACC-002) and one the
/// *app* has no rate for (FR-ACC-005, E-34). Conflating them either nags
/// about a setting the user chose, or silently hides that a rate is missing.
void main() {
  Account account({
    int? id,
    String name = 'Cash',
    int balanceCents = 0,
    String currency = 'LKR',
    bool includeInTotal = true,
    bool isArchived = false,
  }) => Account(
    id: id,
    name: name,
    icon: 'wallet',
    initialBalanceDate: DateTime(2026),
    currency: currency,
    currentBalanceCents: balanceCents,
    includeInTotal: includeInTotal,
    isArchived: isArchived,
  );

  ExchangeRate rate(String from, String to, int micros) => ExchangeRate(
    fromCurrency: from,
    toCurrency: to,
    rateMicros: micros,
    updatedAt: DateTime(2026, 9, 17),
  );

  const noRates = ConversionTable(baseCurrency: 'LKR');
  final usdToLkr = ConversionTable(
    baseCurrency: 'LKR',
    rates: [rate('USD', 'LKR', 300000000)],
  );

  group('the total', () {
    test('adds up accounts in the base currency', () {
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(balanceCents: 40050),
      ], noRates);

      expect(totals.totalCents, 165050);
      expect(totals.baseCurrency, 'LKR');
    });

    test('is zero, not an error, when there is nothing to add', () {
      final totals = AccountTotals.from(const <Account>[], noRates);

      expect(totals.totalCents, 0);
      expect(totals.hasUnconverted, isFalse);
    });

    test('subtracts a credit card that is owing', () {
      // A negative balance is ordinary for a credit card, unlike a transaction
      // amount, which never is. It has to pull the total down.
      final totals = AccountTotals.from([
        account(balanceCents: 200000),
        account(name: 'Visa', balanceCents: -75000),
      ], noRates);

      expect(totals.totalCents, 125000);
    });

    test('matches the base currency whatever case it is stored in', () {
      final totals = AccountTotals.from([
        account(balanceCents: 100, currency: 'lkr'),
      ], noRates);

      expect(totals.totalCents, 100);
      expect(totals.hasUnconverted, isFalse);
    });

    test('is expressed in whatever base the user chose', () {
      final totals = AccountTotals.from([
        account(balanceCents: 100, currency: 'USD'),
      ], const ConversionTable(baseCurrency: 'USD'));

      expect(totals.baseCurrency, 'USD');
      expect(totals.totalCents, 100);
    });

    test('an account the user excluded is not added', () {
      // FR-ACC-002's Include-in-Total toggle.
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(name: 'Household', balanceCents: 500000, includeInTotal: false),
      ], noRates);

      expect(totals.totalCents, 125000);
    });
  });

  group('conversion', () {
    test('a foreign account with a rate is converted and counted in', () {
      // FR-ACC-005: $300.00 at 300 LKR/USD is Rs 90,000.00.
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(name: 'PayPal', balanceCents: 30000, currency: 'USD'),
      ], usdToLkr);

      expect(totals.totalCents, 125000 + 9000000);
      expect(totals.unconvertedCount, 0);
      expect(totals.hasUnconverted, isFalse);
    });

    test('a foreign card that is owing pulls the total down, converted', () {
      final totals = AccountTotals.from([
        account(name: 'USD card', balanceCents: -1000, currency: 'USD'),
      ], usdToLkr);

      expect(totals.totalCents, -300000);
    });

    test('a foreign account with no rate is left out and counted', () {
      // E-34 keeps E-25's behaviour as the fallback: without a rate there is
      // no honest way to add EUR to LKR, so it is left out and the count
      // lets the screen say so and say what would include it.
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(name: 'Wise', balanceCents: 40000, currency: 'EUR'),
      ], usdToLkr);

      expect(totals.totalCents, 125000);
      expect(totals.unconvertedCount, 1);
      expect(totals.hasUnconverted, isTrue);
    });

    test('a rate away from the base is not a rate to it', () {
      // E-34 keys by pair and never inverts: the bank's two rates are not
      // reciprocals, so LKR→USD says nothing about USD→LKR.
      final onlyAway = ConversionTable(
        baseCurrency: 'LKR',
        rates: [rate('LKR', 'USD', 3333)],
      );
      final totals = AccountTotals.from([
        account(name: 'PayPal', balanceCents: 30000, currency: 'USD'),
      ], onlyAway);

      expect(totals.totalCents, 0);
      expect(totals.unconvertedCount, 1);
    });

    test('several unconverted accounts are counted, not summed', () {
      // Summing them would mean adding USD to EUR, which is the same mistake
      // one level down.
      final totals = AccountTotals.from([
        account(name: 'PayPal', balanceCents: 30000, currency: 'USD'),
        account(name: 'Wise', balanceCents: 40000, currency: 'EUR'),
      ], noRates);

      expect(totals.totalCents, 0);
      expect(totals.unconvertedCount, 2);
    });

    test('a foreign account the user already excluded raises no rate note', () {
      // The distinction this class exists for. The user chose to leave it
      // out, so it is not evidence that a rate is missing, and telling them
      // to add one answers a question nobody asked.
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(
          name: 'PayPal',
          balanceCents: 30000,
          currency: 'USD',
          includeInTotal: false,
        ),
      ], noRates);

      expect(totals.totalCents, 125000);
      expect(totals.unconvertedCount, 0);
      expect(totals.hasUnconverted, isFalse);
    });

    test('an archived foreign account raises no rate note either', () {
      final totals = AccountTotals.from([
        account(
          name: 'Closed USD',
          balanceCents: 30000,
          currency: 'USD',
          isArchived: true,
        ),
      ], noRates);

      expect(totals.unconvertedCount, 0);
    });
  });

  test('two totals of the same figures are equal', () {
    expect(
      AccountTotals.from([account(balanceCents: 100)], noRates),
      AccountTotals.from([account(balanceCents: 100)], noRates),
    );
  });
}
