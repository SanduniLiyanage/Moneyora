import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/accounts/domain/repositories/account_repository.dart';
import 'package:moneyora/features/accounts/domain/usecases/add_account.dart';
import 'package:moneyora/features/accounts/domain/usecases/archive_account.dart';
import 'package:moneyora/features/accounts/domain/usecases/delete_account.dart';
import 'package:moneyora/features/accounts/domain/usecases/recompute_account_balance.dart';
import 'package:moneyora/features/accounts/domain/usecases/update_account.dart';
import 'package:moneyora/features/accounts/domain/usecases/watch_accounts.dart';

/// The six account use cases share one collaborator, and the fake below is
/// most of the code either way.
///
/// `ARCHITECTURE.md` §4 says a test file mirrors its source, and six files here
/// would mean six copies of that fake — which is exactly the thing most likely
/// to drift out of step with the interface. One file, six groups, one fake.
void main() {
  late _FakeRepository repository;

  final opened = DateTime(2026, 1, 1);

  Account account({
    int? id = 1,
    String name = 'Savings',
    String currency = 'LKR',
    DateTime? openedOn,
    bool isArchived = false,
  }) => Account(
    id: id,
    name: name,
    icon: 'bank',
    currency: currency,
    initialBalanceDate: openedOn ?? opened,
    isArchived: isArchived,
  );

  setUp(() => repository = _FakeRepository());

  group('AddAccount', () {
    test('saves a valid account', () async {
      final result = await AddAccount(repository)(account(id: null));

      expect(result, const Right<Failure, int>(9));
      expect(repository.added?.name, 'Savings');
    });

    test('rejects a blank name, naming the field', () async {
      final failure = AddAccount.validate(account(name: '   '));

      expect(failure?.field, 'name');
      expect(
        (await AddAccount(repository)(account(name: ''))).isLeft(),
        isTrue,
      );
      expect(repository.added, isNull);
    });

    test('rejects a name too long for the list to render', () async {
      expect(AddAccount.validate(account(name: 'x' * 41)), isNotNull);
      expect(AddAccount.validate(account(name: 'x' * 40)), isNull);
    });

    test('rejects a currency code that is not three letters', () async {
      expect(
        AddAccount.validate(account(currency: 'RUPEE'))?.field,
        'currency',
      );
    });

    test('rejects an opening balance dated in the future', () async {
      final failure = AddAccount.validate(
        account(openedOn: DateTime.now().add(const Duration(days: 30))),
      );

      expect(failure?.field, 'initialBalanceDate');
    });

    test('allows a negative opening balance', () async {
      // A credit card opens owing money. Unlike a transaction amount, a
      // negative here is ordinary rather than suspicious.
      final card = Account(
        name: 'Visa',
        icon: 'card',
        type: AccountType.creditCard,
        initialBalanceCents: -450000,
        initialBalanceDate: opened,
      );

      expect(AddAccount.validate(card), isNull);
    });
  });

  group('UpdateAccount', () {
    test('saves an edit', () async {
      final result = await UpdateAccount(repository)(account(name: 'Renamed'));

      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.updated?.name, 'Renamed');
    });

    test('refuses an account that was never saved', () async {
      final result = await UpdateAccount(repository)(account(id: null));

      expect(result.isLeft(), isTrue);
      expect(repository.updated, isNull);
    });

    test('applies the same rules as AddAccount', () async {
      // Delegated, not restated — an edit form accepting what a create form
      // rejects is a bug nobody thinks to look for.
      final result = await UpdateAccount(repository)(account(name: ''));

      expect(result.isLeft(), isTrue);
    });
  });

  group('ArchiveAccount', () {
    test('archives when another account remains', () async {
      repository.accounts = [account(), account(id: 2, name: 'Cash')];

      final result = await ArchiveAccount(repository)(
        const ArchiveParams(accountId: 1),
      );

      expect(result.isRight(), isTrue);
      expect(repository.archivedCalls.single, (id: 1, archived: true));
    });

    test('refuses to archive the last usable account', () async {
      // Otherwise there is nowhere left to record a transaction, and the entry
      // screen has no account to default to — a dead end reached through a
      // control that looks harmless.
      repository.accounts = [account()];

      final result = await ArchiveAccount(repository)(
        const ArchiveParams(accountId: 1),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.archivedCalls, isEmpty);
    });

    test('counts only unarchived accounts as remaining', () async {
      repository.accounts = [
        account(),
        account(id: 2, name: 'Closed', isArchived: true),
      ];

      final result = await ArchiveAccount(repository)(
        const ArchiveParams(accountId: 1),
      );

      expect(result.isLeft(), isTrue);
    });

    test('un-archiving is always allowed', () async {
      repository.accounts = [account(isArchived: true)];

      final result = await ArchiveAccount(repository)(
        const ArchiveParams(accountId: 1, archived: false),
      );

      expect(result.isRight(), isTrue);
      expect(repository.archivedCalls.single, (id: 1, archived: false));
    });
  });

  group('DeleteAccount', () {
    test('deletes an account nothing references', () async {
      repository.count = 0;

      final result = await DeleteAccount(repository)(1);

      expect(result, const Right<Failure, Unit>(unit));
      expect(repository.deletedId, 1);
    });

    test('refuses once it has history, and says how much', () async {
      repository.count = 12;

      final result = await DeleteAccount(repository)(1);

      expect(repository.deletedId, isNull);
      result.match(
        (failure) => expect(failure.message, contains('12 transactions')),
        (_) => fail('should have refused'),
      );
    });

    test('gets the singular right for one transaction', () async {
      repository.count = 1;

      final result = await DeleteAccount(repository)(1);

      result.match(
        (failure) => expect(failure.message, contains('one transaction')),
        (_) => fail('should have refused'),
      );
    });
  });

  group('RecomputeAccountBalance', () {
    test('recomputes one account and returns its balance', () async {
      repository.recomputed = -125000;

      final result = await RecomputeAccountBalance(repository)(1);

      expect(result, const Right<Failure, int>(-125000));
      expect(repository.recomputedId, 1);
    });

    test('null recomputes every account', () async {
      // What a restore needs: every balance re-derived, with no single number
      // to report back.
      final result = await RecomputeAccountBalance(repository)(null);

      expect(result, const Right<Failure, int>(0));
      expect(repository.recomputedAll, isTrue);
      expect(repository.recomputedId, isNull);
    });

    test('surfaces a failure rather than throwing', () async {
      repository.failWith = const CacheFailure('database is locked');

      final result = await RecomputeAccountBalance(repository)(1);

      expect(result.isLeft(), isTrue);
    });
  });

  group('WatchAccounts', () {
    test('passes the archived flag through', () async {
      await WatchAccounts(repository)(true).first;

      expect(repository.watchedIncludingArchived, isTrue);
    });

    test('forwards what the repository emits', () async {
      repository.accounts = [account()];

      final emitted = await WatchAccounts(repository)(false).first;

      expect(emitted.getOrElse((_) => []), hasLength(1));
    });
  });
}

class _FakeRepository implements AccountRepository {
  List<Account> accounts = [];
  Account? added;
  Account? updated;
  int? deletedId;
  int count = 0;
  int recomputed = 0;
  int? recomputedId;
  bool recomputedAll = false;
  bool? watchedIncludingArchived;
  Failure? failWith;
  final List<({int id, bool archived})> archivedCalls = [];

  @override
  Future<Either<Failure, int>> add(Account account) async {
    if (failWith case final failure?) return Left(failure);
    added = account;
    return const Right(9);
  }

  @override
  Future<Either<Failure, Unit>> update(Account account) async {
    if (failWith case final failure?) return Left(failure);
    updated = account;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> setArchived(
    int id, {
    required bool archived,
  }) async {
    if (failWith case final failure?) return Left(failure);
    archivedCalls.add((id: id, archived: archived));
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    if (failWith case final failure?) return Left(failure);
    deletedId = id;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, int>> transactionCount(int id) async {
    if (failWith case final failure?) return Left(failure);
    return Right(count);
  }

  @override
  Future<Either<Failure, List<Account>>> list({
    bool includeArchived = false,
  }) async {
    if (failWith case final failure?) return Left(failure);
    return Right(
      includeArchived
          ? accounts
          : accounts.where((a) => !a.isArchived).toList(),
    );
  }

  @override
  Stream<Either<Failure, List<Account>>> watch({bool includeArchived = false}) {
    watchedIncludingArchived = includeArchived;
    return Stream.value(Right(accounts));
  }

  @override
  Future<Either<Failure, int>> recomputeBalance(int id) async {
    if (failWith case final failure?) return Left(failure);
    recomputedId = id;
    return Right(recomputed);
  }

  @override
  Future<Either<Failure, Unit>> recomputeAllBalances() async {
    if (failWith case final failure?) return Left(failure);
    recomputedAll = true;
    return const Right(unit);
  }
}
