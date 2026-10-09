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
  });

  test('DeleteDebt removes the one named', () async {
    await DeleteDebt(repository)(7);

    expect(repository.deleted, [7]);
  });
}
