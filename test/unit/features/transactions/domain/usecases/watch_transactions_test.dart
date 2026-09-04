import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/watch_transactions.dart';

/// A pass-through use case, so what is under test is the seam itself: that the
/// filter arrives unaltered and that both sides of the `Either` reach the
/// caller. A screen depends on this rather than on a repository, which is what
/// keeps `data/` swappable.
void main() {
  late _FakeRepository repository;
  late WatchTransactions watchTransactions;

  final expense = Transaction(
    id: 1,
    accountId: 1,
    categoryId: 3,
    amountCents: 50000,
    type: TransactionType.expense,
    date: DateTime(2026, 9, 2),
  );

  setUp(() {
    repository = _FakeRepository();
    watchTransactions = WatchTransactions(repository);
  });

  test('passes the filter through untouched', () async {
    const filter = TransactionFilter.forAnalytics();

    await watchTransactions(filter).first;

    expect(identical(repository.lastFilter, filter), isTrue);
  });

  test('forwards every emission in order', () async {
    repository.emissions = [
      const Right([]),
      Right([expense]),
    ];

    final seen = await watchTransactions(const TransactionFilter()).toList();

    expect(seen, hasLength(2));
    expect(seen.last.getOrElse((_) => []), [expense]);
  });

  test('forwards a failure without swallowing it', () async {
    // A watcher that dropped Lefts would leave a screen showing stale rows
    // with no indication anything had gone wrong.
    repository.emissions = [const Left(CacheFailure('read failed'))];

    final seen = await watchTransactions(const TransactionFilter()).toList();

    expect(seen.single.isLeft(), isTrue);
  });
}

class _FakeRepository implements TransactionRepository {
  TransactionFilter? lastFilter;
  List<Either<Failure, List<Transaction>>> emissions = const [Right([])];

  @override
  Stream<Either<Failure, List<Transaction>>> watch(TransactionFilter filter) {
    lastFilter = filter;
    return Stream.fromIterable(emissions);
  }

  @override
  Future<Either<Failure, int>> add(Transaction transaction) async =>
      const Right(1);

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
  Future<Either<Failure, int>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String? note,
  }) async => const Right(1);
}
