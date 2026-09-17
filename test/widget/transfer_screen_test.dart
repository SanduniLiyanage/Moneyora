@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/core/ports/conversion_table.dart';
import 'package:moneyora/core/ports/exchange_rate.dart';
import 'package:moneyora/core/theme/app_theme.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/features/transactions/presentation/pages/transfer_page.dart';
import 'package:moneyora/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:moneyora/injection.dart';

/// The transfer screen, over a fake repository and no database.
///
/// Everything above `data/` is real, including `MakeTransfer` and its
/// validation — so the refusals asserted here are the use case's own sentences.
/// The atomicity FR-TRF-002 requires is proven a layer down, in
/// `transaction_local_datasource_test.dart`, where a transfer whose second half
/// violates a foreign key leaves no rows and no balance change behind. A widget
/// test cannot make that claim and does not try to.
class _FakeRepository implements TransactionRepository {
  @override
  Future<Either<Failure, List<int>>> addAll(List<Transaction> transactions) =>
      throw UnimplementedError('addAll');

  final List<
    ({int from, int to, int amount, int credited, DateTime date, String? note})
  >
  transfers = [];

  Failure? failWith;

  @override
  Future<Either<Failure, int>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required int creditedAmountCents,
    required DateTime date,
    String? note,
  }) async {
    if (failWith case final failure?) return Left(failure);
    transfers.add((
      from: fromAccountId,
      to: toAccountId,
      amount: amountCents,
      credited: creditedAmountCents,
      date: date,
      note: note,
    ));
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

void main() {
  late _FakeRepository repository;

  setUp(() => repository = _FakeRepository());

  const cash = AccountOption(
    id: 1,
    name: 'Cash',
    balanceCents: 125000,
    icon: 'cash',
  );
  const card = AccountOption(
    id: 2,
    name: 'Payment card',
    balanceCents: -75000,
    icon: 'card',
  );
  const dollars = AccountOption(
    id: 3,
    name: 'PayPal',
    balanceCents: 30000,
    icon: 'mobile',
    currency: 'USD',
  );

  Widget boot(List<AccountOption> accounts, ConversionTable table) =>
      ProviderScope(
        overrides: [
          entryAccountsProvider.overrideWith(
            (ref) => Stream<List<AccountOption>>.value(accounts),
          ),
          transactionRepositoryProvider.overrideWith((ref) async => repository),
          conversionTableProvider.overrideWith((ref) => Stream.value(table)),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const TransferPage()),
      );

  Future<void> open(
    WidgetTester tester, {
    List<AccountOption> accounts = const [cash, card],
    ConversionTable table = const ConversionTable(baseCurrency: 'LKR'),
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(boot(accounts, table));
    await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextField, label);

  group('recording a transfer', () {
    testWidgets('moves the amount between the two accounts', (tester) async {
      // Withdrawing Rs 800 from the card and holding it as cash.
      await open(tester);

      await tester.enterText(find.byType(TextField).first, '800');
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(repository.transfers, hasLength(1));
      expect(repository.transfers.single.from, 1);
      expect(repository.transfers.single.to, 2);
      expect(repository.transfers.single.amount, 80000);
    });

    testWidgets('carries the note onto the transfer', (tester) async {
      // FR-TRF-003. Shown on both halves.
      await open(tester);

      await tester.enterText(find.byType(TextField).at(0), '800');
      await tester.enterText(find.byType(TextField).at(1), 'Cash withdrawal');
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(repository.transfers.single.note, 'Cash withdrawal');
    });

    testWidgets('offers no category, because a transfer is not spending', (
      tester,
    ) async {
      // E-17 made category_id nullable for exactly this reason. A category
      // picker here would invite a transfer to be filed as an expense, which
      // is the double-counting bug E-02 warns about, one layer up.
      await open(tester);

      expect(find.text('Category'), findsNothing);
    });
  });

  group('refused, in the use case\'s own words', () {
    testWidgets('an amount of nothing', (tester) async {
      await open(tester);

      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(find.text('Enter an amount greater than zero.'), findsOneWidget);
      expect(repository.transfers, isEmpty);
    });

    testWidgets('says nothing about the amount before Transfer is pressed', (
      tester,
    ) async {
      await open(tester);

      expect(find.text('Enter an amount greater than zero.'), findsNothing);
    });

    testWidgets('the same account on both sides', (tester) async {
      await open(tester);

      await tester.enterText(find.byType(TextField).first, '800');
      // Point the destination at the source.
      await tester.tap(find.byType(DropdownButtonFormField<int>).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cash').last);
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('money cannot move to where it already is'),
        findsOneWidget,
      );
      expect(repository.transfers, isEmpty);
    });

    testWidgets('two currencies without saying what arrived', (tester) async {
      // E-34. E-25's refusal of two currencies is gone; what remains is that
      // the credit cannot be invented. The sentence is MakeTransfer's.
      await open(tester, accounts: const [cash, dollars]);

      await tester.enterText(field('Amount sent (LKR)'), '800');
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(
        find.text('Enter the amount that arrives in USD.'),
        findsOneWidget,
      );
      expect(repository.transfers, isEmpty);
    });

    testWidgets('shows a write failure rather than pretending it saved', (
      tester,
    ) async {
      repository.failWith = const CacheFailure('The database is locked.');
      await open(tester);

      await tester.enterText(find.byType(TextField).first, '800');
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(find.text('The database is locked.'), findsOneWidget);
      // Still on the transfer screen, because nothing was written.
      expect(find.widgetWithText(FilledButton, 'Transfer'), findsOneWidget);
    });
  });

  group('between two currencies', () {
    final usdToLkr = ExchangeRate(
      fromCurrency: 'LKR',
      toCurrency: 'USD',
      rateMicros: 3333,
      updatedAt: DateTime(2026, 9, 17),
    );

    testWidgets('offers one amount when both sides share a currency', (
      tester,
    ) async {
      await open(tester);

      expect(field('Amount'), findsOneWidget);
      expect(find.textContaining('Amount received'), findsNothing);
    });

    testWidgets('offers a second amount otherwise, named by currency', (
      tester,
    ) async {
      await open(tester, accounts: const [cash, dollars]);

      expect(field('Amount sent (LKR)'), findsOneWidget);
      expect(field('Amount received (USD)'), findsOneWidget);
    });

    testWidgets('records both figures, each in its own currency', (
      tester,
    ) async {
      // FR-TRF-001, FR-ACC-005: Rs 3,000 leaves cash, $10 arrives.
      await open(tester, accounts: const [cash, dollars]);

      await tester.enterText(field('Amount sent (LKR)'), '3000');
      await tester.enterText(field('Amount received (USD)'), '10');
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(repository.transfers.single.amount, 300000);
      expect(repository.transfers.single.credited, 1000);
    });

    testWidgets('pre-fills what arrives from the stored rate', (tester) async {
      // E-34: the rate suggests; the statement decides. Rs 3,000 at
      // 0.003333 USD/LKR is $10.00, to the cent.
      await open(
        tester,
        accounts: const [cash, dollars],
        table: ConversionTable(baseCurrency: 'LKR', rates: [usdToLkr]),
      );

      await tester.enterText(field('Amount sent (LKR)'), '3000');
      await tester.pumpAndSettle();

      final received = tester.widget<TextField>(field('Amount received (USD)'));
      expect(received.controller?.text, '10.00');
      expect(
        find.textContaining('Suggested from your stored rate'),
        findsOneWidget,
      );
    });

    testWidgets('keeps the number the user typed over the suggestion', (
      tester,
    ) async {
      await open(
        tester,
        accounts: const [cash, dollars],
        table: ConversionTable(baseCurrency: 'LKR', rates: [usdToLkr]),
      );

      await tester.enterText(field('Amount received (USD)'), '9.75');
      await tester.enterText(field('Amount sent (LKR)'), '3000');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(repository.transfers.single.credited, 975);
    });

    testWidgets('without a rate, asks for the statement figure', (
      tester,
    ) async {
      await open(tester, accounts: const [cash, dollars]);

      expect(
        find.textContaining('What actually arrived, from your statement.'),
        findsOneWidget,
      );
    });
  });

  group('with nowhere to transfer to', () {
    testWidgets('explains itself instead of showing two dead pickers', (
      tester,
    ) async {
      // E-22: what belongs here, why it is empty, and the one
      // action that fills it.
      await open(tester, accounts: const [cash]);

      expect(
        find.textContaining('you need a second one first'),
        findsOneWidget,
      );
      expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    });
  });

  group('the account pickers', () {
    testWidgets('show each balance in its own currency', (tester) async {
      await open(tester, accounts: const [cash, dollars]);

      expect(find.text('Rs1,250.00'), findsWidgets);
      // Not Rs300.00 — that would state something false about money the app
      // cannot convert.
      expect(find.text('USD 300.00'), findsWidgets);
    });

    testWidgets('start on two different accounts', (tester) async {
      // Defaulting both sides to the same account would open the screen in a
      // state its own validation refuses.
      await open(tester);

      await tester.enterText(find.byType(TextField).first, '800');
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(repository.transfers, hasLength(1));
      expect(
        repository.transfers.single.from,
        isNot(repository.transfers.single.to),
      );
    });
  });
}
