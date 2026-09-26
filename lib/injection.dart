import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'core/database/database_change_bus.dart';
import 'core/database/database_helper.dart';
import 'core/database/database_summary.dart';
import 'core/database/encryption_key_store.dart';
import 'core/database/seed/default_seed.dart';
import 'core/database/seed/keyword_seed.dart';
import 'core/errors/failures.dart';
import 'core/network/connectivity_network_info.dart';
import 'core/network/network_info.dart';
import 'core/notifications/flutter_local_notifier.dart';
import 'core/ports/account_reader.dart';
import 'core/ports/calendar_settings_reader.dart';
import 'core/ports/category_reader.dart';
import 'core/ports/category_writer.dart';
import 'core/ports/conversion_reader.dart';
import 'core/ports/expense_writer.dart';
import 'core/ports/income_reader.dart';
import 'core/ports/local_notifier.dart';
import 'core/ports/monthly_spending_reader.dart';
import 'core/ports/notification_settings_reader.dart';
import 'core/ports/notification_taps.dart';
import 'core/ports/spending_by_category_reader.dart';
import 'features/accounts/data/datasources/account_local_datasource.dart';
import 'features/accounts/data/repositories/account_repository_impl.dart';
import 'features/accounts/domain/repositories/account_repository.dart';
import 'features/accounts/domain/usecases/add_account.dart';
import 'features/accounts/domain/usecases/archive_account.dart';
import 'features/accounts/domain/usecases/delete_account.dart';
import 'features/accounts/domain/usecases/recompute_account_balance.dart';
import 'features/accounts/domain/usecases/recompute_all_account_balances.dart';
import 'features/accounts/domain/usecases/update_account.dart';
import 'features/accounts/domain/usecases/watch_accounts.dart';
import 'features/analytics/data/datasources/analytics_local_datasource.dart';
import 'features/analytics/data/repositories/analytics_repository_impl.dart';
import 'features/analytics/domain/repositories/analytics_repository.dart';
import 'features/analytics/domain/usecases/compare_periods.dart';
import 'features/analytics/domain/usecases/get_income_for_period.dart';
import 'features/analytics/domain/usecases/get_spending_by_category.dart';
import 'features/analytics/domain/usecases/get_spending_calendar.dart';
import 'features/analytics/domain/usecases/get_spending_trend.dart';
import 'features/auth/data/datasources/auth_local_datasource.dart';
import 'features/auth/data/datasources/pin_hasher.dart';
import 'features/auth/data/repositories/auth_repository_impl.dart';
import 'features/auth/data/repositories/local_auth_biometric_gateway.dart';
import 'features/auth/domain/repositories/auth_repository.dart';
import 'features/auth/domain/repositories/biometric_gateway.dart';
import 'features/auth/domain/usecases/authenticate_with_biometrics.dart';
import 'features/auth/domain/usecases/change_passcode.dart';
import 'features/auth/domain/usecases/disable_biometrics.dart';
import 'features/auth/domain/usecases/enable_biometrics.dart';
import 'features/auth/domain/usecases/get_lockout_state.dart';
import 'features/auth/domain/usecases/has_passcode.dart';
import 'features/auth/domain/usecases/is_biometrics_available.dart';
import 'features/auth/domain/usecases/is_biometrics_enabled.dart';
import 'features/auth/domain/usecases/remove_passcode.dart';
import 'features/auth/domain/usecases/set_passcode.dart';
import 'features/auth/domain/usecases/verify_passcode.dart';
import 'features/backup/data/datasources/backup_file_gateway.dart';
import 'features/backup/data/datasources/backup_local_datasource.dart';
import 'features/backup/data/datasources/backup_log.dart';
import 'features/backup/data/repositories/backup_repository_impl.dart';
import 'features/backup/domain/repositories/backup_repository.dart';
import 'features/backup/domain/usecases/clear_all_data.dart';
import 'features/backup/domain/usecases/create_backup.dart';
import 'features/backup/domain/usecases/export_transactions_csv.dart';
import 'features/backup/domain/usecases/export_transactions_pdf.dart';
import 'features/backup/domain/usecases/record_backup_saved.dart';
import 'features/backup/domain/usecases/restore_backup.dart';
import 'features/backup/domain/usecases/schedule_backup_reminder.dart';
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
import 'features/money_plan/data/datasources/money_plan_local_datasource.dart';
import 'features/money_plan/data/repositories/money_plan_repository_impl.dart';
import 'features/money_plan/domain/repositories/money_plan_repository.dart';
import 'features/money_plan/domain/usecases/activate_plan.dart';
import 'features/money_plan/domain/usecases/allocate_budget.dart';
import 'features/money_plan/domain/usecases/check_budget_alerts.dart';
import 'features/money_plan/domain/usecases/classify_categories.dart';
import 'features/money_plan/domain/usecases/compare_plans.dart';
import 'features/money_plan/domain/usecases/compute_category_statistics.dart';
import 'features/money_plan/domain/usecases/recompute_plan_spending.dart';
import 'features/money_plan/domain/usecases/respond_to_overspend.dart';
import 'features/money_plan/domain/usecases/save_plan.dart';
import 'features/money_plan/domain/usecases/update_allocation.dart';
import 'features/money_plan/domain/usecases/watch_active_plan.dart';
import 'features/money_plan/domain/usecases/watch_plans.dart';
import 'features/receipt_scanner/data/datasources/keyword_dictionary_local_datasource.dart';
import 'features/receipt_scanner/data/datasources/ml_kit_text_recogniser.dart';
import 'features/receipt_scanner/data/datasources/ocr_local_datasource.dart';
import 'features/receipt_scanner/data/datasources/receipt_image_local_datasource.dart';
import 'features/receipt_scanner/data/datasources/receipt_image_vault.dart';
import 'features/receipt_scanner/data/datasources/receipt_scan_local_datasource.dart';
import 'features/receipt_scanner/data/repositories/keyword_dictionary_repository_impl.dart';
import 'features/receipt_scanner/data/repositories/receipt_repository_impl.dart';
import 'features/receipt_scanner/domain/repositories/keyword_dictionary_repository.dart';
import 'features/receipt_scanner/domain/repositories/receipt_repository.dart';
import 'features/receipt_scanner/domain/usecases/categorise_receipt.dart';
import 'features/receipt_scanner/domain/usecases/confirm_receipt.dart';
import 'features/receipt_scanner/domain/usecases/get_scan_history.dart';
import 'features/receipt_scanner/domain/usecases/load_receipt_image.dart';
import 'features/receipt_scanner/domain/usecases/parse_receipt_text.dart';
import 'features/receipt_scanner/domain/usecases/pick_receipt_image.dart';
import 'features/receipt_scanner/domain/usecases/read_receipt_image.dart';
import 'features/receipt_scanner/domain/usecases/scan_receipt.dart';
import 'features/settings/data/datasources/exchange_rate_local_datasource.dart';
import 'features/settings/data/datasources/settings_local_datasource.dart';
import 'features/settings/data/repositories/calendar_settings_reader_impl.dart';
import 'features/settings/data/repositories/conversion_reader_impl.dart';
import 'features/settings/data/repositories/exchange_rate_repository_impl.dart';
import 'features/settings/data/repositories/notification_settings_reader_impl.dart';
import 'features/settings/data/repositories/settings_repository_impl.dart';
import 'features/settings/domain/repositories/exchange_rate_repository.dart';
import 'features/settings/domain/repositories/settings_repository.dart';
import 'features/settings/domain/usecases/remove_exchange_rate.dart';
import 'features/settings/domain/usecases/set_base_currency.dart';
import 'features/settings/domain/usecases/set_budget_alerts.dart';
import 'features/settings/domain/usecases/set_exchange_rate.dart';
import 'features/settings/domain/usecases/set_first_day_of_month.dart';
import 'features/settings/domain/usecases/set_first_day_of_week.dart';
import 'features/settings/domain/usecases/set_plan_analysis_months.dart';
import 'features/settings/domain/usecases/set_recurring_reminders.dart';
import 'features/settings/domain/usecases/set_reminder_schedule.dart';
import 'features/settings/domain/usecases/set_savings_target.dart';
import 'features/settings/domain/usecases/set_theme.dart';
import 'features/settings/domain/usecases/watch_exchange_rates.dart';
import 'features/settings/domain/usecases/watch_settings.dart';
import 'features/transactions/data/datasources/recurring_rule_local_datasource.dart';
import 'features/transactions/data/datasources/transaction_local_datasource.dart';
import 'features/transactions/data/repositories/recurring_rule_repository_impl.dart';
import 'features/transactions/data/repositories/transaction_repository_impl.dart';
import 'features/transactions/domain/repositories/recurring_rule_repository.dart';
import 'features/transactions/domain/repositories/transaction_repository.dart';
import 'features/transactions/domain/usecases/add_expenses.dart';
import 'features/transactions/domain/usecases/add_transaction.dart';
import 'features/transactions/domain/usecases/create_recurring_rule.dart';
import 'features/transactions/domain/usecases/delete_recurring_rule.dart';
import 'features/transactions/domain/usecases/delete_transaction.dart';
import 'features/transactions/domain/usecases/make_transfer.dart';
import 'features/transactions/domain/usecases/pause_recurring_rule.dart';
import 'features/transactions/domain/usecases/post_due_recurring_transactions.dart';
import 'features/transactions/domain/usecases/resume_recurring_rule.dart';
import 'features/transactions/domain/usecases/sync_recurring_reminders.dart';
import 'features/transactions/domain/usecases/update_transaction.dart';
import 'features/transactions/domain/usecases/watch_recurring_rules.dart';
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

/// The wall clock, as a function.
///
/// Anything that compares "now" against a stored moment — the passcode
/// lockout (NFR-SEC-003), the re-lock grace after the app was in the
/// background — reads it from here rather than calling `DateTime.now()`, so
/// a test can serve a thirty-second lockout in no time at all by overriding
/// this one provider.
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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
  // Every launch, not only the first: installs that predate Sprint 6 have
  // the dictionary table and nothing in it. One COUNT when already seeded.
  await applyKeywordSeed(db);
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

/// Reads and writes recurring rules and the entries they post. FR-EXP-008,
/// FR-INC-004.
///
/// On the shared bus, because an entry a rule posts moves a balance, plan
/// spend and the transaction list exactly as a typed one does, and every
/// screen showing those must hear it.
final recurringRuleLocalDataSourceProvider =
    FutureProvider<RecurringRuleLocalDataSource>((ref) async {
      final source = RecurringRuleLocalDataSourceImpl(
        await ref.watch(databaseProvider.future),
        changeBus: ref.watch(databaseChangeBusProvider),
      );
      ref.onDispose(source.dispose);
      return source;
    });

/// Turns the rules datasource's exceptions into failures.
final recurringRuleRepositoryProvider = FutureProvider<RecurringRuleRepository>(
  (ref) async => RecurringRuleRepositoryImpl(
    await ref.watch(recurringRuleLocalDataSourceProvider.future),
  ),
);

/// Records an expense or income that repeats. FR-EXP-008, FR-INC-004.
final createRecurringRuleProvider = FutureProvider<CreateRecurringRule>(
  (ref) async => CreateRecurringRule(
    await ref.watch(recurringRuleRepositoryProvider.future),
  ),
);

/// Watches every recurring rule for the rules list. FR-EXP-008, FR-INC-004.
final watchRecurringRulesProvider = FutureProvider<WatchRecurringRules>(
  (ref) async => WatchRecurringRules(
    await ref.watch(recurringRuleRepositoryProvider.future),
  ),
);

/// Stops a recurring rule posting.
final pauseRecurringRuleProvider = FutureProvider<PauseRecurringRule>(
  (ref) async => PauseRecurringRule(
    await ref.watch(recurringRuleRepositoryProvider.future),
  ),
);

/// Starts a paused recurring rule from today.
final resumeRecurringRuleProvider = FutureProvider<ResumeRecurringRule>(
  (ref) async => ResumeRecurringRule(
    await ref.watch(recurringRuleRepositoryProvider.future),
  ),
);

/// Deletes a recurring rule, keeping its entries. E-36.
final deleteRecurringRuleProvider = FutureProvider<DeleteRecurringRule>(
  (ref) async => DeleteRecurringRule(
    await ref.watch(recurringRuleRepositoryProvider.future),
  ),
);

/// Keeps one pending reminder per recurring rule. FR-SET-006, E-37.
///
/// Over [localNotifierProvider], the port the budget alerts already use —
/// synchronous, like it, because the plugin needs no database.
final syncRecurringRemindersProvider = Provider<SyncRecurringReminders>(
  (ref) => SyncRecurringReminders(ref.watch(localNotifierProvider)),
);

/// Posts every recurring entry that has fallen due. FR-EXP-008, FR-INC-004.
///
/// Reads accounts through [accountReaderProvider], the port — the
/// transactions feature may not import the accounts feature (rule 4) — to
/// leave a rule on an archived account unposted.
final postDueRecurringTransactionsProvider =
    FutureProvider<PostDueRecurringTransactions>(
      (ref) async => PostDueRecurringTransactions(
        await ref.watch(recurringRuleRepositoryProvider.future),
        await ref.watch(accountReaderProvider.future),
      ),
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

/// The concrete repository, named by its class rather than its interface.
///
/// Private, and typed concretely, because it satisfies two contracts —
/// [AccountRepository] for this feature and [AccountReader] for anything
/// outside it — and both views must be the same object, the same reasoning
/// `_analyticsRepositoryImplProvider` follows for
/// [AnalyticsRepository]/`SpendingByCategoryReader`.
final _accountRepositoryImplProvider = FutureProvider<AccountRepositoryImpl>(
  (ref) async => AccountRepositoryImpl(
    await ref.watch(accountLocalDataSourceProvider.future),
  ),
);

/// Turns account data-layer exceptions into failures. The layer boundary.
final accountRepositoryProvider = FutureProvider<AccountRepository>(
  (ref) async => ref.watch(_accountRepositoryImplProvider.future),
);

/// The entry and transfer screens' account picker, through the port in
/// `core/ports/` — `features/transactions/` may not import
/// `features/accounts/` (rule 4), so this is the seam between them. E-27.
final accountReaderProvider = FutureProvider<AccountReader>(
  (ref) async => ref.watch(_accountRepositoryImplProvider.future),
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

/// Re-derives one cached balance from history. E-18.
final recomputeAccountBalanceProvider = FutureProvider<RecomputeAccountBalance>(
  (ref) async => RecomputeAccountBalance(
    await ref.watch(accountRepositoryProvider.future),
  ),
);

/// Re-derives every cached balance from history. E-18.
///
/// The Settings action's use case, and the restore path's once Sprint 8
/// builds one. Never called on launch — see the E-18 addendum.
final recomputeAllAccountBalancesProvider =
    FutureProvider<RecomputeAllAccountBalances>(
      (ref) async => RecomputeAllAccountBalances(
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

/// The concrete repository, named by its class rather than its interface.
///
/// Private, and typed concretely, because it satisfies two contracts —
/// [CategoryRepository] for this feature and [CategoryReader] for anything
/// outside it — and both views must be the same object, the same reasoning
/// `_analyticsRepositoryImplProvider` follows for
/// [AnalyticsRepository]/`SpendingByCategoryReader`.
final _categoryRepositoryImplProvider = FutureProvider<CategoryRepositoryImpl>(
  (ref) async => CategoryRepositoryImpl(
    await ref.watch(categoryLocalDataSourceProvider.future),
  ),
);

/// Turns category data-layer exceptions into failures. The layer boundary.
final categoryRepositoryProvider = FutureProvider<CategoryRepository>(
  (ref) async => ref.watch(_categoryRepositoryImplProvider.future),
);

/// Creates a category. FR-EXP-004.
final addCategoryProvider = FutureProvider<AddCategory>(
  (ref) async =>
      AddCategory(await ref.watch(categoryRepositoryProvider.future)),
);

/// The entry screen's category chips, through the port in `core/ports/` —
/// `features/transactions/` may not import `features/categories/` (rule 4),
/// so this is the seam between them. E-27.
final categoryReaderProvider = FutureProvider<CategoryReader>(
  (ref) async => ref.watch(_categoryRepositoryImplProvider.future),
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

/// Total income over a period. FR-COP-008.
final getIncomeForPeriodProvider = FutureProvider<GetIncomeForPeriod>(
  (ref) async =>
      GetIncomeForPeriod(await ref.watch(analyticsRepositoryProvider.future)),
);

/// How spending by category moved between two periods. FR-COP-021.
final comparePeriodsProvider = FutureProvider<ComparePeriods>(
  (ref) async =>
      ComparePeriods(await ref.watch(analyticsRepositoryProvider.future)),
);

/// Per-category spending over time, for the trend lines. FR-RPT-005.
final getSpendingTrendProvider = FutureProvider<GetSpendingTrend>(
  (ref) async =>
      GetSpendingTrend(await ref.watch(analyticsRepositoryProvider.future)),
);

/// One month of daily totals, for the calendar heatmap. FR-RPT-009.
final getSpendingCalendarProvider = FutureProvider<GetSpendingCalendar>(
  (ref) async =>
      GetSpendingCalendar(await ref.watch(analyticsRepositoryProvider.future)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Money Plan
//
// Sprint 5, stage by stage: statistics, classification, allocation,
// confidence — then the saved plan, the feature's first writes.
// ─────────────────────────────────────────────────────────────────────────────

/// The month-cut read the plan's statistics run on.
///
/// The same object as [analyticsRepositoryProvider], seen through the
/// contract in `core/ports/` — one month query, shared with the trend lines.
final monthlySpendingReaderProvider = FutureProvider<MonthlySpendingReader>(
  (ref) async => ref.watch(_analyticsRepositoryImplProvider.future),
);

/// Per-category statistics over a lookback window. FR-PLN-005.
final computeCategoryStatisticsProvider =
    FutureProvider<ComputeCategoryStatistics>(
      (ref) async => ComputeCategoryStatistics(
        await ref.watch(monthlySpendingReaderProvider.future),
      ),
    );

/// Fixed / Variable / Seasonal per category, over those statistics.
/// FR-PLN-004.
final classifyCategoriesProvider = FutureProvider<ClassifyCategories>(
  (ref) async => ClassifyCategories(
    await ref.watch(computeCategoryStatisticsProvider.future),
  ),
);

/// The income read Option B budgets against — the same object as
/// [analyticsRepositoryProvider], through the contract in `core/ports/`.
final incomeReaderProvider = FutureProvider<IncomeReader>(
  (ref) async => ref.watch(_analyticsRepositoryImplProvider.future),
);

/// A budget per category for a plan period, and a total. FR-PLN-007,
/// FR-PLN-008, FR-PLN-009 — less what the previous plan carried over,
/// FR-PLN-014.
final allocateBudgetProvider = FutureProvider<AllocateBudget>(
  (ref) async => AllocateBudget(
    await ref.watch(classifyCategoriesProvider.future),
    await ref.watch(incomeReaderProvider.future),
    plans: await ref.watch(moneyPlanRepositoryProvider.future),
  ),
);

/// Applies one of FR-PLN-014's three responses to an exceeded category.
final respondToOverspendProvider = FutureProvider<RespondToOverspend>(
  (ref) async =>
      RespondToOverspend(await ref.watch(moneyPlanRepositoryProvider.future)),
);

/// Reads and writes saved plans. The only holder of SQL for the feature.
///
/// On the shared bus, as [accountLocalDataSourceProvider] is: FR-PLN-013's
/// spend against the active plan moves when a *transaction* is written, so
/// a plan watcher must hear the transactions datasource too.
final moneyPlanLocalDataSourceProvider =
    FutureProvider<MoneyPlanLocalDataSource>((ref) async {
      final source = MoneyPlanLocalDataSourceImpl(
        await ref.watch(databaseProvider.future),
        changeBus: ref.watch(databaseChangeBusProvider),
      );
      ref.onDispose(source.dispose);
      return source;
    });

/// Turns plan data-layer exceptions into failures. The layer boundary.
final moneyPlanRepositoryProvider = FutureProvider<MoneyPlanRepository>(
  (ref) async => MoneyPlanRepositoryImpl(
    await ref.watch(moneyPlanLocalDataSourceProvider.future),
  ),
);

/// Saves a reviewed draft, activating it by default. FR-PLN-001.
final savePlanProvider = FutureProvider<SavePlan>(
  (ref) async => SavePlan(await ref.watch(moneyPlanRepositoryProvider.future)),
);

/// Makes a saved plan the tracked one. FR-PLN-015.
final activatePlanProvider = FutureProvider<ActivatePlan>(
  (ref) async =>
      ActivatePlan(await ref.watch(moneyPlanRepositoryProvider.future)),
);

/// The active plan, live. FR-PLN-013.
final watchActivePlanProvider = FutureProvider<WatchActivePlan>(
  (ref) async =>
      WatchActivePlan(await ref.watch(moneyPlanRepositoryProvider.future)),
);

/// One allocation set by hand, the rest holding the total. FR-PLN-011.
final updateAllocationProvider = FutureProvider<UpdateAllocation>(
  (ref) async =>
      UpdateAllocation(await ref.watch(moneyPlanRepositoryProvider.future)),
);

/// Every saved plan, live. FR-PLN-015.
final watchPlansProvider = FutureProvider<WatchPlans>(
  (ref) async =>
      WatchPlans(await ref.watch(moneyPlanRepositoryProvider.future)),
);

/// Two saved plans side by side. FR-PLN-015.
final comparePlansProvider = FutureProvider<ComparePlans>(
  (ref) async =>
      ComparePlans(await ref.watch(moneyPlanRepositoryProvider.future)),
);

/// Re-derives a plan's spend from history. FR-PLN-013, E-18.
final recomputePlanSpendingProvider = FutureProvider<RecomputePlanSpending>(
  (ref) async => RecomputePlanSpending(
    await ref.watch(moneyPlanRepositoryProvider.future),
  ),
);

/// Announces the active plan's categories crossing 80% and 100%.
/// FR-SET-007, E-35.
final checkBudgetAlertsProvider = FutureProvider<CheckBudgetAlerts>(
  (ref) async => CheckBudgetAlerts(
    await ref.watch(moneyPlanRepositoryProvider.future),
    ref.watch(localNotifierProvider),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// Receipt scanner
//
// Sprint 6, stage by stage: the parser and the categoriser first, because
// they are the stages a test can prove without a camera; then the
// recogniser, behind a seam a test can fake.
// ─────────────────────────────────────────────────────────────────────────────

/// Reads the keyword dictionary. The only holder of SQL for the feature so
/// far; read-only until FR-RCP-015's learning lands.
final keywordDictionaryLocalDataSourceProvider =
    FutureProvider<KeywordDictionaryLocalDataSource>(
      (ref) async => KeywordDictionaryLocalDataSourceImpl(
        await ref.watch(databaseProvider.future),
      ),
    );

/// Turns dictionary data-layer exceptions into failures. The layer
/// boundary.
final keywordDictionaryRepositoryProvider =
    FutureProvider<KeywordDictionaryRepository>(
      (ref) async => KeywordDictionaryRepositoryImpl(
        await ref.watch(keywordDictionaryLocalDataSourceProvider.future),
      ),
    );

/// Merchant, items, total and tax from the lines OCR read. FR-RCP-005,
/// FR-RCP-006. Stateless; a provider so the screen gets it the same way as
/// every other use case.
final parseReceiptTextProvider = Provider<ParseReceiptText>(
  (ref) => const ParseReceiptText(),
);

/// A category and a confidence for every parsed item. FR-RCP-007.
final categoriseReceiptProvider = FutureProvider<CategoriseReceipt>(
  (ref) async => CategoriseReceipt(
    await ref.watch(keywordDictionaryRepositoryProvider.future),
  ),
);

/// ML Kit's on-device recogniser. FR-RCP-004.
///
/// One instance for the app rather than one per scan: the first call loads
/// the model, and that is the slow part. Closed on dispose so a hot restart
/// releases the native one. Overridden with a fake in tests, which is the
/// reason this is a provider and not a constructor call inside
/// [ocrLocalDataSourceProvider].
final textRecogniserProvider = Provider<TextRecogniser>((ref) {
  final recogniser = MlKitTextRecogniser();
  ref.onDispose(recogniser.close);
  return recogniser;
});

/// Reads the text off a receipt image and puts its rows back in printed
/// order. Synchronous, unlike the dictionary: no database on this path.
final ocrLocalDataSourceProvider = Provider<OcrLocalDataSource>(
  (ref) => OcrLocalDataSourceImpl(ref.watch(textRecogniserProvider)),
);

/// The device's camera and photo library. FR-RCP-002.
///
/// A provider for the reason [textRecogniserProvider] is one: the native
/// picker cannot run in a test. The datasource's own test hands it a fake;
/// the capture screen's test overrides the use cases above it.
final receiptImagePickerProvider = Provider<ReceiptImagePicker>(
  (ref) => ImagePickerReceiptImagePicker(),
);

/// A bounded receipt photo from either source. Synchronous, like the
/// recogniser: no database on this path.
final receiptImageLocalDataSourceProvider =
    Provider<ReceiptImageLocalDataSource>(
      (ref) => ReceiptImageLocalDataSourceImpl(
        ref.watch(receiptImagePickerProvider),
      ),
    );

/// Where a confirmed receipt's photo is kept, encrypted under a key
/// derived from the database's. FR-RCP-012, NFR-SEC-002.
///
/// Over the same [encryptionKeyStoreProvider] the database opens with, so
/// a test's [InMemoryKeyStore] covers both. The directories are
/// `path_provider`'s, asked for on first use; the vault's own test hands
/// it temporary ones.
final receiptImageVaultProvider = Provider<ReceiptImageVault>(
  (ref) => EncryptedReceiptImageVault(
    keyStore: ref.watch(encryptionKeyStoreProvider),
    documents: getApplicationDocumentsDirectory,
    temporary: getTemporaryDirectory,
  ),
);

/// Reads and writes scan records. The holder of SQL for `receipt_scans`
/// and `receipt_items`.
final receiptScanLocalDataSourceProvider =
    FutureProvider<ReceiptScanLocalDataSource>(
      (ref) async => ReceiptScanLocalDataSourceImpl(
        await ref.watch(databaseProvider.future),
      ),
    );

/// Turns recogniser and database exceptions into failures. The layer
/// boundary. A [FutureProvider] because the scan records reach the
/// database; the recogniser alone would not need one.
final receiptRepositoryProvider = FutureProvider<ReceiptRepository>(
  (ref) async => ReceiptRepositoryImpl(
    ref.watch(ocrLocalDataSourceProvider),
    await ref.watch(receiptScanLocalDataSourceProvider.future),
    ref.watch(receiptImageLocalDataSourceProvider),
    ref.watch(receiptImageVaultProvider),
  ),
);

/// A receipt photo's path, from the camera or the gallery. FR-RCP-002.
final pickReceiptImageProvider = FutureProvider<PickReceiptImage>(
  (ref) async =>
      PickReceiptImage(await ref.watch(receiptRepositoryProvider.future)),
);

/// The lines OCR read off an image. FR-RCP-004.
final scanReceiptProvider = FutureProvider<ScanReceipt>(
  (ref) async => ScanReceipt(await ref.watch(receiptRepositoryProvider.future)),
);

/// A photo to what the review screen opens with: scan, parse, categorise.
/// FR-RCP-004, FR-RCP-005, FR-RCP-007.
final readReceiptImageProvider = FutureProvider<ReadReceiptImage>(
  (ref) async => ReadReceiptImage(
    await ref.watch(scanReceiptProvider.future),
    ref.watch(parseReceiptTextProvider),
    await ref.watch(categoriseReceiptProvider.future),
  ),
);

/// The scanner's write path into the ledger, through the port in
/// `core/ports/` — `features/receipt_scanner/` may not import
/// `features/transactions/` (rule 4), so this is the seam between them,
/// the role [categoryWriterProvider] plays for the entry screen. FR-RCP-009.
final expenseWriterProvider = FutureProvider<ExpenseWriter>(
  (ref) async =>
      AddExpenses(await ref.watch(transactionRepositoryProvider.future)),
);

/// Posts a reviewed receipt: the scan record, the usage counts, then one
/// expense per item as a batch. FR-RCP-009.
final confirmReceiptProvider = FutureProvider<ConfirmReceipt>(
  (ref) async => ConfirmReceipt(
    await ref.watch(receiptRepositoryProvider.future),
    await ref.watch(keywordDictionaryRepositoryProvider.future),
    await ref.watch(expenseWriterProvider.future),
  ),
);

/// A receipt photo as bytes a screen can draw — decrypted when it is a
/// kept one. FR-RCP-012.
final loadReceiptImageProvider = FutureProvider<LoadReceiptImage>(
  (ref) async =>
      LoadReceiptImage(await ref.watch(receiptRepositoryProvider.future)),
);

/// Every receipt scanned so far, newest first, narrowed by a search.
/// FR-RCP-013.
final getScanHistoryProvider = FutureProvider<GetScanHistory>(
  (ref) async =>
      GetScanHistory(await ref.watch(receiptRepositoryProvider.future)),
);

// ─────────────────────────────────────────────────────────────────────────────
// Settings
// ─────────────────────────────────────────────────────────────────────────────

/// Reads and writes the single `users` row. The only holder of SQL for the
/// feature.
///
/// On the shared [DatabaseChangeBus], unlike categories: FR-ACC-005's base
/// currency lives in this row, and every summed balance on screen has to
/// follow a change to it the way it follows a transaction write.
final settingsLocalDataSourceProvider = FutureProvider<SettingsLocalDataSource>(
  (ref) async {
    final source = SettingsLocalDataSourceImpl(
      await ref.watch(databaseProvider.future),
      changeBus: ref.watch(databaseChangeBusProvider),
    );
    ref.onDispose(source.dispose);
    return source;
  },
);

/// Turns data-layer exceptions into failures. The layer boundary.
final settingsRepositoryProvider = FutureProvider<SettingsRepository>(
  (ref) async => SettingsRepositoryImpl(
    await ref.watch(settingsLocalDataSourceProvider.future),
  ),
);

/// The user's preferences, kept live. SRS §3.8.
final watchSettingsProvider = FutureProvider<WatchSettings>(
  (ref) async =>
      WatchSettings(await ref.watch(settingsRepositoryProvider.future)),
);

/// Chooses the theme. FR-SET-001.
final setThemeProvider = FutureProvider<SetTheme>(
  (ref) async => SetTheme(await ref.watch(settingsRepositoryProvider.future)),
);

/// Chooses the currency totals are expressed in. FR-SET-003.
final setBaseCurrencyProvider = FutureProvider<SetBaseCurrency>(
  (ref) async =>
      SetBaseCurrency(await ref.watch(settingsRepositoryProvider.future)),
);

/// Chooses the day a week starts on. FR-SET-004.
final setFirstDayOfWeekProvider = FutureProvider<SetFirstDayOfWeek>(
  (ref) async =>
      SetFirstDayOfWeek(await ref.watch(settingsRepositoryProvider.future)),
);

/// Chooses the day a month starts on. FR-SET-004.
final setFirstDayOfMonthProvider = FutureProvider<SetFirstDayOfMonth>(
  (ref) async =>
      SetFirstDayOfMonth(await ref.watch(settingsRepositoryProvider.future)),
);

/// Chooses how far back the Money Plan looks. FR-SET-012, FR-PLN-003.
final setPlanAnalysisMonthsProvider = FutureProvider<SetPlanAnalysisMonths>(
  (ref) async =>
      SetPlanAnalysisMonths(await ref.watch(settingsRepositoryProvider.future)),
);

/// Sets the savings target a suggested plan starts from. FR-SET-008.
final setSavingsTargetProvider = FutureProvider<SetSavingsTarget>(
  (ref) async =>
      SetSavingsTarget(await ref.watch(settingsRepositoryProvider.future)),
);

/// Turns budget alerts on, asking the platform first, or off. FR-SET-007.
final setBudgetAlertsProvider = FutureProvider<SetBudgetAlerts>(
  (ref) async => SetBudgetAlerts(
    await ref.watch(settingsRepositoryProvider.future),
    ref.watch(localNotifierProvider),
  ),
);

/// Turns recurring reminders on or off, asking permission first.
/// FR-SET-006, E-37.
final setRecurringRemindersProvider = FutureProvider<SetRecurringReminders>(
  (ref) async => SetRecurringReminders(
    await ref.watch(settingsRepositoryProvider.future),
    ref.watch(localNotifierProvider),
  ),
);

/// Sets how many days before, and at what time, reminders come. FR-SET-006.
final setReminderScheduleProvider = FutureProvider<SetReminderSchedule>(
  (ref) async =>
      SetReminderSchedule(await ref.watch(settingsRepositoryProvider.future)),
);

/// The notification settings, for features outside settings. FR-SET-007.
final notificationSettingsReaderProvider =
    FutureProvider<NotificationSettingsReader>(
      (ref) async => NotificationSettingsReaderImpl(
        await ref.watch(settingsRepositoryProvider.future),
      ),
    );

/// [NotificationSettings], kept live, for the Money Plan's budget alerts.
///
/// Here rather than in the Money Plan's providers for the reason
/// [calendarSettingsProvider] is: this file is the one place that may name
/// both the feature that owns the row and the one that reads it.
final notificationSettingsProvider = StreamProvider<NotificationSettings>((
  ref,
) {
  return Stream.fromFuture(ref.watch(notificationSettingsReaderProvider.future))
      .asyncExpand((reader) => reader.watch())
      .transform(
        StreamTransformer<
          Either<Failure, NotificationSettings>,
          NotificationSettings
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// The calendar settings, for features outside settings. FR-SET-004,
/// FR-SET-012.
final calendarSettingsReaderProvider = FutureProvider<CalendarSettingsReader>(
  (ref) async => CalendarSettingsReaderImpl(
    await ref.watch(settingsRepositoryProvider.future),
  ),
);

/// [CalendarSettings], kept live, for every period that has to be cut where
/// the user said and the Money Plan's lookback.
///
/// Here rather than in one feature's providers because analytics and the
/// Money Plan both read it, and this file is the one place both may name.
final calendarSettingsProvider = StreamProvider<CalendarSettings>((ref) {
  return Stream.fromFuture(ref.watch(calendarSettingsReaderProvider.future))
      .asyncExpand((reader) => reader.watch())
      .transform(
        StreamTransformer<
          Either<Failure, CalendarSettings>,
          CalendarSettings
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// Reads and writes `exchange_rates`. The only holder of SQL for the table.
///
/// On the shared [DatabaseChangeBus]: a rate is what converts every foreign
/// balance on screen (FR-ACC-005), so a total has to follow a rate change.
final exchangeRateLocalDataSourceProvider =
    FutureProvider<ExchangeRateLocalDataSource>((ref) async {
      final source = ExchangeRateLocalDataSourceImpl(
        await ref.watch(databaseProvider.future),
        changeBus: ref.watch(databaseChangeBusProvider),
      );
      ref.onDispose(source.dispose);
      return source;
    });

/// Turns data-layer exceptions into failures. The layer boundary.
final exchangeRateRepositoryProvider = FutureProvider<ExchangeRateRepository>(
  (ref) async => ExchangeRateRepositoryImpl(
    await ref.watch(exchangeRateLocalDataSourceProvider.future),
  ),
);

/// Every stored rate, kept live. FR-SET-003.
final watchExchangeRatesProvider = FutureProvider<WatchExchangeRates>(
  (ref) async => WatchExchangeRates(
    await ref.watch(exchangeRateRepositoryProvider.future),
  ),
);

/// Stores a user-entered rate. FR-SET-003, E-34.
final setExchangeRateProvider = FutureProvider<SetExchangeRate>(
  (ref) async =>
      SetExchangeRate(await ref.watch(exchangeRateRepositoryProvider.future)),
);

/// Forgets a rate. FR-SET-003.
final removeExchangeRateProvider = FutureProvider<RemoveExchangeRate>(
  (ref) async => RemoveExchangeRate(
    await ref.watch(exchangeRateRepositoryProvider.future),
  ),
);

/// The base currency and every rate, for features outside settings.
/// FR-ACC-005.
///
/// The seam the accounts feature converts through and the transfer screen
/// pre-fills from, so neither imports `features/settings/` (rule 4).
final conversionReaderProvider = FutureProvider<ConversionReader>(
  (ref) async => ConversionReaderImpl(
    await ref.watch(settingsRepositoryProvider.future),
    await ref.watch(exchangeRateRepositoryProvider.future),
  ),
);

/// The [ConversionTable], kept live, for any screen that sums or converts.
///
/// Here rather than in one feature's providers because two features read it
/// — the accounts panel (totals) and the transfer screen (the credited
/// amount's pre-fill) — and this file is the one place both may name.
final conversionTableProvider = StreamProvider<ConversionTable>((ref) {
  return Stream.fromFuture(ref.watch(conversionReaderProvider.future))
      .asyncExpand((reader) => reader.watch())
      .transform(
        StreamTransformer<
          Either<Failure, ConversionTable>,
          ConversionTable
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

// ─────────────────────────────────────────────────────────────────────────────
// Auth
//
// Sprint 7. Synchronous providers throughout: the passcode lives in the
// platform keychain, not the database, so the lock screen can be answered
// before the database is open — which is when it is drawn.
// ─────────────────────────────────────────────────────────────────────────────

/// The passcode record and the lockout state, in the platform keychain.
/// FR-SET-005, NFR-SEC-003, E-31 §1.
///
/// Overridden with [InMemoryAuthDataSource] in widget tests, where a method
/// channel never answers — the reason this is a provider rather than a
/// constructor call inside [authRepositoryProvider].
final authLocalDataSourceProvider = Provider<AuthLocalDataSource>(
  (ref) => SecureStorageAuthDataSource(),
);

/// PBKDF2 over the PIN, on a separate isolate. E-31 §1.
final pinHasherProvider = Provider<PinHasher>((ref) => Pbkdf2PinHasher());

/// Turns keychain exceptions into failures. The layer boundary.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepositoryImpl(
    ref.watch(authLocalDataSourceProvider),
    ref.watch(pinHasherProvider),
  ),
);

/// Whether the app is behind a passcode. FR-SET-005.
final hasPasscodeProvider = Provider<HasPasscode>(
  (ref) => HasPasscode(ref.watch(authRepositoryProvider)),
);

/// Where the gate stands before an attempt. NFR-SEC-003.
final getLockoutStateProvider = Provider<GetLockoutState>(
  (ref) => GetLockoutState(ref.watch(authRepositoryProvider)),
);

/// Checks a PIN and applies the lockout. NFR-SEC-003.
///
/// The one gate every attempt goes through; `ChangePasscode` and
/// `RemovePasscode` below are built over this same instance.
final verifyPasscodeProvider = Provider<VerifyPasscode>(
  (ref) => VerifyPasscode(
    ref.watch(authRepositoryProvider),
    now: ref.watch(clockProvider),
  ),
);

/// Turns the passcode on. FR-SET-005.
final setPasscodeProvider = Provider<SetPasscode>(
  (ref) => SetPasscode(ref.watch(authRepositoryProvider)),
);

/// Replaces the passcode, on proof of the current one. FR-SET-005.
final changePasscodeProvider = Provider<ChangePasscode>(
  (ref) => ChangePasscode(
    ref.watch(authRepositoryProvider),
    ref.watch(verifyPasscodeProvider),
  ),
);

/// Turns the passcode off, on proof of it. FR-SET-005.
final removePasscodeProvider = Provider<RemovePasscode>(
  (ref) => RemovePasscode(
    ref.watch(authRepositoryProvider),
    ref.watch(verifyPasscodeProvider),
  ),
);

/// The device's fingerprint / Face ID sensor, over `local_auth`. NFR-SEC-004.
///
/// Overridden with a fake in widget tests, where a method channel never
/// answers — the reason this is a provider and not a constructor call
/// inside the use cases below, the way [textRecogniserProvider] is one.
final biometricGatewayProvider = Provider<BiometricGateway>(
  (ref) => LocalAuthBiometricGateway(),
);

/// Whether the device can authenticate biometrically at all. NFR-SEC-004.
final isBiometricsAvailableProvider = Provider<IsBiometricsAvailable>(
  (ref) => IsBiometricsAvailable(ref.watch(biometricGatewayProvider)),
);

/// Whether biometric unlock is turned on. NFR-SEC-004.
final isBiometricsEnabledProvider = Provider<IsBiometricsEnabled>(
  (ref) => IsBiometricsEnabled(ref.watch(authRepositoryProvider)),
);

/// Turns biometric unlock on, after one successful prompt. NFR-SEC-004.
final enableBiometricsProvider = Provider<EnableBiometrics>(
  (ref) => EnableBiometrics(
    ref.watch(authRepositoryProvider),
    ref.watch(biometricGatewayProvider),
  ),
);

/// Turns biometric unlock off. NFR-SEC-004.
final disableBiometricsProvider = Provider<DisableBiometrics>(
  (ref) => DisableBiometrics(ref.watch(authRepositoryProvider)),
);

/// Prompts biometric authentication, for the lock screen. NFR-SEC-004.
final authenticateWithBiometricsProvider = Provider<AuthenticateWithBiometrics>(
  (ref) => AuthenticateWithBiometrics(ref.watch(biometricGatewayProvider)),
);
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Notifications
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

/// The one platform notifier, behind both of its contracts.
///
/// Private and concretely typed, as the analytics repository's provider is,
/// so [localNotifierProvider] and [notificationTapsProvider] hand out the
/// same object â€” the taps it reports are of the notifications it showed.
final _flutterLocalNotifierProvider = Provider<FlutterLocalNotifier>(
  (ref) => FlutterLocalNotifier(),
);

/// The device's notification tray. FR-SET-007.
///
/// Overridden with a fake in widget tests, where a method channel never
/// answers â€” the reason this is a provider, as [biometricGatewayProvider] is.
final localNotifierProvider = Provider<LocalNotifier>(
  (ref) => ref.watch(_flutterLocalNotifierProvider),
);

/// Notifications the user tapped, for the app root to open. FR-SET-007.
final notificationTapsProvider = Provider<NotificationTaps>(
  (ref) => ref.watch(_flutterLocalNotifierProvider),
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

// ─────────────────────────────────────────────────────────────────────────────
// Backup
//
// Sprint 8. FR-BAK-001, FR-BAK-005, FR-SET-009, E-38.
// ─────────────────────────────────────────────────────────────────────────────

/// Makes and restores `.mora` backups. The holder of SQL for the feature.
///
/// Over the receipt vault as its photo store, so a backup carries the kept
/// photos and a restore seals them again under this phone's key.
final backupLocalDataSourceProvider = FutureProvider<BackupLocalDataSource>(
  (ref) async => BackupLocalDataSourceImpl(
    await ref.watch(databaseProvider.future),
    photos: ref.watch(receiptImageVaultProvider),
    changeBus: ref.watch(databaseChangeBusProvider),
  ),
);

/// Turns backup exceptions into failures.
final backupRepositoryProvider = FutureProvider<BackupRepository>(
  (ref) async => BackupRepositoryImpl(
    await ref.watch(backupLocalDataSourceProvider.future),
    log: ref.watch(backupLogProvider),
    clock: ref.watch(clockProvider),
  ),
);

/// When this phone last saved a backup, in the keychain. FR-BAK-006.
final backupLogProvider = Provider<BackupLog>(
  (ref) => SecureStorageBackupLog(),
);

/// Keeps the backup reminder scheduled. FR-BAK-006.
final scheduleBackupReminderProvider = FutureProvider<ScheduleBackupReminder>(
  (ref) async => ScheduleBackupReminder(
    await ref.watch(backupRepositoryProvider.future),
    ref.watch(localNotifierProvider),
  ),
);

/// Notes that a backup was saved. FR-BAK-006.
final recordBackupSavedProvider = FutureProvider<RecordBackupSaved>(
  (ref) async =>
      RecordBackupSaved(await ref.watch(backupRepositoryProvider.future)),
);

/// Seals everything under a password. FR-BAK-001.
final createBackupProvider = FutureProvider<CreateBackup>(
  (ref) async => CreateBackup(await ref.watch(backupRepositoryProvider.future)),
);

/// Replaces everything with a backup. FR-BAK-005.
final restoreBackupProvider = FutureProvider<RestoreBackup>(
  (ref) async =>
      RestoreBackup(await ref.watch(backupRepositoryProvider.future)),
);

/// The platform's save and open dialogs. A seam so the screens are tested
/// against a fake.
final backupFileGatewayProvider = Provider<BackupFileGateway>(
  (ref) => const FilePickerBackupFileGateway(),
);

/// Deletes everything and reseeds the first-launch defaults. FR-SET-009.
final clearAllDataProvider = FutureProvider<ClearAllData>(
  (ref) async => ClearAllData(await ref.watch(backupRepositoryProvider.future)),
);

/// Every transaction as CSV. FR-RPT-007.
final exportTransactionsCsvProvider = FutureProvider<ExportTransactionsCsv>(
  (ref) async =>
      ExportTransactionsCsv(await ref.watch(backupRepositoryProvider.future)),
);

/// Every transaction as a PDF. FR-RPT-007.
final exportTransactionsPdfProvider = FutureProvider<ExportTransactionsPdf>(
  (ref) async =>
      ExportTransactionsPdf(await ref.watch(backupRepositoryProvider.future)),
);
