/// The home screen's spending-by-category donut chart. FR-RPT-001.
///
/// SDD SCR-001 draws this on the home screen, not a separate report screen,
/// so it is composed there the way `AccountDrawer` is — passed in from
/// `core/router/app_router.dart`, which already names every feature's pages,
/// rather than `features/home/` importing `features/analytics/`
/// (`check_architecture.sh` rule 4).
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../core/theme/category_palette.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/category_icons.dart';
import '../../../../injection.dart';
import '../../domain/entities/category_total.dart';
import '../providers/analytics_providers.dart';
import 'account_filter.dart';
import 'period_selector.dart';

/// A fixed height for every state (loading, empty, error, drawn), so the
/// card does not jump as data resolves — the "skeleton flash" anti-pattern
/// in reverse.
const double _chartHeight = 180;

/// Beyond this many categories, the tail folds into one "Other" slice.
///
/// A pie/donut chart earns its "part-to-whole at a glance" promise only up
/// to about six or seven wedges — past that, adjacent slices blur into each
/// other regardless of colour. [GetSpendingByCategory] already orders by
/// amount, so "the rest" is always the smallest contributors, which is what
/// a reader expects "Other" to mean. This is also the presentation-side
/// answer to NFR-PER-005/E-10's "tested to 50, never refuses the 51st": the
/// chart itself never draws more than [_maxSlices] wedges no matter how many
/// categories exist.
const int _maxSlices = 6;

/// Spending by category, over the selected period and account.
/// FR-RPT-001, FR-RPT-002, FR-RPT-003.
class SpendingDonutChart extends ConsumerWidget {
  /// Creates the chart.
  const SpendingDonutChart({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(analyticsPeriodProvider);
    final query = ref.watch(spendingQueryProvider);
    final totals = ref.watch(spendingByCategoryTotalsProvider(query));
    final categories = ref.watch(categoryOptionsProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending by category', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              periodLabel(selection),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            const PeriodSelector(),
            const AccountFilter(),
            const SizedBox(height: 8),
            switch ((totals, categories)) {
              (AsyncError(:final error), _) => _Problem(error: error),
              (_, AsyncError(:final error)) => _Problem(error: error),
              (
                AsyncData(value: final totalsValue),
                AsyncData(value: final categoriesValue),
              ) =>
                _Chart(totals: totalsValue, categories: categoriesValue),
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
}

/// One wedge, after [CategoryTotal] and [CategoryOption] are joined and the
/// tail past [_maxSlices] is folded down.
class _Slice {
  const _Slice({
    required this.name,
    required this.icon,
    required this.color,
    required this.amountCents,
  });

  final String name;

  /// Null for the folded "Other" wedge — it names no single category, so it
  /// draws no icon rather than borrowing one that would mislead.
  final IconData? icon;
  final Color color;
  final int amountCents;
}

class _Chart extends StatelessWidget {
  const _Chart({required this.totals, required this.categories});

  final List<CategoryTotal> totals;
  final List<CategoryOption> categories;

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const _NoSpending();

    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final iconByCategory = {for (final c in categories) c.id: c.icon};

    final slices = <_Slice>[
      for (final total in totals.take(_maxSlices))
        _Slice(
          name: total.name,
          icon: categoryIconFor(iconByCategory[total.categoryId] ?? ''),
          color: categoryColorFor(total.color, brightness),
          amountCents: total.amountCents,
        ),
    ];

    if (totals.length > _maxSlices) {
      final rest = totals.skip(_maxSlices);
      slices.add(
        _Slice(
          name: 'Other',
          icon: null,
          color: theme.colorScheme.outline,
          amountCents: rest.fold(0, (sum, t) => sum + t.amountCents),
        ),
      );
    }

    final totalCents = slices.fold(0, (sum, s) => sum + s.amountCents);

    return Column(
      children: [
        SizedBox(
          height: _chartHeight,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 36,
              sections: [
                for (final slice in slices)
                  PieChartSectionData(
                    value: slice.amountCents.toDouble(),
                    color: slice.color,
                    radius: 52,
                    title: _percentLabel(slice.amountCents, totalCents),
                    titleStyle: theme.textTheme.labelSmall?.copyWith(
                      color: _onColor(slice.color),
                      fontWeight: FontWeight.w600,
                    ),
                    badgeWidget: slice.icon == null
                        ? null
                        : Icon(
                            slice.icon,
                            size: 14,
                            color: _onColor(slice.color),
                          ),
                    badgePositionPercentageOffset: 0.6,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Legend(slices: slices),
      ],
    );
  }

  String _percentLabel(int amountCents, int totalCents) {
    if (totalCents == 0) return '0%';
    final percent = amountCents * 100 / totalCents;
    return percent < 1 ? '<1%' : '${percent.round()}%';
  }

  /// White or black over [background], whichever reads — the same
  /// black-or-white-text-on-a-colour-swatch problem every category chip
  /// already solves via [AppColors], but here the swatch is arbitrary user
  /// data rather than one of two fixed brand colours, so it is computed
  /// per-slice from relative luminance instead.
  Color _onColor(Color background) =>
      background.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.slices});

  final List<_Slice> slices;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        for (final slice in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: slice.color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(slice.name, style: theme.textTheme.bodyMedium),
                ),
                Text(
                  formatCents(slice.amountCents),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// FR-RPT-001 with nothing to show. E-22 requires two different sentences —
/// conflating them is "the familiar bug of telling a user with four hundred
/// transactions to add their first expense because they picked a quiet date
/// range."
///
/// Which one applies is read off `databaseSummaryProvider`'s existing
/// transaction count rather than a second analytics query: no expense *in
/// this period* is ambiguous by itself, but no transaction *ever* is not.
/// Now that FR-RPT-002's picker exists, a quiet Day or a custom interval over
/// a gap is the ordinary way the two diverge — which is what E-22 wrote the
/// second sentence for, and the count still tells them apart without a
/// second spending-specific query.
class _NoSpending extends ConsumerWidget {
  const _NoSpending();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(databaseSummaryProvider);
    final hasAnyTransactions = summary.valueOrNull?.transactions != 0;

    return SizedBox(
      height: _chartHeight,
      child: Center(
        child: Text(
          hasAnyTransactions
              ? 'No spending in this period.'
              : 'Your spending breakdown appears here once you have added '
                    'an expense.',
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
                // A Failure carries its own message precisely so the UI
                // never has to invent one; anything else reaching here is a
                // bug rather than something to explain to the user.
                switch (error) {
                  final Failure failure => failure.message,
                  _ => 'Could not load your spending.',
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
