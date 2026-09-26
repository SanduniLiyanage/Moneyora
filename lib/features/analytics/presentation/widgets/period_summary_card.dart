/// The headline figures for the selected period. FR-RPT-006.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/period_selection.dart';
import '../../domain/entities/period_summary.dart';
import '../providers/analytics_providers.dart';
import 'period_selector.dart';

/// Total income, total expenses, net savings, average daily spend, the
/// largest category and the change against the period before, in one card.
///
/// Reads the filters that render on the donut's card, like every chart below
/// it, so the figures always describe the period on screen.
class PeriodSummaryCard extends ConsumerWidget {
  /// Creates the card.
  const PeriodSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(analyticsPeriodProvider);
    final range = ref.watch(analyticsRangeProvider);
    final summary = ref.watch(periodSummaryProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Summary', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              periodLabel(selection, range),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 12),
            switch (summary) {
              AsyncData(:final value) => _Figures(
                summary: value,
                before: _previousLabel(selection.period),
              ),
              AsyncError(:final error) => Text(
                error is Failure
                    ? error.message
                    : 'The summary could not be worked out.',
              ),
              _ => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }

  static String _previousLabel(AnalyticsPeriod period) => switch (period) {
    AnalyticsPeriod.day => 'yesterday',
    AnalyticsPeriod.week => 'last week',
    AnalyticsPeriod.month => 'last month',
    AnalyticsPeriod.year => 'last year',
    AnalyticsPeriod.custom => 'the period before',
    AnalyticsPeriod.all => '',
  };
}

class _Figures extends StatelessWidget {
  const _Figures({required this.summary, required this.before});

  final PeriodSummary summary;
  final String before;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<AppColors>()!;
    final net = summary.netSavingsCents;
    final average = summary.averageDailySpendCents;
    final largest = summary.largestCategory;
    final change = summary.expenseChangePercent;

    final figures = <_Figure>[
      _Figure('Income', formatCents(summary.incomeCents), colors.income),
      _Figure('Expenses', formatCents(summary.expenseCents), colors.expense),
      _Figure(
        'Net savings',
        formatCents(net),
        net < 0 ? colors.expense : colors.income,
      ),
      _Figure(
        'Average a day',
        average == null ? '—' : formatCents(average),
        null,
      ),
      _Figure(
        'Largest category',
        largest == null
            ? '—'
            : '${largest.name} · ${formatCents(largest.amountCents)}',
        null,
      ),
      _Figure(
        before.isEmpty ? 'Change' : 'Spending vs $before',
        switch (change) {
          null when summary.previousExpenseCents == null => '—',
          null => 'Nothing spent $before',
          0 => 'The same',
          final c when c > 0 => '+$c%',
          final c => '$c%',
        },
        switch (change) {
          final c? when c > 0 => colors.expense,
          final c? when c < 0 => colors.income,
          _ => null,
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final figure in figures) SizedBox(width: width, child: figure),
          ],
        );
      },
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure(this.label, this.value, this.color);

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
