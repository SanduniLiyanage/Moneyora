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

  Widget boot(_InMemoryDebts repository) => ProviderScope(
    overrides: [
      clockProvider.overrideWithValue(() => today),
      debtRepositoryProvider.overrideWith((ref) async => repository),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
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

  testWidgets('with none, says what belongs here', (tester) async {
    await open(tester, _InMemoryDebts());

    expect(find.text('No debts yet'), findsOneWidget);
    expect(find.text('Add debt'), findsOneWidget);
  });

  testWidgets('the totals each way, each side under its heading, overdue '
      'said, and the paid ones folded away', (tester) async {
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

    expect(find.text('Owed to you'), findsNWidgets(2));
    expect(find.text('Rs2,500.00'), findsNWidgets(2));
    expect(find.text('You owe'), findsNWidgets(2));
    expect(find.text('Rs1,200.00'), findsNWidgets(2));
    expect(find.text('1 debt is overdue.'), findsOneWidget);
    expect(
      find.text('Train tickets · Overdue since Oct 1, 2026'),
      findsOneWidget,
    );
    expect(find.text('Paid · 1'), findsOneWidget);
    // Folded: the paid one is not drawn until the section is opened.
    expect(find.text('Kamala'), findsNothing);

    await tester.tap(find.text('Paid · 1'));
    await tester.pumpAndSettle();
    expect(find.text('Kamala'), findsOneWidget);
  });

  testWidgets('the tick marks it paid today, and Undo opens it again', (
    tester,
  ) async {
    final repository = _InMemoryDebts([
      debt(1, 'Nimal', DebtDirection.owedToMe, 250000),
    ]);
    await open(tester, repository);

    await tester.tap(find.byTooltip('Mark as paid'));
    await tester.pumpAndSettle();

    expect(repository.debts.single.paidOn, today);
    expect(find.text('Paid · 1'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();

    expect(repository.debts.single.paidOn, isNull);
    expect(find.text('Paid · 1'), findsNothing);
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
    await tester.enterText(
      find.widgetWithText(TextField, 'What for (optional)'),
      'Lunch',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Add debt'));
    await tester.pumpAndSettle();

    final saved = repository.debts.single;
    expect(saved.person, 'Saman');
    expect(saved.direction, DebtDirection.iOwe);
    expect(saved.amountCents, 120000);
    expect(saved.note, 'Lunch');
    expect(find.text('You owe'), findsNWidgets(2));
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
        find.widgetWithText(TextField, 'What for (optional)'),
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
      expect(find.text('Owed to you'), findsNWidgets(2));
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

    expect(find.byTooltip('Mark as paid'), findsOneWidget);
  });
}
