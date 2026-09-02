import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';

/// The entity is not a dumb data bag, so it is not tested like one.
///
/// `copyWith` runs on every edit, and equality decides whether Riverpod
/// rebuilds a widget — a `props` list missing a field produces a screen that
/// silently stops updating when that field changes, which is close to
/// impossible to diagnose from the symptom.
void main() {
  final date = DateTime(2026, 9, 2);

  Transaction expense({
    int amountCents = 125000,
    int? categoryId = 1,
    List<TransactionSplit> splits = const [],
  }) => Transaction(
    id: 1,
    accountId: 1,
    categoryId: categoryId,
    amountCents: amountCents,
    type: TransactionType.expense,
    date: date,
    time: '14:30',
    note: 'Groceries',
    splits: splits,
  );

  group('equality', () {
    test('two identical transactions are equal', () {
      expect(expense(), expense());
      expect(expense().hashCode, expense().hashCode);
    });

    test('a difference in any field breaks equality', () {
      // Walks every field rather than spot-checking one. A props list that
      // omits a field passes a single-field test and then quietly stops the
      // UI updating for exactly that field.
      final base = expense();
      final variants = <String, Transaction>{
        'id': base.copyWith(id: 2),
        'accountId': base.copyWith(accountId: 2),
        'categoryId': base.copyWith(categoryId: 2),
        'amountCents': base.copyWith(amountCents: 999),
        'type': base.copyWith(type: TransactionType.income),
        'date': base.copyWith(date: DateTime(2026, 9, 3)),
        'time': base.copyWith(time: '09:00'),
        'note': base.copyWith(note: 'Something else'),
        'receiptScanId': base.copyWith(receiptScanId: 5),
        'isRecurring': base.copyWith(isRecurring: true),
        'splits': base.copyWith(
          splits: const [TransactionSplit(categoryId: 1, amountCents: 125000)],
        ),
      };

      for (final entry in variants.entries) {
        expect(
          entry.value,
          isNot(base),
          reason: '${entry.key} is missing from props',
        );
      }
    });

    test('splits compare by value, not identity', () {
      const a = TransactionSplit(categoryId: 1, amountCents: 500, note: 'x');
      const b = TransactionSplit(categoryId: 1, amountCents: 500, note: 'x');
      const c = TransactionSplit(categoryId: 1, amountCents: 600, note: 'x');

      expect(a, b);
      expect(a, isNot(c));
    });
  });

  group('copyWith', () {
    test('changes only what it is given', () {
      final original = expense();
      final changed = original.copyWith(amountCents: 500);

      expect(changed.amountCents, 500);
      expect(changed.id, original.id);
      expect(changed.note, original.note);
      expect(changed.date, original.date);
      expect(changed.type, original.type);
    });

    test('returns an equal object when given nothing', () {
      expect(expense().copyWith(), expense());
    });
  });

  group('splits', () {
    test('isSplit is false without parts', () {
      expect(expense().isSplit, isFalse);
      expect(expense().splitTotalCents, 0);
    });

    test('splitTotalCents adds the parts up', () {
      final transaction = expense(
        amountCents: 10000,
        splits: const [
          TransactionSplit(categoryId: 1, amountCents: 6000),
          TransactionSplit(categoryId: 2, amountCents: 4000),
        ],
      );

      expect(transaction.isSplit, isTrue);
      expect(transaction.splitTotalCents, 10000);
    });

    test('dominantCategoryId picks the largest part', () {
      final transaction = expense(
        amountCents: 10000,
        splits: const [
          TransactionSplit(categoryId: 1, amountCents: 2000),
          TransactionSplit(categoryId: 2, amountCents: 7000),
          TransactionSplit(categoryId: 3, amountCents: 1000),
        ],
      );
      expect(transaction.dominantCategoryId, 2);
    });

    test('a tie resolves to the first part, not to nothing', () {
      // Equal shares are common when someone splits a bill down the middle.
      // Returning null here would leave the donut chart with an uncategorised
      // slice for a transaction that plainly has categories.
      final transaction = expense(
        amountCents: 10000,
        splits: const [
          TransactionSplit(categoryId: 4, amountCents: 5000),
          TransactionSplit(categoryId: 9, amountCents: 5000),
        ],
      );
      expect(transaction.dominantCategoryId, 4);
    });

    test('an unsplit transaction falls back to its own category', () {
      expect(expense(categoryId: 7).dominantCategoryId, 7);
    });
  });

  group('TransactionType', () {
    test('only transfers are excluded from totals', () {
      // The distinction E-02 turns on: counting a transfer as spending
      // inflates both income and expense.
      expect(TransactionType.expense.affectsTotals, isTrue);
      expect(TransactionType.income.affectsTotals, isTrue);
      expect(TransactionType.transfer.affectsTotals, isFalse);
    });
  });
}
