import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'core/database/database_change_bus.dart';
import 'core/database/database_helper.dart';
import 'core/database/database_summary.dart';
import 'core/database/encryption_key_store.dart';
import 'core/database/seed/default_seed.dart';
import 'core/network/connectivity_network_info.dart';
import 'core/network/network_info.dart';
import 'core/ports/category_writer.dart';
import 'core/ports/spending_by_category_reader.dart';
import 'features/accounts/data/datasources/account_local_datasource.dart';
import 'features/accounts/data/repositories/account_repository_impl.dart';
import 'features/accounts/domain/repositories/account_repository.dart';
import 'features/accounts/domain/usecases/add_account.dart';
import 'features/accounts/domain/usecases/archive_account.dart';
import 'features/accounts/domain/usecases/delete_account.dart';
import 'features/accounts/domain/usecases/recompute_account_balance.dart';
import 'features/accounts/domain/usecases/update_account.dart';
import 'features/accounts/domain/usecases/watch_accounts.dart';
import 'features/analytics/data/datasources/analytics_local_datasource.dart';
import 'features/analytics/data/repositories/analytics_repository_impl.dart';
import 'features/analytics/domain/repositories/analytics_repository.dart';
import 'features/analytics/domain/usecases/get_spending_by_category.dart';
import 'features/categories/data/datasources/category_local_datasource.dart';
import 'features/categories/data/repositories/category_repository_impl.dart';
import 'features/categories/domain/repositories/category_repository.dart';
import 'features/categories/domain/usecases/add_category.dart';
import 'features/categories/domain/usecases/delete_category.dart';
import 'features/categories/domain/usecases/quick_add_category.dart';
import 'features/categories/domain/usecases/update_category.dart';
import 'features/categories/domain/usecases/watch_categories.dart';
import 'features/copilot/data/datasources/gemini_remote_datasource.dart';
import 'features/copilot/data/datasources/secure_llm_api_key_store.dart';
import 'features/copilot/data/repositories/llm_repository_impl.dart';
import 'features/copilot/domain/repositories/llm_repository.dart';
import 'features/copilot/domain/usecases/run_copilot_query.dart';
import 'features/copilot/domain/usecases/tools/copilot_tool.dart';
import 'features/copilot/domain/usecases/tools/get_spending_by_category_tool.dart';
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

/// The one change signal every datasource publishes to. E-18, FR-ACC-003.
///
/// Shared rather than per-datasource because a write in one feature can move
/// another's rows: every transaction write adjusts
/// `accounts.current_balance_cents`, inside the same database transaction, so
/// an accounts watcher listening only to accounts writes shows a stale
/// balance. Owned here — the datasources are handed it and never close it,
/// because the first one disposed would otherwise silence the rest.
///
/// Synchronous, unlike everything below it: the bus needs no database.
final databaseChangeBusProvider = Provider<DatabaseChangeBus>((ref) {
  final bus = DatabaseChangeBus();
  ref.onDispose(bus.close);
  return bus;
});

/// Reads and writes transaction rows. The only holder of SQL for the feature.
final transactionLocalDataSourceProvider =
    FutureProvider<TransactionLocalDataSource>((ref) async {
      final source = TransactionLocalDataSourceImpl(
        await ref.watch(databaseProvider.future),
        changeBus: ref.watch(databaseChangeBusProvider),
      );
      // Disposing the datasource no longer closes the change stream — the bus
      // owns it, and closing it here would silence the accounts datasource
      // too. The bus's own provider closes it, which still stops a hot restart
      // from leaving listeners attached to a dead controller.
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

// ─────────────────────────────────────────────────────────────────────────────
// Accounts
// ─────────────────────────────────────────────────────────────────────────────

/// Reads and writes account rows, and re-derives their balances.
final accountLocalDataSourceProvider = FutureProvider<AccountLocalDataSource>((
  ref,
) async {
  final source = AccountLocalDataSourceImpl(
    await ref.watch(databaseProvider.future),
    changeBus: ref.watch(databaseChangeBusProvider),
  );
  ref.onDispose(source.dispose);
  return source;
});

/// Turns account data-layer exceptions into failures.
final accountRepositoryProvider = FutureProvider<AccountRepository>(
  (ref) async => AccountRepositoryImpl(
    await ref.watch(accountLocalDataSourceProvider.future),
  ),
);

/// Creates an account. FR-ACC-001.
final addAccountProvider = FutureProvider<AddAccount>(
  (ref) async => AddAccount(await ref.watch(accountRepositoryProvider.future)),
);

/// Edits an account. FR-ACC-002.
final updateAccountProvider = FutureProvider<UpdateAccount>(
  (ref) async =>
      UpdateAccount(await ref.watch(accountRepositoryProvider.future)),
);

/// Hides an account without losing its history. FR-ACC-004.
final archiveAccountProvider = FutureProvider<ArchiveAccount>(
  (ref) async =>
      ArchiveAccount(await ref.watch(accountRepositoryProvider.future)),
);

/// Removes an account that has never been used. FR-ACC-007, E-25.
final deleteAccountProvider = FutureProvider<DeleteAccount>(
  (ref) async =>
      DeleteAccount(await ref.watch(accountRepositoryProvider.future)),
);

/// Watches accounts and their balances. FR-ACC-003.
final watchAccountsProvider = FutureProvider<WatchAccounts>(
  (ref) async =>
      WatchAccounts(await ref.watch(accountRepositoryProvider.future)),
);

/// Re-derives a cached balance from history. E-18.
final recomputeAccountBalanceProvider = FutureProvider<RecomputeAccountBalance>(
  (ref) async => RecomputeAccountBalance(
    await ref.watch(accountRepositoryProvider.future),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Categories
// ─────────────────────────────────────────────────────────────────────────────

/// Reads and writes category rows.
///
/// No shared `DatabaseChangeBus` here, unlike [accountLocalDataSourceProvider]
/// — a category list changes only when a category itself is written, never as
/// a side effect of a transaction the way a balance cache does (E-18), so a
/// private bus is all this needs.
final categoryLocalDataSourceProvider = FutureProvider<CategoryLocalDataSource>(
  (ref) async {
    final source = CategoryLocalDataSourceImpl(
      await ref.watch(databaseProvider.future),
    );
    ref.onDispose(source.dispose);
    return source;
  },
);

/// Turns category data-layer exceptions into failures.
final categoryRepositoryProvider = FutureProvider<CategoryRepository>(
  (ref) async => CategoryRepositoryImpl(
    await ref.watch(categoryLocalDataSourceProvider.future),
  ),
);

/// Creates a category. FR-EXP-004.
final addCategoryProvider = FutureProvider<AddCategory>(
  (ref) async =>
      AddCategory(await ref.watch(categoryRepositoryProvider.future)),
);

/// The entry screen's inline `+`, through the port in `core/ports/` —
/// `features/transactions/` may not import `features/categories/` (rule 4),
/// so this is the seam between them. E-13.
final categoryWriterProvider = FutureProvider<CategoryWriter>(
  (ref) async => QuickAddCategory(await ref.watch(addCategoryProvider.future)),
);

/// Renames, recolours, re-icons or re-parents a category. FR-EXP-004,
/// FR-EXP-005.
final updateCategoryProvider = FutureProvider<UpdateCategory>(
  (ref) async =>
      UpdateCategory(await ref.watch(categoryRepositoryProvider.future)),
);

/// Removes a category nothing depends on. FR-EXP-004.
final deleteCategoryProvider = FutureProvider<DeleteCategory>(
  (ref) async =>
      DeleteCategory(await ref.watch(categoryRepositoryProvider.future)),
);

/// Watches the category list. FR-EXP-004, FR-EXP-011.
final watchCategoriesProvider = FutureProvider<WatchCategories>(
  (ref) async =>
      WatchCategories(await ref.watch(categoryRepositoryProvider.future)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Analytics
//
// Read-only: nothing here writes a row. The aggregates are derived from
// history every time they are asked for, which is the only way they cannot
// drift from it.
// ─────────────────────────────────────────────────────────────────────────────

/// Runs the aggregate queries. The only holder of SQL for the feature.
final analyticsLocalDataSourceProvider =
    FutureProvider<AnalyticsLocalDataSource>(
      (ref) async => AnalyticsLocalDataSourceImpl(
        await ref.watch(databaseProvider.future),
      ),
    );

/// The concrete repository, named by its class rather than its interface.
///
/// Private, and typed concretely, because it satisfies two contracts —
/// [AnalyticsRepository] for this feature and [SpendingByCategoryReader] for
/// anything outside it — and both views must be the same object. Two providers
/// each calling the constructor would be two repositories over one database:
/// harmless today, and exactly the kind of thing that stops being harmless
/// once one of them caches.
final _analyticsRepositoryImplProvider =
    FutureProvider<AnalyticsRepositoryImpl>(
      (ref) async => AnalyticsRepositoryImpl(
        await ref.watch(analyticsLocalDataSourceProvider.future),
      ),
    );

/// Turns analytics data-layer exceptions into failures. The layer boundary.
final analyticsRepositoryProvider = FutureProvider<AnalyticsRepository>(
  (ref) async => ref.watch(_analyticsRepositoryImplProvider.future),
);

/// What was spent per category over a period. FR-RPT-001.
final getSpendingByCategoryProvider = FutureProvider<GetSpendingByCategory>(
  (ref) async => GetSpendingByCategory(
    await ref.watch(analyticsRepositoryProvider.future),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Copilot
// ─────────────────────────────────────────────────────────────────────────────

/// The narrow read the Copilot's spending tool runs on.
///
/// The same object as [analyticsRepositoryProvider], seen through the contract
/// in `core/ports/`. That is what keeps the agent and the donut chart counting
/// spending the same way — there is one query, not two.
final spendingByCategoryReaderProvider =
    FutureProvider<SpendingByCategoryReader>(
      (ref) async => ref.watch(_analyticsRepositoryImplProvider.future),
    );

/// Every tool the agent may call, registered declaratively.
///
/// Adding a tool is one entry in this list and no change to the loop, which
/// indexes them by their own descriptor names (NFR-POR-007).
final copilotToolsProvider = FutureProvider<List<CopilotTool>>(
  (ref) async => [
    GetSpendingByCategoryTool(
      await ref.watch(spendingByCategoryReaderProvider.future),
    ),
  ],
);

/// The HTTP client, shared by everything that talks to the network.
///
/// One client rather than one per call, because each `http.Client()` opens its
/// own connection pool; closed on dispose so a hot restart does not leave the
/// old pool holding sockets.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Whether the radio is up. FR-COP-013.
///
/// Only optional features ask. Everything core to Moneyora works offline, so a
/// second caller here would be a bug worth investigating rather than a feature.
final networkInfoProvider = Provider<NetworkInfo>(
  (ref) => ConnectivityNetworkInfo(),
);

/// The Copilot's API key, in the platform keychain and nowhere else.
///
/// Non-negotiable #3. Overridden with [InMemoryLlmApiKeyStore] in tests, which
/// is the whole reason this is a provider and not a constructor call.
final llmApiKeyStoreProvider = Provider<LlmApiKeyStore>(
  (ref) => SecureLlmApiKeyStore(),
);

/// Asks Gemini what to do next. The only networked code in the application.
final geminiRemoteDataSourceProvider = Provider<GeminiRemoteDataSource>(
  (ref) => GeminiRemoteDataSource(
    ref.watch(httpClientProvider),
    ref.watch(llmApiKeyStoreProvider),
  ),
);

/// Turns transport and provider errors into failures. The layer boundary.
///
/// Typed as [LlmRepository], so swapping Gemini for another provider changes
/// this line and nothing above it (NFR-POR-007).
final llmRepositoryProvider = Provider<LlmRepository>(
  (ref) => LlmRepositoryImpl(ref.watch(geminiRemoteDataSourceProvider)),
);

/// The agent loop. FR-COP-004.
///
/// A [FutureProvider] because the tools reach the database, which opens
/// asynchronously — not because the loop itself is slow to build.
final runCopilotQueryProvider = FutureProvider<RunCopilotQuery>(
  (ref) async => RunCopilotQuery(
    ref.watch(llmRepositoryProvider),
    ref.watch(networkInfoProvider),
    tools: await ref.watch(copilotToolsProvider.future),
  ),
);
