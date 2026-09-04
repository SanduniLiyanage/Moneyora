import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'core/database/database_helper.dart';
import 'core/database/database_summary.dart';
import 'core/database/encryption_key_store.dart';
import 'core/database/seed/default_seed.dart';
import 'features/transactions/data/datasources/transaction_local_datasource.dart';
import 'features/transactions/data/repositories/transaction_repository_impl.dart';
import 'features/transactions/domain/repositories/transaction_repository.dart';
import 'features/transactions/domain/usecases/add_transaction.dart';
import 'features/transactions/domain/usecases/delete_transaction.dart';
import 'features/transactions/domain/usecases/make_transfer.dart';
import 'features/transactions/domain/usecases/update_transaction.dart';
import 'features/transactions/domain/usecases/watch_transactions.dart';

/// Dependency wiring, per SDD §3.3.
///
/// Riverpod is the DI container — there is no second framework. Each provider
/// names one dependency and states what it is built from, so the graph is
/// readable top to bottom.
///
/// Anything a test needs to replace is overridable at `ProviderScope`, which
/// is the point of declaring them here rather than constructing objects inside
/// widgets.

/// Supplies the AES-256 database key from the platform keychain.
///
/// Overridden with [InMemoryKeyStore] in tests, which is why this is a
/// provider rather than a constructor call inside [databaseHelperProvider].
final encryptionKeyStoreProvider = Provider<EncryptionKeyStore>(
  (ref) => SecureStorageKeyStore(),
);

/// The connection factory. `databaseFactory` here is sqflite_sqlcipher's,
/// which is what makes the file encrypted at rest (NFR-SEC-001).
///
/// Tests override this with `databaseFactoryFfi` so they run without a device.
final databaseFactoryProvider = Provider<DatabaseFactory>(
  (ref) => databaseFactory,
);

/// The database file name.
///
/// A provider rather than a constant so tests can point it at
/// `inMemoryDatabasePath` and override configuration instead of replacing
/// [databaseHelperProvider] itself — which would mean the thing under test was
/// no longer the thing that ships.
final databaseNameProvider = Provider<String>((ref) => 'moneyora.db');

/// Opens the database and runs any pending migrations.
final databaseHelperProvider = Provider<DatabaseHelper>((ref) {
  final helper = DatabaseHelper(
    dbFactory: ref.watch(databaseFactoryProvider),
    keyStore: ref.watch(encryptionKeyStoreProvider),
    databaseName: ref.watch(databaseNameProvider),
  );
  // Close on dispose so a hot restart does not leak the handle and leave the
  // file locked — which presents as a mysterious "database is locked" on the
  // next open rather than as anything resembling its cause.
  ref.onDispose(helper.close);
  return helper;
});

/// Opens the database, applies migrations, and seeds defaults on first run.
///
/// Exposed as a [FutureProvider] because every one of those steps is async and
/// can fail; `AsyncValue` gives the UI loading and error states for free rather
/// than leaving the first screen to guess.
final databaseProvider = FutureProvider<Database>((ref) async {
  final helper = ref.watch(databaseHelperProvider);
  final db = await helper.database;

  // First launch only. FR-EXP-003 and FR-INC-002 expect the default categories
  // to exist before the user sees anything, so this runs before the first
  // frame that needs them rather than lazily.
  if (await isFirstLaunch(db)) {
    await applyDefaultSeed(db);
  }
  return db;
});

/// A count of what the database holds. See [readDatabaseSummary].
///
/// A [FutureProvider] because the read is async and can fail; `AsyncValue`
/// gives the UI loading and error states without the screen inventing them.
final databaseSummaryProvider = FutureProvider<DatabaseSummary>((ref) async {
  final db = await ref.watch(databaseProvider.future);
  return readDatabaseSummary(db);
});

// ─────────────────────────────────────────────────────────────────────────────
// Transactions
//
// This file is the one place allowed to name a concrete `data/` class; the
// layer check forbids it everywhere above `domain/`. Everything below is a
// `FutureProvider` because the database opens asynchronously, and pretending
// otherwise would mean a synchronous provider that throws on first use.
// ─────────────────────────────────────────────────────────────────────────────

/// Reads and writes transaction rows. The only holder of SQL for the feature.
final transactionLocalDataSourceProvider =
    FutureProvider<TransactionLocalDataSource>((ref) async {
      final source = TransactionLocalDataSourceImpl(
        await ref.watch(databaseProvider.future),
      );
      // The change stream is a broadcast controller. Closing it on dispose
      // stops a hot restart from leaving listeners attached to the old one,
      // which presents as a screen that updates twice per write.
      ref.onDispose(source.dispose);
      return source;
    });

/// Turns data-layer exceptions into failures. The layer boundary.
final transactionRepositoryProvider = FutureProvider<TransactionRepository>((
  ref,
) async {
  return TransactionRepositoryImpl(
    await ref.watch(transactionLocalDataSourceProvider.future),
  );
});

/// Records a new expense or income, after validating it. FR-EXP-001.
final addTransactionProvider = FutureProvider<AddTransaction>(
  (ref) async =>
      AddTransaction(await ref.watch(transactionRepositoryProvider.future)),
);

/// Edits an existing transaction. FR-EXP-006.
final updateTransactionProvider = FutureProvider<UpdateTransaction>(
  (ref) async =>
      UpdateTransaction(await ref.watch(transactionRepositoryProvider.future)),
);

/// Removes a transaction, and a whole transfer if it is half of one.
final deleteTransactionProvider = FutureProvider<DeleteTransaction>(
  (ref) async =>
      DeleteTransaction(await ref.watch(transactionRepositoryProvider.future)),
);

/// Moves money between two accounts atomically. FR-TRF-002.
final makeTransferProvider = FutureProvider<MakeTransfer>(
  (ref) async =>
      MakeTransfer(await ref.watch(transactionRepositoryProvider.future)),
);

/// Watches the transactions matching a filter. FR-RPT-002.
final watchTransactionsProvider = FutureProvider<WatchTransactions>(
  (ref) async =>
      WatchTransactions(await ref.watch(transactionRepositoryProvider.future)),
);
