import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/domain/usecases/make_transfer.dart';

/// Validation is the whole point of this use case.
///
/// The schema already refuses most of what is tested here, but a `CHECK`
/// constraint failing produces a SQLite error message. These rules produce
/// sentences a screen can show, and they run before the database is touched.
void main() {
  late _FakeRepository repository;
  late MakeTransfer makeTransfer;

  final date = DateTime(2026, 9, 2);

  TransferParams params({
    int from = 2,
    int to = 1,
    int amountCents = 800000,
    DateTime? on,
    String? note,
    String fromCurrency = 'LKR',
    String toCurrency = 'LKR',
  }) => TransferParams(
    fromAccountId: from,
    toAccountId: to,
    amountCents: amountCents,
    date: on ?? date,
    note: note,
    fromCurrency: fromCurrency,
    toCurrency: toCurrency,
  );

  setUp(() {
    repository = _FakeRepository();
    makeTransfer = MakeTransfer(repository);
  });

  group('a valid transfer', () {
    test('reaches the repository with every field intact', () async {
      // Withdrawing Rs 8,000 from the card and holding it as cash.
      final result = await makeTransfer(params(note: 'Cash withdrawal'));

      expect(result, const Right<Failure, int>(7));
      expect(repository.received, (
        from: 2,
        to: 1,
        amount: 800000,
        date: date,
        note: 'Cash withdrawal',
      ));
    });

    test('surfaces a repository failure rather than throwing', () async {
      repository.failWith = const CacheFailure('disk full');

      final result = await makeTransfer(params());

      expect(result, const Left<Failure, int>(CacheFailure('disk full')));
    });
  });

  group('rejected before the database is touched', () {
    test('an amount of zero', () async {
      final result = await makeTransfer(params(amountCents: 0));

      expect(result.isLeft(), isTrue);
      expect(repository.received, isNull);
    });

    test('a negative amount', () async {
      // Direction comes from the two account fields, never from the sign, so
      // a negative amount has no meaning to interpret.
      expect((await makeTransfer(params(amountCents: -500))).isLeft(), isTrue);
    });

    test('the same account on both sides', () async {
      // Money cannot move to where it already is. CHECK(from_account_id <>
      // to_account_id) says the same thing in SQLite's voice.
      final result = await makeTransfer(params(from: 1, to: 1));

      expect(result.isLeft(), isTrue);
      expect(repository.received, isNull);
    });

    test('a date well into the future', () async {
      final result = await makeTransfer(
        params(on: DateTime.now().add(const Duration(days: 30))),
      );

      expect(result.isLeft(), isTrue);
    });

    test('but not tomorrow, which is a time zone away', () async {
      // A device clock in another zone is a legitimate reason for a date to
      // look like tomorrow. A month ahead is a typo.
      final result = await makeTransfer(
        params(on: DateTime.now().add(const Duration(hours: 6))),
      );

      expect(result.isRight(), isTrue);
    });

    test('two accounts holding different currencies', () async {
      // E-25's interim rule. FR-ACC-005 — the conversion that would make this
      // meaningful — is deferred to Sprint 7, so there is no rate to convert
      // at. Moving 100 from a USD account to an LKR one would credit 100
      // rupees: wrong by a factor of three hundred, and entirely plausible
      // on screen.
      final result = await makeTransfer(
        params(fromCurrency: 'USD', toCurrency: 'LKR'),
      );

      expect(result.isLeft(), isTrue);
      expect(repository.received, isNull);
    });

    test('and says which currency it would have to be, not just "no"', () {
      final failure = MakeTransfer.validate(
        params(fromCurrency: 'USD', toCurrency: 'LKR'),
      );

      expect(failure?.message, contains('two USD accounts'));
      // The destination is the control the user can usefully change; the
      // source is the account they started from.
      expect(failure?.field, 'toAccount');
    });

    test('but not two accounts whose codes differ only in case', () async {
      // `accounts.currency` is free text with a three-letter check, and
      // nothing forces upper case on the way in. Refusing LKR-to-lkr would be
      // refusing a transfer between two rupee accounts.
      final result = await makeTransfer(
        params(fromCurrency: 'lkr', toCurrency: ' LKR '),
      );

      expect(result.isRight(), isTrue);
      expect(repository.received, isNotNull);
    });
  });

  group('validate', () {
    test('names the field so a screen can highlight the right control', () {
      expect(MakeTransfer.validate(params(amountCents: 0))?.field, 'amount');
      expect(MakeTransfer.validate(params(from: 1, to: 1))?.field, 'toAccount');
    });

    test('returns null for a transfer that is fine', () {
      expect(MakeTransfer.validate(params()), isNull);
    });
  });

  group('TransferParams', () {
    test('compares by value, so it can be asserted on directly', () {
      expect(params(), params());
      expect(params(), isNot(params(amountCents: 1)));
      expect(params().hashCode, params().hashCode);
    });
  });
}

class _FakeRepository implements TransactionRepository {
  ({int from, int to, int amount, DateTime date, String? note})? received;
  Failure? failWith;

  @override
  Future<Either<Failure, int>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String? note,
  }) async {
    if (failWith case final failure?) return Left(failure);
    received = (
      from: fromAccountId,
      to: toAccountId,
      amount: amountCents,
      date: date,
      note: note,
    );
    return const Right(7);
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
  Stream<Either<Failure, List<Transaction>>> watch(TransactionFilter filter) =>
      const Stream.empty();
}
