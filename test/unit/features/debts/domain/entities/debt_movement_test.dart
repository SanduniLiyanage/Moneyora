import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/entities/debt_movement.dart';

/// The money a debt moves, and through which account. FR-DBT-009, E-47.
void main() {
  final began = DateTime(2026, 10, 5);
  final paid = DateTime(2026, 10, 18);

  Debt debt(
    DebtDirection direction, {
    int? account,
    int? paidThrough,
    DateTime? paidOn,
    bool payment = false,
    String? note,
  }) => Debt(
    direction: direction,
    person: ' Nimal ',
    amountCents: 250000,
    incurredOn: began,
    accountId: account,
    paidOn: paidOn,
    paidAccountId: paidThrough,
    isPayment: payment,
    note: note,
  );

  test('no account, no movement', () {
    expect(DebtMovement.of(debt(DebtDirection.owedToMe)), isEmpty);
    expect(
      DebtMovement.of(
        debt(DebtDirection.owedToMe, paidOn: paid, paidThrough: null),
      ),
      isEmpty,
    );
  });

  test('lent from an account: the money leaves it on the day', () {
    expect(DebtMovement.of(debt(DebtDirection.owedToMe, account: 1)), [
      DebtMovement(
        accountId: 1,
        incoming: false,
        amountCents: 250000,
        on: began,
        label: 'Lent to Nimal',
      ),
    ]);
  });

  test('borrowed into an account: the money arrives', () {
    final movement = DebtMovement.of(debt(DebtDirection.iOwe, account: 2))
        .single;

    expect(movement.incoming, isTrue);
    expect(movement.deltaCents, 250000);
    expect(movement.label, 'Borrowed from Nimal');
  });

  test('paid back through an account: the money goes the other way', () {
    final lent = DebtMovement.of(
      debt(DebtDirection.owedToMe, account: 1, paidOn: paid, paidThrough: 2),
    );
    final borrowed = DebtMovement.of(
      debt(DebtDirection.iOwe, paidOn: paid, paidThrough: 2),
    );

    expect(lent, hasLength(2));
    expect(lent.last.accountId, 2);
    expect(lent.last.incoming, isTrue);
    expect(lent.last.on, paid);
    expect(lent.last.label, 'Nimal paid back');
    expect(borrowed.single.incoming, isFalse);
    expect(borrowed.single.label, 'Paid back Nimal');
  });

  test('a payment moves once, the way it ran, whatever else it names', () {
    final fromThem = DebtMovement.of(
      debt(
        DebtDirection.iOwe,
        account: 1,
        payment: true,
        paidOn: paid,
        paidThrough: 2,
      ),
    );
    final toThem = DebtMovement.of(
      debt(DebtDirection.owedToMe, account: 1, payment: true),
    );

    expect(fromThem.single.incoming, isTrue);
    expect(fromThem.single.label, 'Nimal paid back');
    expect(toThem.single.incoming, isFalse);
    expect(toThem.single.label, 'Paid back Nimal');
  });

  test('says what it was for, after who', () {
    expect(
      DebtMovement.of(
        debt(DebtDirection.owedToMe, account: 1, note: 'Train tickets'),
      ).single.label,
      'Lent to Nimal · Train tickets',
    );
  });
}
