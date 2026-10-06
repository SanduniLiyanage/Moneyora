import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../injection.dart';
import '../widgets/main_menu.dart';

/// The home screen. SCR-001.
///
/// The reference app the owner uses, in Moneyora's colours: a ring of where
/// the money went, the balance under it, − and + for the two things done
/// most often, and a panel on each side — on the left which account and
/// which days, on the right every other screen. The other charts are under
/// Reports in that menu.
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

  /// FR-RPT-001's spending ring, composed in from `features/analytics/` the
  /// same way [filterPanel] is, and for the same architectural reason.
  ///
  /// Nullable for the same reason [filterPanel] is: a widget test can build
  /// this screen without the analytics slice behind it.
  final Widget? spendingChart;

  /// Income less expenses for the period and account the ring shows,
  /// composed in the same way (FR-RPT-006). Under the ring, as the reference
  /// app keeps its Balance; a tap opens the transactions behind it.
  final Widget? balanceBar;

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
        ),
        AsyncError(:final error) => _Failed(error: error),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// The ring, the balance under it, and − and + at the bottom: the reference
/// app's home, where the two things done most often are the two biggest
/// buttons on the screen.
class _Ready extends StatelessWidget {
  const _Ready({required this.spendingChart, required this.balanceBar});

  final Widget? spendingChart;
  final Widget? balanceBar;

  /// The least the ring can be drawn in and still say anything.
  static const double _ringFloor = 280;

  @override
  Widget build(BuildContext context) {
    final chart = spendingChart;
    final balance = balanceBar;
    final below = [
      if (balance != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: balance,
        ),
      const _EntryButtons(),
    ];

    return SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A short screen, or the largest font, leaves the ring too little
          // room beside everything under it. Then it keeps its floor and the
          // screen scrolls, rather than drawing a ring the size of a coin.
          // What is under it grows with the text; the ring does not.
          final textScale = MediaQuery.textScalerOf(context).scale(1);
          final roomy = constraints.maxHeight >= _ringFloor + 230 * textScale;
          if (roomy) {
            return Column(
              children: [
                if (chart != null) Expanded(child: chart) else const Spacer(),
                ...below,
              ],
            );
          }
          return ListView(
            children: [
              if (chart != null) SizedBox(height: _ringFloor, child: chart),
              ...below,
            ],
          );
        },
      ),
    );
  }
}

/// − for an expense, + for income. FR-EXP-001, FR-INC-001.
class _EntryButtons extends StatelessWidget {
  const _EntryButtons();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;

    Widget button({
      required IconData icon,
      required String tooltip,
      required Color color,
      required String route,
    }) => IconButton.filled(
      icon: Icon(icon, size: 40),
      tooltip: tooltip,
      // push, so the entry screen stacks on home and saving returns here.
      onPressed: () => context.push(route),
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        fixedSize: const Size.square(72),
      ),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          button(
            icon: Icons.remove,
            tooltip: 'New expense',
            color: colors.expense,
            route: Routes.addTransaction,
          ),
          button(
            icon: Icons.add,
            tooltip: 'New income',
            color: colors.income,
            route: Routes.addIncome,
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
