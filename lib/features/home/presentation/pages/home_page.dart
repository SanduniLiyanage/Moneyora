import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/database/database_summary.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection.dart';

/// Sprint 1's home screen.
///
/// Not SCR-001 — the donut chart, balance bar and category ring arrive in
/// Sprint 4. What this screen does is prove the foundation works **on a real
/// device**, which no unit test can: the SQLCipher file opened with a key from
/// the platform keychain, the migration ran, and the default categories seeded.
///
/// Those three things pass in tests against an in-memory database on a laptop.
/// Whether they work on an Android phone is a different question, and this
/// screen is how it gets answered.
class HomePage extends ConsumerWidget {
  /// Creates the home screen.
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(databaseSummaryProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moneyora'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go(Routes.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: switch (summary) {
        AsyncData(:final value) => _Ready(summary: value),
        AsyncError(:final error) => _Failed(error: error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({required this.summary});

  final DatabaseSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
          ('Money Plan', Routes.moneyPlan),
          ('Scan Receipt', Routes.scanReceipt),
        ])
          ListTile(
            title: Text(label),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.go(route),
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
