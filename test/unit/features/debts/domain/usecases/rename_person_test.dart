import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/entities/debt_person.dart';
import 'package:moneyora/features/debts/domain/repositories/debt_repository.dart';
import 'package:moneyora/features/debts/domain/usecases/rename_person.dart';

class _Recording implements DebtRepository {
  final List<List<Debt>> updates = [];

  @override
  Future<Either<Failure, Unit>> updateAll(List<Debt> debts) async {
    updates.add(debts);
    return const Right(unit);
  }

  @override
  Stream<Either<Failure, List<Debt>>> watch() => const Stream.empty();

  @override
  Future<Either<Failure, int>> add(Debt debt) => throw UnimplementedError();

  @override
  Future<Either<Failure, List<int>>> addAll(List<Debt> debts) =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> update(Debt debt) => throw UnimplementedError();

  @override
  Future<Either<Failure, List<int>>> batch({
    List<Debt> add = const [],
    List<Debt> update = const [],
    List<int> delete = const [],
  }) => throw UnimplementedError();

  @override
  Future<Either<Failure, Unit>> delete(int id) => throw UnimplementedError();
}

/// A person renamed on every record, or put together with another.
/// FR-DBT-006, E-47.
void main() {
  late _Recording repository;
  late RenamePerson rename;

  setUp(() {
    repository = _Recording();
    rename = RenamePerson(repository);
  });

  Debt debt(int id, String person) => Debt(
    id: id,
    direction: DebtDirection.owedToMe,
    person: person,
    amountCents: 1000,
    incurredOn: DateTime(2026, 10, 1),
  );

  final nimalP = DebtPerson(
    name: 'Nimal P.',
    records: [debt(1, 'Nimal P.'), debt(2, 'nimal p.')],
  );

  test('renames every record of the person, in one write', () async {
    final result = await rename(PersonRename(nimalP, to: '  Nimal  '));

    expect(result, const Right<Failure, Unit>(unit));
    expect(repository.updates, hasLength(1));
    expect(
      [for (final d in repository.updates.single) d.person],
      ['Nimal', 'Nimal'],
    );
    // Nothing but the name changes.
    expect(repository.updates.single.first.amountCents, 1000);
    expect(repository.updates.single.first.id, 1);
  });

  test('leaves records already spelled that way alone', () async {
    await rename(
      PersonRename(
        DebtPerson(
          name: 'Nimal',
          records: [debt(1, 'Nimal'), debt(2, 'nimal')],
        ),
        to: 'Nimal',
      ),
    );

    expect([for (final d in repository.updates.single) d.id], [2]);
  });

  test('does nothing for the name it already has', () async {
    final result = await rename(
      PersonRename(
        DebtPerson(name: 'Nimal', records: [debt(1, 'Nimal')]),
        to: 'Nimal',
      ),
    );

    expect(result.isRight(), isTrue);
    expect(repository.updates, isEmpty);
  });

  test('refuses no name, in the form\'s own words', () async {
    final result = await rename(PersonRename(nimalP, to: '   '));

    expect(
      result,
      const Left<Failure, Unit>(ValidationFailure('Say who.', field: 'person')),
    );
    expect(repository.updates, isEmpty);
  });

  test('refuses a name too long to keep', () async {
    final result = await rename(PersonRename(nimalP, to: 'x' * 61));

    expect(result.isLeft(), isTrue);
    expect(repository.updates, isEmpty);
  });
}
