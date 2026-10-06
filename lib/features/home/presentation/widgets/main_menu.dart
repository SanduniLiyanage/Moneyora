import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/widgets/side_panel.dart';

/// The right panel of home: every part of the app, Settings last.
///
/// Opened from ⋮ at the top right, the way the reference app keeps its
/// screens out of the way of its chart. It replaced the grid of tiles at the
/// top of home on 2026-10-06, at the owner's request.
class MainMenu extends StatelessWidget {
  /// Creates the menu, with [accounts] under its Accounts item.
  const MainMenu({super.key, this.accounts});

  /// What the Accounts item opens in place. FR-ACC-003.
  ///
  /// Passed in by `core/router/app_router.dart` for the reason `HomePage`'s
  /// composed widgets are: it belongs to the accounts feature. Nullable so a
  /// widget test can build the menu without that slice behind it.
  final Widget? accounts;

  static const List<(String, IconData, String)> _screens = [
    ('Transactions', Icons.receipt_long_outlined, Routes.transactions),
    ('Scan receipt', Icons.document_scanner_outlined, Routes.scanReceipt),
    ('Transfer', Icons.swap_horiz, Routes.transfer),
    ('Budget plans', Icons.savings_outlined, Routes.plans),
    ('Recurring', Icons.repeat, Routes.recurring),
    ('Categories', Icons.category_outlined, Routes.categories),
  ];

  @override
  Widget build(BuildContext context) {
    final accounts = this.accounts;

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            for (final screen in _screens) _Destination(screen),
            if (accounts != null)
              ExpansionTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: const Text('Accounts'),
                // No lines above and below when it opens: the rows inside
                // read as the menu's own.
                shape: const Border(),
                collapsedShape: const Border(),
                children: [accounts],
              ),
            const _Destination((
              'Ask Moneyora',
              Icons.chat_bubble_outline,
              Routes.copilot,
            )),
            const Divider(),
            const _Destination((
              'Settings',
              Icons.settings_outlined,
              Routes.settings,
            )),
          ],
        ),
      ),
    );
  }
}

class _Destination extends StatelessWidget {
  const _Destination(this.destination);

  final (String, IconData, String) destination;

  @override
  Widget build(BuildContext context) {
    final (label, icon, route) = destination;
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () {
        // Closed first, and pushed rather than gone to, so the screen
        // stacks on home and its back arrow returns there with the menu
        // shut.
        final router = GoRouter.of(context);
        closeSidePanel(context);
        router.push(route);
      },
    );
  }
}
