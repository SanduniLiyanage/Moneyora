import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/transactions/domain/entities/category_group.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';

void main() {
  final day = DateTime(2026, 9, 27);

  Transaction expense(int id, int categoryId, int cents) => Transaction(
    id: id,
    accountId: 1,
    categoryId: categoryId,
    amountCents: cents,
    type: TransactionType.expense,
    date: day,
  );

  Transaction income(int id, int categoryId, int cents) => Transaction(
    id: id,
    accountId: 1,
    categoryId: categoryId,
    amountCents: cents,
    type: TransactionType.income,
    date: day,
  );

  Transaction transfer(int id, TransferDirection direction) => Transaction(
    id: id,
    accountId: 1,
    amountCents: 5000,
    type: TransactionType.transfer,
    transferDirection: direction,
    date: day,
  );

  group('CategoryGroup.group', () {
    test('nothing in, nothing out', () {
      expect(CategoryGroup.group(const []), isEmpty);
    });

    test('one group per category, with its count and total', () {
      final groups = CategoryGroup.group([
        expense(1, 10, 1000),
        expense(2, 20, 300),
        expense(3, 10, 500),
      ]);

      expect(groups.map((g) => g.categoryId), [10, 20]);
      expect(groups.first.count, 2);
      expect(groups.first.netCents, -1500);
      expect(groups.last.count, 1);
      expect(groups.last.netCents, -300);
    });

    test('keeps the order it was given inside a group', () {
      final groups = CategoryGroup.group([
        expense(3, 10, 100),
        expense(1, 10, 100),
        expense(2, 10, 100),
      ]);

      expect(groups.single.entries.map((e) => e.transaction.id), [3, 1, 2]);
    });

    test('largest total first, whether spent or earned', () {
      final groups = CategoryGroup.group([
        expense(1, 10, 200),
        income(2, 30, 90000),
        expense(3, 20, 5000),
      ]);

      expect(groups.map((g) => g.categoryId), [30, 20, 10]);
      expect(groups.first.netCents, 90000);
    });

    test('a tie goes to the busier group, then the lower id', () {
      final groups = CategoryGroup.group([
        expense(1, 40, 600),
        expense(2, 20, 300),
        expense(3, 20, 300),
        expense(4, 30, 600),
      ]);

      expect(groups.map((g) => g.categoryId), [20, 30, 40]);
    });

    test('income and spending in one category net against each other', () {
      final groups = CategoryGroup.group([
        expense(1, 10, 1000),
        income(2, 10, 400),
      ]);

      expect(groups.single.netCents, -600);
      expect(groups.single.count, 2);
    });

    test('transfers are one group, last, adding nothing (E-02)', () {
      final groups = CategoryGroup.group([
        transfer(1, TransferDirection.out),
        expense(2, 10, 1),
        transfer(3, TransferDirection.incoming),
      ]);

      expect(groups.map((g) => g.categoryId), [10, null]);
      expect(groups.last.isTransfers, isTrue);
      expect(groups.last.count, 2);
      expect(groups.last.netCents, 0);
      expect(groups.first.isTransfers, isFalse);
    });

    test('a split sits in each part category with that part (E-04)', () {
      final split = Transaction(
        id: 7,
        accountId: 1,
        categoryId: 10,
        amountCents: 1000,
        type: TransactionType.expense,
        date: day,
        splits: const [
          TransactionSplit(categoryId: 10, amountCents: 700),
          TransactionSplit(categoryId: 20, amountCents: 300),
        ],
      );

      final groups = CategoryGroup.group([split, expense(8, 20, 50)]);

      expect(groups.map((g) => g.categoryId), [10, 20]);
      expect(groups.first.entries.single.amountCents, 700);
      expect(groups.first.entries.single.transaction, split);
      expect(groups.last.count, 2);
      expect(groups.last.netCents, -350);
    });

    test('two parts in one category are one entry', () {
      final split = Transaction(
        id: 7,
        accountId: 1,
        categoryId: 10,
        amountCents: 1000,
        type: TransactionType.expense,
        date: day,
        splits: const [
          TransactionSplit(categoryId: 10, amountCents: 600),
          TransactionSplit(categoryId: 20, amountCents: 100),
          TransactionSplit(categoryId: 10, amountCents: 300),
        ],
      );

      final groups = CategoryGroup.group([split]);

      expect(groups.first.categoryId, 10);
      expect(groups.first.count, 1);
      expect(groups.first.netCents, -900);
    });

    test('every group added up is the net of the rows given', () {
      final rows = [
        for (var i = 0; i < 40; i++)
          i.isEven
              ? expense(i, 10 + i % 7, 100 + i * 37)
              : income(i, 50 + i % 3, 1000 + i * 11),
        transfer(100, TransferDirection.out),
      ];
      final expected = rows.fold(0, (sum, t) {
        return switch (t.type) {
          TransactionType.income => sum + t.amountCents,
          TransactionType.expense => sum - t.amountCents,
          TransactionType.transfer => sum,
        };
      });

      final groups = CategoryGroup.group(rows);

      expect(groups.fold(0, (sum, g) => sum + g.netCents), expected);
      expect(groups.fold(0, (sum, g) => sum + g.count), rows.length);
    });
  });
}
