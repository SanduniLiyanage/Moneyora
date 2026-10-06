import 'package:flutter/material.dart';

import '../widgets/balance_bar.dart';
import '../widgets/income_expense_bars.dart';
import '../widgets/period_stepper.dart';
import '../widgets/period_summary_card.dart';
import '../widgets/spending_donut_chart.dart';
import '../widgets/spending_heatmap.dart';
import '../widgets/spending_trend_lines.dart';

/// Every chart, for the period and account home shows.
/// FR-RPT-001, FR-RPT-004, FR-RPT-005, FR-RPT-006, FR-RPT-009.
///
/// Home became one screen — the ring, the balance, − and + — on
/// 2026-10-06. The cards that were under its ring moved here, in the order
/// they had, so none was lost: the amounts by category, income
/// against spending, the summary, the lines over time and the calendar.
class ReportsPage extends StatelessWidget {
  /// Creates the screen.
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reports')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          // The arrows rather than a swipe here: the charts take touches of
          // their own, and a swipe that moved the period while reading a bar
          // would lose the reader's place.
          const PeriodStepper(),
          const SizedBox(height: 8),
          for (final card in const [
            BalanceBar(),
            SpendingDonutChart(),
            IncomeExpenseBars(),
            PeriodSummaryCard(),
            SpendingTrendLines(),
            SpendingHeatmap(),
          ]) ...[card, const SizedBox(height: 16)],
        ],
      ),
    );
  }
}
