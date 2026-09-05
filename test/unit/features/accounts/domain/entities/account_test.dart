import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';

/// Equality decides whether Riverpod rebuilds a widget, so a `props` list
/// missing a field produces a screen that silently stops updating when exactly
/// that field changes — close to impossible to diagnose from the symptom.
void main() {
  final opened = DateTime(2026, 1, 1);

  Account cash() => Account(
    id: 1,
    name: 'Cash',
    icon: 'wallet',
    initialBalanceCents: 250000,
    currentBalanceCents: 190000,
    initialBalanceDate: opened,
  );

  group('equality', () {
    test('two identical accounts are equal', () {
      expect(cash(), cash());
      expect(cash().hashCode, cash().hashCode);
    });

    test('a difference in any field breaks equality', () {
      // Walks every field rather than spot-checking one. A props list that
      // omits a field passes a single-field test and then quietly stops the
      // UI updating for that field alone.
      final base = cash();
      final variants = <String, Account>{
        'id': base.copyWith(id: 2),
        'name': base.copyWith(name: 'Petty cash'),
        'icon': base.copyWith(icon: 'coins'),
        'type': base.copyWith(type: AccountType.bank),
        'currency': base.copyWith(currency: 'USD'),
        'initialBalanceCents': base.copyWith(initialBalanceCents: 1),
        'currentBalanceCents': base.copyWith(currentBalanceCents: 1),
        'initialBalanceDate': base.copyWith(
          initialBalanceDate: DateTime(2025, 6, 1),
        ),
        'includeInTotal': base.copyWith(includeInTotal: false),
        'isArchived': base.copyWith(isArchived: true),
      };

      for (final entry in variants.entries) {
        expect(
          entry.value,
          isNot(base),
          reason: '${entry.key} is missing from props',
        );
      }
    });
  });

  group('defaults', () {
    test('a new account is cash, in rupees, counted, and not archived', () {
      final account = Account(
        name: 'Wallet',
        icon: 'wallet',
        initialBalanceDate: opened,
      );

      expect(account.type, AccountType.cash);
      expect(account.currency, 'LKR');
      expect(account.includeInTotal, isTrue);
      expect(account.isArchived, isFalse);
      expect(account.initialBalanceCents, 0);
      expect(account.id, isNull);
    });
  });

  group('AccountType', () {
    test('every type has a storage string the schema will accept', () {
      // The CHECK constraint lists these exactly. A type whose storageValue
      // drifts from the schema is an account that cannot be inserted.
      const permitted = {
        'cash',
        'bank',
        'credit_card',
        'digital_wallet',
        'crypto',
        'custom',
      };

      expect(AccountType.values.map((t) => t.storageValue).toSet(), permitted);
    });

    test('storage strings are distinct', () {
      expect(
        AccountType.values.map((t) => t.storageValue).toSet(),
        hasLength(AccountType.values.length),
      );
    });

    test('creditCard is where name and storage value diverge', () {
      // The trap this whole convention exists for, and the same one
      // TransferDirection.incoming has against 'in' (E-16).
      expect(AccountType.creditCard.name, 'creditCard');
      expect(AccountType.creditCard.storageValue, 'credit_card');
      expect(AccountType.digitalWallet.storageValue, 'digital_wallet');
    });
  });

  group('copyWith', () {
    test('leaves untouched fields alone', () {
      final renamed = cash().copyWith(name: 'Petty cash');

      expect(renamed.name, 'Petty cash');
      expect(renamed.id, 1);
      expect(renamed.currentBalanceCents, 190000);
      expect(renamed.initialBalanceDate, opened);
    });
  });
}
