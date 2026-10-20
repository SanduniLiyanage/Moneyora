import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/entities/debt_person.dart';

/// Debts grouped by person and netted. FR-DBT-005, FR-DBT-006, E-47.
void main() {
  final today = DateTime(2026, 10, 20, 9);
  var nextId = 1;

  Debt debt(
    String person,
    DebtDirection direction,
    int cents, {
    DateTime? on,
    DateTime? due,
    DateTime? paid,
  }) => Debt(
    id: nextId++,
    direction: direction,
    person: person,
    amountCents: cents,
    incurredOn: on ?? DateTime(2026, 10, 1),
    dueOn: due,
    paidOn: paid,
  );

  group('matching people', () {
    test('ignores case, the spaces around, and doubled spaces between', () {
      expect(personKey('  Nimal  Perera '), 'nimal perera');
      expect(personKey('NIMAL'), personKey('nimal'));
    });

    test('keeps a different name a different person until told', () {
      expect(personKey('Nimal P.'), isNot(personKey('Nimal')));
    });
  });

  group('one person', () {
    test('nets a new record against what is already there', () {
      // The tester's example: Nimal owes Rs1,000, then the user owes him
      // Rs400; the list says he owes Rs600.
      final people = DebtPerson.group([
        debt('Nimal', DebtDirection.owedToMe, 100000),
        debt('nimal', DebtDirection.iOwe, 40000),
      ], today: today);

      expect(people, hasLength(1));
      expect(people.single.netCents, 60000);
      expect(people.single.records, hasLength(2));
    });

    test('owed more by the user than to them, the net is below zero', () {
      final person = DebtPerson.group([
        debt('Saman', DebtDirection.owedToMe, 10000),
        debt('Saman', DebtDirection.iOwe, 35000),
      ], today: today).single;

      expect(person.netCents, -25000);
    });

    test('paid records are history: kept, and not counted', () {
      final person = DebtPerson.group([
        debt('Nimal', DebtDirection.owedToMe, 100000),
        debt(
          'Nimal',
          DebtDirection.owedToMe,
          70000,
          paid: DateTime(2026, 10, 5),
        ),
      ], today: today).single;

      expect(person.netCents, 100000);
      expect(person.open, hasLength(1));
      expect(person.paid, hasLength(1));
    });

    test('is named as most of their records are, the first a tie', () {
      final tie = DebtPerson.group([
        debt('Nimal', DebtDirection.owedToMe, 100, on: DateTime(2026, 9, 1)),
        debt('nimal', DebtDirection.owedToMe, 100, on: DateTime(2026, 10, 1)),
      ], today: today).single;
      final most = DebtPerson.group([
        debt('kasun', DebtDirection.owedToMe, 100, on: DateTime(2026, 9, 1)),
        debt('Kasun', DebtDirection.owedToMe, 100, on: DateTime(2026, 10, 1)),
        debt('Kasun', DebtDirection.owedToMe, 100, on: DateTime(2026, 10, 2)),
      ], today: today).single;

      expect(tie.name, 'Nimal');
      expect(most.name, 'Kasun');
    });

    test('is overdue only on a record running the way the net runs', () {
      final owesUser = DebtPerson.group([
        debt('Nimal', DebtDirection.owedToMe, 100000),
        // The user's own debt to him is late, but he owes more.
        debt('Nimal', DebtDirection.iOwe, 10000, due: DateTime(2026, 10, 10)),
      ], today: today).single;
      final late = DebtPerson.group([
        debt(
          'Kasun',
          DebtDirection.owedToMe,
          5000,
          due: DateTime(2026, 10, 10),
        ),
      ], today: today).single;

      expect(owesUser.isOverdue(today), isFalse);
      expect(late.isOverdue(today), isTrue);
    });

    test('square, is not overdue', () {
      final person = DebtPerson.group([
        debt('Nimal', DebtDirection.owedToMe, 5000, due: DateTime(2026, 10, 1)),
        debt('Nimal', DebtDirection.iOwe, 5000),
      ], today: today).single;

      expect(person.netCents, 0);
      expect(person.isOverdue(today), isFalse);
    });
  });

  group('the order of people', () {
    test('open first: overdue, then soonest due, then most owed', () {
      final people = DebtPerson.group([
        debt('Small', DebtDirection.owedToMe, 100),
        debt('Big', DebtDirection.iOwe, 900000),
        debt('Soon', DebtDirection.owedToMe, 100, due: DateTime(2026, 11, 1)),
        debt('Late', DebtDirection.owedToMe, 100, due: DateTime(2026, 10, 2)),
        debt('Done', DebtDirection.owedToMe, 100, paid: DateTime(2026, 10, 3)),
      ], today: today);

      expect(
        [for (final p in people) p.name],
        ['Late', 'Soon', 'Big', 'Small', 'Done'],
      );
    });

    test('settled people last, the most recently settled first', () {
      final people = DebtPerson.group([
        debt('Early', DebtDirection.iOwe, 100, paid: DateTime(2026, 9, 1)),
        debt('Lately', DebtDirection.iOwe, 100, paid: DateTime(2026, 10, 9)),
      ], today: today);

      expect([for (final p in people) p.name], ['Lately', 'Early']);
      expect(people.every((p) => !p.hasOpen), isTrue);
    });
  });

  test('names offers each person once, as the list names them', () {
    final names = DebtPerson.names([
      debt('Saman', DebtDirection.iOwe, 100, on: DateTime(2026, 9, 1)),
      debt('saman', DebtDirection.iOwe, 100, on: DateTime(2026, 10, 1)),
      debt('Amal', DebtDirection.owedToMe, 100),
    ]);

    expect(names, ['Amal', 'Saman']);
  });
}
