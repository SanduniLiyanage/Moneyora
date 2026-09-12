/// The income-vs-expense comparison, with net savings highlighted.
/// FR-RPT-004.
///
/// Reads the same [analyticsQueryProvider] the donut chart does, so
/// FR-RPT-002's period and FR-RPT-003's account move both charts at once and
/// neither can be left reporting the period the user just changed away from.
/// The filters render once, on the donut's card above; a second copy of them
/// here would be two controls for one piece of state.
///
/// ## The colour question `SPEC_ERRATA.md` left open
///
/// The errata's colour-collision check flagged that `default_seed.dart` pairs
/// each income category with an expense category sharing its exact colour —
/// Bills/Deposits, Entertainment/Salary, Gifts/Savings — and left it "for
/// whoever builds Sprint 4's charts to verify against the actual chart set
/// being built". FR-RPT-001's donut could skip it by showing expenses only.
/// **This chart cannot collide either**, for a different reason: it draws two
/// *totals*, not a category breakdown, so no category colour renders on it at
/// all. Its two bars use `AppColors.income` and `AppColors.expense`, the fixed
/// semantic pair, whose contrast `app_colors_test.dart` already measures.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/category_total.dart';
import '../providers/analytics_providers.dart';
import 'period_selector.dart';

/// One height for every state, so the card does not jump as data resolves —
/// the same rule `SpendingDonutChart` follows.
const double _chartHeight = 160;

/// Income against expenses over the selected period and account, with net
/// savings called out. FR-RPT-004.
class IncomeExpenseBars extends ConsumerWidget {
  /// Creates the chart.
  const IncomeExpenseBars({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(analyticsPeriodProvider);
    final query = ref.watch(analyticsQueryProvider);
    final income = ref.watch(incomeTotalProvider(query));
    final spending = ref.watch(spendingByCategoryTotalsProvider(query));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Income vs expenses', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              periodLabel(selection),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            switch ((income, spending)) {
              (AsyncError(:final error), _) => _Problem(error: error),
              (_, AsyncError(:final error)) => _Problem(error: error),
              (
                AsyncData(value: final incomeCents),
                AsyncData(value: final totals),
              ) =>
                _Comparison(
                  incomeCents: incomeCents,
                  // The expense total is the spending query's own rows added
                  // up, not a third aggregate: the donut above already asks
                  // for them, the provider is keyed identically, so this
                  // reads a cached answer rather than running new SQL.
                  expenseCents: _sum(totals),
                ),
              _ => const SizedBox(
                height: _chartHeight,
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }

  static int _sum(List<CategoryTotal> totals) =>
      totals.fold(0, (sum, total) => sum + total.amountCents);
}

class _Comparison extends StatelessWidget {
  const _Comparison({required this.incomeCents, required this.expenseCents});

  final int incomeCents;
  final int expenseCents;

  @override
  Widget build(BuildContext context) {
    if (incomeCents == 0 && expenseCents == 0) return const _NoActivity();

    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;

    return Column(
      children: [
        SizedBox(
          height: _chartHeight,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceEvenly,
              // Headroom so the value label above the taller bar has somewhere
              // to sit rather than being clipped by the chart's own ceiling.
              maxY: _axisCeiling(),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barTouchData: const BarTouchData(enabled: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, _) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        value == 0 ? 'Income' : 'Expenses',
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ),
                ),
              ),
              barGroups: [
                _bar(0, incomeCents, colors.income),
                _bar(1, expenseCents, colors.expense),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _NetSavings(netCents: incomeCents - expenseCents),
      ],
    );
  }

  /// A little above the taller bar, and never zero — a `maxY` of 0 makes
  /// `fl_chart` draw nothing at all rather than two flat bars.
  double _axisCeiling() {
    final tallest = incomeCents > expenseCents ? incomeCents : expenseCents;
    return tallest == 0 ? 1 : tallest * 1.25;
  }

  BarChartGroupData _bar(int x, int cents, Color color) => BarChartGroupData(
    x: x,
    barRods: [
      BarChartRodData(
        toY: cents.toDouble(),
        color: color,
        width: 44,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
      ),
    ],
  );
}

/// FR-RPT-004's "net savings highlighted" — the one number a person actually
/// wants from this chart, so it is stated in words rather than left to be
/// eyeballed as the gap between two bars.
class _NetSavings extends StatelessWidget {
  const _NetSavings({required this.netCents});

  final int netCents;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    // Overspending is not "negative savings" in anyone's head; it is its own
    // word, and saying it plainly is the difference between a chart that
    // informs and one that has to be decoded.
    final overspent = netCents < 0;
    final color = overspent ? colors.expense : colors.income;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            overspent ? 'Overspent' : 'Net savings',
            style: theme.textTheme.bodyMedium,
          ),
          Text(
            formatCents(overspent ? -netCents : netCents),
            style: theme.textTheme.titleMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Nothing moved either way in this period. E-22 wants a sentence, not an
/// empty frame — and unlike the donut's two cases, there is only one to say
/// here: a chart of two totals that are both zero says the same thing to a
/// new user and to one who picked a quiet week.
class _NoActivity extends StatelessWidget {
  const _NoActivity();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _chartHeight,
      child: Center(
        child: Text(
          'No income or spending in this period.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _chartHeight,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 8),
              Text(
                // A Failure carries its own message so the UI never has to
                // invent one; anything else here is a bug, not something to
                // explain to the user.
                switch (error) {
                  final Failure failure => failure.message,
                  _ => 'Could not load your income and spending.',
                },
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
