import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/data/datasources/transaction_local_datasource.dart';
import 'package:moneyora/features/transactions/data/models/transaction_model.dart';
import 'package:moneyora/features/transactions/data/repositories/transaction_repository_impl.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';

/// The repository has one job — translate — so these tests are about
/// translation and nothing else.
///
/// The datasource is a hand-written fake rather than a mock. What needs
/// controlling here is *when a stream fires* and *which exception comes back*,
/// and a fake that simply holds those is easier to read than the matcher
/// syntax that would express the same thing.
void main() {
  late _FakeLocalDataSource local;
  late TransactionRepositoryImpl repository;

  final date = DateTime(2026, 9, 2);

  Transaction expense({int? id, int amountCents = 50000}) => Transaction(
    id: id,
    accountId: 1,
    categoryId: 3,
    amountCents: amountCents,
    type: TransactionType.expense,
    date: date,
  );

  /// Lets the generator run: it awaits a query between every emission, so a
  /// single turn of the event loop is not enough to see the next value.
  Future<void> settle() async {
    for (var turn = 0; turn < 5; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    local = _FakeLocalDataSource();
    repository = TransactionRepositoryImpl(local);
  });

  tearDown(() => local.dispose());

  group('add', () {
    test('returns the new id on success', () async {
      local.nextId = 42;

      final result = await repository.add(expense());

      expect(result, const Right<Failure, int>(42));
    });

    test('hands the datasource a model built from the entity', () async {
      await repository.add(expense(amountCents: 125000));

      expect(local.added.single.amountCents, 125000);
      expect(local.added.single, isA<TransactionModel>());
    });

    test('converts a thrown exception into a Left', () async {
      local.failWith = const CacheException('disk full');

      final result = await repository.add(expense());

      expect(result, const Left<Failure, int>(CacheFailure('disk full')));
    });

    test('never throws, whatever the datasource does', () async {
      local.failWith = const EncryptionException('key rotated');

      // The contract above data/ is that nothing throws. A use case has no
      // try/catch to save it, so an escaping exception would reach a widget.
      await expectLater(repository.add(expense()), completes);
    });
  });

  group('update and delete', () {
    test('return unit on success', () async {
      expect(
        await repository.update(expense(id: 1)),
        const Right<Failure, Unit>(unit),
      );
      expect(await repository.delete(1), const Right<Failure, Unit>(unit));
    });

    test('surface failures', () async {
      local.failWith = const CacheException('no such row');

      expect(
        await repository.update(expense(id: 9)),
        const Left<Failure, Unit>(CacheFailure('no such row')),
      );
      expect(
        await repository.delete(9),
        const Left<Failure, Unit>(CacheFailure('no such row')),
      );
    });
  });

  group('list', () {
    test('returns plain entities, not models', () async {
      // Equatable compares runtimeType, so a model handed upward would never
      // equal an identical entity. This is the assertion that keeps that
      // conversion from being quietly dropped.
      local.rows = [TransactionModel.fromEntity(expense(id: 1))];

      final result = await repository.list(const TransactionFilter());

      final rows = result.getOrElse((_) => []);
      expect(rows.single.runtimeType, Transaction);
      expect(rows.single, expense(id: 1));
    });

    test('passes the filter straight through', () async {
      const filter = TransactionFilter.forAnalytics();

      await repository.list(filter);

      expect(identical(local.lastFilter, filter), isTrue);
    });

    test('surfaces a failure', () async {
      local.failWith = const CacheException('read failed');

      final result = await repository.list(const TransactionFilter());

      expect(result.isLeft(), isTrue);
    });
  });

  group('transfer', () {
    test('forwards every argument and returns the header id', () async {
      local.nextId = 7;

      final result = await repository.transfer(
        fromAccountId: 2,
        toAccountId: 1,
        amountCents: 800000,
        date: date,
        note: 'Cash withdrawal',
      );

      expect(result, const Right<Failure, int>(7));
      expect(local.transfers.single, (
        from: 2,
        to: 1,
        amount: 800000,
        date: date,
        note: 'Cash withdrawal',
      ));
    });

    test('surfaces the constraint failure as a Left', () async {
      // The schema refuses a transfer to the same account it came from. Until
      // a MakeTransfer use case validates that first, this is the path a
      // caller meets, and it must not throw.
      local.failWith = const CacheException('Could not record a transfer.');

      final result = await repository.transfer(
        fromAccountId: 1,
        toAccountId: 1,
        amountCents: 500,
        date: date,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('watch', () {
    test('emits once immediately, before anything changes', () async {
      local.rows = [TransactionModel.fromEntity(expense(id: 1))];

      final first = await repository.watch(const TransactionFilter()).first;

      expect(first.getOrElse((_) => []), hasLength(1));
    });

    test('re-queries on every change signal', () async {
      final seen = <int>[];
      final subscription = repository
          .watch(const TransactionFilter())
          .listen((either) => seen.add(either.getOrElse((_) => []).length));

      await settle();
      local
        ..rows = [TransactionModel.fromEntity(expense(id: 1))]
        ..emitChange();
      await settle();
      local
        ..rows = [
          TransactionModel.fromEntity(expense(id: 1)),
          TransactionModel.fromEntity(expense(id: 2)),
        ]
        ..emitChange();
      await settle();

      expect(seen, [0, 1, 2]);
      await subscription.cancel();
    });

    test('cancelling actually completes, and stops the reads', () async {
      // The regression test for a real bug. The obvious implementation —
      // `async* { yield ...; await for (_ in changes) yield ...; }` — reads
      // better and hangs here forever: a subscription to an async generator
      // suspended in `await for` over a broadcast stream cannot be cancelled,
      // because the generator never resumes to run its own cleanup. In the app
      // that is a screen which navigates away and keeps listening for the life
      // of the process.
      var reads = 0;
      local.onList = () => reads++;

      final subscription = repository
          .watch(const TransactionFilter())
          .listen((_) {});
      await settle();

      await subscription.cancel().timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('cancel() did not complete'),
      );

      final readsAtCancel = reads;
      local.emitChange();
      await settle();

      expect(reads, readsAtCancel, reason: 'no reads after cancelling');
    });

    test('delivers a read failure without closing the stream', () async {
      // A watcher that ended on the first error would leave the screen frozen
      // on stale data with no way back.
      final seen = <Either<Failure, List<Transaction>>>[];
      final subscription = repository
          .watch(const TransactionFilter())
          .listen(seen.add);

      await settle();
      local
        ..failWith = const CacheException('read failed')
        ..emitChange();
      await settle();
      local
        ..failWith = null
        ..rows = [TransactionModel.fromEntity(expense(id: 1))]
        ..emitChange();
      await settle();

      expect(seen[0].isRight(), isTrue);
      expect(seen[1].isLeft(), isTrue, reason: 'the failure is delivered');
      expect(seen[2].isRight(), isTrue, reason: 'and it recovers afterwards');
      await subscription.cancel();
    });
  });

  group('exception translation', () {
    // AppException is sealed, so the switch that does this is exhaustive at
    // compile time. This table is what proves each arm points somewhere
    // sensible rather than merely somewhere.
    final cases = <AppException, Failure>{
      const CacheException('a'): const CacheFailure('a'),
      const EncryptionException('b'): const EncryptionFailure('b'),
      const ServerException('c'): const ServerFailure('c'),
      const NetworkException(): const NetworkFailure(),
      const OcrException('d'): const OcrFailure('d'),
      const PermissionException('e'): const PermissionFailure('e'),
    };

    for (final entry in cases.entries) {
      test(
        '${entry.key.runtimeType} becomes ${entry.value.runtimeType}',
        () async {
          local.failWith = entry.key;

          final result = await repository.add(expense());

          expect(result, Left<Failure, int>(entry.value));
        },
      );
    }
  });
}

/// A datasource whose every response is set by the test.
class _FakeLocalDataSource implements TransactionLocalDataSource {
  final _changes = StreamController<void>.broadcast();

  /// Thrown by the next call, if set.
  AppException? failWith;

  /// Returned by [add] and [createTransfer].
  int nextId = 1;

  /// Returned by [list].
  List<TransactionModel> rows = [];

  /// Called on every [list], so a test can count reads.
  void Function()? onList;

  final List<TransactionModel> added = [];
  final List<({int from, int to, int amount, DateTime date, String? note})>
  transfers = [];
  TransactionFilter? lastFilter;

  void emitChange() => _changes.add(null);

  void _maybeThrow() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<int> add(TransactionModel transaction) async {
    _maybeThrow();
    added.add(transaction);
    return nextId;
  }

  @override
  Future<void> update(TransactionModel transaction) async => _maybeThrow();

  @override
  Future<void> delete(int id) async => _maybeThrow();

  @override
  Future<List<TransactionModel>> list(TransactionFilter filter) async {
    lastFilter = filter;
    onList?.call();
    _maybeThrow();
    return rows;
  }

  @override
  Future<int> createTransfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String? note,
  }) async {
    _maybeThrow();
    transfers.add((
      from: fromAccountId,
      to: toAccountId,
      amount: amountCents,
      date: date,
      note: note,
    ));
    return nextId;
  }

  @override
  Future<void> dispose() => _changes.close();
}
