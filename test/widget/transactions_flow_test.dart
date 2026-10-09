import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:intl/intl.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/ports/category_writer.dart';
import 'package:moneyora/core/ports/expense_photos.dart';
import 'package:moneyora/core/theme/app_colors.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/core/utils/currency_utils.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/presentation/pages/transaction_list_page.dart';
import 'package:moneyora/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:moneyora/features/transactions/presentation/widgets/amount_keypad.dart';
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
  late _FakePhotos photos;

  const categories = [
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
  ];
  const accounts = [
    AccountOption(id: 1, name: 'Cash', balanceCents: 0),
    AccountOption(id: 2, name: 'Bank', balanceCents: 0),
  ];

  setUp(() {
    repository = _FakeRepository();
    photos = _FakePhotos();
  });
  tearDown(() => repository.dispose());

  Widget boot({
    double textScale = 1,
    Widget page = const TransactionListPage(),
    List<AccountOption> accountList = accounts,
  }) => ProviderScope(
    overrides: [
      entryCategoriesProvider.overrideWith(
        (ref) => Stream<List<CategoryOption>>.value(categories),
      ),
      entryAccountsProvider.overrideWith(
        (ref) => Stream<List<AccountOption>>.value(accountList),
      ),
      transactionRepositoryProvider.overrideWith((ref) => repository),
      expensePhotosProvider.overrideWithValue(photos),
    ],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: page,
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

  /// [amount] on a transaction row, not on its day's header: a day with
  /// one row totals the same figure (FR-EXP-006).
  Finder onRow(String amount) => find.descendant(
    of: find.byType(TransactionRow),
    matching: find.text(amount),
  );

  Future<void> tapRow(WidgetTester tester, String amount) async {
    await tester.ensureVisible(onRow(amount));
    await tester.tap(onRow(amount));
    await tester.pumpAndSettle();
  }

  /// Holds the row, then Delete. A sideways swipe steps the period since
  /// 2026-10-06, so this is how a row leaves the list.
  Future<void> deleteRow(WidgetTester tester, String amount) async {
    await tester.ensureVisible(onRow(amount));
    await tester.longPress(onRow(amount));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
  }

  /// The list's − (a new expense) or + (a new income).
  Future<void> openNew(WidgetTester tester, {bool income = false}) async {
    await tester.tap(find.byTooltip(income ? 'New income' : 'New expense'));
    await tester.pumpAndSettle();
  }

  Future<void> keyIn(WidgetTester tester, String keys) async {
    for (final key in keys.split('')) {
      await tapText(tester, key);
    }
  }

  final chooseButton = find.widgetWithText(OutlinedButton, 'CHOOSE CATEGORY');
  final changeCategory = find.byTooltip('Change category');
  final saveButton = find.widgetWithText(FilledButton, 'SAVE');

  /// CHOOSE CATEGORY (or the category already chosen, on an edit), then
  /// [category] in the grid, then SAVE, which records the entry.
  Future<void> choose(WidgetTester tester, String category) async {
    await tester.tap(
      chooseButton.evaluate().isEmpty ? changeCategory : chooseButton,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(category));
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();
  }

  /// Records one expense through the UI, leaving the list showing it.
  Future<void> addExpense(
    WidgetTester tester, {
    String amount = '500',
    String category = 'Food',
  }) async {
    await openNew(tester);
    await keyIn(tester, amount);
    await choose(tester, category);
  }

  group('the empty list', () {
    testWidgets('says what belongs here and how to fill it', (tester) async {
      await pumpApp(tester);

      // E-22: the first screen a new user meets must not be a blank page.
      expect(find.text('No transactions yet'), findsOneWidget);
      expect(find.textContaining('Tap − for an expense'), findsOneWidget);
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

      await openNew(tester);
      expect(find.text('New expense'), findsOneWidget);

      // Rs 1,250 of groceries plus a Rs 340 bus fare — the sum a person
      // actually has in front of them, added on the keypad (FR-EXP-002).
      await keyIn(tester, '1250');
      await tapText(tester, '+');
      await keyIn(tester, '340');

      // The open sum is finished as = would finish it, then the category
      // records it.
      await choose(tester, 'Food');

      // Back on the list, showing the row just written. Nothing told this
      // screen to refresh — the watch stream did.
      expect(find.text('No transactions yet'), findsNothing);
      expect(onRow('−Rs1,590.00'), findsOneWidget);
    });

    testWidgets('= finishes the sum on the amount', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      await keyIn(tester, '12');
      await tapText(tester, '×');
      await keyIn(tester, '3');
      await tapText(tester, '=');

      expect(find.text('Rs36.00'), findsOneWidget);
    });

    testWidgets('will not choose a category without an amount', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      // A zero-amount transaction is almost always a half-finished entry, and
      // storing one leaves a row that pollutes averages while looking fine.
      expect(tester.widget<OutlinedButton>(chooseButton).onPressed, isNull);
      await keyIn(tester, '5');
      expect(tester.widget<OutlinedButton>(chooseButton).onPressed, isNotNull);
      await tester.tap(find.byTooltip('Backspace'));
      await tester.pumpAndSettle();
      expect(tester.widget<OutlinedButton>(chooseButton).onPressed, isNull);
      expect(repository.saved, isEmpty);
    });

    testWidgets('the date is at the top, today unless changed', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      expect(
        find.text(DateFormat('EEEE, d MMMM').format(DateTime.now())),
        findsOneWidget,
      );
    });

    testWidgets('Cancel leaves without recording anything', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await keyIn(tester, '500');

      await tapText(tester, 'Cancel');

      expect(find.text('No transactions yet'), findsOneWidget);
      expect(repository.saved, isEmpty);
    });

    testWidgets('a category tapped is chosen, and only Save records', (
      tester,
    ) async {
      await pumpApp(tester);
      await openNew(tester);
      await keyIn(tester, '500');
      await tester.tap(chooseButton);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();

      // Back on the entry, with the category beside Save and nothing
      // written: a wrong tap is one more tap to change.
      expect(find.text('New expense'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Transport'), findsOneWidget);
      expect(repository.saved, isEmpty);

      await tester.tap(changeCategory);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(repository.saved.single.categoryId, 1);
      expect(onRow('−Rs500.00'), findsOneWidget);
    });

    testWidgets('Save waits for an amount', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await keyIn(tester, '5');
      await tester.tap(chooseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Backspace'));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);
    });

    testWidgets('backing out of the grid records nothing', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await keyIn(tester, '500');
      await tester.tap(chooseButton);
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('New expense'), findsOneWidget);
      expect(find.text('Rs500.00'), findsOneWidget);
      expect(repository.saved, isEmpty);
    });

    testWidgets('saves the note along with the amount', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      await keyIn(tester, '500');
      await tester.enterText(find.byType(TextField), 'Groceries');
      await tester.pumpAndSettle();
      await choose(tester, 'Food');

      expect(repository.saved.single.note, 'Groceries');
      expect(repository.saved.single.amountCents, 50000);
      // Under the category's name, not in place of it.
      // The date is the day's header (FR-EXP-006); the note sits under the
      // row's category.
      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Groceries'), findsOneWidget);
    });

    testWidgets('switching to income swaps the category list', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await keyIn(tester, '5');

      await tester.tap(find.byTooltip('Switch to income'));
      await tester.pumpAndSettle();
      expect(find.text('New income'), findsOneWidget);
      await tester.tap(chooseButton);
      await tester.pumpAndSettle();

      // An expense filed under Salary is not a mistake worth allowing.
      expect(find.text('Food'), findsNothing);
      expect(find.text('Salary'), findsOneWidget);
    });

    testWidgets('+ on the list records an income', (tester) async {
      await pumpApp(tester);
      await openNew(tester, income: true);

      expect(find.text('New income'), findsOneWidget);
      await keyIn(tester, '2500');
      await choose(tester, 'Salary');

      expect(repository.saved.single.type, TransactionType.income);
      expect(repository.saved.single.categoryId, 3);
      expect(onRow('+Rs2,500.00'), findsOneWidget);
    });

    testWidgets('shows the failure instead of pretending it saved', (
      tester,
    ) async {
      repository.failWith = const CacheFailure('The database is locked.');

      await pumpApp(tester);
      await openNew(tester);
      await keyIn(tester, '500');
      await choose(tester, 'Food');

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
      await openNew(tester);

      // FR-EXP-001: account is a field of the entry, not a fixed default —
      // both accounts must be reachable, not just the one preselected. It
      // is the icon at the left of the amount.
      expect(find.byTooltip('Account: Cash'), findsOneWidget);
      await tester.tap(find.byTooltip('Account: Cash'));
      await tester.pumpAndSettle();
      expect(find.text('Cash'), findsOneWidget);
      expect(find.text('Bank'), findsOneWidget);
      await tester.tapAt(const Offset(180, 100));
      await tester.pumpAndSettle();

      await keyIn(tester, '500');
      await choose(tester, 'Food');

      expect(repository.saved.single.accountId, 1);
    });

    testWidgets('starts in the account the list is showing', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        boot(page: const TransactionListPage(accountId: 2)),
      );
      await tester.pumpAndSettle();

      // The list of one account is where an entry for it is started; the
      // first account was the default before, and the entry went there.
      await openNew(tester, income: true);
      expect(find.byTooltip('Account: Bank'), findsOneWidget);
      await keyIn(tester, '500');
      await choose(tester, 'Salary');

      expect(repository.saved.single.accountId, 2);
    });

    testWidgets('an account no longer offered falls back to the first', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      // Archived since it was chosen: not among the accounts offered.
      await tester.pumpWidget(
        boot(page: const TransactionListPage(accountId: 9)),
      );
      await tester.pumpAndSettle();

      await openNew(tester);

      expect(find.byTooltip('Account: Cash'), findsOneWidget);
    });

    testWidgets('saves the account the user picks, not the default', (
      tester,
    ) async {
      await pumpApp(tester);
      await openNew(tester);

      await keyIn(tester, '500');
      await tester.tap(find.byTooltip('Account: Cash'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Bank');
      expect(find.byTooltip('Account: Bank'), findsOneWidget);
      await choose(tester, 'Food');

      expect(repository.saved.single.accountId, 2);
    });
  });

  group('editing', () {
    testWidgets('opens the row already filled in', (tester) async {
      await pumpApp(tester);
      await addExpense(tester, amount: '1250');

      await tapRow(tester, '−Rs1,250.00');

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

      // 1,250 corrected to 1,300: three backspaces leave "1", then 300. This
      // test once asserted the amount was *unchanged* after three
      // backspaces — the bug, pinned as behaviour: the keypad was seeded
      // "1250.00" and they only removed an invisible ".00".
      await tapRow(tester, '−Rs1,250.00');
      await tester.tap(find.byTooltip('Backspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Backspace'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Backspace'));
      await tester.pumpAndSettle();
      await keyIn(tester, '300');
      await choose(tester, 'Food');

      expect(repository.saved, hasLength(1), reason: 'edited, not duplicated');
      expect(repository.updated.single.id, 1);
      expect(repository.updated.single.amountCents, 130000);
    });

    testWidgets('keeps everything the form does not show', (tester) async {
      // The update writes every column. An edit built from the form alone
      // wrote the time, the split parts, the receipt link and the recurring
      // link back as empty — changing a split's category deleted its parts.
      final original = Transaction(
        id: 7,
        accountId: 1,
        categoryId: 1,
        amountCents: 30000,
        type: TransactionType.expense,
        date: DateTime(2026, 9, 1),
        time: '08:15',
        note: 'Market',
        splits: const [
          TransactionSplit(categoryId: 1, amountCents: 20000),
          TransactionSplit(categoryId: 2, amountCents: 10000),
        ],
        receiptScanId: 3,
        receiptImagePath: '/vault/3.enc',
        recurringRuleId: 5,
        isRecurring: true,
      );
      repository.saved.add(original);

      await pumpApp(tester);
      await tapRow(tester, '−Rs300.00');
      await choose(tester, 'Food');

      expect(repository.updated.single, original);
    });
  });

  group('a photo on an expense. FR-EXP-009', () {
    /// The photo row is the last detail, below the fold on a phone.
    Future<void> reveal(WidgetTester tester, Finder finder) async {
      await tester.dragUntilVisible(
        finder,
        find.byType(ListView).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();
    }

    Future<void> startExpense(WidgetTester tester) async {
      await pumpApp(tester);
      await openNew(tester);
      await keyIn(tester, '500');
    }

    Future<void> attach(WidgetTester tester, String path) async {
      photos.nextPick = Right(path);
      await tester.tap(find.byTooltip('Attach a photo'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Take a photo');
    }

    testWidgets('is attached, and saved on the row', (tester) async {
      await startExpense(tester);
      await attach(tester, 'kept.jpg');

      expect(photos.pickedFrom, [PhotoSource.camera]);
      expect(find.byTooltip('Remove photo'), findsOneWidget);

      await choose(tester, 'Food');

      expect(repository.saved.single.receiptImagePath, 'kept.jpg');
      expect(photos.discarded, isEmpty);
    });

    testWidgets('can come from the photo library', (tester) async {
      await startExpense(tester);
      photos.nextPick = const Right('kept.jpg');
      await tester.tap(find.byTooltip('Attach a photo'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Choose from your photos');

      expect(photos.pickedFrom, [PhotoSource.gallery]);
    });

    testWidgets('is discarded when the form is abandoned', (tester) async {
      await startExpense(tester);
      await attach(tester, 'kept.jpg');

      await tapText(tester, 'Cancel');

      expect(repository.saved, isEmpty);
      expect(photos.discarded, ['kept.jpg']);
    });

    testWidgets('replaced before saving, the first is discarded', (
      tester,
    ) async {
      await startExpense(tester);
      await attach(tester, 'a.jpg');
      photos.nextPick = const Right('b.jpg');
      await tester.tap(find.byTooltip('Replace photo'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Take a photo');

      await choose(tester, 'Food');

      expect(repository.saved.single.receiptImagePath, 'b.jpg');
      expect(photos.discarded, ['a.jpg']);
    });

    testWidgets('removed in an edit, is discarded once saved', (tester) async {
      repository.saved.add(
        Transaction(
          id: 7,
          accountId: 1,
          categoryId: 1,
          amountCents: 30000,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 1),
          receiptImagePath: 'old.jpg',
        ),
      );
      await pumpApp(tester);
      await tapRow(tester, '−Rs300.00');

      await reveal(tester, find.byTooltip('Remove photo'));
      await tester.tap(find.byTooltip('Remove photo'));
      await tester.pumpAndSettle();
      expect(photos.discarded, isEmpty, reason: 'not before the save');

      await choose(tester, 'Food');

      expect(repository.updated.single.receiptImagePath, isNull);
      expect(photos.discarded, ['old.jpg']);
    });

    testWidgets('from a scan is shown, and cannot be changed here', (
      tester,
    ) async {
      repository.saved.add(
        Transaction(
          id: 7,
          accountId: 1,
          categoryId: 1,
          amountCents: 30000,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 1),
          receiptScanId: 3,
          receiptImagePath: '/vault/3.enc',
        ),
      );
      await pumpApp(tester);
      await tapRow(tester, '−Rs300.00');
      await reveal(tester, find.text('Photo from the receipt scan'));

      expect(find.text('Photo from the receipt scan'), findsOneWidget);
      expect(find.byTooltip('Remove photo'), findsNothing);
      expect(find.byTooltip('Replace photo'), findsNothing);
    });

    testWidgets('is not offered on an income', (tester) async {
      await pumpApp(tester);
      await openNew(tester);
      expect(find.byTooltip('Attach a photo'), findsOneWidget);
      await tester.tap(find.byTooltip('Switch to income'));
      await tester.pumpAndSettle();

      expect(find.byTooltip('Attach a photo'), findsNothing);
    });

    testWidgets('a refused camera says so in its own words', (tester) async {
      await startExpense(tester);
      photos.nextPick = const Left(PermissionFailure('Allow the camera.'));
      await tester.tap(find.byTooltip('Attach a photo'));
      await tester.pumpAndSettle();
      await tapText(tester, 'Take a photo');

      expect(find.text('Allow the camera.'), findsOneWidget);
      expect(find.byTooltip('Attach a photo'), findsOneWidget);
    });

    testWidgets('goes with its row once the delete is written', (tester) async {
      await startExpense(tester);
      await attach(tester, 'kept.jpg');
      await choose(tester, 'Food');

      await deleteRow(tester, '−Rs500.00');
      await tester.pumpAndSettle();
      expect(photos.discarded, isEmpty, reason: 'undo still possible');

      await tester.pump(PendingDeletions.window);
      await tester.pumpAndSettle();

      expect(repository.deleted, [1]);
      expect(photos.discarded, ['kept.jpg']);
    });
  });

  group('at twice the text size on a 320dp phone. SRS §4.1', () {
    // Android's largest font setting on the smallest supported screen. A
    // layout that overflows here throws in the test, so each case passes
    // only when nothing is clipped or striped.
    Future<void> pumpLarge(WidgetTester tester) async {
      tester.view.physicalSize = const Size(960, 1920);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(boot(textScale: 2));
      await tester.pumpAndSettle();
    }

    void seedRows() => repository.saved.addAll([
      Transaction(
        id: 1,
        accountId: 1,
        categoryId: 2,
        amountCents: 123456789,
        type: TransactionType.expense,
        date: DateTime(2026, 9, 1),
        note: 'A very long note about a taxi across the whole city at night',
      ),
      Transaction(
        id: 2,
        accountId: 1,
        categoryId: 3,
        amountCents: 987654321,
        type: TransactionType.income,
        date: DateTime(2026, 9, 2),
      ),
      Transaction(
        id: 3,
        accountId: 1,
        amountCents: 50000,
        type: TransactionType.transfer,
        transferDirection: TransferDirection.out,
        counterpartyAccountId: 2,
        date: DateTime(2026, 9, 3),
      ),
    ]);

    testWidgets('the empty list', (tester) async {
      await pumpLarge(tester);

      expect(find.text('No transactions yet'), findsOneWidget);
    });

    testWidgets('the list, by date and by category', (tester) async {
      seedRows();
      await pumpLarge(tester);
      expect(find.text('Transport'), findsOneWidget);

      await tester.tap(find.byTooltip('Group by category'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();

      expect(find.textContaining('A very long note'), findsOneWidget);
    });

    testWidgets('the entry screen, keypad and details', (tester) async {
      await pumpLarge(tester);
      await openNew(tester);
      await keyIn(tester, '123456789');

      expect(find.byTooltip('Attach a photo'), findsOneWidget);
      expect(find.byTooltip('Account: Cash'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(chooseButton).onPressed, isNotNull);
    });

    testWidgets('the category grid', (tester) async {
      await pumpLarge(tester);
      await openNew(tester);
      await keyIn(tester, '500');
      await tester.tap(chooseButton);
      await tester.pumpAndSettle();

      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('New'), findsOneWidget);
    });

    testWidgets('a long category beside Save', (tester) async {
      await pumpLarge(tester);
      await openNew(tester);
      await keyIn(tester, '500');
      await tester.tap(chooseButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();

      expect(changeCategory, findsOneWidget);
      expect(saveButton, findsOneWidget);
    });

    testWidgets('an edit with a photo', (tester) async {
      repository.saved.add(
        Transaction(
          id: 9,
          accountId: 1,
          categoryId: 1,
          amountCents: 700,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 4),
          receiptImagePath: 'kept.jpg',
        ),
      );
      await pumpLarge(tester);
      await tapRow(tester, '−${formatCents(700)}');

      await tester.dragUntilVisible(
        find.byTooltip('Remove photo'),
        find.byType(ListView).first,
        const Offset(0, -120),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Remove photo'), findsOneWidget);
    });

    testWidgets('a new entry that repeats', (tester) async {
      await pumpLarge(tester);
      await openNew(tester);
      await tester.tap(find.byTooltip('Repeat'));
      await tester.pumpAndSettle();

      // Brought into view, which at this size scrolls the note row away.
      expect(find.text('Repeats'), findsOneWidget);
    });
  });

  testWidgets('offers no sample data: this is where real money is read', (
    tester,
  ) async {
    await pumpApp(tester);

    expect(find.textContaining('sample data'), findsNothing);
    expect(find.byIcon(Icons.science_outlined), findsNothing);
  });

  group('transfer rows. FR-TRF-004, E-02', () {
    // Cash drawn from a card: the card's leg is money gone, the cash leg
    // money arrived. Both sit alone on today, so the day has no spending.
    void seedTransfer() {
      final today = DateTime.now();
      repository.saved.addAll([
        Transaction(
          id: 1,
          accountId: 2,
          amountCents: 20000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.out,
          counterpartyAccountId: 1,
          date: today,
        ),
        Transaction(
          id: 2,
          accountId: 1,
          amountCents: 20000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.incoming,
          counterpartyAccountId: 2,
          date: today,
        ),
      ]);
    }

    Color colourOf(WidgetTester tester, String text) =>
        tester.widget<Text>(find.text(text)).style!.color!;

    AppColors colours(WidgetTester tester) =>
        Theme.of(tester.element(find.byType(TransactionListPage)))
            .extension<AppColors>()!;

    testWidgets('money leaving an account is a minus, in red', (tester) async {
      seedTransfer();
      await pumpApp(tester);

      expect(colourOf(tester, '−Rs200.00'), colours(tester).expense);
    });

    testWidgets('money arriving is a plus, in green', (tester) async {
      seedTransfer();
      await pumpApp(tester);

      expect(colourOf(tester, '+Rs200.00'), colours(tester).income);
    });

    testWidgets('a day of transfers alone shows no total', (tester) async {
      seedTransfer();
      await pumpApp(tester);

      // Nothing was spent: a red "−Rs0.00" would read as a loss.
      expect(find.text('−Rs0.00'), findsNothing);
    });
  });

  group('arrows point the way the balance moves', () {
    // The owner's call, 2026-10-05: an expense takes the balance down and
    // an income brings it up, so the arrows say that.
    Finder iconOnRow(String amount, IconData icon) => find.descendant(
      of: find.ancestor(of: find.text(amount), matching: find.byType(ListTile)),
      matching: find.byIcon(icon),
    );

    testWidgets('an expense row points down, an income row up', (tester) async {
      final today = DateTime.now();
      repository.saved.addAll([
        Transaction(
          id: 1,
          accountId: 1,
          amountCents: 9000,
          type: TransactionType.expense,
          categoryId: 1,
          date: today,
        ),
        Transaction(
          id: 2,
          accountId: 1,
          amountCents: 500000,
          type: TransactionType.income,
          categoryId: 3,
          date: today,
        ),
      ]);
      await pumpApp(tester);

      expect(iconOnRow('−Rs90.00', Icons.arrow_downward), findsOneWidget);
      expect(iconOnRow('−Rs90.00', Icons.arrow_upward), findsNothing);
      expect(iconOnRow('+Rs5,000.00', Icons.arrow_upward), findsOneWidget);
      expect(iconOnRow('+Rs5,000.00', Icons.arrow_downward), findsNothing);
    });

    testWidgets('the entry screen switches between the two', (tester) async {
      // Up and down on one icon at the top right, as the list's arrows
      // point; its words say which way it goes from here.
      await pumpApp(tester);
      await openNew(tester);
      expect(find.text('New expense'), findsOneWidget);

      await tester.tap(find.byTooltip('Switch to income'));
      await tester.pumpAndSettle();
      expect(find.text('New income'), findsOneWidget);

      await tester.tap(find.byTooltip('Switch to expense'));
      await tester.pumpAndSettle();
      expect(find.text('New expense'), findsOneWidget);
    });
  });

  group('row names', () {
    testWidgets('name a row by its category. FR-EXP-006', (tester) async {
      await pumpApp(tester);
      await addExpense(tester, category: 'Transport');

      expect(find.text('Transport'), findsOneWidget);
      expect(find.text('Uncategorised'), findsNothing);
    });

    testWidgets('fall back to the note, then a bare word', (tester) async {
      // A category the catalog does not carry — archived since, or still
      // loading — must not blank the row.
      repository.saved.addAll([
        Transaction(
          id: 1,
          accountId: 1,
          categoryId: 998,
          amountCents: 1000,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 1),
          note: 'Lunch',
        ),
        Transaction(
          id: 2,
          accountId: 1,
          categoryId: 999,
          amountCents: 2000,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 1),
        ),
      ]);

      await pumpApp(tester);

      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('2026-09-01 · Lunch'), findsNothing);
      expect(find.text('Uncategorised'), findsOneWidget);
    });

    testWidgets('a long note stops at two lines', (tester) async {
      // A tester's scanned bus ticket, 2026-10-05: the whole OCR text came
      // back as the item's name, and its row filled a third of the screen.
      // The full note is still one tap away, on the edit screen.
      const ticket =
          'OLIAER :0412283207 Bs.56. 00 TRIP HO :8 TICKET HO: E?749 '
          'FROM:MATARR T9HEU5 DATE g4\'18.26 TIME RUUTE HO:36g-B01 HORMAL '
          'HB-9971 1903 COOP LINK-AKURESSA 56.80 (BUS)';
      repository.saved.add(
        Transaction(
          id: 1,
          accountId: 1,
          categoryId: 1,
          amountCents: 5600,
          type: TransactionType.expense,
          date: DateTime.now(),
          note: ticket,
        ),
      );
      await pumpApp(tester);

      final note = tester.widget<Text>(find.textContaining('OLIAER'));
      expect(note.maxLines, 2);
      expect(note.overflow, TextOverflow.ellipsis);
    });
  });

  group('the keypad', () {
    testWidgets('folds away for a note, and comes back from the amount', (
      tester,
    ) async {
      // The system keyboard and the keypad do not both fit on a phone.
      await pumpApp(tester);
      await openNew(tester);
      expect(find.byType(AmountKeypad), findsOneWidget);

      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      expect(find.byType(AmountKeypad), findsNothing);

      await tester.tap(find.text('0'));
      await tester.pumpAndSettle();
      expect(find.byType(AmountKeypad), findsOneWidget);
    });

    testWidgets('runs 1 at the top to = beside 0', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      final one = tester.getCenter(find.text('1'));
      final seven = tester.getCenter(find.text('7'));
      final equals = tester.getCenter(find.text('='));
      final zero = tester.getCenter(find.text('0').last);
      expect(one.dy, lessThan(seven.dy));
      expect(equals.dy, zero.dy);
      expect(equals.dx, greaterThan(zero.dx));
    });
  });

  group('deleting, with the undo window', () {
    testWidgets('hides the row immediately', (tester) async {
      await pumpApp(tester);
      await addExpense(tester);

      await deleteRow(tester, '−Rs500.00');
      await tester.pumpAndSettle();

      expect(onRow('−Rs500.00'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
    });

    testWidgets('the offer does not follow onto the entry screen', (
      tester,
    ) async {
      // Found on the emulator: left up, "Transaction deleted" sat over the
      // entry screen's Save button, and a tap on Save hit the bar instead.
      await pumpApp(tester);
      await addExpense(tester);
      await deleteRow(tester, '−Rs500.00');
      await tester.pumpAndSettle();
      expect(find.text('Undo'), findsOneWidget);

      await openNew(tester);

      expect(find.text('Transaction deleted'), findsNothing);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('writes nothing at all if undo is tapped', (tester) async {
      await pumpApp(tester);
      await addExpense(tester);

      await deleteRow(tester, '−Rs500.00');
      await tester.pumpAndSettle();
      await tapText(tester, 'Undo');

      // The point of E-23: nothing was deleted and re-inserted, so the row
      // keeps its id and any child rows it had. The delete simply never ran.
      expect(repository.deleted, isEmpty);
      expect(onRow('−Rs500.00'), findsOneWidget);
    });

    testWidgets('commits when the app goes to the background', (tester) async {
      // The case that would otherwise look like a bug: swipe a row away, close
      // the app inside five seconds, and find it back on the next launch. A
      // pause is an orderly shutdown, not a crash, so the delete is honoured.
      // A force-stop runs no callback and still fails safe, per E-23.
      await pumpApp(tester);
      await addExpense(tester);

      await deleteRow(tester, '−Rs500.00');
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

      await deleteRow(tester, '−Rs500.00');
      await tester.pumpAndSettle();
      expect(repository.deleted, isEmpty, reason: 'not written yet');

      await tester.pump(PendingDeletions.window);
      await tester.pumpAndSettle();

      expect(repository.deleted, [1]);
      expect(find.text('No transactions yet'), findsOneWidget);
    });

    testWidgets('a sideways swipe on a row deletes nothing', (tester) async {
      // The swipe steps the period now, as on home. A row it used to take
      // away stays put.
      await pumpApp(tester);
      await addExpense(tester);

      await tester.drag(onRow('−Rs500.00'), const Offset(-500, 0));
      await tester.pumpAndSettle();

      expect(onRow('−Rs500.00'), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
    });

    testWidgets('a held row offers Edit as well', (tester) async {
      await pumpApp(tester);
      await addExpense(tester);

      await tester.longPress(onRow('−Rs500.00'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit expense'), findsOneWidget);
    });

    testWidgets('Delete on the edit screen has the same undo window', (
      tester,
    ) async {
      await pumpApp(tester);
      await addExpense(tester);
      await tapRow(tester, '−Rs500.00');

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(onRow('−Rs500.00'), findsNothing);
      expect(find.text('Undo'), findsOneWidget);
      expect(repository.deleted, isEmpty, reason: 'not written yet');

      await tapText(tester, 'Undo');
      expect(onRow('−Rs500.00'), findsOneWidget);
    });

    testWidgets('a new entry has no Delete', (tester) async {
      await pumpApp(tester);
      await openNew(tester);

      expect(find.byTooltip('Delete'), findsNothing);
    });

    testWidgets('the snackbar disappears when the undo window closes', (
      tester,
    ) async {
      await pumpApp(tester);
      await addExpense(tester);

      await deleteRow(tester, '−Rs500.00');
      await tester.pumpAndSettle();
      expect(find.text('Transaction deleted'), findsOneWidget);
      expect(find.text('Undo'), findsOneWidget);

      await tester.pump(PendingDeletions.window);
      await tester.pumpAndSettle();

      expect(find.text('Transaction deleted'), findsNothing);
      expect(find.text('Undo'), findsNothing);
    });
  });

  group('the filter', () {
    testWidgets('narrows to what was asked for, and back', (tester) async {
      await pumpApp(tester);

      await openNew(tester);
      await keyIn(tester, '500');
      await choose(tester, 'Food');

      expect(onRow('−Rs500.00'), findsOneWidget);

      await tapText(tester, 'Income');
      expect(onRow('−Rs500.00'), findsNothing);
      expect(find.text('Nothing matches this filter'), findsOneWidget);

      await tapText(tester, 'Expenses');
      expect(onRow('−Rs500.00'), findsOneWidget);
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
    /// created through the writer shows up in a catalog read afterwards, the
    /// same live-stream shape [entryCategoriesProvider] actually has, which
    /// needs the two to share state the outer group's fixed `categories` does
    /// not.
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

      final categoriesController = StreamController<List<CategoryOption>>()
        ..add(List.of(categories));
      addTearDown(categoriesController.close);

      final app = ProviderScope(
        overrides: [
          entryCategoriesProvider.overrideWith(
            (ref) => categoriesController.stream,
          ),
          entryAccountsProvider.overrideWith(
            (ref) => Stream<List<AccountOption>>.value(const [
              AccountOption(id: 1, name: 'Cash', balanceCents: 0),
            ]),
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
                  categoriesController.add(List.of(categories));
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
      'creates a category from the grid and records the entry in it',
      (tester) async {
        final booted = bootWithWriter();
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(booted.app);
        await tester.pumpAndSettle();

        await openNew(tester);
        await keyIn(tester, '500');
        await tester.tap(chooseButton);
        await tester.pumpAndSettle();
        await tapText(tester, 'New');
        expect(find.text('New expense category'), findsOneWidget);

        final sheetNameField = find.descendant(
          of: find.byType(BottomSheet),
          matching: find.byType(TextField),
        );
        await tester.enterText(sheetNameField, 'Streaming');
        await tapText(tester, 'Add category');

        // Made, so chosen: the entry the user came to record is in it, and
        // Save records it.
        expect(find.text('Streaming'), findsOneWidget);
        await tester.tap(saveButton);
        await tester.pumpAndSettle();
        expect(booted.created, ['Streaming']);
        expect(repository.saved.single.categoryId, 2);
        expect(onRow('−Rs500.00'), findsOneWidget);
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

      await openNew(tester);
      await keyIn(tester, '500');
      await tester.tap(chooseButton);
      await tester.pumpAndSettle();
      await tapText(tester, 'New');
      await tapText(tester, 'Add category');

      // AddCategory.validate's own sentence, not a second one invented here.
      expect(find.text('Give the category a name.'), findsOneWidget);
      expect(booted.created, isEmpty);
    });
  });

  group('grouped by category. FR-EXP-011', () {
    final groupByCategory = find.byTooltip('Group by category');

    Transaction expense(int id, int categoryId, int cents, {String? note}) =>
        Transaction(
          id: id,
          accountId: 1,
          categoryId: categoryId,
          amountCents: cents,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 1),
          note: note,
        );

    testWidgets('each header names its category, count and total', (
      tester,
    ) async {
      repository.saved.addAll([
        expense(1, 1, 1000, note: 'Lunch'),
        expense(2, 2, 300),
        expense(3, 1, 500, note: 'Dinner'),
      ]);
      await pumpApp(tester);

      await tester.tap(groupByCategory);
      await tester.pumpAndSettle();

      final food = find.widgetWithText(ExpansionTile, 'Food');
      expect(food, findsOneWidget);
      expect(
        find.descendant(of: food, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: food, matching: find.text('−${formatCents(1500)}')),
        findsOneWidget,
      );
      expect(find.widgetWithText(ExpansionTile, 'Transport'), findsOneWidget);
      // Closed until tapped: the rows are not on screen yet.
      expect(find.text('Lunch'), findsNothing);
      // Largest total first.
      expect(
        tester.getTopLeft(food).dy,
        lessThan(
          tester.getTopLeft(find.widgetWithText(ExpansionTile, 'Transport')).dy,
        ),
      );
    });

    testWidgets('a header opens to its rows, led by the note', (tester) async {
      repository.saved.addAll([
        expense(1, 1, 1000, note: 'Lunch'),
        expense(2, 1, 500),
      ]);
      await pumpApp(tester);
      await tester.tap(groupByCategory);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Food'));
      await tester.pumpAndSettle();

      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('2026-09-01'), findsNWidgets(2));
      // The category is the header; the rows do not repeat it.
      expect(find.text('Food'), findsOneWidget);
    });

    testWidgets('a split shows its part under each category', (tester) async {
      repository.saved.add(
        Transaction(
          id: 1,
          accountId: 1,
          categoryId: 1,
          amountCents: 1000,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 1),
          splits: const [
            TransactionSplit(categoryId: 1, amountCents: 700),
            TransactionSplit(categoryId: 2, amountCents: 300),
          ],
        ),
      );
      await pumpApp(tester);
      await tester.tap(groupByCategory);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Transport'));
      await tester.pumpAndSettle();

      expect(find.text('−${formatCents(300)}'), findsNWidgets(2));
      expect(find.text('−${formatCents(700)}'), findsOneWidget);
    });

    testWidgets('transfers are one group with no total', (tester) async {
      repository.saved.addAll([
        Transaction(
          id: 1,
          accountId: 1,
          amountCents: 5000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.out,
          date: DateTime(2026, 9, 1),
        ),
        expense(2, 1, 100),
      ]);
      await pumpApp(tester);
      await tester.tap(groupByCategory);
      await tester.pumpAndSettle();

      final transfers = find.widgetWithText(ExpansionTile, 'Transfers');
      expect(transfers, findsOneWidget);
      expect(
        find.descendant(of: transfers, matching: find.textContaining('5')),
        findsNothing,
      );
    });

    testWidgets('the same filter applies, and the toggle comes back', (
      tester,
    ) async {
      repository.saved.addAll([
        expense(1, 1, 1000),
        Transaction(
          id: 2,
          accountId: 1,
          categoryId: 3,
          amountCents: 90000,
          type: TransactionType.income,
          date: DateTime(2026, 9, 1),
        ),
      ]);
      await pumpApp(tester);
      await tester.tap(groupByCategory);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(ExpansionTile, 'Salary'), findsOneWidget);

      await tapText(tester, 'Expenses');
      expect(find.widgetWithText(ExpansionTile, 'Salary'), findsNothing);
      expect(find.widgetWithText(ExpansionTile, 'Food'), findsOneWidget);

      await tester.tap(find.byTooltip('List by date'));
      await tester.pumpAndSettle();
      // By date again: the groups are days now (FR-EXP-006), and Food is
      // a row inside one, not a group of its own.
      expect(find.byTooltip('Group by category'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TransactionRow),
          matching: find.text('Food'),
        ),
        findsOneWidget,
      );
    });
  });

  group('by day. FR-EXP-006', () {
    Transaction row(
      int id,
      DateTime date,
      int cents, {
      TransactionType type = TransactionType.expense,
      String? note,
    }) => Transaction(
      id: id,
      accountId: 1,
      categoryId: type == TransactionType.income ? 3 : 1,
      amountCents: cents,
      type: type,
      date: date,
      note: note,
    );

    final saturday = DateTime(2026, 9, 26);
    final sunday = DateTime(2026, 9, 27);

    Finder header(DateTime day) =>
        find.widgetWithText(ExpansionTile, dayLabel(day, DateTime.now()));

    testWidgets('each day says how many, and what it cost', (tester) async {
      repository.saved.addAll([
        row(1, sunday, 159800, note: 'Data package'),
        row(2, sunday, 24000, note: 'Rice'),
        row(3, saturday, 40000, note: 'Rice and dhal'),
      ]);
      await pumpApp(tester);

      final day = header(sunday);
      expect(day, findsOneWidget);
      expect(
        find.descendant(of: day, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: day, matching: find.text('−Rs1,838.00')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: header(saturday), matching: find.text('1')),
        findsOneWidget,
      );
      // Under its day, a row names its category and its note; the date is
      // the header's.
      expect(find.text('Data package'), findsOneWidget);
    });

    testWidgets('income shows under the spending, and a transfer in neither', (
      tester,
    ) async {
      repository.saved.addAll([
        row(1, saturday, 40000),
        row(2, saturday, 500000, type: TransactionType.income),
        Transaction(
          id: 3,
          accountId: 1,
          amountCents: 70000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.out,
          date: saturday,
        ),
      ]);
      await pumpApp(tester);

      final day = header(saturday);
      expect(
        find.descendant(of: day, matching: find.text('3')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: day, matching: find.text('−Rs400.00')),
        findsWidgets,
      );
      expect(
        find.descendant(of: day, matching: find.text('+Rs5,000.00')),
        findsWidgets,
      );
      expect(find.textContaining('4,700'), findsNothing);
      expect(find.textContaining('5,400'), findsNothing);
    });

    testWidgets('a day folds away, and opens again', (tester) async {
      repository.saved.addAll([
        row(1, sunday, 24000, note: 'Rice'),
        row(2, saturday, 40000, note: 'Dhal'),
      ]);
      await pumpApp(tester);
      expect(find.text('Rice'), findsOneWidget);

      await tester.tap(find.text(dayLabel(sunday, DateTime.now())));
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsNothing);
      expect(find.text('Dhal'), findsOneWidget, reason: 'other days stay open');

      await tester.tap(find.text(dayLabel(sunday, DateTime.now())));
      await tester.pumpAndSettle();
      expect(find.text('Rice'), findsOneWidget);
    });

    test('a day is Today, Yesterday, or its weekday and date', () {
      final now = DateTime(2026, 9, 28, 19);
      expect(dayLabel(DateTime(2026, 9, 28), now), 'Today');
      expect(dayLabel(DateTime(2026, 9, 27), now), 'Yesterday');
      expect(dayLabel(DateTime(2026, 9, 24), now), 'Thursday, 24 September');
      expect(
        dayLabel(DateTime(2025, 12, 23), now),
        'Tuesday, 23 December 2025',
      );
      // Across a month and a year boundary, yesterday is still Yesterday.
      expect(dayLabel(DateTime(2025, 12, 31), DateTime(2026)), 'Yesterday');
    });
  });

  group('scoped to a period and an account. FR-RPT-002, FR-RPT-003', () {
    Transaction row(int id, DateTime date, {int accountId = 1}) => Transaction(
      id: id,
      accountId: accountId,
      categoryId: 1,
      amountCents: 10000 * id,
      type: TransactionType.expense,
      date: date,
      note: 'Row $id',
    );

    Future<void> pumpScoped(
      WidgetTester tester, {
      int? accountId,
      Widget? header,
    }) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        boot(
          page: TransactionListPage(
            from: DateTime(2026, 9),
            to: DateTime(2026, 9, 30),
            accountId: accountId,
            header: header,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows only the period, under its header', (tester) async {
      repository.saved.addAll([
        row(1, DateTime(2026, 9, 12)),
        row(2, DateTime(2026, 8, 31)),
        row(3, DateTime(2026, 10)),
      ]);
      await pumpScoped(tester, header: const Text('the balance'));

      expect(find.text('the balance'), findsOneWidget);
      expect(find.text('Row 1'), findsOneWidget);
      expect(find.text('Row 2'), findsNothing);
      expect(find.text('Row 3'), findsNothing);
    });

    testWidgets('and only the account chosen', (tester) async {
      repository.saved.addAll([
        row(1, DateTime(2026, 9, 12)),
        row(2, DateTime(2026, 9, 13), accountId: 2),
      ]);
      await pumpScoped(tester, accountId: 2);

      expect(find.text('Row 1'), findsNothing);
      expect(find.text('Row 2'), findsOneWidget);
    });

    group('an opening balance. E-41', () {
      // Savings opened on 20 September with Rs5,000; Cash in August.
      final opened = [
        AccountOption(
          id: 1,
          name: 'Cash',
          balanceCents: 0,
          openingBalanceCents: 70000,
          openingDate: DateTime(2026, 8, 3),
        ),
        AccountOption(
          id: 2,
          name: 'Savings',
          balanceCents: 500000,
          openingBalanceCents: 500000,
          openingDate: DateTime(2026, 9, 20),
        ),
      ];

      Future<void> pumpOpened(WidgetTester tester, {int? accountId}) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          boot(
            accountList: opened,
            page: TransactionListPage(
              from: DateTime(2026, 9),
              to: DateTime(2026, 9, 30),
              accountId: accountId,
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      testWidgets('is a row on the day it was true, among the days', (
        tester,
      ) async {
        repository.saved.addAll([
          row(1, DateTime(2026, 9, 25), accountId: 2),
          row(2, DateTime(2026, 9, 12), accountId: 2),
        ]);
        await pumpOpened(tester, accountId: 2);

        expect(find.text('Opening balance'), findsOneWidget);
        expect(find.text('+Rs5,000.00'), findsOneWidget);
        // After the 25th's rows and before the 12th's: in date order.
        final opening = tester.getTopLeft(find.text('Opening balance')).dy;
        expect(opening, greaterThan(tester.getTopLeft(find.text('Row 1')).dy));
        expect(opening, lessThan(tester.getTopLeft(find.text('Row 2')).dy));
      });

      testWidgets('an empty period still shows it', (tester) async {
        // The tester's case: a new account, nothing recorded in it yet,
        // and a history that said nothing at all.
        await pumpOpened(tester, accountId: 2);

        expect(find.text('Nothing in this period'), findsNothing);
        expect(find.text('Opening balance'), findsOneWidget);
      });

      testWidgets('only for the period and account shown', (tester) async {
        await pumpOpened(tester, accountId: 1);

        // Cash opened in August, outside September.
        expect(find.text('Opening balance'), findsNothing);
        expect(find.text('Nothing in this period'), findsOneWidget);
      });

      testWidgets('is neither an expense nor an income', (tester) async {
        await pumpOpened(tester, accountId: 2);

        await tapText(tester, 'Income');

        expect(find.text('Opening balance'), findsNothing);
      });
    });

    group('a transfer moves one account. FR-TRF-004', () {
      // Rs200 of cash drawn from the card (account 2) into cash (account 1).
      void drawCash() => repository.saved.addAll([
        Transaction(
          id: 1,
          accountId: 2,
          amountCents: 20000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.out,
          counterpartyAccountId: 1,
          date: DateTime(2026, 9, 28),
        ),
        Transaction(
          id: 2,
          accountId: 1,
          amountCents: 20000,
          type: TransactionType.transfer,
          transferDirection: TransferDirection.incoming,
          counterpartyAccountId: 2,
          date: DateTime(2026, 9, 28),
        ),
      ]);

      testWidgets('on the card, the day lost it', (tester) async {
        drawCash();
        await pumpScoped(tester, accountId: 2);

        // The row, and the day's total above it.
        expect(find.text('−Rs200.00'), findsNWidgets(2));
        expect(find.text('+Rs200.00'), findsNothing);
      });

      testWidgets('in cash, the day gained it', (tester) async {
        drawCash();
        await pumpScoped(tester, accountId: 1);

        expect(find.text('+Rs200.00'), findsNWidgets(2));
        expect(find.text('−Rs200.00'), findsNothing);
      });

      testWidgets('across every account, the day has no total', (tester) async {
        drawCash();
        await pumpScoped(tester);

        // Both rows, and no total: the legs cancel (E-02).
        expect(find.text('−Rs200.00'), findsOneWidget);
        expect(find.text('+Rs200.00'), findsOneWidget);
      });
    });

    testWidgets('an empty period says so, and keeps the header', (
      tester,
    ) async {
      repository.saved.add(row(1, DateTime(2026, 8, 12)));
      await pumpScoped(tester, header: const Text('the balance'));

      expect(find.text('Nothing in this period'), findsOneWidget);
      expect(find.text('No transactions yet'), findsNothing);
      expect(find.text('the balance'), findsOneWidget);
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
  @override
  Future<Either<Failure, List<int>>> addAll(List<Transaction> transactions) =>
      throw UnimplementedError('addAll');

  final List<Transaction> saved = [];
  final _changes = StreamController<void>.broadcast();

  /// When set, the next write fails with this.
  Failure? failWith;

  var _nextId = 1;

  void dispose() => _changes.close();

  List<Transaction> _matching(TransactionFilter filter) => saved
      .where((t) => filter.type == null || t.type == filter.type)
      .where((t) => !filter.excludeTransfers || t.affectsTotals)
      .where((t) => filter.accountId == null || t.accountId == filter.accountId)
      .where((t) => filter.from == null || !t.date.isBefore(filter.from!))
      .where((t) => filter.to == null || !t.date.isAfter(filter.to!))
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
    required int creditedAmountCents,
    required DateTime date,
    String? note,
  }) async => const Right(1);
}

class _FakePhotos implements ExpensePhotos {
  Either<Failure, String?> nextPick = const Right(null);
  final List<PhotoSource> pickedFrom = [];
  final List<String> discarded = [];

  @override
  Future<Either<Failure, String?>> pickAndKeep(PhotoSource source) async {
    pickedFrom.add(source);
    return nextPick;
  }

  /// Always gone: real image bytes would have to decode under test.
  @override
  Future<Either<Failure, Uint8List?>> read(String path) async =>
      const Right(null);

  @override
  Future<Either<Failure, Unit>> discard(String path) async {
    discarded.add(path);
    return const Right(unit);
  }
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
