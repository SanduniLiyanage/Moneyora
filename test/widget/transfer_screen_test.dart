@TestOn('vm')
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/database/entry_catalog.dart';
import 'package:moneyora/core/errors/failures.dart';
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
  final List<({int from, int to, int amount, DateTime date, String? note})>
  transfers = [];

  Failure? failWith;

  @override
  Future<Either<Failure, int>> transfer({
    required int fromAccountId,
    required int toAccountId,
    required int amountCents,
    required DateTime date,
    String? note,
  }) async {
    if (failWith case final failure?) return Left(failure);
    transfers.add((
      from: fromAccountId,
      to: toAccountId,
      amount: amountCents,
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

  EntryCatalog catalogOf(List<AccountOption> accounts) =>
      EntryCatalog(categories: const [], accounts: accounts);

  Widget boot(List<AccountOption> accounts) => ProviderScope(
    overrides: [
      entryCatalogProvider.overrideWith((ref) => catalogOf(accounts)),
      transactionRepositoryProvider.overrideWith((ref) async => repository),
    ],
    child: MaterialApp(theme: AppTheme.light, home: const TransferPage()),
  );

  Future<void> open(
    WidgetTester tester, {
    List<AccountOption> accounts = const [cash, card],
  }) async {
    tester.view
      ..physicalSize = const Size(1200, 2000)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(boot(accounts));
    await tester.pumpAndSettle();
  }

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

    testWidgets('two accounts that do not share a currency', (tester) async {
      // E-25's interim rule. Without conversion, moving 100 from a USD account
      // to an LKR one would credit 100 rupees — wrong by a factor of three
      // hundred and entirely plausible on screen.
      await open(tester, accounts: const [cash, dollars]);

      await tester.enterText(find.byType(TextField).first, '800');
      await tester.tap(find.widgetWithText(FilledButton, 'Transfer'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('cannot convert between currencies yet'),
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

  group('with nowhere to transfer to', () {
    testWidgets('explains itself instead of showing two dead pickers', (
      tester,
    ) async {
      // E-22, NFR-USA-001: what belongs here, why it is empty, and the one
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
