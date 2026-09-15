import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/expense_writer.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/add_expenses.dart';

class _FakeRepository implements TransactionRepository {
  List<Transaction>? batch;
  Either<Failure, List<int>> result = const Right([]);

  @override
  Future<Either<Failure, List<int>>> addAll(
    List<Transaction> transactions,
  ) async {
    batch = transactions;
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late _FakeRepository repository;
  late AddExpenses addExpenses;

  final date = DateTime(2026, 4, 3);

  ExpenseToRecord line({
    int amountCents = 125000,
    int categoryId = 7,
    String? note,
  }) => ExpenseToRecord(
    accountId: 1,
    categoryId: categoryId,
    amountCents: amountCents,
    date: date,
    time: '14:32',
    note: note,
    receiptScanId: 42,
    receiptImagePath: '/receipts/42.jpg',
  );

  setUp(() {
    repository = _FakeRepository();
    addExpenses = AddExpenses(repository);
  });

  test('every line becomes an expense on the receipt, in order', () async {
    repository.result = const Right([10, 11]);

    final result = await addExpenses([
      line(note: 'RICE 5KG'),
      line(amountCents: 18000, categoryId: 8, note: 'BREAD'),
    ]);

    expect(result, const Right<Failure, List<int>>([10, 11]));
    final batch = repository.batch!;
    expect(batch.map((t) => t.note), ['RICE 5KG', 'BREAD']);
    expect(batch.map((t) => t.amountCents), [125000, 18000]);
    expect(batch.map((t) => t.categoryId), [7, 8]);
    for (final t in batch) {
      expect(t.type, TransactionType.expense);
      expect(t.accountId, 1);
      expect(t.date, date);
      expect(t.time, '14:32');
      expect(t.receiptScanId, 42);
      expect(t.receiptImagePath, '/receipts/42.jpg');
      expect(t.isSplit, isFalse);
      expect(t.isRecurring, isFalse);
      expect(t.transferDirection, isNull);
    }
  });

  test('a bad line refuses the whole receipt and names the line', () async {
    // Nothing reaches the repository: the alternative is a receipt half in
    // the ledger and a user who confirms it again.
    final result = await addExpenses([line(), line(amountCents: 0), line()]);

    expect(
      result,
      const Left<Failure, List<int>>(
        ValidationFailure('Item 2: Enter an amount greater than zero.'),
      ),
    );
    expect(repository.batch, isNull);
  });

  test('a date in the future is refused the same way', () async {
    final result = await addExpenses([
      ExpenseToRecord(
        accountId: 1,
        categoryId: 7,
        amountCents: 100,
        date: DateTime.now().add(const Duration(days: 30)),
      ),
    ]);

    expect(result.isLeft(), isTrue);
    expect(repository.batch, isNull);
  });

  test('an empty receipt is refused', () async {
    expect((await addExpenses(const [])).isLeft(), isTrue);
    expect(repository.batch, isNull);
  });

  test('the repository failure passes through', () async {
    repository.result = const Left(CacheFailure());

    expect(
      await addExpenses([line()]),
      const Left<Failure, List<int>>(CacheFailure()),
    );
  });
}
