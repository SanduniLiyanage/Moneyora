import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection.dart';
import '../widgets/main_menu.dart';

/// The home screen. SCR-001.
///
/// The cards that say where the money went, an Add button for the thing done
/// most often, and a panel on each side, as in the reference app the owner
/// uses: on the left which account and which days, on the right every other
/// screen.
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
    this.filterPanel,
    this.accounts,
    this.spendingChart,
    this.balanceBar,
    this.incomeExpenseChart,
    this.summaryCard,
    this.spendingTrendChart,
    this.spendingHeatmap,
  });

  /// The left panel, opened from the filter icon: the period and account
  /// every figure on home is for (FR-RPT-002, FR-RPT-003).
  ///
  /// Passed in by `core/router/app_router.dart` rather than constructed here,
  /// because the panel belongs to the analytics feature and `features/home/`
  /// importing `features/analytics/` is what rule 4 of
  /// `scripts/check_architecture.sh` forbids. The router already names every
  /// feature's pages, so composing one more widget there is the shape the
  /// project already uses — the same reason `injection.dart` is the only file
  /// allowed to name a concrete `data/` class.
  ///
  /// Nullable so a widget test can build this screen without the analytics
  /// slice behind it.
  final Widget? filterPanel;

  /// The accounts and their balances (FR-ACC-003), opened in place under the
  /// right panel's Accounts item. Composed in from `features/accounts/` the
  /// same way [filterPanel] is, and for the same reason.
  final Widget? accounts;

  /// FR-RPT-001's donut chart, composed in from `features/analytics/` the
  /// same way [filterPanel] is, and for the same architectural reason.
  ///
  /// Nullable for the same reason [filterPanel] is: a widget test can build
  /// this screen without the analytics slice behind it.
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
      drawer: filterPanel,
      endDrawer: MainMenu(accounts: accounts),
      appBar: AppBar(
        // Supplied rather than left to the defaults, which would draw the
        // same three-line icon on both sides for two different panels.
        leading: filterPanel == null
            ? null
            : Builder(
                builder: (context) => IconButton(
                  icon: const Icon(Icons.filter_list),
                  tooltip: 'Period and account',
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              ),
        automaticallyImplyLeading: false,
        title: const Text('Moneyora'),
        actions: [
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            // push, not go, so the screen stacks on home and its back arrow
            // returns here.
            onPressed: () => context.push(Routes.transfer),
            tooltip: 'Transfer',
          ),
          Builder(
            builder: (context) => IconButton(
              icon: const Icon(Icons.more_vert),
              tooltip: 'Menu',
              onPressed: () => Scaffold.of(context).openEndDrawer(),
            ),
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
