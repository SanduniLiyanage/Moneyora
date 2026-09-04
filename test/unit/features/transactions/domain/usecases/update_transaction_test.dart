import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/update_transaction.dart';

void main() {
  late _FakeRepository repository;
  late UpdateTransaction updateTransaction;

  final date = DateTime(2026, 9, 2);

  Transaction expense({
    int? id = 1,
    int amountCents = 50000,
    int? categoryId = 3,
    List<TransactionSplit> splits = const [],
  }) => Transaction(
    id: id,
    accountId: 1,
    categoryId: categoryId,
    amountCents: amountCents,
    type: TransactionType.expense,
    date: date,
    splits: splits,
  );

  setUp(() {
    repository = _FakeRepository();
    updateTransaction = UpdateTransaction(repository);
  });

  test('saves a valid edit', () async {
    final result = await updateTransaction(expense(amountCents: 75000));

    expect(result, const Right<Failure, Unit>(unit));
    expect(repository.saved?.amountCents, 75000);
  });

  test('surfaces a repository failure', () async {
    repository.failWith = const CacheFailure('no such row');

    final result = await updateTransaction(expense());

    expect(result, const Left<Failure, Unit>(CacheFailure('no such row')));
  });

  group('rejects', () {
    test('a transaction that was never saved', () async {
      final result = await updateTransaction(expense(id: null));

      expect(result.isLeft(), isTrue);
      expect(repository.saved, isNull);
    });

    test('half of a transfer', () async {
      // Editing one side alone would leave the other half and the header row
      // describing a movement that no longer happened (E-15). A transfer is
      // edited as a transfer.
      final half = Transaction(
        id: 1,
        accountId: 1,
        amountCents: 50000,
        type: TransactionType.transfer,
        transferDirection: TransferDirection.out,
        date: date,
      );

      final result = await updateTransaction(half);

      expect(result.isLeft(), isTrue);
      expect(repository.saved, isNull);
    });
  });

  group('applies the same rules as AddTransaction', () {
    // Not a copy of them — UpdateTransaction calls AddTransaction.validate.
    // These assert the delegation actually happens, because an edit screen
    // that accepted what an entry screen rejects is a bug nobody looks for.
    test('a zero amount', () async {
      expect((await updateTransaction(expense(amountCents: 0))).isLeft(), true);
    });

    test('a missing category on an expense', () async {
      expect(
        (await updateTransaction(expense(categoryId: null))).isLeft(),
        true,
      );
    });

    test('split parts that do not total the parent', () async {
      final result = await updateTransaction(
        expense(
          amountCents: 100000,
          splits: const [
            TransactionSplit(categoryId: 3, amountCents: 60000),
            TransactionSplit(categoryId: 4, amountCents: 30000),
          ],
        ),
      );

      expect(result.isLeft(), isTrue);
    });

    test('and lets a correct split through', () async {
      final result = await updateTransaction(
        expense(
          amountCents: 100000,
          splits: const [
            TransactionSplit(categoryId: 3, amountCents: 60000),
            TransactionSplit(categoryId: 4, amountCents: 40000),
          ],
        ),
      );

      expect(result.isRight(), isTrue);
    });
  });
}

class _FakeRepository implements TransactionRepository {
  Transaction? saved;
  Failure? failWith;

  @override
  Future<Either<Failure, Unit>> update(Transaction transaction) async {
    if (failWith case final failure?) return Left(failure);
    saved = transaction;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, int>> add(Transaction transaction) async =>
      const Right(1);

  @override
  Future<Either<Failure, Unit>> delete(int id) async => const Right(unit);

  @override
  Future<Either<Failure, List<Transaction>>> list(
    TransactionFilter filter,
  ) async => const Right([]);

  @override
  Stream<Either<Failure, List<Transaction>>> watch(TransactionFilter filter) =>
      const Stream.empty();

  @override
  Future<Either<Failure, int>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String? note,
  }) async => const Right(1);
}
