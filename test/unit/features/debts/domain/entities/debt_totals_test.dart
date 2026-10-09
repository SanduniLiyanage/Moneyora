import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/entities/debt_totals.dart';

/// What is still owed, each way. FR-DBT-002.
void main() {
  final today = DateTime(2026, 10, 9, 15);

  Debt debt(
    DebtDirection direction,
    int cents, {
    DateTime? due,
    DateTime? paid,
  }) => Debt(
    direction: direction,
    person: 'Someone',
    amountCents: cents,
    incurredOn: DateTime(2026, 9, 1),
    dueOn: due,
    paidOn: paid,
  );

  test('adds up the open debts each way, and leaves the paid ones out', () {
    final totals = DebtTotals.of([
      debt(DebtDirection.owedToMe, 250000),
      debt(DebtDirection.owedToMe, 50000),
      debt(DebtDirection.iOwe, 120000),
      debt(DebtDirection.owedToMe, 999900, paid: DateTime(2026, 10, 1)),
    ], today: today);

    expect(totals.owedToMeCents, 300000);
    expect(totals.iOweCents, 120000);
    expect(totals.netCents, 180000);
  });

  test('overdue is open and past its due day, not on it', () {
    final totals = DebtTotals.of([
      debt(DebtDirection.iOwe, 100, due: DateTime(2026, 10, 8)),
      // Due today: not overdue until tomorrow.
      debt(DebtDirection.iOwe, 100, due: DateTime(2026, 10, 9)),
      debt(DebtDirection.iOwe, 100),
      debt(
        DebtDirection.iOwe,
        100,
        due: DateTime(2026, 9, 2),
        paid: DateTime(2026, 9, 3),
      ),
    ], today: today);

    expect(totals.overdue, 1);
  });

  test('nothing owed is nothing', () {
    expect(
      DebtTotals.of(const [], today: today),
      const DebtTotals(owedToMeCents: 0, iOweCents: 0, overdue: 0),
    );
  });
}
