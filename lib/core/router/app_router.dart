import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/accounts/domain/entities/account.dart';
import '../../features/accounts/presentation/pages/account_form_page.dart';
import '../../features/accounts/presentation/widgets/account_drawer.dart';
import '../../features/analytics/presentation/providers/analytics_providers.dart';
import '../../features/analytics/presentation/widgets/balance_bar.dart';
import '../../features/analytics/presentation/widgets/income_expense_bars.dart';
import '../../features/analytics/presentation/widgets/period_summary_card.dart';
import '../../features/analytics/presentation/widgets/spending_donut_chart.dart';
import '../../features/analytics/presentation/widgets/spending_heatmap.dart';
import '../../features/analytics/presentation/widgets/spending_trend_lines.dart';
import '../../features/auth/presentation/pages/passcode_flow_page.dart';
import '../../features/auth/presentation/widgets/security_settings_section.dart';
import '../../features/backup/presentation/widgets/backup_settings_section.dart';
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
import '../../features/money_plan/presentation/pages/plan_editor_page.dart';
import '../../features/money_plan/presentation/pages/plan_list_page.dart';
import '../../features/money_plan/presentation/pages/plan_review_page.dart';
import '../../features/receipt_scanner/domain/entities/scanned_receipt.dart';
import '../../features/receipt_scanner/presentation/pages/receipt_history_page.dart';
import '../../features/receipt_scanner/presentation/pages/receipt_review_page.dart';
import '../../features/receipt_scanner/presentation/pages/scan_receipt_page.dart';
import '../../features/settings/presentation/pages/exchange_rates_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';
import '../../features/transactions/presentation/pages/add_transaction_page.dart';
import '../../features/transactions/presentation/pages/recurring_rules_page.dart';
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

  /// SCR-002 and SCR-003 — recording an expense or income. The home
  /// screen's Add (SCR-001's FAB) opens it here; the list opens the same
  /// page directly. FR-EXP-001.
  static const String addTransaction = '/transactions/add';

  /// SCR-010 — the money plan wizard's first step. FR-PLN-001.
  static const String moneyPlan = '/plan';

  /// The generated draft, for review. FR-PLN-007 to FR-PLN-010.
  ///
  /// The `AllocationRequest` the wizard built travels as `extra`; reached
  /// without one — a deep link — it opens the first step instead, which is
  /// the only honest answer to "review what?".
  static const String moneyPlanReview = '/plan/review';

  /// A plan built by hand, or a generated one being edited before it is
  /// saved. E-39. The `PlanEditorArgs` travel as `extra`; reached without
  /// them, it opens the wizard, which is where a period is chosen.
  static const String planEditor = '/plan/edit';

  /// The active plan: adjust it, ask what-if, and (FR-PLN-013, later) watch
  /// spending against it. FR-PLN-011, FR-PLN-012.
  static const String activePlan = '/plan/active';

  /// Every saved plan: switch the active one, pick two to compare.
  /// FR-PLN-015; the SDD's SCR-010.
  static const String plans = '/plans';

  /// Every recurring rule, with pause, resume and delete. FR-EXP-008,
  /// FR-INC-004. No SDD screen places it (E-13's addendum).
  static const String recurring = '/recurring';

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

  /// SCR-015 — every receipt scanned so far, searchable. FR-RCP-013.
  static const String receiptHistory = '/scan/history';

  /// SCR-016 — settings.
  static const String settings = '/settings';

  /// The exchange-rate table, under settings. FR-SET-003, E-34.
  static const String exchangeRates = '/settings/rates';

  /// Setting, changing or removing the passcode, under settings.
  /// FR-SET-005.
  ///
  /// Which of the three travels as `extra`, a `PasscodeFlow`; reached
  /// without one — a deep link — it offers to set a passcode, and the use
  /// case refuses if one exists, which is the honest answer.
  static const String passcode = '/settings/passcode';

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
/// Every route here has a screen behind it. They were declared before their
/// screens existed, as placeholders, because the shape of the navigation
/// graph is a design decision worth settling before five features each invent
/// their own — and because a route that exists is a route a deep link can
/// already reach. The last placeholder went with Sprint 7's settings screen.
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
        balanceBar: BalanceBar(),
        incomeExpenseChart: IncomeExpenseBars(),
        summaryCard: PeriodSummaryCard(),
        spendingTrendChart: SpendingTrendLines(),
        spendingHeatmap: SpendingHeatmap(),
      ),
      // Every other screen sits under home, so the stack below any of them
      // is never empty. Reached with `go` — a saved receipt goes to the
      // list — a screen in a flat table was the only page left: no back
      // arrow, and a back swipe closed the app. Paths are unchanged.
      routes: <RouteBase>[
        GoRoute(
          path: _child(Routes.transactions),
          name: 'transactions',
          // The list follows the period and account the home screen's figures
          // are for, with their balance above it (FR-RPT-002, FR-RPT-003,
          // FR-RPT-006): composed here, as the charts are into home, because
          // the transactions feature may not import analytics.
          builder: (context, state) => Consumer(
            builder: (context, ref, _) {
              final query = ref.watch(analyticsQueryProvider);
              return TransactionListPage(
                from: query.range.from,
                to: query.range.to,
                accountId: query.accountId,
                header: const BalanceBar(),
              );
            },
          ),
        ),
        GoRoute(
          path: _child(Routes.addTransaction),
          name: 'addTransaction',
          builder: (context, state) => const AddTransactionPage(),
        ),
        GoRoute(
          path: _child(Routes.moneyPlan),
          name: 'moneyPlan',
          builder: (context, state) => const MoneyPlanPage(),
        ),
        GoRoute(
          path: _child(Routes.moneyPlanReview),
          name: 'moneyPlanReview',
          builder: (context, state) => switch (state.extra) {
            final AllocationRequest request => PlanReviewPage(request: request),
            _ => const MoneyPlanPage(),
          },
        ),
        GoRoute(
          path: _child(Routes.planEditor),
          name: 'planEditor',
          builder: (context, state) => switch (state.extra) {
            final PlanEditorArgs args => PlanEditorPage(args: args),
            _ => const MoneyPlanPage(),
          },
        ),
        GoRoute(
          path: _child(Routes.activePlan),
          name: 'activePlan',
          builder: (context, state) => const ActivePlanPage(),
        ),
        GoRoute(
          path: _child(Routes.plans),
          name: 'plans',
          builder: (context, state) => const PlanListPage(),
        ),
        GoRoute(
          path: _child(Routes.recurring),
          name: 'recurring',
          builder: (context, state) => const RecurringRulesPage(),
        ),
        GoRoute(
          path: _child(Routes.comparePlans),
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
          path: _child(Routes.scanReceipt),
          name: 'scanReceipt',
          builder: (context, state) => const ScanReceiptPage(),
        ),
        GoRoute(
          path: _child(Routes.scanReceiptReview),
          name: 'scanReceiptReview',
          builder: (context, state) => switch (state.extra) {
            final ScannedReceipt scanned => ReceiptReviewPage(scanned: scanned),
            _ => const ScanReceiptPage(),
          },
        ),
        GoRoute(
          path: _child(Routes.receiptHistory),
          name: 'receiptHistory',
          builder: (context, state) => const ReceiptHistoryPage(),
        ),
        GoRoute(
          path: _child(Routes.settings),
          name: 'settings',
          // The Security rows (FR-SET-005) are the auth feature's and the
          // backup rows (FR-SET-009) the backup feature's, composed in here for
          // the reason the home screen's panel is.
          builder: (context, state) => const SettingsPage(
            securitySection: SecuritySettingsSection(),
            backupSection: BackupSettingsSection(),
          ),
        ),
        GoRoute(
          path: _child(Routes.exchangeRates),
          name: 'exchangeRates',
          builder: (context, state) => const ExchangeRatesPage(),
        ),
        GoRoute(
          path: _child(Routes.passcode),
          name: 'passcode',
          builder: (context, state) => PasscodeFlowPage(
            flow: switch (state.extra) {
              final PasscodeFlow flow => flow,
              _ => PasscodeFlow.set,
            },
          ),
        ),
        // One route, and nothing else in the app reaches into the feature. Taking
        // the Copilot out again is deleting this entry (NFR-REL-004).
        GoRoute(
          path: _child(Routes.copilot),
          name: 'copilot',
          builder: (context, state) => const CopilotPage(),
        ),
        GoRoute(
          path: _child(Routes.transfer),
          name: 'transfer',
          builder: (context, state) => const TransferPage(),
        ),
        GoRoute(
          path: _child(Routes.accountForm),
          name: 'accountForm',
          // `extra` is untyped by go_router, so the cast is checked rather than
          // assumed: anything that is not an Account — including the null a deep
          // link brings — opens the form empty rather than crashing.
          builder: (context, state) => AccountFormPage(
            initial: state.extra is Account ? state.extra! as Account : null,
          ),
        ),
        GoRoute(
          path: _child(Routes.categories),
          name: 'categories',
          builder: (context, state) => const CategoryListPage(),
        ),
        GoRoute(
          path: _child(Routes.categoryForm),
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
    ),
  ],
  errorBuilder: (context, state) => _RouteNotFound(location: state.uri.path),
);

/// [path] as a route under home: `/plan` is `plan` there.
String _child(String path) => path.substring(1);

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
