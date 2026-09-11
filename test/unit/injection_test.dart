@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
import 'package:moneyora/core/ports/account_reader.dart';
import 'package:moneyora/features/accounts/domain/entities/account.dart';
import 'package:moneyora/features/categories/domain/entities/category.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/repositories/transaction_repository.dart';
import 'package:moneyora/injection.dart';
// sqflite exports a Transaction of its own — the database kind, not the
// money kind.
import 'package:sqflite_common_ffi/sqflite_ffi.dart' hide Transaction;

/// Proves the transactions slice is actually reachable from the app.
///
/// Worth its own file because every layer of it can be correct and fully
/// tested while nothing constructs any of it — which is exactly the state this
/// repository was in until now. Unit tests pass, CI is green, and the feature
/// is unreachable dead code.
///
/// So this resolves the real providers, with only the database swapped for an
/// in-memory one, and drives a transaction all the way down and back.
/// Waits for [done], failing with [what] rather than hanging if it never comes.
///
/// A repository's watch re-reads asynchronously, so there is no number of
/// microtask turns that reliably covers it. The deadline keeps a broken
/// change signal to a two-second failure with a sentence attached, instead of
/// the suite's default timeout and no explanation.
Future<void> pumpUntil(bool Function() done, String what) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('timed out waiting for $what');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  sqfliteFfiInit();

  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [
        // The three seams the app already exposes for exactly this. Note that
        // the thing under test is still the real wiring — only the storage and
        // the key are replaced.
        databaseFactoryProvider.overrideWithValue(databaseFactoryFfi),
        databaseNameProvider.overrideWithValue(inMemoryDatabasePath),
        encryptionKeyStoreProvider.overrideWithValue(InMemoryKeyStore()),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('every transactions provider resolves', () async {
    // If any link in the chain is missing, this throws rather than failing an
    // assertion — which is the point.
    await expectLater(
      Future.wait([
        container.read(transactionLocalDataSourceProvider.future),
        container.read(transactionRepositoryProvider.future),
        container.read(addTransactionProvider.future),
        container.read(updateTransactionProvider.future),
        container.read(deleteTransactionProvider.future),
        container.read(makeTransferProvider.future),
        container.read(watchTransactionsProvider.future),
      ]),
      completes,
    );
  });

  test('an expense added through the use case comes back out', () async {
    // The seeded default account and categories come from applyDefaultSeed,
    // which databaseProvider runs on first launch — so ids 1 exist.
    final addTransaction = await container.read(addTransactionProvider.future);
    final watchTransactions = await container.read(
      watchTransactionsProvider.future,
    );

    final saved = await addTransaction(
      Transaction(
        accountId: 1,
        categoryId: 1,
        amountCents: 125000,
        type: TransactionType.expense,
        date: DateTime(2026, 9, 2),
        note: 'Groceries',
      ),
    );

    expect(saved.isRight(), isTrue, reason: 'add failed: $saved');

    final rows = await watchTransactions(const TransactionFilter()).first;
    final transactions = rows.getOrElse((_) => []);

    expect(transactions, hasLength(1));
    expect(transactions.single.amountCents, 125000);
    expect(transactions.single.note, 'Groceries');
    // The repository converts at the boundary; a model here would compare
    // unequal to an identical entity everywhere above.
    expect(transactions.single.runtimeType, Transaction);
  });

  test('an account balance on screen follows a transaction write', () async {
    // The wiring E-18 depends on, asserted through the real providers rather
    // than the datasources directly. `current_balance_cents` is moved by the
    // transactions datasource, and the accounts repository watches a stream
    // fed by the accounts one; they only meet because injection.dart hands
    // both the same DatabaseChangeBus.
    //
    // Remove that from either provider and this test fails: FR-ACC-003's
    // drawer would show a balance correct only until the first expense.
    //
    // The initial read **must** be allowed to land before the write. It is
    // scheduled when the stream is subscribed to but runs asynchronously, so
    // a write issued immediately is folded into it — after which the very
    // first emission already carries the new balance and the test passes
    // whether the bus exists or not. Not hypothetical: the first draft of
    // this test did exactly that and passed with the wiring removed.
    final watchAccounts = await container.read(watchAccountsProvider.future);
    final addTransaction = await container.read(addTransactionProvider.future);

    final emissions = <List<Account>>[];
    final subscription = watchAccounts(false)
        .map((result) => result.getOrElse((_) => <Account>[]))
        .listen(emissions.add);
    addTearDown(subscription.cancel);

    await pumpUntil(() => emissions.isNotEmpty, 'the initial account read');
    final opening = emissions.first
        .singleWhere((account) => account.id == 1)
        .currentBalanceCents;

    final saved = await addTransaction(
      Transaction(
        accountId: 1,
        categoryId: 1,
        amountCents: 125000,
        type: TransactionType.expense,
        date: DateTime(2026, 9, 2),
      ),
    );
    expect(saved.isRight(), isTrue, reason: 'add failed: $saved');

    await pumpUntil(
      () => emissions.length > 1,
      'a second emission after the transaction write',
    );

    expect(
      emissions.last
          .singleWhere((account) => account.id == 1)
          .currentBalanceCents,
      opening - 125000,
      reason: 'the watched balance did not follow the write',
    );
  });

  test(
    'the entry screen account port reads the same repository. E-27',
    () async {
      // Proves accountReaderProvider is not a second read path — a balance
      // moved by a transaction write comes back out of the port the entry
      // and transfer screens actually watch.
      final reader = await container.read(accountReaderProvider.future);
      final addTransaction = await container.read(
        addTransactionProvider.future,
      );

      final emissions = <List<AccountOption>>[];
      final subscription = reader
          .watchAll()
          .map((result) => result.getOrElse((_) => <AccountOption>[]))
          .listen(emissions.add);
      addTearDown(subscription.cancel);

      await pumpUntil(() => emissions.isNotEmpty, 'the initial account read');
      final opening = emissions.first
          .singleWhere((account) => account.id == 1)
          .balanceCents;

      final saved = await addTransaction(
        Transaction(
          accountId: 1,
          categoryId: 1,
          amountCents: 75000,
          type: TransactionType.expense,
          date: DateTime(2026, 9, 2),
        ),
      );
      expect(saved.isRight(), isTrue, reason: 'add failed: $saved');

      await pumpUntil(
        () => emissions.length > 1,
        'a second emission after the transaction write',
      );

      expect(
        emissions.last.singleWhere((account) => account.id == 1).balanceCents,
        opening - 75000,
        reason: 'the account port did not follow the write',
      );
    },
  );

  test('every categories provider resolves', () async {
    await expectLater(
      Future.wait([
        container.read(categoryLocalDataSourceProvider.future),
        container.read(categoryRepositoryProvider.future),
        container.read(addCategoryProvider.future),
        container.read(updateCategoryProvider.future),
        container.read(deleteCategoryProvider.future),
        container.read(watchCategoriesProvider.future),
        container.read(categoryWriterProvider.future),
        container.read(categoryReaderProvider.future),
      ]),
      completes,
    );
  });

  test(
    'the entry screen category port reads the same repository. E-27',
    () async {
      // Proves categoryReaderProvider is not a second read path — a category
      // added through the use case comes back out of the port the entry
      // screen actually watches.
      final addCategory = await container.read(addCategoryProvider.future);
      final reader = await container.read(categoryReaderProvider.future);

      final saved = await addCategory(
        const Category(
          name: 'Stationery',
          icon: 'pencil',
          colorHex: '#795548',
          type: CategoryType.expense,
        ),
      );
      expect(saved.isRight(), isTrue, reason: 'add failed: $saved');

      final rows = await reader.watchAll().first;
      final categories = rows.getOrElse((_) => []);

      expect(categories.any((c) => c.name == 'Stationery'), isTrue);
    },
  );

  test(
    'the entry screen inline + writes through the same repository',
    () async {
      // E-13: proves categoryWriterProvider is not a second path to the table —
      // a category it creates comes back out of the same WatchCategories the
      // categories screen reads.
      final writer = await container.read(categoryWriterProvider.future);
      final watchCategories = await container.read(
        watchCategoriesProvider.future,
      );

      final saved = await writer(name: 'Subscriptions', isExpense: true);
      expect(saved.isRight(), isTrue, reason: 'quick add failed: $saved');

      final rows = await watchCategories(null).first;
      final categories = rows.getOrElse((_) => []);

      expect(categories.any((c) => c.name == 'Subscriptions'), isTrue);
    },
  );

  test('a category added through the use case comes back out', () async {
    final addCategory = await container.read(addCategoryProvider.future);
    final watchCategories = await container.read(
      watchCategoriesProvider.future,
    );

    final saved = await addCategory(
      const Category(
        name: 'Hobbies',
        icon: 'star',
        colorHex: '#673AB7',
        type: CategoryType.expense,
      ),
    );

    expect(saved.isRight(), isTrue, reason: 'add failed: $saved');

    final rows = await watchCategories(null).first;
    final categories = rows.getOrElse((_) => []);

    final hobbies = categories.firstWhere((c) => c.name == 'Hobbies');
    // The repository converts at the boundary; a model here would compare
    // unequal to an identical entity everywhere above.
    expect(hobbies.runtimeType, Category);
  });

  test('validation runs before anything is written', () async {
    final addTransaction = await container.read(addTransactionProvider.future);
    final watchTransactions = await container.read(
      watchTransactionsProvider.future,
    );

    final result = await addTransaction(
      Transaction(
        accountId: 1,
        categoryId: 1,
        amountCents: 0,
        type: TransactionType.expense,
        date: DateTime(2026, 9, 2),
      ),
    );

    expect(result.isLeft(), isTrue);
    final rows = await watchTransactions(const TransactionFilter()).first;
    expect(rows.getOrElse((_) => []), isEmpty);
  });
}
