import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/delete_transaction.dart';

void main() {
  late _FakeRepository repository;
  late DeleteTransaction deleteTransaction;

  setUp(() {
    repository = _FakeRepository();
    deleteTransaction = DeleteTransaction(repository);
  });

  test('deletes by id', () async {
    final result = await deleteTransaction(12);

    expect(result, const Right<Failure, Unit>(unit));
    expect(repository.deletedId, 12);
  });

  test('surfaces a repository failure', () async {
    repository.failWith = const CacheFailure('no such row');

    final result = await deleteTransaction(12);

    expect(result, const Left<Failure, Unit>(CacheFailure('no such row')));
  });

  group('refuses an id that cannot name a row', () {
    // Ids come from AUTOINCREMENT and are always positive, so anything else
    // means a caller passed a placeholder rather than a saved row.
    test('zero', () async {
      expect((await deleteTransaction(0)).isLeft(), isTrue);
      expect(repository.deletedId, isNull);
    });

    test('negative', () async {
      expect((await deleteTransaction(-1)).isLeft(), isTrue);
      expect(repository.deletedId, isNull);
    });
  });
}

class _FakeRepository implements TransactionRepository {
  int? deletedId;
  Failure? failWith;

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    if (failWith case final failure?) return Left(failure);
    deletedId = id;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, int>> add(Transaction transaction) async =>
      const Right(1);

  @override
  Future<Either<Failure, Unit>> update(Transaction transaction) async =>
      const Right(unit);

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
