import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/add_transaction.dart';

/// Records what it was asked to save, and can be told to fail.
///
/// A hand-written fake rather than a generated mock: the interface has five
/// methods, only one of which this test needs, and `build_runner` costs a
/// codegen step on every change for no benefit at this size.
class _FakeRepository implements TransactionRepository {
  Transaction? saved;
  Failure? failWith;

  @override
  Future<Either<Failure, int>> add(Transaction transaction) async {
    if (failWith case final failure?) return Left(failure);
    saved = transaction;
    return const Right(42);
  }

  @override
  Future<Either<Failure, Unit>> update(Transaction transaction) async =>
      const Right(unit);

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

void main() {
  late _FakeRepository repository;
  late AddTransaction addTransaction;

  final today = DateTime(2026, 9, 2);

  setUp(() {
    repository = _FakeRepository();
    addTransaction = AddTransaction(repository);
  });

  /// A valid expense, with fields overridable per test.
  Transaction expense({
    int amountCents = 125000,
    int? categoryId = 1,
    TransactionType type = TransactionType.expense,
    TransferDirection? direction,
    List<TransactionSplit> splits = const [],
    DateTime? date,
  }) => Transaction(
    accountId: 1,
    categoryId: categoryId,
    amountCents: amountCents,
    type: type,
    transferDirection: direction,
    date: date ?? today,
    splits: splits,
  );

  group('happy path', () {
    test('saves a valid expense and returns its id', () async {
      final result = await addTransaction(expense());

      expect(result, const Right<Failure, int>(42));
      expect(repository.saved, isNotNull);
      expect(repository.saved!.amountCents, 125000);
    });

    test('passes a repository failure through unchanged', () async {
      // The use case validates; it does not swallow or reinterpret what the
      // data layer reports. A screen showing "invalid amount" for a disk
      // error would send someone hunting in the wrong place entirely.
      repository.failWith = const CacheFailure('disk full');

      final result = await addTransaction(expense());

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('should not have saved'),
      );
    });
  });

  group('amount', () {
    test('rejects zero', () async {
      // Zero is almost always a half-finished entry. Storing one leaves a row
      // that drags every average down while looking harmless.
      final result = await addTransaction(expense(amountCents: 0));

      expect(result.isLeft(), isTrue);
      expect(repository.saved, isNull);
    });

    test('rejects a negative amount', () async {
      // Direction is carried by `type`, never by the sign (E-06). A negative
      // amount has no agreed meaning, and different screens would guess
      // differently.
      final result = await addTransaction(expense(amountCents: -1));
      expect(result.isLeft(), isTrue);
    });
  });

  group('category rules (E-17)', () {
    test('an expense must have a category', () async {
      final result = await addTransaction(expense(categoryId: null));

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f.message, contains('category')),
        (_) => fail('should not have saved'),
      );
    });

    test('a transfer must not have one', () async {
      // Allowing it would need a sentinel category, which then appears in the
      // donut chart as though it were spending.
      final result = await addTransaction(
        expense(
          type: TransactionType.transfer,
          categoryId: 1,
          direction: TransferDirection.out,
        ),
      );
      expect(result.isLeft(), isTrue);
    });
  });

  group('transfer direction (E-16)', () {
    test('a transfer must state its direction', () async {
      // amountCents is always positive and both halves say `transfer`, so
      // without a direction nothing on the row says which way money moved.
      final result = await addTransaction(
        expense(type: TransactionType.transfer, categoryId: null),
      );
      expect(result.isLeft(), isTrue);
    });

    test('an expense must not carry one', () async {
      final result = await addTransaction(
        expense(direction: TransferDirection.out),
      );
      expect(result.isLeft(), isTrue);
    });

    test('a well-formed transfer half is accepted', () async {
      final result = await addTransaction(
        expense(
          type: TransactionType.transfer,
          categoryId: null,
          direction: TransferDirection.out,
        ),
      );
      expect(result.isRight(), isTrue);
    });
  });

  group('splits (E-04)', () {
    test('accepts parts that sum exactly to the total', () async {
      final result = await addTransaction(
        expense(
          amountCents: 10000,
          splits: const [
            TransactionSplit(categoryId: 1, amountCents: 6000),
            TransactionSplit(categoryId: 2, amountCents: 4000),
          ],
        ),
      );
      expect(result.isRight(), isTrue);
    });

    test('rejects parts that do not add up, and says by how much', () async {
      // SQLite cannot express "children sum to parent" as a constraint, so
      // this use case is the only thing enforcing it anywhere.
      final result = await addTransaction(
        expense(
          amountCents: 10000,
          splits: const [
            TransactionSplit(categoryId: 1, amountCents: 6000),
            TransactionSplit(categoryId: 2, amountCents: 3000),
          ],
        ),
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f.message, contains('1000')),
        (_) => fail('should not have saved'),
      );
    });

    test('rejects a zero-value part', () async {
      final result = await addTransaction(
        expense(
          amountCents: 10000,
          splits: const [
            TransactionSplit(categoryId: 1, amountCents: 10000),
            TransactionSplit(categoryId: 2, amountCents: 0),
          ],
        ),
      );
      expect(result.isLeft(), isTrue);
    });

    test('refuses to split a transfer', () async {
      final result = await addTransaction(
        expense(
          type: TransactionType.transfer,
          categoryId: null,
          direction: TransferDirection.out,
          splits: const [TransactionSplit(categoryId: 1, amountCents: 125000)],
        ),
      );
      expect(result.isLeft(), isTrue);
    });
  });

  group('date', () {
    test('rejects a date well in the future', () async {
      final result = await addTransaction(
        expense(date: DateTime.now().add(const Duration(days: 30))),
      );
      expect(result.isLeft(), isTrue);
    });

    test('tolerates tomorrow, for time-zone skew', () async {
      // A device clock in another zone is a legitimate reason for a date to
      // read as tomorrow. A month ahead is a typo.
      final result = await addTransaction(
        expense(date: DateTime.now().add(const Duration(hours: 12))),
      );
      expect(result.isRight(), isTrue);
    });
  });

  group('dominant category', () {
    test('an unsplit transaction reports its own category', () {
      expect(expense(categoryId: 7).dominantCategoryId, 7);
    });

    test('a split reports the category holding the largest share', () {
      // The parent row keeps this so list views and the donut chart render
      // without joining transaction_splits (E-04).
      final transaction = expense(
        amountCents: 10000,
        splits: const [
          TransactionSplit(categoryId: 1, amountCents: 3000),
          TransactionSplit(categoryId: 2, amountCents: 7000),
        ],
      );
      expect(transaction.dominantCategoryId, 2);
    });
  });

  group('analytics filter (E-02)', () {
    test('forAnalytics excludes transfers', () {
      // Counting a transfer as both income and expense inflates each total,
      // and stays invisible until someone with two accounts reads their
      // monthly summary.
      const filter = TransactionFilter.forAnalytics();
      expect(filter.excludeTransfers, isTrue);
    });

    test('the default filter does not', () {
      // The transaction list shows transfers; only analytics drops them.
      const filter = TransactionFilter();
      expect(filter.excludeTransfers, isFalse);
    });

    test('transfers are flagged as not affecting totals', () {
      expect(TransactionType.transfer.affectsTotals, isFalse);
      expect(TransactionType.expense.affectsTotals, isTrue);
      expect(TransactionType.income.affectsTotals, isTrue);
    });
  });
}
