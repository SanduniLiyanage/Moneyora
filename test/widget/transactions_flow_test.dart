import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/database/entry_catalog.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/category_writer.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/presentation/pages/transaction_list_page.dart';
import 'package:moneyora/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:moneyora/injection.dart';

/// The two screens, driven the way a person drives them.
///
/// The repository is a fake and the database is absent, which is deliberate:
/// `flutter_test` runs the body in a fake-time zone, so real sqflite I/O never
/// completes under `pump()` and every screen would sit on its spinner forever.
/// `docs/ARCHITECTURE.md` §7 already prescribes overriding providers here.
///
/// Everything above `data/` is real — the widgets, the providers, and the
/// actual `AddTransaction` and `WatchTransactions` use cases with their
/// validation. `test/unit/injection_test.dart` covers the same path against a
/// real database, so between them nothing is only ever exercised by a fake.
void main() {
  late _FakeRepository repository;

  const catalog = EntryCatalog(
    categories: [
      CategoryOption(
        id: 1,
        name: 'Food',
        icon: 'basket',
        colorHex: '#C62828',
        isExpense: true,
      ),
      CategoryOption(
        id: 2,
        name: 'Transport',
        icon: 'bus',
        colorHex: '#3F51B5',
        isExpense: true,
      ),
      CategoryOption(
        id: 3,
        name: 'Salary',
        icon: 'wallet',
        colorHex: '#2E7D32',
        isExpense: false,
      ),
    ],
    accounts: [
      AccountOption(id: 1, name: 'Cash', balanceCents: 0),
      AccountOption(id: 2, name: 'Bank', balanceCents: 0),
    ],
  );

  setUp(() => repository = _FakeRepository());
  tearDown(() => repository.dispose());

  Widget boot() => ProviderScope(
    overrides: [
      entryCatalogProvider.overrideWith((ref) => catalog),
      transactionRepositoryProvider.overrideWith((ref) => repository),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      home: const TransactionListPage(),
    ),
  );

  /// Boots the app on a phone-shaped surface.
  ///
  /// The default test viewport is 800x600 — a landscape desktop window, which
  /// this screen is not designed for and where the note field falls outside
  /// the built area of the list. 360x800 logical pixels is an ordinary Android
  /// phone, and testing the layout people will actually see is the point.
  Future<void> pumpApp(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String label) async {
    // The entry screen's category row now carries an extra "New" chip
    // (E-13), which can push a later field below the fold on the fixed test
    // viewport — a no-op when the target is already visible or has no
    // scrollable ancestor.
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  Future<void> keyIn(WidgetTester tester, String keys) async {
    for (final key in keys.split('')) {
      await tapText(tester, key);
    }
  }

  final saveButton = find.widgetWithText(FilledButton, 'Save');

  /// Records one expense through the UI, leaving the list showing it.
  Future<void> addExpense(
    WidgetTester tester, {
    String amount = '500',
    String category = 'Food',
  }) async {
    await tapText(tester, 'Add');
    await keyIn(tester, amount);
    await tapText(tester, category);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  group('the empty list', () {
    testWidgets('says what belongs here and how to fill it', (tester) async {
      await pumpApp(tester);

      // E-22: the first screen a new user meets must not be a blank page.
      expect(find.text('No transactions yet'), findsOneWidget);
      expect(find.textContaining('Tap Add'), findsOneWidget);
    });

    testWidgets('says something different when a filter hid everything', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapText(tester, 'Income');

      // Telling someone who filtered to "add your first one" is precisely the
      // bug E-22's two states exist to prevent.
      expect(find.text('Nothing matches this filter'), findsOneWidget);
      expect(find.text('No transactions yet'), findsNothing);
    });

    testWidgets('offers a way back out of the filter', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Income');

      await tapText(tester, 'Show everything');

      expect(find.text('No transactions yet'), findsOneWidget);
    });
  });

  group('adding an expense', () {
    testWidgets('keypad arithmetic reaches the list', (tester) async {
      await pumpApp(tester);

      await tapText(tester, 'Add');
      expect(find.text('New expense'), findsOneWidget);

      // Rs 1,250 of groceries plus a Rs 340 bus fare — the sum a person
      // actually has in front of them, added on the keypad (FR-EXP-002).
      await keyIn(tester, '1250');
      await tapText(tester, '+');
      await keyIn(tester, '340');

      // Save stays disabled until a category is chosen.
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      await tapText(tester, 'Food');
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Back on the list, showing the row just written. Nothing told this
      // screen to refresh — the watch stream did.
      expect(find.text('No transactions yet'), findsNothing);
      expect(find.text('−Rs1,590.00'), findsOneWidget);
    });

    testWidgets('will not save without an amount', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Add');

      await tapText(tester, 'Food');

      // A zero-amount transaction is almost always a half-finished entry, and
      // storing one leaves a row that pollutes averages while looking fine.
      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
      expect(repository.saved, isEmpty);
    });

    testWidgets('saves the note along with the amount', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Add');

      await keyIn(tester, '500');
      await tapText(tester, 'Food');
      await tester.enterText(find.byType(TextField), 'Groceries');
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repository.saved.single.note, 'Groceries');
      expect(repository.saved.single.amountCents, 50000);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('switching to income swaps the category list', (tester) async {
      await pumpApp(tester);
      await tapText(tester, 'Add');

      expect(find.text('Food'), findsOneWidget);
      expect(find.text('Salary'), findsNothing);

      await tapText(tester, 'Income');

      // An expense filed under Salary is not a mistake worth allowing.
      expect(find.text('Food'), findsNothing);
      expect(find.text('Salary'), findsOneWidget);
      expect(find.text('New income'), findsOneWidget);
    });

    testWidgets('shows the failure instead of pretending it saved', (
      tester,
    ) async {
      repository.failWith = const CacheFailure('The database is locked.');

      await pumpApp(tester);
      await tapText(tester, 'Add');
      await keyIn(tester, '500');
      await tapText(tester, 'Food');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      // Still on the entry screen, with the reason on screen. Popping back to
      // a list that does not contain the transaction would be worse than the
      // error itself.
      expect(find.text('New expense'), findsOneWidget);
      expect(find.text('The database is locked.'), findsOneWidget);
    });
  });

  group('choosing an account', () {
    testWidgets('offers every account, defaulting to the first', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapText(tester, 'Add');

      // FR-EXP-001: account is a field of the entry, not a fixed default —
      // both accounts must be reachable, not just the one preselected.
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);

      await keyIn(tester, '500');
      await tapText(tester, 'Food');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repository.saved.single.accountId, 1);
    });

    testWidgets('saves the account the user picks, not the default', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapText(tester, 'Add');

      await keyIn(tester, '500');
      await tapText(tester, 'Food');
      await tapText(tester, 'Bank');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repository.saved.single.accountId, 2);
    });
  });

  group('editing', () {
    testWidgets('opens the row already filled in', (tester) async {
      await pumpApp(tester);
      await addExpense(tester, amount: '1250');

      await tapText(tester, '−Rs1,250.00');

      expect(find.text('Edit expense'), findsOneWidget);
      // Prefilled through the same text entry a user would have typed, so the
      // keypad behaves afterwards exactly as it does on a fresh entry.
      expect(find.text('Rs1,250.00'), findsOneWidget);
    });

    testWidgets('saves the change rather than adding a second row', (
      tester,
    ) async {
      await pumpApp(tester);
      await addExpense(tester, amount: '1250');

      await tapText(tester, '−Rs1,250.00');
      await tapText(tester, '⌫');
      await tapText(tester, '⌫');
      await tapText(tester, '⌫');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repository.saved, hasLength(1), reason: 'edited, not duplicated');
      expect(repository.updated.single.id, 1);
      expect(repository.updated.single.amountCents, 125000);
    });
  });

  group('deleting, with the undo window', () {
    testWidgets('hides the row immediately', (tester) async {
      await pumpApp(tester);
      await addExpense(tester);

      await tester.drag(find.text('−Rs500.00'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(find.text('−Rs500.00'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('writes nothing at all if undo is tapped', (tester) async {
      await pumpApp(tester);
      await addExpense(tester);

      await tester.drag(find.text('−Rs500.00'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tapText(tester, 'Undo');

      // The point of E-23: nothing was deleted and re-inserted, so the row
      // keeps its id and any child rows it had. The delete simply never ran.
      expect(repository.deleted, isEmpty);
      expect(find.text('−Rs500.00'), findsOneWidget);
    });

    testWidgets('commits when the app goes to the background', (tester) async {
      // The case that would otherwise look like a bug: swipe a row away, close
      // the app inside five seconds, and find it back on the next launch. A
      // pause is an orderly shutdown, not a crash, so the delete is honoured.
      // A force-stop runs no callback and still fails safe, per E-23.
      await pumpApp(tester);
      await addExpense(tester);

      await tester.drag(find.text('−Rs500.00'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(repository.deleted, isEmpty, reason: 'window still open');

      // The real sequence Android sends. Skipping a state trips an assertion
      // in the framework, which is itself the reminder that these are a state
      // machine and not a set of independent flags.
      for (final phase in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(phase);
      }
      await tester.pumpAndSettle();

      expect(repository.deleted, [1], reason: 'committed without waiting');
    });

    testWidgets('commits once the window closes', (tester) async {
      await pumpApp(tester);
      await addExpense(tester);

      await tester.drag(find.text('−Rs500.00'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(repository.deleted, isEmpty, reason: 'not written yet');

      await tester.pump(PendingDeletions.window);
      await tester.pumpAndSettle();

      expect(repository.deleted, [1]);
      expect(find.text('No transactions yet'), findsOneWidget);
    });
  });

  group('the filter', () {
    testWidgets('narrows to what was asked for, and back', (tester) async {
      await pumpApp(tester);

      await tapText(tester, 'Add');
      await keyIn(tester, '500');
      await tapText(tester, 'Food');
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('−Rs500.00'), findsOneWidget);

      await tapText(tester, 'Income');
      expect(find.text('−Rs500.00'), findsNothing);
      expect(find.text('Nothing matches this filter'), findsOneWidget);

      await tapText(tester, 'Expenses');
      expect(find.text('−Rs500.00'), findsOneWidget);
    });
  });

  group('transfer rows', () {
    testWidgets('label each half by the other account. FR-TRF-004', (
      tester,
    ) async {
      // Both halves of one transfer: Rs 5,000 moved from Bank into Cash.
      // E-16's transfer_direction already picks the row's sign; this is the
      // part that was missing — naming the account on the other end.
      repository.saved.addAll([
        Transaction(
          id: 1,
          accountId: 2,
          amountCents: 500000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.out,
          counterpartyAccountId: 1,
          date: DateTime(2026, 9, 1),
        ),
        Transaction(
          id: 2,
          accountId: 1,
          amountCents: 500000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.incoming,
          counterpartyAccountId: 2,
          date: DateTime(2026, 9, 1),
        ),
      ]);

      await pumpApp(tester);

      expect(find.text('To Cash'), findsOneWidget);
      expect(find.text('From Bank'), findsOneWidget);
      expect(find.text('Transfer'), findsNothing);
    });

    testWidgets('falls back to the bare word if the account is not known', (
      tester,
    ) async {
      // The counterparty account was archived after the transfer, so the
      // catalog no longer carries its name — the row must still render
      // something rather than crash or show a blank title.
      repository.saved.add(
        Transaction(
          id: 1,
          accountId: 1,
          amountCents: 500000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.incoming,
          counterpartyAccountId: 999,
          date: DateTime(2026, 9, 1),
        ),
      );

      await pumpApp(tester);

      expect(find.text('Transfer'), findsOneWidget);
    });
  });

  group('the inline category +. E-13', () {
    /// Boots the app with its own mutable catalog and a fake [CategoryWriter],
    /// rather than reusing [boot] — the point of this group is that a category
    /// created through the writer shows up in a catalog read afterwards, which
    /// needs the two to share state the outer group's fixed `catalog` does not.
    ({Widget app, List<CategoryOption> categories, List<String> created})
    bootWithWriter() {
      final categories = [
        const CategoryOption(
          id: 1,
          name: 'Food',
          icon: 'basket',
          colorHex: '#C62828',
          isExpense: true,
        ),
      ];
      final created = <String>[];
      var nextId = 2;

      final app = ProviderScope(
        overrides: [
          entryCatalogProvider.overrideWith(
            (ref) async => EntryCatalog(
              categories: List.of(categories),
              accounts: const [
                AccountOption(id: 1, name: 'Cash', balanceCents: 0),
              ],
            ),
          ),
          categoryWriterProvider.overrideWith(
            (ref) async =>
                _FakeCategoryWriter(({required name, required isExpense}) {
                  created.add(name);
                  final id = nextId++;
                  categories.add(
                    CategoryOption(
                      id: id,
                      name: name,
                      icon: 'other',
                      colorHex: '#2a78d6',
                      isExpense: isExpense,
                    ),
                  );
                  return id;
                }),
          ),
          transactionRepositoryProvider.overrideWith((ref) => repository),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          home: const TransactionListPage(),
        ),
      );

      return (app: app, categories: categories, created: created);
    }

    testWidgets(
      'creates a category and selects it, without leaving the screen',
      (tester) async {
        final booted = bootWithWriter();
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(booted.app);
        await tester.pumpAndSettle();

        await tapText(tester, 'Add');
        await tapText(tester, 'New');
        expect(find.text('New expense category'), findsOneWidget);

        // The entry screen's own note field is still in the tree behind the
        // sheet, so the field is found within it rather than by type alone.
        final sheetNameField = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        );
        await tester.enterText(sheetNameField, 'Streaming');
        await tapText(tester, 'Add category');

        // Back on the entry screen — the sheet closed on its own — with the
        // new category already chosen, not merely present in the list.
        expect(booted.created, ['Streaming']);
        expect(find.text('New expense'), findsOneWidget);
        final chip = tester.widget<ChoiceChip>(
          find.widgetWithText(ChoiceChip, 'Streaming'),
        );
        expect(chip.selected, isTrue);
      },
    );

    testWidgets('shows the refusal for a blank name and creates nothing', (
      tester,
    ) async {
      final booted = bootWithWriter();
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(booted.app);
      await tester.pumpAndSettle();

      await tapText(tester, 'Add');
      await tapText(tester, 'New');
      await tapText(tester, 'Add category');

      // AddCategory.validate's own sentence, not a second one invented here.
      expect(find.text('Give the category a name.'), findsOneWidget);
      expect(booted.created, isEmpty);
    });
  });
}

/// Records what it is asked to create and hands back an incrementing id,
/// the same shape [QuickAddCategory] gives on success — without a database.
class _FakeCategoryWriter implements CategoryWriter {
  _FakeCategoryWriter(this._onCreate);

  final int Function({required String name, required bool isExpense}) _onCreate;

  @override
  Future<Either<Failure, int>> call({
    required String name,
    required bool isExpense,
  }) async {
    if (name.trim().isEmpty) {
      return const Left(
        ValidationFailure('Give the category a name.', field: 'name'),
      );
    }
    return Right(_onCreate(name: name, isExpense: isExpense));
  }
}

/// An in-memory repository that behaves like the real one for the parts the
/// screens use: it assigns ids, filters by type, and pushes a new list to
/// every watcher after each write.
class _FakeRepository implements TransactionRepository {
  final List<Transaction> saved = [];
  final _changes = StreamController<void>.broadcast();

  /// When set, the next write fails with this.
  Failure? failWith;

  var _nextId = 1;

  void dispose() => _changes.close();

  List<Transaction> _matching(TransactionFilter filter) => saved
      .where((t) => filter.type == null || t.type == filter.type)
      .where((t) => !filter.excludeTransfers || t.affectsTotals)
      .toList();

  @override
  Future<Either<Failure, int>> add(Transaction transaction) async {
    if (failWith case final failure?) return Left(failure);
    saved.add(transaction.copyWith(id: _nextId++));
    _changes.add(null);
    return Right(_nextId - 1);
  }

  @override
  Stream<Either<Failure, List<Transaction>>> watch(TransactionFilter filter) =>
      Stream<void>.value(null)
          .followedBy(_changes.stream)
          .map((_) => Right(_matching(filter)));

  final List<Transaction> updated = [];
  final List<int> deleted = [];

  @override
  Future<Either<Failure, Unit>> update(Transaction transaction) async {
    if (failWith case final failure?) return Left(failure);
    updated.add(transaction);
    final at = saved.indexWhere((t) => t.id == transaction.id);
    if (at != -1) saved[at] = transaction;
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> delete(int id) async {
    if (failWith case final failure?) return Left(failure);
    deleted.add(id);
    saved.removeWhere((t) => t.id == id);
    _changes.add(null);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, List<Transaction>>> list(
    TransactionFilter filter,
  ) async => Right(_matching(filter));

  @override
  Future<Either<Failure, int>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String? note,
  }) async => const Right(1);
}

extension _FollowedBy<T> on Stream<T> {
  /// Emits this stream's events, then [next]'s.
  Stream<T> followedBy(Stream<T> next) async* {
    yield* this;
    yield* next;
  }
}

extension _AffectsTotals on Transaction {
  bool get affectsTotals => type.affectsTotals;
}
