@TestOn('vm')
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moneyora/core/database/encryption_key_store.dart';
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
