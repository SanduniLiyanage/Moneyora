import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/domain/entities/account.dart';
import '../../features/accounts/presentation/pages/account_form_page.dart';
import '../../features/accounts/presentation/widgets/account_drawer.dart';
import '../../features/analytics/presentation/widgets/income_expense_bars.dart';
import '../../features/analytics/presentation/widgets/spending_donut_chart.dart';
import '../../features/analytics/presentation/widgets/spending_heatmap.dart';
import '../../features/analytics/presentation/widgets/spending_trend_lines.dart';
import '../../features/categories/domain/entities/category.dart';
import '../../features/categories/presentation/pages/category_form_page.dart';
import '../../features/categories/presentation/pages/category_list_page.dart';
import '../../features/copilot/presentation/pages/copilot_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/money_plan/domain/entities/allocation_request.dart';
import '../../features/money_plan/domain/usecases/compare_plans.dart';
import '../../features/money_plan/presentation/pages/active_plan_page.dart';
import '../../features/money_plan/presentation/pages/compare_plans_page.dart';
import '../../features/money_plan/presentation/pages/money_plan_page.dart';
import '../../features/money_plan/presentation/pages/plan_list_page.dart';
import '../../features/money_plan/presentation/pages/plan_review_page.dart';
import '../../features/receipt_scanner/domain/entities/scanned_receipt.dart';
import '../../features/receipt_scanner/presentation/pages/receipt_review_page.dart';
import '../../features/transactions/presentation/pages/transaction_list_page.dart';
import '../../features/transactions/presentation/pages/transfer_page.dart';

/// Route paths, as constants rather than string literals scattered about.
///
/// A typo in `context.go('/setings')` is a runtime no-op that fails silently;
/// a typo in `Routes.setings` does not compile.
abstract final class Routes {
  /// SCR-001 — home.
  static const String home = '/';

  /// SCR-005 — transaction list.
  static const String transactions = '/transactions';

  /// SCR-010 — the money plan wizard's first step. FR-PLN-001.
  static const String moneyPlan = '/plan';

  /// The generated draft, for review. FR-PLN-007 to FR-PLN-010.
  ///
  /// The `AllocationRequest` the wizard built travels as `extra`; reached
  /// without one — a deep link — it opens the first step instead, which is
  /// the only honest answer to "review what?".
  static const String moneyPlanReview = '/plan/review';

  /// The active plan: adjust it, ask what-if, and (FR-PLN-013, later) watch
  /// spending against it. FR-PLN-011, FR-PLN-012.
  static const String activePlan = '/plan/active';

  /// Every saved plan: switch the active one, pick two to compare.
  /// FR-PLN-015; the SDD's SCR-010.
  static const String plans = '/plans';

  /// Two plans side by side, named by `?a=` and `?b=`. FR-PLN-015.
  static const String comparePlans = '/plans/compare';

  /// SCR-013 — receipt scanner.
  static const String scanReceipt = '/scan';

  /// SCR-014 — the scan, reviewed and confirmed. FR-RCP-008, FR-RCP-009.
  ///
  /// The `ScannedReceipt` the pipeline produced travels as `extra`, the
  /// way the plan review takes its request; reached without one — a deep
  /// link — it opens the scanner instead, which is the only honest answer
  /// to "review what?".
  static const String scanReceiptReview = '/scan/review';

  /// SCR-016 — settings.
  static const String settings = '/settings';

  /// The AI Copilot. Not in the SDD's screen inventory — it is a later
  /// addition, specified in `SRS_Copilot.md` §5.1.
  static const String copilot = '/copilot';

  /// Moving money between two accounts. FR-TRF-001 to FR-TRF-003.
  static const String transfer = '/transfer';

  /// Creating or editing one account. FR-ACC-001, FR-ACC-002.
  ///
  /// One path for both, with the account to edit passed as `extra`. A path
  /// parameter would read better, but nothing can yet load an account by id —
  /// there is no use case for it — so `/accounts/form/7` would be a URL the
  /// app could not honour. Reached with no `extra`, it creates a new account,
  /// which is the right answer for a deep link.
  static const String accountForm = '/accounts/form';

  /// Managing categories. FR-EXP-004, FR-EXP-005.
  static const String categories = '/categories';

  /// Creating or editing one category, the same shape as [accountForm]: one
  /// path for both, with the category to edit passed as `extra`.
  static const String categoryForm = '/categories/form';
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
      // The accounts panel (FR-ACC-003), the donut chart (FR-RPT-001), the
      // income-vs-expense bars (FR-RPT-004), the trend lines (FR-RPT-005)
      // and the heatmap (FR-RPT-009) are composed in here rather than imported by the home screen, which
      // would be one feature importing another. This file already names
      // every feature's pages, so it is where the app is assembled.
      builder: (context, state) => const HomePage(
        drawer: AccountDrawer(),
        spendingChart: SpendingDonutChart(),
        incomeExpenseChart: IncomeExpenseBars(),
        spendingTrendChart: SpendingTrendLines(),
        spendingHeatmap: SpendingHeatmap(),
      ),
    ),
    GoRoute(
      path: Routes.transactions,
      name: 'transactions',
      builder: (context, state) => const TransactionListPage(),
    ),
    GoRoute(
      path: Routes.moneyPlan,
      name: 'moneyPlan',
      builder: (context, state) => const MoneyPlanPage(),
    ),
    GoRoute(
      path: Routes.moneyPlanReview,
      name: 'moneyPlanReview',
      builder: (context, state) => switch (state.extra) {
        final AllocationRequest request => PlanReviewPage(request: request),
        _ => const MoneyPlanPage(),
      },
    ),
    GoRoute(
      path: Routes.activePlan,
      name: 'activePlan',
      builder: (context, state) => const ActivePlanPage(),
    ),
    GoRoute(
      path: Routes.plans,
      name: 'plans',
      builder: (context, state) => const PlanListPage(),
    ),
    GoRoute(
      path: Routes.comparePlans,
      name: 'comparePlans',
      // Both ids come from the query so the screen is a plain link. One
      // that is missing or not a number opens the list rather than
      // crashing — the same rule the form routes apply to `extra`.
      builder: (context, state) => switch ((
        int.tryParse(state.uri.queryParameters['a'] ?? ''),
        int.tryParse(state.uri.queryParameters['b'] ?? ''),
      )) {
        (final int a, final int b) => ComparePlansPage(
          request: ComparePlansRequest(leftId: a, rightId: b),
        ),
        _ => const PlanListPage(),
      },
    ),
    GoRoute(
      path: Routes.scanReceipt,
      name: 'scanReceipt',
      builder: (context, state) =>
          const _PlannedScreen(title: 'Scan Receipt', sprint: 'Sprint 6'),
    ),
    GoRoute(
      path: Routes.scanReceiptReview,
      name: 'scanReceiptReview',
      builder: (context, state) => switch (state.extra) {
        final ScannedReceipt scanned => ReceiptReviewPage(scanned: scanned),
        _ => const _PlannedScreen(title: 'Scan Receipt', sprint: 'Sprint 6'),
      },
    ),
    GoRoute(
      path: Routes.settings,
      name: 'settings',
      builder: (context, state) =>
          const _PlannedScreen(title: 'Settings', sprint: 'Sprint 7'),
    ),
    // One route, and nothing else in the app reaches into the feature. Taking
    // the Copilot out again is deleting this entry (NFR-REL-004).
    GoRoute(
      path: Routes.copilot,
      name: 'copilot',
      builder: (context, state) => const CopilotPage(),
    ),
    GoRoute(
      path: Routes.transfer,
      name: 'transfer',
      builder: (context, state) => const TransferPage(),
    ),
    GoRoute(
      path: Routes.accountForm,
      name: 'accountForm',
      // `extra` is untyped by go_router, so the cast is checked rather than
      // assumed: anything that is not an Account — including the null a deep
      // link brings — opens the form empty rather than crashing.
      builder: (context, state) => AccountFormPage(
        initial: state.extra is Account ? state.extra! as Account : null,
      ),
    ),
    GoRoute(
      path: Routes.categories,
      name: 'categories',
      builder: (context, state) => const CategoryListPage(),
    ),
    GoRoute(
      path: Routes.categoryForm,
      name: 'categoryForm',
      // `extra` carries either the `Category` being edited, or the
      // `CategoryType` a new one should start as — the list page's two tabs
      // hand back whichever the user was looking at. Anything else,
      // including the null a deep link brings, opens a new expense category.
      builder: (context, state) => switch (state.extra) {
        final Category category => CategoryFormPage(initial: category),
        final CategoryType type => CategoryFormPage(initialType: type),
        _ => const CategoryFormPage(),
      },
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
