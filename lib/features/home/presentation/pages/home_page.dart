import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_summary.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection.dart';

/// Sprint 1's home screen.
///
/// Not SCR-001's full design — the balance bar and category ring are still
/// open — but the donut chart (FR-RPT-001) arrived this session. What the
/// rest of this screen does is prove the foundation works **on a real
/// device**, which no unit test can: the SQLCipher file opened with a key from
/// the platform keychain, the migration ran, and the default categories seeded.
///
/// Those three things pass in tests against an in-memory database on a laptop.
/// Whether they work on an Android phone is a different question, and this
/// screen is how it gets answered.
class HomePage extends ConsumerWidget {
  /// Creates the home screen.
  const HomePage({
    super.key,
    this.drawer,
    this.spendingChart,
    this.incomeExpenseChart,
  });

  /// The side panel opened from the app bar, if one was supplied.
  ///
  /// Passed in by `core/router/app_router.dart` rather than constructed here,
  /// because the panel FR-ACC-003 asks for belongs to the accounts feature and
  /// `features/home/` importing `features/accounts/` is what rule 4 of
  /// `scripts/check_architecture.sh` forbids. The router already names every
  /// feature's pages, so composing one more widget there is the shape the
  /// project already uses — the same reason `injection.dart` is the only file
  /// allowed to name a concrete `data/` class.
  ///
  /// Nullable so a widget test can build this screen without the accounts
  /// slice behind it.
  final Widget? drawer;

  /// FR-RPT-001's donut chart, composed in from `features/analytics/` the
  /// same way [drawer] is composed in from `features/accounts/`, and for the
  /// same architectural reason.
  ///
  /// Nullable for the same reason [drawer] is: a widget test can build this
  /// screen without the analytics slice behind it.
  final Widget? spendingChart;

  /// FR-RPT-004's income-vs-expense bars, composed in the same way
  /// [spendingChart] is. It reads the period and account filters that render
  /// on the donut's card, so it is placed directly below it.
  final Widget? incomeExpenseChart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(databaseSummaryProvider);

    return Scaffold(
      drawer: drawer,
      appBar: AppBar(
        title: const Text('Moneyora'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            // push, not go — see the note on the destination list below.
            onPressed: () => context.push(Routes.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: switch (summary) {
        AsyncData(:final value) => _Ready(
          summary: value,
          spendingChart: spendingChart,
          incomeExpenseChart: incomeExpenseChart,
        ),
        AsyncError(:final error) => _Failed(error: error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({
    required this.summary,
    required this.spendingChart,
    required this.incomeExpenseChart,
  });

  final DatabaseSummary summary;
  final Widget? spendingChart;
  final Widget? incomeExpenseChart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (spendingChart != null) ...[
          spendingChart!,
          const SizedBox(height: 16),
        ],
        if (incomeExpenseChart != null) ...[
          incomeExpenseChart!,
          const SizedBox(height: 16),
        ],
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle, color: colors.income),
                    const SizedBox(width: 8),
                    Text('Database ready', style: theme.textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                _Stat(
                  label: 'Schema version',
                  value: '${summary.schemaVersion}',
                ),
                _Stat(label: 'Accounts', value: '${summary.accounts}'),
                _Stat(label: 'Categories', value: '${summary.categories}'),
                _Stat(label: 'Transactions', value: '${summary.transactions}'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Coming next', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final (label, route) in const [
          ('Transactions', Routes.transactions),
          ('Categories', Routes.categories),
          ('Ask Moneyora', Routes.copilot),
          ('Money Plan', Routes.moneyPlan),
          ('Scan Receipt', Routes.scanReceipt),
        ])
          // `push`, not `go`. Every route here is top-level, and `go` replaces
          // the location rather than stacking on it — which leaves the screen
          // with nothing to pop, no back arrow, and a device back button that
          // exits the app instead of returning here.
          ListTile(
            title: Text(label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(route),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shown when the database cannot be opened.
///
/// The message is deliberately specific. The likely causes — a keychain entry
/// that disappeared, or a migration that failed — are indistinguishable from
/// "the app is broken" unless the screen says otherwise.
class _Failed extends StatelessWidget {
  const _Failed({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.expense, size: 48),
            const SizedBox(height: 16),
            Text(
              'Could not open the database',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
