@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:go_router/go_router.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/ports/expense_writer.dart';
import 'package:moneyora/core/router/app_router.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/categorised_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/category_suggestion.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/keyword_match.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/parsed_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/payment_method.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_image_source.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_line_item.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/receipt_scan.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/recognised_text.dart';
import 'package:moneyora/features/receipt_scanner/domain/entities/scanned_receipt.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/keyword_dictionary_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'package:moneyora/features/receipt_scanner/domain/usecases/confirm_receipt.dart';
import 'package:moneyora/features/receipt_scanner/presentation/pages/receipt_review_page.dart';
import 'package:moneyora/injection.dart';

/// The review screen over the real `ConfirmReceipt` and fakes beneath it,
/// so what reaches the ledger is what the screen built — not what a mock
/// was told to expect.
class _FakeReceipts implements ReceiptRepository {
  @override
  Future<Either<Failure, List<ReceiptScan>>> getScanHistory() =>
      throw UnimplementedError();

  @override
  Future<Either<Failure, String?>> pickImage(ReceiptImageSource source) =>
      throw UnimplementedError();

  ReceiptScan? saved;
  Either<Failure, int> result = const Right(42);

  @override
  Future<Either<Failure, int>> confirmScan(ReceiptScan scan) async {
    saved = scan;
    return result;
  }

  @override
  Future<Either<Failure, RecognisedText>> scanReceipt(String imagePath) =>
      throw UnimplementedError();
}

class _FakeDictionary implements KeywordDictionaryRepository {
  final List<(String, int)> learnt = [];

  @override
  Future<Either<Failure, Unit>> learn({
    required String text,
    required int categoryId,
  }) async {
    learnt.add((text, categoryId));
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> recordApplied({
    required String text,
    required int categoryId,
  }) async => const Right(unit);

  @override
  Future<Either<Failure, List<KeywordMatch>>> matchesFor(String text) =>
      throw UnimplementedError();
}

class _FakeExpenses implements ExpenseWriter {
  List<ExpenseToRecord>? posted;
  Either<Failure, List<int>>? result;

  @override
  Future<Either<Failure, List<int>>> call(
    List<ExpenseToRecord> expenses,
  ) async {
    posted = expenses;
    return result ?? Right([for (var i = 0; i < expenses.length; i++) i + 1]);
  }
}

class _FakeCategories implements CategoryReader {
  _FakeCategories(this.categories);

  final List<CategoryOption> categories;

  @override
  Stream<Either<Failure, List<CategoryOption>>> watchAll() =>
      Stream.value(Right(categories));
}

class _FakeAccounts implements AccountReader {
  _FakeAccounts(this.accounts);

  final List<AccountOption> accounts;

  @override
  Stream<Either<Failure, List<AccountOption>>> watchAll() =>
      Stream.value(Right(accounts));
}

const _food = CategoryOption(
  id: 7,
  name: 'Food',
  icon: 'basket',
  colorHex: '#00aa00',
  isExpense: true,
);
const _health = CategoryOption(
  id: 9,
  name: 'Health',
  icon: 'health',
  colorHex: '#e87ba4',
  isExpense: true,
);
const _salary = CategoryOption(
  id: 20,
  name: 'Salary',
  icon: 'cash',
  colorHex: '#c98500',
  isExpense: false,
);
const _cash = AccountOption(id: 1, name: 'Cash', balanceCents: 500000);
const _card = AccountOption(
  id: 2,
  name: 'Card',
  type: AccountType.creditCard,
  balanceCents: 1500000,
);

const _rice = ReceiptLineItem(
  name: 'RICE 5KG',
  totalPriceCents: 125000,
  quantity: 5,
  unitPriceCents: 25000,
);
const _bread = ReceiptLineItem(name: 'BREAD', totalPriceCents: 30000);
const _panadol = ReceiptLineItem(name: 'PANADOL 10S', totalPriceCents: 15000);

const _byKeyword = CategorySuggestion(
  categoryId: 7,
  categoryName: 'Food',
  confidence: 90,
  source: SuggestionSource.keyword,
);
const _byMerchant = CategorySuggestion(
  categoryId: 9,
  categoryName: 'Health',
  confidence: 20,
  source: SuggestionSource.merchant,
);

ScannedReceipt _scanned({
  List<CategorisedItem> items = const [
    CategorisedItem(item: _rice, suggestion: _byKeyword),
    CategorisedItem(item: _bread, suggestion: _byKeyword),
    CategorisedItem(item: _panadol, suggestion: _byMerchant),
  ],
  int? totalCents = 170000,
  PaymentMethod? paymentMethod,
}) => ScannedReceipt(
  imagePath: '/no/such/keells.jpg',
  receipt: CategorisedReceipt(
    receipt: ParsedReceipt(
      merchantName: 'KEELLS SUPER',
      receiptDate: DateTime(2026, 4, 3, 14, 20),
      items: [for (final i in items) i.item],
      totalCents: totalCents,
      taxCents: 12000,
      receiptNumber: 'INV-0042',
      paymentMethod: paymentMethod,
    ),
    items: items,
    merchantCategoryId: 9,
    merchantCategoryName: 'Health',
  ),
);

void main() {
  late _FakeReceipts receipts;
  late _FakeDictionary dictionary;
  late _FakeExpenses expenses;
  final today = DateTime(2026, 9, 15, 10);

  setUp(() {
    receipts = _FakeReceipts();
    dictionary = _FakeDictionary();
    expenses = _FakeExpenses();
  });

  Widget boot({
    List<CategoryOption> categories = const [_food, _health, _salary],
    List<AccountOption> accounts = const [_cash, _card],
  }) => ProviderScope(
    overrides: [
      categoryReaderProvider.overrideWith(
        (ref) async => _FakeCategories(categories),
      ),
      accountReaderProvider.overrideWith(
        (ref) async => _FakeAccounts(accounts),
      ),
      confirmReceiptProvider.overrideWith(
        (ref) async => ConfirmReceipt(receipts, dictionary, expenses),
      ),
    ],
    child: MaterialApp.router(
      theme: AppTheme.light,
      routerConfig: GoRouter(
        initialLocation: Routes.scanReceipt,
        routes: [
          GoRoute(
            path: Routes.scanReceipt,
            builder: (context, state) => const Scaffold(body: Text('scanner')),
          ),
          GoRoute(
            path: Routes.scanReceiptReview,
            builder: (context, state) => ReceiptReviewPage(
              scanned: state.extra! as ScannedReceipt,
              now: today,
            ),
          ),
          GoRoute(
            path: Routes.transactions,
            builder: (context, state) =>
                const Scaffold(body: Text('transactions')),
          ),
        ],
      ),
    ),
  );

  /// Pumps the app and opens the review the way the scanner will: pushed,
  /// with the scan as `extra`, so Discard has somewhere to go back to.
  Future<void> open(
    WidgetTester tester, {
    ScannedReceipt? scanned,
    List<CategoryOption> categories = const [_food, _health, _salary],
    List<AccountOption> accounts = const [_cash, _card],
  }) async {
    // Tall enough that every card is built: the list is lazy, and a test
    // that taps a line the default 600px viewport never laid out finds
    // nothing.
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(boot(categories: categories, accounts: accounts));
    await tester.pumpAndSettle();
    final context = tester.element(find.text('scanner'));
    unawaited(
      GoRouter.of(context)
          .push(Routes.scanReceiptReview, extra: scanned ?? _scanned()),
    );
    await tester.pumpAndSettle();
  }

  Finder card(int key) => find.byKey(ValueKey(key));

  Finder confirmButton() => find.widgetWithText(FilledButton, 'Confirm');

  bool confirmEnabled(WidgetTester tester) =>
      tester.widget<FilledButton>(confirmButton()).onPressed != null;

  Future<void> chooseCategory(WidgetTester tester, int key, String name) async {
    await tester.tap(
      find.descendant(
        of: card(key),
        matching: find.byType(DropdownButtonFormField<int>),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> itemMenu(WidgetTester tester, int key, String action) async {
    await tester.tap(
      find.descendant(of: card(key), matching: find.byTooltip('More')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(action).last);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the header, every line with its suggestion, and the '
      'badge on the line only the shop vouched for', (tester) async {
    await open(tester);

    expect(find.widgetWithText(TextFormField, 'KEELLS SUPER'), findsOneWidget);
    expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
    expect(find.text('Total Rs1,700.00'), findsOneWidget);
    expect(
      find.text('Dated 2026-04-03 14:20 · Tax Rs120.00 · No. INV-0042'),
      findsOneWidget,
    );
    expect(find.text('The items add up to the total.'), findsOneWidget);
    expect(find.text('Items · 3 · Rs1,700.00'), findsOneWidget);
    expect(find.text('Record on 2026-4-3'), findsOneWidget);

    expect(find.widgetWithText(TextField, 'RICE 5KG'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1,250.00'), findsOneWidget);
    expect(find.text('5 × Rs250.00'), findsOneWidget);
    expect(find.text('Suggested Food · 90%'), findsNWidgets(2));
    expect(
      find.text('Suggested Health · 20% · only because the shop is Health'),
      findsOneWidget,
    );
    expect(find.text('Low confidence'), findsOneWidget);
    expect(
      find.descendant(of: card(2), matching: find.text('Low confidence')),
      findsOneWidget,
    );

    // The first account is taken as read, and nothing is left to do.
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cash'))
          .selected,
      isTrue,
    );
    expect(confirmEnabled(tester), isTrue);
    // Salary is an income category and is not offered.
    await tester.tap(
      find.descendant(
        of: card(0),
        matching: find.byType(DropdownButtonFormField<int>),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Salary'), findsNothing);
  });

  testWidgets('confirms what the screen built: the account, the day, a '
      'correction learnt, and moves to the list (FR-RCP-009)', (tester) async {
    await open(tester);

    await chooseCategory(tester, 2, 'Food');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Card'));
    await tester.pumpAndSettle();
    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    final scan = receipts.saved!;
    expect(scan.status, ReceiptScanStatus.confirmed);
    expect(scan.imagePath, '/no/such/keells.jpg');
    expect(scan.merchantName, 'KEELLS SUPER');
    expect(scan.items.length, 3);
    expect(scan.items[2].suggestedCategoryId, 9);
    expect(scan.items[2].confirmedCategoryId, 7);
    expect(dictionary.learnt, [('PANADOL 10S', 7)]);

    final posted = expenses.posted!;
    expect(posted.length, 3);
    expect(posted.map((e) => e.accountId).toSet(), {2});
    expect(posted.map((e) => e.date).toSet(), {DateTime(2026, 4, 3)});
    expect(posted.map((e) => e.time).toSet(), {'14:20'});
    expect(posted.map((e) => e.receiptScanId).toSet(), {42});
    expect(posted[0].note, 'RICE 5KG (KEELLS SUPER)');
    expect(posted[0].amountCents, 125000);

    expect(find.text('Saved 3 expenses.'), findsOneWidget);
    expect(find.text('transactions'), findsOneWidget);
  });

  testWidgets('a line with no suggestion holds Confirm until it has a '
      'category', (tester) async {
    await open(
      tester,
      scanned: _scanned(
        items: const [
          CategorisedItem(item: _rice, suggestion: _byKeyword),
          CategorisedItem(item: _bread, suggestion: CategorySuggestion.none),
        ],
        totalCents: 155000,
      ),
    );

    expect(find.text('No suggestion'), findsOneWidget);
    expect(find.text('Choose a category for every item.'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse);

    await chooseCategory(tester, 1, 'Food');
    expect(find.text('Choose a category for every item.'), findsNothing);
    expect(confirmEnabled(tester), isTrue);
  });

  testWidgets('a receipt paid by card opens on the card account, and the '
      'user can still change it', (tester) async {
    await open(tester, scanned: _scanned(paymentMethod: PaymentMethod.card));

    bool selected(String name) => tester
        .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, name))
        .selected;
    expect(selected('Card'), isTrue);
    expect(selected('Cash'), isFalse);
    expect(confirmEnabled(tester), isTrue);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Cash'));
    await tester.pumpAndSettle();
    expect(selected('Cash'), isTrue);
  });

  testWidgets('a receipt paid by card with no card account opens on the '
      'first account', (tester) async {
    await open(
      tester,
      scanned: _scanned(paymentMethod: PaymentMethod.card),
      accounts: const [_cash],
    );

    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cash'))
          .selected,
      isTrue,
    );
  });

  testWidgets('with no accounts, says so and holds Confirm', (tester) async {
    await open(tester, accounts: const []);

    expect(find.text('No accounts yet.'), findsOneWidget);
    expect(find.text('Choose an account.'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets('discarding a line drops it, and the sum no longer matching '
      'the total is said', (tester) async {
    await open(tester);

    await itemMenu(tester, 1, 'Discard');

    expect(find.widgetWithText(TextField, 'BREAD'), findsNothing);
    expect(find.text('Items · 2 · Rs1,400.00'), findsOneWidget);
    expect(
      find.text(
        'The items add up to Rs1,400.00, not the total — check for a line '
        'missed or misread.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('discarding every line says what belongs here and holds '
      'Confirm with ConfirmReceipt\'s own sentence', (tester) async {
    await open(
      tester,
      scanned: _scanned(
        items: const [CategorisedItem(item: _rice, suggestion: _byKeyword)],
        totalCents: 125000,
      ),
    );

    await itemMenu(tester, 0, 'Discard');

    expect(find.textContaining('No items kept.'), findsOneWidget);
    expect(find.text('Keep at least one item.'), findsOneWidget);
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets('merging a line with the next makes one purchase', (
    tester,
  ) async {
    await open(tester);

    await itemMenu(tester, 0, 'Merge with next');

    expect(find.widgetWithText(TextField, 'RICE 5KG + BREAD'), findsOneWidget);
    expect(find.widgetWithText(TextField, '1,550.00'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'BREAD'), findsNothing);
    expect(find.text('Items · 2 · Rs1,700.00'), findsOneWidget);
    expect(find.text('5 × Rs250.00'), findsNothing);
  });

  testWidgets('splitting a line asks for the first part and makes two', (
    tester,
  ) async {
    await open(tester);

    await itemMenu(tester, 0, 'Split');
    expect(find.text('Split RICE 5KG'), findsOneWidget);

    // Out of range is refused in the dialog, not the draft.
    await tester.enterText(
      find.widgetWithText(TextField, 'First part'),
      '1250',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Split'));
    await tester.pumpAndSettle();
    expect(find.text('An amount between zero and Rs1,250.00.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'First part'),
      '1000',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Split'));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextField, 'RICE 5KG'), findsNWidgets(2));
    expect(find.widgetWithText(TextField, '1,000.00'), findsOneWidget);
    expect(find.widgetWithText(TextField, '250.00'), findsOneWidget);
    expect(find.text('Items · 4 · Rs1,700.00'), findsOneWidget);
  });

  testWidgets('an amount edited to nothing holds Confirm by line number', (
    tester,
  ) async {
    await open(tester);

    await tester.enterText(
      find.descendant(
        of: card(1),
        matching: find.widgetWithText(TextField, '300.00'),
      ),
      '',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Item 2 needs an amount greater than zero.'),
      findsOneWidget,
    );
    expect(confirmEnabled(tester), isFalse);
  });

  testWidgets('a failure confirming shows its message and stays', (
    tester,
  ) async {
    expenses.result = const Left(CacheFailure('disk is full'));
    await open(tester);

    await tester.tap(confirmButton());
    await tester.pumpAndSettle();

    expect(find.text('disk is full'), findsOneWidget);
    expect(find.text('Review receipt'), findsOneWidget);
    expect(find.text('transactions'), findsNothing);
  });

  group('single-category mode (FR-RCP-010)', () {
    Finder toggle() => find.byType(SwitchListTile);

    testWidgets('folds the lines away, asks for one category, and posts '
        'the total as one expense named after the shop', (tester) async {
      await open(tester);

      expect(find.text('Instead of one expense per line.'), findsOneWidget);
      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(find.text('Rs1,700.00 as one expense.'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'RICE 5KG'), findsNothing);
      expect(find.text('Items · 3 · Rs1,700.00'), findsNothing);
      expect(find.text('The shop is Health.'), findsOneWidget);
      expect(find.text('Choose a category for the receipt.'), findsOneWidget);
      expect(confirmEnabled(tester), isFalse);

      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Food').last);
      await tester.pumpAndSettle();
      expect(confirmEnabled(tester), isTrue);

      await tester.tap(confirmButton());
      await tester.pumpAndSettle();

      final posted = expenses.posted!;
      expect(posted.length, 1);
      expect(posted.single.amountCents, 170000);
      expect(posted.single.categoryId, 7);
      expect(posted.single.note, 'KEELLS SUPER');
      expect(receipts.saved!.items.single.suggestedCategoryId, 9);
      expect(dictionary.learnt, [('KEELLS SUPER', 7)]);
      expect(find.text('Saved 1 expense.'), findsOneWidget);
    });

    testWidgets('switching back shows every line again', (tester) async {
      await open(tester);

      await tester.tap(toggle());
      await tester.pumpAndSettle();
      await tester.tap(toggle());
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextField, 'RICE 5KG'), findsOneWidget);
      expect(find.text('Items · 3 · Rs1,700.00'), findsOneWidget);
      expect(confirmEnabled(tester), isTrue);
    });
  });

  testWidgets('Discard leaves without writing anything', (tester) async {
    await open(tester);

    await tester.tap(find.widgetWithText(TextButton, 'Discard'));
    await tester.pumpAndSettle();

    expect(find.text('scanner'), findsOneWidget);
    expect(receipts.saved, isNull);
    expect(expenses.posted, isNull);
  });
}
