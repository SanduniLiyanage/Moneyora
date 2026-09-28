import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection.dart';

/// The home screen. SCR-001.
///
/// Shortcuts to every part of the app first, then the five cards that say
/// where the money went, and an Add button for the thing done most often:
/// recording an expense.
///
/// It waits on the database summary before showing anything, so a database
/// that cannot be opened (a keychain entry gone, a migration failed) says so
/// here rather than leaving every card spinning. The summary's figures
/// themselves are in Settings › About: they help with a support question
/// and mean nothing to someone checking their spending.
class HomePage extends ConsumerWidget {
  /// Creates the home screen.
  const HomePage({
    super.key,
    this.drawer,
    this.spendingChart,
    this.balanceBar,
    this.incomeExpenseChart,
    this.summaryCard,
    this.spendingTrendChart,
    this.spendingHeatmap,
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

  /// Income less expenses for the period and account the donut card
  /// chose, composed in the same way (FR-RPT-006). Under that card, whose
  /// filters it follows, as the reference app keeps it under its chart.
  final Widget? balanceBar;

  /// FR-RPT-004's income-vs-expense bars, composed in the same way
  /// [spendingChart] is. It reads the period and account filters that render
  /// on the donut's card, so it is placed directly below it.
  final Widget? incomeExpenseChart;

  /// FR-RPT-006's headline figures, composed in the same way and placed
  /// below the bars, whose income, expenses and net savings it restates
  /// beside the three figures they cannot show.
  final Widget? summaryCard;

  /// FR-RPT-005's trend lines, composed in the same way and placed below the
  /// bars: third of the three charts that read the one filter row on the
  /// donut's card.
  final Widget? spendingTrendChart;

  /// FR-RPT-009's calendar heatmap, composed in the same way and placed
  /// below the lines: fourth and last of the Sprint 4 charts.
  final Widget? spendingHeatmap;

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
        AsyncData() => _Ready(
          spendingChart: spendingChart,
          balanceBar: balanceBar,
          incomeExpenseChart: incomeExpenseChart,
          summaryCard: summaryCard,
          spendingTrendChart: spendingTrendChart,
          spendingHeatmap: spendingHeatmap,
        ),
        AsyncError(:final error) => _Failed(error: error),
        _ => const Center(child: CircularProgressIndicator()),
      },
      floatingActionButton: switch (summary) {
        AsyncData() => FloatingActionButton.extended(
          onPressed: () => context.push(Routes.addTransaction),
          icon: const Icon(Icons.add),
          label: const Text('Add'),
        ),
        _ => null,
      },
    );
  }
}

class _Ready extends StatelessWidget {
  const _Ready({
    required this.spendingChart,
    required this.balanceBar,
    required this.incomeExpenseChart,
    required this.summaryCard,
    required this.spendingTrendChart,
    required this.spendingHeatmap,
  });

  final Widget? spendingChart;
  final Widget? balanceBar;
  final Widget? incomeExpenseChart;
  final Widget? summaryCard;
  final Widget? spendingTrendChart;
  final Widget? spendingHeatmap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // Room under the last card for the Add button.
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 88),
      children: [
        const _Shortcuts(),
        const SizedBox(height: 16),
        for (final card in [
          spendingChart,
          balanceBar,
          incomeExpenseChart,
          summaryCard,
          spendingTrendChart,
          spendingHeatmap,
        ])
          if (card != null) ...[card, const SizedBox(height: 16)],
      ],
    );
  }
}

/// Every part of the app, one tap from home, most used first.
///
/// `push`, not `go`. Every route here is top-level, and `go` replaces the
/// location rather than stacking on it — which leaves the screen with
/// nothing to pop, no back arrow, and a device back button that exits the
/// app instead of returning here.
class _Shortcuts extends StatelessWidget {
  const _Shortcuts();

  static const List<(String, IconData, String)> _destinations = [
    ('Transactions', Icons.receipt_long_outlined, Routes.transactions),
    ('Scan Receipt', Icons.document_scanner_outlined, Routes.scanReceipt),
    ('Your plan', Icons.savings_outlined, Routes.activePlan),
    ('Create Money Plan', Icons.edit_calendar_outlined, Routes.moneyPlan),
    ('Recurring', Icons.repeat, Routes.recurring),
    ('Categories', Icons.category_outlined, Routes.categories),
    ('Saved plans', Icons.folder_open_outlined, Routes.plans),
    ('Ask Moneyora', Icons.chat_bubble_outline, Routes.copilot),
  ];

  @override
  Widget build(BuildContext context) {
    // Two to a row, each as tall as the taller of the pair: at the largest
    // font a long label wraps to a second line instead of overflowing.
    return Column(
      children: [
        for (var i = 0; i < _destinations.length; i += 2)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: _Shortcut(_destinations[i])),
                  const SizedBox(width: 8),
                  Expanded(child: _Shortcut(_destinations[i + 1])),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut(this.destination);

  final (String, IconData, String) destination;

  @override
  Widget build(BuildContext context) {
    final (label, icon, route) = destination;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(route),
        // The icon above its label, not beside it: beside, a 320dp phone
        // left "Transactions" too little room and it broke mid-word.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge,
              ),
            ],
          ),
        ),
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
