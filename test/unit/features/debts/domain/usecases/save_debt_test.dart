import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/repositories/debt_repository.dart';
import 'package:moneyora/features/debts/domain/usecases/delete_debt.dart';
import 'package:moneyora/features/debts/domain/usecases/save_debt.dart';
import 'package:moneyora/features/debts/domain/usecases/set_debt_paid.dart';

/// Records what it was asked to write.
class _FakeRepository implements DebtRepository {
  final List<Debt> added = [];
  final List<Debt> updated = [];
  final List<int> deleted = [];

  @override
  Future<Either<Failure, int>> add(Debt debt) async {
    added.add(debt);
    return Right(added.length);
  }

  @override
  Future<Either<Failure, Unit>> update(Debt debt) async {
    updated.add(debt);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> updateAll(List<Debt> debts) async {
    updated.addAll(debts);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, List<int>>> batch({
    List<Debt> add = const [],
    List<Debt> update = const [],
    List<int> delete = const [],
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    deleted.add(id);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, List<int>>> addAll(List<Debt> debts) =>
      throw UnimplementedError();

  @override
  Stream<Either<Failure, List<Debt>>> watch() => throw UnimplementedError();
}

/// FR-DBT-001, FR-DBT-003.
void main() {
  late _FakeRepository repository;
  final today = DateTime.now();

  setUp(() => repository = _FakeRepository());

  Debt debt({
    int? id,
    String person = 'Nimal',
    int cents = 250000,
    DateTime? incurredOn,
    DateTime? dueOn,
    String? note,
  }) => Debt(
    id: id,
    direction: DebtDirection.owedToMe,
    person: person,
    amountCents: cents,
    incurredOn: incurredOn ?? DateTime(2026, 10, 1),
    dueOn: dueOn,
    note: note,
  );

  group('SaveDebt', () {
    test('a new debt is added, its name and note trimmed', () async {
      final result = await SaveDebt(repository)(
        debt(person: '  Nimal ', note: '  Train  '),
      );

      expect(result.isRight(), isTrue);
      expect(repository.added.single.person, 'Nimal');
      expect(repository.added.single.note, 'Train');
      expect(repository.updated, isEmpty);
    });

    test('a blank note is no note', () async {
      await SaveDebt(repository)(debt(note: '   '));

      expect(repository.added.single.note, isNull);
    });

    test('a payment is kept as one, with no due day. FR-DBT-008', () async {
      await SaveDebt(repository)(
        Debt(
          direction: DebtDirection.iOwe,
          person: 'Nimal',
          amountCents: 30000,
          incurredOn: DateTime(2026, 10, 5),
          dueOn: DateTime(2026, 11, 1),
          isPayment: true,
        ),
      );

      expect(repository.added.single.isPayment, isTrue);
      expect(repository.added.single.dueOn, isNull);
      expect(repository.added.single.amountCents, 30000);
    });

    test('keeps the account it went through, and the one it came back '
        'through only once paid. FR-DBT-009', () async {
      Debt linked({DateTime? paidOn, bool payment = false}) => Debt(
        direction: DebtDirection.owedToMe,
        person: 'Nimal',
        amountCents: 1000,
        incurredOn: DateTime(2026, 10, 1),
        accountId: 1,
        paidOn: paidOn,
        paidAccountId: 2,
        isPayment: payment,
      );

      await SaveDebt(repository)(linked());
      await SaveDebt(repository)(linked(paidOn: DateTime(2026, 10, 3)));
      await SaveDebt(repository)(
        linked(paidOn: DateTime(2026, 10, 3), payment: true),
      );

      expect([for (final d in repository.added) d.accountId], [1, 1, 1]);
      expect(
        [for (final d in repository.added) d.paidAccountId],
        [null, 2, null],
      );
    });

    test('one with an id is a change, not a second debt', () async {
      await SaveDebt(repository)(debt(id: 4));

      expect(repository.updated.single.id, 4);
      expect(repository.added, isEmpty);
    });

    test('refuses no one, in its own words', () async {
      final result = await SaveDebt(repository)(debt(person: '  '));

      expect(
        result,
        const Left<Failure, Unit>(
          ValidationFailure('Say who.', field: 'person'),
        ),
      );
      expect(repository.added, isEmpty);
    });

    test('refuses a name past the limit', () {
      expect(SaveDebt.validate(debt(person: 'x' * 61))?.field, 'person');
      expect(SaveDebt.validate(debt(person: 'x' * 60)), isNull);
    });

    test('refuses nothing owed', () {
      expect(SaveDebt.validate(debt(cents: 0))?.field, 'amount');
      expect(SaveDebt.validate(debt(cents: -5))?.field, 'amount');
    });

    test('refuses a start in the future, but not today', () {
      expect(
        SaveDebt.validate(debt(incurredOn: today.add(const Duration(days: 1))))
            ?.field,
        'incurredOn',
      );
      expect(SaveDebt.validate(debt(incurredOn: today)), isNull);
    });

    test('refuses a due day before the start, but not on it', () {
      expect(
        SaveDebt.validate(debt(dueOn: DateTime(2026, 9, 30)))?.field,
        'dueOn',
      );
      expect(SaveDebt.validate(debt(dueOn: DateTime(2026, 10, 1))), isNull);
    });
  });

  group('SetDebtPaid', () {
    test('records the day it was paid, and opens it again', () async {
      final paid = await SetDebtPaid(repository)(
        DebtPayment(debt(id: 2), paidOn: DateTime(2026, 10, 9)),
      );
      final reopened = await SetDebtPaid(repository)(
        DebtPayment(debt(id: 2), paidOn: null),
      );

      expect(paid.isRight() && reopened.isRight(), isTrue);
      expect(repository.updated.map((d) => d.paidOn), [
        DateTime(2026, 10, 9),
        null,
      ]);
    });

    test('refuses a debt never saved, and a payment before it began', () async {
      final unsaved = await SetDebtPaid(repository)(
        DebtPayment(debt(), paidOn: DateTime(2026, 10, 9)),
      );
      final early = await SetDebtPaid(repository)(
        DebtPayment(debt(id: 2), paidOn: DateTime(2026, 9, 1)),
      );

      expect(unsaved.isLeft(), isTrue);
      expect(early.isLeft(), isTrue);
      expect(repository.updated, isEmpty);
    });

    test('paid back through an account, and opened again through none. '
        'FR-DBT-009', () async {
      final linked = Debt(
        id: 2,
        direction: DebtDirection.owedToMe,
        person: 'Nimal',
        amountCents: 1000,
        incurredOn: DateTime(2026, 10, 1),
        accountId: 1,
      );

      await SetDebtPaid(repository)(
        DebtPayment(linked, paidOn: DateTime(2026, 10, 9), through: 2),
      );
      await SetDebtPaid(repository)(
        DebtPayment(
          linked.withPaidOn(DateTime(2026, 10, 9), through: 2),
          paidOn: null,
          through: 2,
        ),
      );

      expect(repository.updated.first.paidAccountId, 2);
      expect(repository.updated.first.accountId, 1);
      expect(repository.updated.last.paidOn, isNull);
      expect(repository.updated.last.paidAccountId, isNull);
    });

    test(
      'refuses a payment, which closes when the person is settled up',
      () async {
        final result = await SetDebtPaid(repository)(
          DebtPayment(
            Debt(
              id: 3,
              direction: DebtDirection.iOwe,
              person: 'Nimal',
              amountCents: 30000,
              incurredOn: DateTime(2026, 10, 5),
              isPayment: true,
            ),
            paidOn: DateTime(2026, 10, 9),
          ),
        );

        expect(
          result.match((f) => f.message, (_) => 'written'),
          'A payment closes when you settle up with the person.',
        );
        expect(repository.updated, isEmpty);
      },
    );
  });

  test('DeleteDebt removes the one named', () async {
    await DeleteDebt(repository)(7);

    expect(repository.deleted, [7]);
  });
}
