@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/debts/domain/entities/debt.dart';
import 'package:moneyora/features/debts/domain/repositories/debt_repository.dart';
import 'package:moneyora/features/debts/presentation/pages/debt_form_page.dart';
import 'package:moneyora/features/debts/presentation/pages/debts_page.dart';
import 'package:moneyora/features/debts/presentation/pages/split_bill_page.dart';
import 'package:moneyora/features/debts/presentation/widgets/person_name_field.dart';
import 'package:moneyora/injection.dart';

import 'large_text.dart';

/// A repository in memory that streams every change, as the real one does.
class _InMemoryDebts implements DebtRepository {
  _InMemoryDebts([List<Debt> debts = const []]) : _debts = [...debts];

  final List<Debt> _debts;
  final _changes = StreamController<void>.broadcast();
  var _nextId = 100;

  List<Debt> get debts => List.unmodifiable(_debts);

  @override
  Stream<Either<Failure, List<Debt>>> watch() async* {
    yield Right(_sorted());
    await for (final _ in _changes.stream) {
      yield Right(_sorted());
    }
  }

  List<Debt> _sorted() => [
    ..._debts.where((d) => d.isOpen),
    ..._debts.where((d) => !d.isOpen),
  ];

  @override
  Future<Either<Failure, int>> add(Debt debt) async {
    final id = _nextId++;
    _debts.add(
      Debt(
        id: id,
        direction: debt.direction,
        person: debt.person,
        amountCents: debt.amountCents,
        note: debt.note,
        incurredOn: debt.incurredOn,
        dueOn: debt.dueOn,
        paidOn: debt.paidOn,
      ),
    );
    _changes.add(null);
    return Right(id);
  }

  @override
  Future<Either<Failure, List<int>>> addAll(List<Debt> debts) async =>
      Right([for (final debt in debts) (await add(debt)).getOrElse((_) => -1)]);

  @override
  Future<Either<Failure, Unit>> update(Debt debt) async {
    _debts[_debts.indexWhere((d) => d.id == debt.id)] = debt;
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> updateAll(List<Debt> debts) async {
    for (final debt in debts) {
      _debts[_debts.indexWhere((d) => d.id == debt.id)] = debt;
    }
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    _debts.removeWhere((d) => d.id == id);
    _changes.add(null);
    return const Right(unit);
  }
}

/// The debts list and form, over the real use cases. FR-DBT-001..003.
void main() {
  final today = DateTime(2026, 10, 9, 12);

  Debt debt(
    int id,
    String person,
    DebtDirection direction,
    int cents, {
    DateTime? due,
    DateTime? paid,
    String? note,
  }) => Debt(
    id: id,
    direction: direction,
    person: person,
    amountCents: cents,
    incurredOn: DateTime(2026, 9, 20),
    dueOn: due,
    paidOn: paid,
    note: note,
  );

  Widget boot(_InMemoryDebts repository, {bool dark = false}) => ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => today),
      debtRepositoryProvider.overrideWith((ref) async => repository),
    ],
    child: MaterialApp.router(
      theme: dark ? AppTheme.dark : AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.debts,
        routes: [
          GoRoute(
            path: Routes.debts,
            builder: (context, state) => const DebtsPage(),
          ),
          GoRoute(
            path: Routes.debtForm,
            builder: (context, state) =>
                DebtFormPage(initial: state.extra as Debt?),
          ),
          GoRoute(
            path: Routes.splitBill,
            builder: (context, state) => const SplitBillPage(),
          ),
        ],
      ),
    ),
  );

  Future<void> open(WidgetTester tester, _InMemoryDebts repository) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(boot(repository));
    await tester.pumpAndSettle();
  }

  /// Opens [name]'s row by its avatar, at the left: at the largest font
  /// the row starts below the totals, and the Add debt button floats over
  /// the middle of what is on screen.
  Future<void> expand(WidgetTester tester, String name) async {
    final avatar = find.descendant(
      of: find.ancestor(
        of: find.text(name),
        matching: find.byType(ExpansionTile),
      ),
      matching: find.byType(CircleAvatar),
    );
    await tester.scrollUntilVisible(
      avatar,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(avatar);
    await tester.pumpAndSettle();
    await tester.tap(avatar);
    await tester.pumpAndSettle();
  }

  /// Brings [finder] into view in the list.
  Future<void> reveal(WidgetTester tester, Finder finder) =>
      tester.scrollUntilVisible(
        finder,
        100,
        scrollable: find.byType(Scrollable).first,
      );

  testWidgets('with none, says what belongs here', (tester) async {
    await open(tester, _InMemoryDebts());

    expect(find.text('No debts yet'), findsOneWidget);
    expect(find.text('Add debt'), findsOneWidget);
  });

  testWidgets('the totals each way, one row per person, overdue said, and '
      'the settled folded away', (tester) async {
    await open(
      tester,
      _InMemoryDebts([
        debt(
          1,
          'Nimal',
          DebtDirection.owedToMe,
          250000,
          due: DateTime(2026, 10, 1),
          note: 'Train tickets',
        ),
        debt(2, 'Saman', DebtDirection.iOwe, 120000),
        debt(
          3,
          'Kamala',
          DebtDirection.owedToMe,
          50000,
          paid: DateTime(2026, 10, 2),
        ),
      ]),
    );

    expect(find.text('Owed to you'), findsOneWidget);
    expect(find.text('Rs2,500.00'), findsOneWidget);
    expect(find.text('You owe'), findsOneWidget);
    expect(find.text('Rs1,200.00'), findsOneWidget);
    expect(find.text('1 person is overdue.'), findsOneWidget);
    expect(find.text('Owes you Rs2,500.00 · overdue'), findsOneWidget);
    expect(find.text('You owe Rs1,200.00'), findsOneWidget);
    expect(find.text('Settled · 1'), findsOneWidget);
    // Folded: the settled person is not drawn until the section is opened.
    expect(find.text('Kamala'), findsNothing);

    // A person opens to the records behind the figure.
    expect(find.text('Train tickets'), findsNothing);
    await tester.tap(find.text('Nimal'));
    await tester.pumpAndSettle();
    expect(find.text('Train tickets'), findsOneWidget);
    expect(find.text('Overdue since Oct 1, 2026'), findsOneWidget);

    await tester.tap(find.text('Settled · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Kamala'), findsOneWidget);
  });

  group('by person. FR-DBT-005, E-47', () {
    testWidgets('a new record either way offsets what is already there', (
      tester,
    ) async {
      // The tester's example: Nimal owes the user Rs1,000, then the user
      // owes him Rs400. One row: he owes Rs600.
      await open(
        tester,
        _InMemoryDebts([
          debt(1, 'Nimal', DebtDirection.owedToMe, 100000, note: 'Loan'),
          debt(2, ' nimal', DebtDirection.iOwe, 40000, note: 'Lunch'),
        ]),
      );

      expect(find.text('Nimal'), findsOneWidget);
      expect(find.text('Owes you Rs600.00'), findsOneWidget);
      expect(find.text('Rs600.00'), findsOneWidget);
      expect(
        find.text(
          'Worked out person by person: what each one owes you, less what '
          'you owe them.',
        ),
        findsOneWidget,
      );

      // Both records are kept, each with its own tick.
      await tester.tap(find.text('Nimal'));
      await tester.pumpAndSettle();
      expect(find.text('Loan'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.byTooltip('Mark as paid'), findsNWidgets(2));
    });

    testWidgets('owing more than they do, the user owes them', (tester) async {
      await open(
        tester,
        _InMemoryDebts([
          debt(1, 'Saman', DebtDirection.owedToMe, 10000),
          debt(2, 'Saman', DebtDirection.iOwe, 35000),
        ]),
      );

      expect(find.text('You owe Rs250.00'), findsOneWidget);
    });

    testWidgets('square either way, says so', (tester) async {
      await open(
        tester,
        _InMemoryDebts([
          debt(1, 'Saman', DebtDirection.owedToMe, 35000),
          debt(2, 'Saman', DebtDirection.iOwe, 35000),
        ]),
      );

      expect(find.text('All square'), findsOneWidget);
    });
  });

  group('renaming a person. FR-DBT-006, E-47', () {
    Future<void> rename(WidgetTester tester, String from, String to) async {
      await tester.tap(find.text(from));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rename'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Name'), to);
      await tester.tap(find.widgetWithText(TextButton, 'Rename').last);
      await tester.pumpAndSettle();
    }

    testWidgets('renames every one of their records', (tester) async {
      final repository = _InMemoryDebts([
        debt(1, 'Nimal P', DebtDirection.owedToMe, 100000),
        debt(2, 'nimal p', DebtDirection.iOwe, 40000),
      ]);
      await open(tester, repository);

      await rename(tester, 'Nimal P', 'Nimal Perera');

      expect(repository.debts.map((d) => d.person), [
        'Nimal Perera',
        'Nimal Perera',
      ]);
      expect(find.text('Nimal Perera'), findsOneWidget);
    });

    testWidgets('to someone already listed, asks, then puts them together', (
      tester,
    ) async {
      final repository = _InMemoryDebts([
        debt(1, 'Nimal', DebtDirection.owedToMe, 100000),
        debt(2, 'Nimal P.', DebtDirection.iOwe, 40000),
      ]);
      await open(tester, repository);

      await rename(tester, 'Nimal P.', 'nimal');

      expect(find.text('Put them with Nimal?'), findsOneWidget);
      await tester.tap(find.text('Put together'));
      await tester.pumpAndSettle();

      // One spelling, the one already listed, and one net.
      expect(repository.debts.map((d) => d.person), ['Nimal', 'Nimal']);
      expect(find.text('Owes you Rs600.00'), findsOneWidget);
    });

    testWidgets('nothing is put together without saying so', (tester) async {
      final repository = _InMemoryDebts([
        debt(1, 'Nimal', DebtDirection.owedToMe, 100000),
        debt(2, 'Nimal P.', DebtDirection.iOwe, 40000),
      ]);
      await open(tester, repository);

      await rename(tester, 'Nimal P.', 'Nimal');
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(repository.debts.map((d) => d.person), ['Nimal', 'Nimal P.']);
    });

    testWidgets('a name of nothing is refused in the dialog', (tester) async {
      final repository = _InMemoryDebts([
        debt(1, 'Nimal', DebtDirection.owedToMe, 100000),
      ]);
      await open(tester, repository);

      await rename(tester, 'Nimal', '  ');

      expect(find.text('Say who.'), findsOneWidget);
      expect(repository.debts.single.person, 'Nimal');
    });
  });

  group('names already recorded are offered. FR-DBT-006', () {
    testWidgets('in the form, and taken with a tap', (tester) async {
      final repository = _InMemoryDebts([
        debt(1, 'Nimal Perera', DebtDirection.owedToMe, 100000),
      ]);
      await open(tester, repository);

      await tester.tap(find.text('Add debt'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Who owes you'),
        'nim',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ListTile, 'Nimal Perera'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '50');
      await tester.tap(find.widgetWithText(FilledButton, 'Add debt'));
      await tester.pumpAndSettle();

      expect(repository.debts.last.person, 'Nimal Perera');
      expect(find.text('Owes you Rs1,050.00'), findsOneWidget);
    });

    testWidgets('in a split, for each person', (tester) async {
      await open(
        tester,
        _InMemoryDebts([debt(1, 'Saman', DebtDirection.iOwe, 100)]),
      );
      await tester.tap(find.byTooltip('Split a bill'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Person 2'), 'sa');
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ListTile, 'Saman'), findsOneWidget);
    });

    test('a name is offered by its start first, then anywhere in it', () {
      expect(
        PersonNameField.suggestionsFor('ma', [
          'Amal',
          'Mala',
          'Kamala',
          'Nimal',
        ]),
        ['Mala', 'Amal', 'Kamala', 'Nimal'],
      );
      expect(PersonNameField.suggestionsFor('', ['Mala']), isEmpty);
      expect(PersonNameField.suggestionsFor('Mala', ['Mala']), isEmpty);
      expect(PersonNameField.suggestionsFor('mala', ['Mala']), ['Mala']);
    });
  });

  testWidgets('the tick marks it paid today, and Undo opens it again', (
    tester,
  ) async {
    final repository = _InMemoryDebts([
      debt(1, 'Nimal', DebtDirection.owedToMe, 250000),
    ]);
    await open(tester, repository);
    await tester.tap(find.text('Nimal'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Mark as paid'));
    await tester.pumpAndSettle();

    expect(repository.debts.single.paidOn, today);
    expect(find.text('Settled · 1'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(repository.debts.single.paidOn, isNull);
    expect(find.text('Settled · 1'), findsNothing);
  });

  testWidgets('a new debt is recorded from the form', (tester) async {
    final repository = _InMemoryDebts();
    await open(tester, repository);

    await tester.tap(find.text('Add debt'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I owe'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Who you owe'),
      'Saman',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '1200');
    await tester.enterText(find.widgetWithText(TextField, 'What for'), 'Lunch');
    await tester.tap(find.widgetWithText(FilledButton, 'Add debt'));
    await tester.pumpAndSettle();

    final saved = repository.debts.single;
    expect(saved.person, 'Saman');
    expect(saved.direction, DebtDirection.iOwe);
    expect(saved.amountCents, 120000);
    expect(saved.note, 'Lunch');
    expect(find.text('You owe Rs1,200.00'), findsOneWidget);
  });

  testWidgets('the form says what is missing, in the use case\'s words', (
    tester,
  ) async {
    final repository = _InMemoryDebts();
    await open(tester, repository);

    await tester.tap(find.text('Add debt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add debt'));
    await tester.pumpAndSettle();

    expect(find.text('Say who.'), findsOneWidget);
    expect(repository.debts, isEmpty);
  });

  testWidgets('a debt is opened to change, and deleted after asking', (
    tester,
  ) async {
    final repository = _InMemoryDebts([
      debt(1, 'Nimal', DebtDirection.owedToMe, 250000),
    ]);
    await open(tester, repository);

    await tester.tap(find.text('Nimal'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Owed to you').last);
    await tester.pumpAndSettle();
    expect(find.text('Edit debt'), findsOneWidget);
    await tester.tap(find.text('Delete debt'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repository.debts, isEmpty);
    expect(find.text('No debts yet'), findsOneWidget);
  });

  group('splitting a bill. FR-DBT-004', () {
    Future<void> openSplit(WidgetTester tester, _InMemoryDebts debts) async {
      await open(tester, debts);
      await tester.tap(find.byTooltip('Split a bill'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows each share as it is typed, adding up to the bill, '
        'and saves what the others owe', (tester) async {
      final repository = _InMemoryDebts();
      await openSplit(tester, repository);

      await tester.enterText(find.widgetWithText(TextField, 'Total'), '1000');
      await tester.enterText(
        find.widgetWithText(TextField, 'What for'),
        'Dinner',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Person 2'),
        'Nimal',
      );
      await tester.tap(find.text('Add a person'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Person 3'),
        'Saman',
      );
      await tester.pumpAndSettle();

      expect(find.text('Shared by 3'), findsOneWidget);
      // 1,000 in three: the odd cent is the user's.
      expect(find.text('Rs333.34'), findsOneWidget);
      expect(find.text('Rs333.33'), findsNWidgets(2));

      await tester.tap(find.text('Save as debts'));
      await tester.pumpAndSettle();

      expect(
        repository.debts.map((d) => (d.person, d.direction, d.amountCents)),
        [
          ('Nimal', DebtDirection.owedToMe, 33333),
          ('Saman', DebtDirection.owedToMe, 33333),
        ],
      );
      expect(repository.debts.first.note, 'Dinner, split 3 ways');
      // Back on the list, which shows them.
      expect(find.text('Owes you Rs333.33'), findsNWidgets(2));
    });

    testWidgets('someone else paid: the user owes them a share', (
      tester,
    ) async {
      final repository = _InMemoryDebts();
      await openSplit(tester, repository);

      await tester.enterText(find.widgetWithText(TextField, 'Total'), '900');
      await tester.enterText(
        find.widgetWithText(TextField, 'Person 2'),
        'Nimal',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('You').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nimal').last);
      await tester.pumpAndSettle();

      expect(find.text('You will owe Nimal Rs450.00.'), findsOneWidget);
      await tester.tap(find.text('Save as debts'));
      await tester.pumpAndSettle();

      expect(repository.debts.single.direction, DebtDirection.iOwe);
      expect(repository.debts.single.amountCents, 45000);
    });

    testWidgets('a person with no name is refused, and nothing is saved', (
      tester,
    ) async {
      final repository = _InMemoryDebts();
      await openSplit(tester, repository);

      await tester.enterText(find.widgetWithText(TextField, 'Total'), '900');
      await tester.tap(find.text('Save as debts'));
      await tester.pumpAndSettle();

      expect(find.text('Give everyone a name.'), findsOneWidget);
      expect(repository.debts, isEmpty);
    });

    testWidgets('removing the one who paid hands it back to the user', (
      tester,
    ) async {
      await openSplit(tester, _InMemoryDebts());

      await tester.enterText(find.widgetWithText(TextField, 'Total'), '900');
      await tester.enterText(
        find.widgetWithText(TextField, 'Person 2'),
        'Nimal',
      );
      await tester.tap(find.text('Add a person'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Person 3'),
        'Saman',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('You').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Saman').last);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove').last);
      await tester.pumpAndSettle();

      expect(
        find.text('Each of the others will owe you their share.'),
        findsOneWidget,
      );
    });

    testWidgets('holds at the largest font on a 320dp phone', (tester) async {
      useLargeTextOnSmallPhone(tester);
      await tester.pumpWidget(boot(_InMemoryDebts()));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Split a bill'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Total'),
        '1234567',
      );
      await tester.pumpAndSettle();
      await scrollToEnd(tester);

      expect(find.text('Save as debts'), findsOneWidget);
    });
  });

  testWidgets('holds at the largest font on a 320dp phone. SRS §4.1', (
    tester,
  ) async {
    useLargeTextOnSmallPhone(tester);
    await tester.pumpWidget(
      boot(
        _InMemoryDebts([
          debt(
            1,
            'Someone with a rather long name',
            DebtDirection.owedToMe,
            123456789,
            due: DateTime(2026, 10, 1),
            note: 'A long note about what the money was for',
          ),
        ]),
      ),
    );
    await tester.pumpAndSettle();
    await expand(tester, 'Someone with a rather long name');
    await reveal(tester, find.byTooltip('Mark as paid'));
    await scrollToEnd(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Rename'), findsOneWidget);
  });

  group('read whole at the largest font on a 320dp phone. SRS §4.1', () {
    for (final dark in [false, true]) {
      final theme = dark ? 'dark' : 'light';

      testWidgets('a record keeps the row for what it was: the amount moves '
          'under it ($theme)', (tester) async {
        useLargeTextOnSmallPhone(tester);
        await tester.pumpWidget(
          boot(
            _InMemoryDebts([
              debt(1, 'Ama', DebtDirection.owedToMe, 123456789, note: 'Rent'),
            ]),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        await expand(tester, 'Ama');
        await reveal(tester, find.byTooltip('Mark as paid'));

        // Beside the amount and the tick, the name had 16px.
        expect(isCut(tester, find.text('Rent')), isFalse);
        final amount = find.text('Rs1,234,567.89').last;
        expect(
          tester.getTopLeft(amount).dy,
          greaterThan(tester.getBottomLeft(find.text('Rent')).dy - 1),
        );
        expect(find.byTooltip('Mark as paid'), findsOneWidget);
      });

      testWidgets('a person says what is owed in full ($theme)', (
        tester,
      ) async {
        useLargeTextOnSmallPhone(tester);
        await tester.pumpWidget(
          boot(
            _InMemoryDebts([
              debt(
                1,
                'Someone with a rather long name',
                DebtDirection.iOwe,
                123456789,
                due: DateTime(2026, 10, 1),
              ),
            ]),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(
          isCut(tester, find.text('You owe Rs1,234,567.89 · overdue')),
          isFalse,
        );
      });

      testWidgets('the rename dialog holds its field and its refusal '
          '($theme)', (tester) async {
        useLargeTextOnSmallPhone(tester);
        await tester.pumpWidget(
          boot(
            _InMemoryDebts([debt(1, 'Ama', DebtDirection.owedToMe, 100)]),
            dark: dark,
          ),
        );
        await tester.pumpAndSettle();
        await expand(tester, 'Ama');
        await scrollToEnd(tester);
        await tester.tap(find.text('Rename'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '');
        await tester.tap(find.widgetWithText(TextButton, 'Rename').last);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('Say who.'), findsOneWidget);
      });

      testWidgets('the debt form names its note field in full ($theme)', (
        tester,
      ) async {
        useSmallPhone(tester);
        await tester.pumpWidget(boot(_InMemoryDebts(), dark: dark));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add debt'));
        await tester.pumpAndSettle();
        await tester.dragUntilVisible(
          find.text('Optional'),
          find.byType(ListView).last,
          const Offset(0, -150),
        );

        expect(isCut(tester, find.text('What for')), isFalse);
      });

      testWidgets('a split names its note field in full ($theme)', (
        tester,
      ) async {
        useSmallPhone(tester);
        await tester.pumpWidget(boot(_InMemoryDebts(), dark: dark));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Split a bill'));
        await tester.pumpAndSettle();

        expect(isCut(tester, find.text('What for')), isFalse);
      });

      testWidgets('a person in a split has the room their share does not '
          'need ($theme)', (tester) async {
        useLargeTextOnSmallPhone(tester);
        await tester.pumpWidget(boot(_InMemoryDebts(), dark: dark));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Split a bill'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.widgetWithText(TextField, 'Total'),
          '1234567',
        );
        await tester.pumpAndSettle();

        // An even split with the share left the name field 138px here,
        // too narrow for its own "Person 2" at this size.
        final person = find.widgetWithText(TextField, 'Person 2');
        await tester.dragUntilVisible(
          person,
          find.byType(ListView).last,
          const Offset(0, -150),
        );
        expect(tester.getSize(person).width, greaterThan(170));
      });
    }
  });
}
