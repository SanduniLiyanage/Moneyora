import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/entities/debt_totals.dart';

/// What is still owed, each way, netted person by person. FR-DBT-002,
/// FR-DBT-005, E-47.
void main() {
  final today = DateTime(2026, 10, 9, 15);

  Debt debt(
    DebtDirection direction,
    int cents, {
    String person = 'Someone',
    DateTime? due,
    DateTime? paid,
  }) => Debt(
    direction: direction,
    person: person,
    amountCents: cents,
    incurredOn: DateTime(2026, 9, 1),
    dueOn: due,
    paidOn: paid,
  );

  test('adds up the open debts each way across people, and leaves the paid '
      'ones out', () {
    final totals = DebtTotals.of([
      debt(DebtDirection.owedToMe, 250000, person: 'Nimal'),
      debt(DebtDirection.owedToMe, 50000, person: 'Kamala'),
      debt(DebtDirection.iOwe, 120000, person: 'Saman'),
      debt(
        DebtDirection.owedToMe,
        999900,
        person: 'Ruwan',
        paid: DateTime(2026, 10, 1),
      ),
    ], today: today);

    expect(totals.owedToMeCents, 300000);
    expect(totals.iOweCents, 120000);
    expect(totals.netCents, 180000);
  });

  test('nets what one person owes against what is owed to them', () {
    // The tester's example: Nimal owes Rs1,000, then the user owes him
    // Rs400. He owes Rs600, and the user owes nobody.
    final totals = DebtTotals.of([
      debt(DebtDirection.owedToMe, 100000, person: 'Nimal'),
      debt(DebtDirection.iOwe, 40000, person: 'nimal '),
      debt(DebtDirection.iOwe, 25000, person: 'Saman'),
    ], today: today);

    expect(totals.owedToMeCents, 60000);
    expect(totals.iOweCents, 25000);
  });

  test('a person square either way is on neither side', () {
    final totals = DebtTotals.of([
      debt(DebtDirection.owedToMe, 40000, person: 'Nimal'),
      debt(DebtDirection.iOwe, 40000, person: 'Nimal'),
    ], today: today);

    expect(totals.owedToMeCents, 0);
    expect(totals.iOweCents, 0);
  });

  test('overdue counts people, open and past a due day, not on it', () {
    final totals = DebtTotals.of([
      debt(DebtDirection.iOwe, 100, person: 'A', due: DateTime(2026, 10, 8)),
      debt(DebtDirection.iOwe, 100, person: 'A', due: DateTime(2026, 10, 7)),
      // Due today: not overdue until tomorrow.
      debt(DebtDirection.iOwe, 100, person: 'B', due: DateTime(2026, 10, 9)),
      debt(DebtDirection.iOwe, 100, person: 'C'),
      debt(
        DebtDirection.iOwe,
        100,
        person: 'D',
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
