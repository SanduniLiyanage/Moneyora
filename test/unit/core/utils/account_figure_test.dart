import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/ports/account_type.dart';
import 'package:moneyora/core/utils/account_figure.dart';
import 'package:moneyora/core/utils/currency_utils.dart';

/// What a row shows for an account: its balance, or, for a credit card
/// with a limit, what is left to spend. E-46.
void main() {
  const lkr = CurrencyFormat.lkr;

  AccountFigure card({int? limit = 5000000, int balance = 0}) =>
      AccountFigure.of(
        type: AccountType.creditCard,
        balanceCents: balance,
        creditLimitCents: limit,
      );

  group('a credit card with a limit', () {
    test('unused, shows the whole limit, not a balance of nothing', () {
      final figure = card();

      expect(figure.cents, 5000000);
      expect(figure.isAvailableCredit, isTrue);
      expect(figure.amount(lkr), 'Rs50,000.00');
      expect(figure.caption(lkr), 'Available · nothing owed');
      expect(figure.label(lkr), 'Rs50,000.00 available');
      expect(figure.summary(lkr), 'Rs50,000.00 available · nothing owed');
    });

    test('owing, shows the limit less what is owed', () {
      final figure = card(balance: -1250000);

      expect(figure.cents, 3750000);
      expect(figure.owedCents, 1250000);
      expect(figure.caption(lkr), 'Available · owed Rs12,500.00');
      expect(figure.summary(lkr), 'Rs37,500.00 available · owed Rs12,500.00');
    });

    test('over the limit, says by how much', () {
      final figure = card(limit: 1000000, balance: -1200000);

      expect(figure.cents, -200000);
      expect(figure.amount(lkr), '-Rs2,000.00');
      expect(figure.label(lkr), 'Rs2,000.00 over the limit');
      expect(figure.caption(lkr), 'Over the limit · owed Rs12,000.00');
    });

    test('in credit owes nothing, as on Credit cards (E-43)', () {
      final figure = card(balance: 30000);

      expect(figure.cents, 5000000);
      expect(figure.owedCents, 0);
    });

    test('in another currency, says so in it', () {
      final figure = card(balance: -1000);

      expect(
        figure.label(CurrencyFormat.forCode('USD')),
        'USD 49,990.00 available',
      );
    });
  });

  group('everything else shows its balance', () {
    test('a card with no limit entered', () {
      final figure = card(limit: null, balance: -75000);

      expect(figure.cents, -75000);
      expect(figure.isAvailableCredit, isFalse);
      expect(figure.caption(lkr), isNull);
      expect(figure.label(lkr), '-Rs750.00');
      expect(figure.summary(lkr), '-Rs750.00');
    });

    test('an account of another type, whatever limit it is handed', () {
      // E-43 clears a card's terms when its type changes; a stray limit is
      // still not credit on cash.
      final figure = AccountFigure.of(
        type: AccountType.cash,
        balanceCents: 125000,
        creditLimitCents: 5000000,
      );

      expect(figure.cents, 125000);
      expect(figure.summary(lkr), 'Rs1,250.00');
    });
  });
}
