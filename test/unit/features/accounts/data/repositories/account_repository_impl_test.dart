import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/exceptions.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/accounts/data/datasources/account_local_datasource.dart';
import 'package:moneyora/features/accounts/data/models/account_model.dart';
import 'package:moneyora/features/accounts/data/repositories/account_repository_impl.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';

/// The repository translates and nothing else, so these tests are about
/// translation: exceptions becoming failures, models becoming entities, and a
/// watch stream that can actually be cancelled.
void main() {
  late _FakeLocalDataSource local;
  late AccountRepositoryImpl repository;

  final opened = DateTime(2026, 1, 1);

  Account account({int? id = 1, String name = 'Cash'}) =>
      Account(id: id, name: name, icon: 'wallet', initialBalanceDate: opened);

  Future<void> settle() async {
    for (var turn = 0; turn < 5; turn++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    local = _FakeLocalDataSource();
    repository = AccountRepositoryImpl(local);
  });

  tearDown(() => local.dispose());

  group('writes', () {
    test('add returns the new id', () async {
      local.nextId = 4;

      expect(
        await repository.add(account(id: null)),
        const Right<Failure, int>(4),
      );
      expect(local.added.single, isA<AccountModel>());
    });

    test('update, archive and delete return unit', () async {
      expect(
        await repository.update(account()),
        const Right<Failure, Unit>(unit),
      );
      expect(
        await repository.setArchived(1, archived: true),
        const Right<Failure, Unit>(unit),
      );
      expect(await repository.delete(1), const Right<Failure, Unit>(unit));
      expect(local.archivedCalls.single, (id: 1, archived: true));
    });

    test('a thrown exception becomes a Left, never an escape', () async {
      local.failWith = const CacheException('database is locked');

      final result = await repository.add(account(id: null));

      expect(
        result,
        const Left<Failure, int>(CacheFailure('database is locked')),
      );
    });

    test('every exception type maps to a sensible failure', () async {
      // AppException is sealed, so the switch is exhaustive at compile time.
      // This is what proves each arm points somewhere useful.
      final cases = <AppException, Failure>{
        const CacheException('a'): const CacheFailure('a'),
        const EncryptionException('b'): const EncryptionFailure('b'),
        const ServerException('c'): const ServerFailure('c'),
        const NetworkException(): const NetworkFailure(),
        const OcrException('d'): const OcrFailure('d'),
        const PermissionException('e'): const PermissionFailure('e'),
      };

      for (final entry in cases.entries) {
        local.failWith = entry.key;
        expect(
          await repository.delete(1),
          Left<Failure, Unit>(entry.value),
          reason: '${entry.key.runtimeType}',
        );
      }
    });
  });

  group('reads', () {
    test('list returns plain entities, not models', () async {
      // Equatable compares runtimeType, so a model handed upward would never
      // equal an identical entity. This assertion is what stops the
      // conversion being dropped as redundant later.
      local.rows = [AccountModel.fromEntity(account())];

      final rows = (await repository.list()).getOrElse((_) => []);

      expect(rows.single.runtimeType, Account);
      expect(rows.single, account());
    });

    test('passes includeArchived through', () async {
      await repository.list(includeArchived: true);

      expect(local.lastIncludeArchived, isTrue);
    });

    test('transactionCount forwards the number', () async {
      local.count = 7;

      expect(
        await repository.transactionCount(1),
        const Right<Failure, int>(7),
      );
    });
  });

  group('recompute', () {
    test('returns the recomputed balance', () async {
      local.recomputed = -125000;

      expect(
        await repository.recomputeBalance(1),
        const Right<Failure, int>(-125000),
      );
    });

    test('recomputeAllBalances returns unit', () async {
      expect(
        await repository.recomputeAllBalances(),
        const Right<Failure, Unit>(unit),
      );
      expect(local.recomputedAll, isTrue);
    });
  });

  group('watch', () {
    test('emits once immediately, then on every change', () async {
      final seen = <int>[];
      final subscription = repository.watch().listen(
        (either) => seen.add(either.getOrElse((_) => []).length),
      );

      await settle();
      local
        ..rows = [AccountModel.fromEntity(account())]
        ..emitChange();
      await settle();

      expect(seen, [0, 1]);
      await subscription.cancel();
    });

    test('cancelling completes, and stops the reads', () async {
      // The regression test for the bug found in the transactions repository:
      // an async* suspended in `await for` over a broadcast stream cannot be
      // cancelled, so a screen that navigates away listens forever. This
      // repository is built the same way to avoid it, so it is pinned here too.
      var reads = 0;
      local.onList = () => reads++;

      final subscription = repository.watch().listen((_) {});
      await settle();

      await subscription.cancel().timeout(
        const Duration(seconds: 5),
        onTimeout: () => fail('cancel() did not complete'),
      );

      final atCancel = reads;
      local.emitChange();
      await settle();

      expect(reads, atCancel, reason: 'no reads after cancelling');
    });

    test('delivers a failure without ending the stream', () async {
      final seen = <Either<Failure, List<Account>>>[];
      final subscription = repository.watch().listen(seen.add);

      await settle();
      local
        ..failWith = const CacheException('read failed')
        ..emitChange();
      await settle();
      local
        ..failWith = null
        ..emitChange();
      await settle();

      expect(seen[1].isLeft(), isTrue);
      expect(seen[2].isRight(), isTrue, reason: 'recovers on the next write');
      await subscription.cancel();
    });
  });

  group('watchAll (AccountReader, E-27)', () {
    test('maps entities down to the narrower option', () async {
      local.rows = [
        AccountModel.fromEntity(
          account(id: 2, name: 'Bank').copyWith(
            icon: 'bank',
            currentBalanceCents: -125000,
            currency: 'USD',
          ),
        ),
      ];

      final rows = (await repository.watchAll().first).getOrElse((_) => []);

      expect(rows.single.id, 2);
      expect(rows.single.name, 'Bank');
      expect(rows.single.icon, 'bank');
      expect(rows.single.balanceCents, -125000);
      expect(rows.single.currency, 'USD');
    });

    test('excludes archived accounts, same as watch', () async {
      await repository.watchAll().first;
      expect(local.lastIncludeArchived, isFalse);
    });

    test(
      'is the same live read as watch — a write shows up unprompted',
      () async {
        final seen = <int>[];
        final subscription = repository.watchAll().listen(
          (either) => seen.add(either.getOrElse((_) => []).length),
        );

        await settle();
        local
          ..rows = [AccountModel.fromEntity(account())]
          ..emitChange();
        await settle();

        expect(seen, [0, 1]);
        await subscription.cancel();
      },
    );
  });
}

class _FakeLocalDataSource implements AccountLocalDataSource {
  final _changes = StreamController<void>.broadcast();

  AppException? failWith;
  int nextId = 1;
  int count = 0;
  int recomputed = 0;
  bool recomputedAll = false;
  bool? lastIncludeArchived;
  List<AccountModel> rows = [];
  final List<AccountModel> added = [];
  final List<({int id, bool archived})> archivedCalls = [];
  void Function()? onList;

  void emitChange() => _changes.add(null);

  void _maybeThrow() {
    final failure = failWith;
    if (failure != null) throw failure;
  }

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<int> add(AccountModel account) async {
    _maybeThrow();
    added.add(account);
    return nextId;
  }

  @override
  Future<void> update(AccountModel account) async => _maybeThrow();

  @override
  Future<void> setArchived(int id, {required bool archived}) async {
    _maybeThrow();
    archivedCalls.add((id: id, archived: archived));
  }

  @override
  Future<void> delete(int id) async => _maybeThrow();

  @override
  Future<int> transactionCount(int id) async {
    _maybeThrow();
    return count;
  }

  @override
  Future<List<AccountModel>> list({bool includeArchived = false}) async {
    lastIncludeArchived = includeArchived;
    onList?.call();
    _maybeThrow();
    return rows;
  }

  @override
  Future<int> recomputeBalance(int id) async {
    _maybeThrow();
    return recomputed;
  }

  @override
  Future<void> recomputeAllBalances() async {
    _maybeThrow();
    recomputedAll = true;
  }

  @override
  Future<void> dispose() => _changes.close();
}
