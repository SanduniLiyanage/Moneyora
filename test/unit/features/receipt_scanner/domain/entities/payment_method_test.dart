import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/payment_method.dart';

const cash = AccountOption(id: 1, name: 'Cash', balanceCents: 0);
const bank = AccountOption(
  id: 2,
  name: 'BOC current',
  type: AccountType.bank,
  balanceCents: 0,
);
const visa = AccountOption(
  id: 3,
  name: 'Visa',
  type: AccountType.creditCard,
  balanceCents: 0,
);
const master = AccountOption(
  id: 4,
  name: 'Master',
  type: AccountType.creditCard,
  balanceCents: 0,
);
const wallet = AccountOption(
  id: 5,
  name: 'FriMi',
  type: AccountType.digitalWallet,
  balanceCents: 0,
);

void main() {
  group('PaymentMethod.defaultAccount', () {
    test('cash is the first cash account', () {
      expect(PaymentMethod.cash.defaultAccount([bank, cash]), 1);
    });

    test('card is the first credit card, before any bank account', () {
      expect(PaymentMethod.card.defaultAccount([cash, bank, master, visa]), 4);
    });

    test('card falls back to a bank account when there is no card', () {
      expect(PaymentMethod.card.defaultAccount([cash, bank]), 2);
    });

    test('null when no account is of a matching kind', () {
      expect(PaymentMethod.card.defaultAccount([cash, wallet]), isNull);
      expect(PaymentMethod.cash.defaultAccount([bank, visa]), isNull);
      expect(PaymentMethod.cash.defaultAccount([]), isNull);
    });
  });
}
