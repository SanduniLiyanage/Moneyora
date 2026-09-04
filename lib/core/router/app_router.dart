import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/home/presentation/pages/home_page.dart';
import '../../features/transactions/presentation/pages/transaction_list_page.dart';

/// Route paths, as constants rather than string literals scattered about.
///
/// A typo in `context.go('/setings')` is a runtime no-op that fails silently;
/// a typo in `Routes.setings` does not compile.
abstract final class Routes {
  /// SCR-001 — home.
  static const String home = '/';

  /// SCR-005 — transaction list.
  static const String transactions = '/transactions';

  /// SCR-010 — money plan.
  static const String moneyPlan = '/plan';

  /// SCR-013 — receipt scanner.
  static const String scanReceipt = '/scan';

  /// SCR-016 — settings.
  static const String settings = '/settings';
}

/// The app's routing table. SDD §4.3 specifies `go_router`.
///
/// Home and transactions have real screens. The rest are declared now, as
/// placeholders, because the shape of the navigation graph is a design
/// decision worth settling before five features each invent their own — and
/// because a route that exists is a route a deep link can already reach.
GoRouter buildRouter() => GoRouter(
  initialLocation: Routes.home,
  routes: <RouteBase>[
    GoRoute(
      path: Routes.home,
      name: 'home',
      builder: (context, state) => const HomePage(),
    ),
    GoRoute(
      path: Routes.transactions,
      name: 'transactions',
      builder: (context, state) => const TransactionListPage(),
    ),
    GoRoute(
      path: Routes.moneyPlan,
      name: 'moneyPlan',
      builder: (context, state) =>
          const _PlannedScreen(title: 'Money Plan', sprint: 'Sprint 5'),
    ),
    GoRoute(
      path: Routes.scanReceipt,
      name: 'scanReceipt',
      builder: (context, state) =>
          const _PlannedScreen(title: 'Scan Receipt', sprint: 'Sprint 6'),
    ),
    GoRoute(
      path: Routes.settings,
      name: 'settings',
      builder: (context, state) =>
          const _PlannedScreen(title: 'Settings', sprint: 'Sprint 7'),
    ),
  ],
  errorBuilder: (context, state) => _RouteNotFound(location: state.uri.path),
);

/// Placeholder for a route whose screen is not built yet.
///
/// Deliberately states which sprint owns it, so an unfinished screen reads as
/// planned work rather than as something broken.
class _PlannedScreen extends StatelessWidget {
  const _PlannedScreen({required this.title, required this.sprint});

  final String title;
  final String sprint;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Arrives in $sprint.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown for a path with no route.
///
/// go_router's default is a bare error page; this one names the path, which is
/// the single most useful thing when a deep link or a typo goes astray.
class _RouteNotFound extends StatelessWidget {
  const _RouteNotFound({required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Not found')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'No screen at $location',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go(Routes.home),
                child: const Text('Go home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
