import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/domain/entities/account_totals.dart';

/// The arithmetic behind the one number at the top of the account list.
///
/// Worth its own file because two different exclusions meet here and mean
/// opposite things: an account the *user* left out (FR-ACC-002) and one the
/// *app* cannot yet add (FR-ACC-005, deferred by E-25). Conflating them either
/// nags about a setting the user chose, or silently hides that conversion is
/// missing.
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

  group('the total', () {
    test('adds up accounts in the base currency', () {
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(balanceCents: 40050),
      ]);

      expect(totals.totalCents, 165050);
      expect(totals.baseCurrency, 'LKR');
    });

    test('is zero, not an error, when there is nothing to add', () {
      final totals = AccountTotals.from(const <Account>[]);

      expect(totals.totalCents, 0);
      expect(totals.hasExcludedForeign, isFalse);
    });

    test('subtracts a credit card that is owing', () {
      // A negative balance is ordinary for a credit card, unlike a transaction
      // amount, which never is. It has to pull the total down.
      final totals = AccountTotals.from([
        account(balanceCents: 200000),
        account(name: 'Visa', balanceCents: -75000),
      ]);

      expect(totals.totalCents, 125000);
    });

    test('matches the base currency whatever case it is stored in', () {
      final totals = AccountTotals.from([
        account(balanceCents: 100, currency: 'lkr'),
      ], baseCurrency: 'LKR');

      expect(totals.totalCents, 100);
      expect(totals.excludedForeignCount, 0);
    });

    test('reports the base currency it was asked for, normalised', () {
      final totals = AccountTotals.from(const <Account>[], baseCurrency: 'usd');

      expect(totals.baseCurrency, 'USD');
    });
  });

  group('what is left out', () {
    test('an archived account counts for nothing', () {
      // FR-ACC-004 hides it from active views. A hidden account contributing
      // to a visible total is the worst of both.
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(name: 'Old bank', balanceCents: 999999, isArchived: true),
      ]);

      expect(totals.totalCents, 125000);
      expect(totals.hasExcludedForeign, isFalse);
    });

    test('an account the user excluded is not added', () {
      // FR-ACC-002's Include-in-Total toggle.
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(name: 'Household', balanceCents: 500000, includeInTotal: false),
      ]);

      expect(totals.totalCents, 125000);
    });

    test('a foreign-currency account is excluded and counted', () {
      // E-25: without conversion there is no honest way to add USD to LKR, so
      // it is left out and the count lets the screen say so.
      final totals = AccountTotals.from([
        account(balanceCents: 125000),
        account(name: 'PayPal', balanceCents: 30000, currency: 'USD'),
      ]);

      expect(totals.totalCents, 125000);
      expect(totals.excludedForeignCount, 1);
      expect(totals.hasExcludedForeign, isTrue);
    });

    test('several foreign accounts are counted, not summed', () {
      // Summing them would mean adding USD to EUR, which is the same mistake
      // one level down.
      final totals = AccountTotals.from([
        account(name: 'PayPal', balanceCents: 30000, currency: 'USD'),
        account(name: 'Wise', balanceCents: 40000, currency: 'EUR'),
      ]);

      expect(totals.totalCents, 0);
      expect(totals.excludedForeignCount, 2);
    });

    test(
      'a foreign account the user already excluded raises no currency note',
      () {
        // The distinction this class exists for. The user chose to leave it
        // out, so it is not evidence that conversion is missing, and telling
        // them the app cannot convert it answers a question nobody asked.
        final totals = AccountTotals.from([
          account(balanceCents: 125000),
          account(
            name: 'PayPal',
            balanceCents: 30000,
            currency: 'USD',
            includeInTotal: false,
          ),
        ]);

        expect(totals.totalCents, 125000);
        expect(totals.excludedForeignCount, 0);
        expect(totals.hasExcludedForeign, isFalse);
      },
    );

    test('an archived foreign account raises no currency note either', () {
      final totals = AccountTotals.from([
        account(
          name: 'Closed USD',
          balanceCents: 30000,
          currency: 'USD',
          isArchived: true,
        ),
      ]);

      expect(totals.excludedForeignCount, 0);
    });
  });

  test('two totals of the same figures are equal', () {
    // Equatable, so a rebuild with unchanged accounts is not a state change.
    expect(
      AccountTotals.from([account(balanceCents: 100)]),
      AccountTotals.from([account(balanceCents: 100)]),
    );
  });
}
