import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/transactions/domain/entities/day_group.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';

void main() {
  Transaction row(
    int id,
    DateTime date,
    int cents, {
    TransactionType type = TransactionType.expense,
  }) => Transaction(
    id: id,
    accountId: 1,
    categoryId: type == TransactionType.transfer ? null : 10,
    amountCents: cents,
    type: type,
    transferDirection: type == TransactionType.transfer
        ? TransferDirection.out
        : null,
    date: date,
  );

  test('nothing in, nothing out', () {
    expect(DayGroup.group(const []), isEmpty);
  });

  test('one group per day, newest first, rows in the order given', () {
    final groups = DayGroup.group([
      row(1, DateTime(2026, 9, 27, 20), 24000),
      row(2, DateTime(2026, 9, 27, 9), 19000),
      row(3, DateTime(2026, 9, 26, 13), 40000),
    ]);

    expect(groups.map((g) => g.day), [
      DateTime(2026, 9, 27),
      DateTime(2026, 9, 26),
    ]);
    expect(groups.first.transactions.map((t) => t.id), [1, 2]);
    expect(groups.first.count, 2);
  });

  test("a day's spending is its expenses, whole", () {
    final day = DayGroup.group([
      row(1, DateTime(2026, 9, 27), 159800),
      row(2, DateTime(2026, 9, 27), 24000),
    ]).single;

    expect(day.spentCents, 183800);
    expect(day.incomeCents, 0);
  });

  test('income is kept apart, and a transfer is neither (E-02)', () {
    final day = DayGroup.group([
      row(1, DateTime(2026, 9, 25), 1000),
      row(2, DateTime(2026, 9, 25), 500000, type: TransactionType.income),
      row(3, DateTime(2026, 9, 25), 70000, type: TransactionType.transfer),
    ]).single;

    expect(day.spentCents, 1000);
    expect(day.incomeCents, 500000);
    expect(day.count, 3, reason: 'the transfer is listed, just not totalled');
  });

  test('transfers are totalled apart, by direction. FR-TRF-004', () {
    final incoming = Transaction(
      id: 4,
      accountId: 1,
      amountCents: 20000,
      type: TransactionType.transfer,
      transferDirection: TransferDirection.incoming,
      date: DateTime(2026, 9, 28),
    );
    final day = DayGroup.group([
      row(1, DateTime(2026, 9, 28), 1000),
      row(2, DateTime(2026, 9, 28), 30000, type: TransactionType.transfer),
      incoming,
    ]).single;

    expect(day.transferOutCents, 30000);
    expect(day.transferInCents, 20000);
    // Still neither spending nor income.
    expect(day.spentCents, 1000);
    expect(day.incomeCents, 0);
  });

  test('midnight belongs to the day it starts', () {
    final groups = DayGroup.group([
      row(1, DateTime(2026, 9, 27), 100),
      row(2, DateTime(2026, 9, 26, 23, 59), 100),
    ]);

    expect(groups, hasLength(2));
  });
}
