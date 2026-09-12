/// Per-category spending over time, as trend lines. FR-RPT-005.
///
/// Reads the same [analyticsQueryProvider] the donut and the bars do, so
/// FR-RPT-002's period and FR-RPT-003's account move all three charts at
/// once. The filters render once, on the donut's card above. The account
/// filter reaches this chart deliberately: it sits under the same filter
/// row as two charts that honour it, and a line that ignored the account
/// would look filtered and not be — the "wrong total that looks right" the
/// filter's own doc comment warns about.
///
/// ## The colour question `SPEC_ERRATA.md` left open
///
/// The errata's colour-collision check names this chart as the one place
/// that could reopen it: `default_seed.dart` pairs each income category with
/// an expense category sharing its exact colour (Bills/Deposits,
/// Entertainment/Salary, Gifts/Savings), and "a line per category over time
/// could in principle plot both kinds at once". **It does not.** FR-RPT-005
/// asks for per-category *spending*, and the query beneath this chart is the
/// donut's own spending rows cut by date — `type = 'expense'` only, income
/// never selected. So an income colour never renders here, for the same
/// reason it never renders on the donut, and the check stays closed. Past
/// [_maxLines] categories the tail folds into "Other" in
/// `colorScheme.outline`, which is not a category colour at all — the same
/// fold the donut applies past six wedges.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/category_palette.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../injection.dart';
import '../../domain/entities/spending_trend.dart';
import '../../domain/entities/trend_point.dart';
import '../providers/analytics_providers.dart';
import 'period_selector.dart';

/// One height for every state, so the card does not jump as data resolves —
/// the same rule the donut and the bars follow.
const double _chartHeight = 180;

/// Beyond this many categories, the rest fold into one "Other" line.
///
/// Five rather than the donut's six: wedges sit side by side, lines cross,
/// and past five the crossings are what the eye reads instead of the trend.
/// [GetSpendingTrend] already orders series by their total over the period,
/// so "the rest" is always the smallest contributors — the same thing
/// "Other" means on the donut, and the same presentation-side answer to
/// E-10/NFR-PER-005's "never refuses the 51st category".
const int _maxLines = 5;

/// Up to this many points, each carries a dot; past it the line runs bare.
///
/// A dot per day on a 31-day line is a bead chain, not a trend; a dot per
/// month on a 12-month line is what tells the reader where the months are.
const int _maxDottedPoints = 12;

/// Spending by category over the selected period and account, one line per
/// category. FR-RPT-005.
class SpendingTrendLines extends ConsumerWidget {
  /// Creates the chart.
  const SpendingTrendLines({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(analyticsPeriodProvider);
    final query = ref.watch(analyticsQueryProvider);
    final trend = ref.watch(spendingTrendProvider(query));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Spending over time', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              periodLabel(selection),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            switch (trend) {
              AsyncError(:final error) => _Problem(error: error),
              AsyncData(:final value) => _Chart(trend: value),
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

/// One line, after the tail past [_maxLines] is folded down.
class _Line {
  const _Line({
    required this.name,
    required this.color,
    required this.amountsCents,
  });

  final String name;
  final Color color;
  final List<int> amountsCents;

  int get totalCents => amountsCents.fold(0, (sum, c) => sum + c);
}

class _Chart extends StatelessWidget {
  const _Chart({required this.trend});

  final SpendingTrend trend;

  @override
  Widget build(BuildContext context) {
    if (trend.isEmpty) return const _NoSpending();
    // One bucket is one point, and a point is not a trend. Saying so beats
    // drawing a dot in the middle of an empty axis.
    if (trend.buckets.length < 2) return const _TooShort();

    final theme = Theme.of(context);
    final brightness = theme.brightness;

    final lines = <_Line>[
      for (final series in trend.series.take(_maxLines))
        _Line(
          name: series.name,
          color: categoryColorFor(series.color, brightness),
          amountsCents: series.amountsCents,
        ),
    ];

    if (trend.series.length > _maxLines) {
      final rest = trend.series.skip(_maxLines);
      lines.add(
        _Line(
          name: 'Other',
          // The donut's "Other" colour, faded: a solid `outline` line would
          // be the darkest mark on the chart and read as the story, when it
          // is the tail.
          color: theme.colorScheme.outline.withValues(alpha: 0.45),
          amountsCents: [
            for (var i = 0; i < trend.buckets.length; i++)
              rest.fold(0, (sum, s) => sum + s.amountsCents[i]),
          ],
        ),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: _chartHeight,
          child: _Plot(
            lines: lines,
            buckets: trend.buckets,
            granularity: trend.granularity,
          ),
        ),
        const SizedBox(height: 16),
        _Legend(lines: lines),
      ],
    );
  }
}

class _Plot extends StatelessWidget {
  const _Plot({
    required this.lines,
    required this.buckets,
    required this.granularity,
  });

  final List<_Line> lines;
  final List<DateTime> buckets;
  final TrendGranularity granularity;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    // `AppTheme` sets no `outlineVariant`, so it falls back to `onSurface`;
    // a hairline at low alpha is what keeps it recessive.
    final hairline = theme.colorScheme.onSurface.withValues(alpha: 0.15);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    final labelled = _labelIndices(buckets.length);
    final ceiling = _axisCeiling();
    final showDots = buckets.length <= _maxDottedPoints;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (buckets.length - 1).toDouble(),
        minY: 0,
        maxY: ceiling,
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: ceiling / 4,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: hairline, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: ceiling / 4,
              getTitlesWidget: (value, meta) => value == 0 || value >= ceiling
                  // The floor is the baseline and the ceiling is headroom;
                  // labelling either adds a number nobody reads.
                  ? const SizedBox.shrink()
                  : Text(
                      formatCentsCompact(value.round()),
                      style: labelStyle,
                      textAlign: TextAlign.right,
                    ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if ((value - index).abs() > 0.001 ||
                    !labelled.contains(index)) {
                  return const SizedBox.shrink();
                }
                // Fitted inside the axis, so the first and last labels are
                // nudged inward rather than centred on an edge and cut in
                // half.
                return SideTitleWidget(
                  meta: meta,
                  space: 6,
                  fitInside: SideTitleFitInsideData.fromTitleMeta(
                    meta,
                    distanceFromEdge: 0,
                  ),
                  child: Text(_bucketLabel(buckets[index]), style: labelStyle),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => theme.colorScheme.inverseSurface,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  '${lines[spot.barIndex].name}  '
                  '${formatCents(spot.y.round())}',
                  theme.textTheme.labelSmall!.copyWith(
                    color: theme.colorScheme.onInverseSurface,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          for (final line in lines)
            LineChartBarData(
              spots: [
                for (var i = 0; i < line.amountsCents.length; i++)
                  FlSpot(i.toDouble(), line.amountsCents[i].toDouble()),
              ],
              color: line.color,
              barWidth: 2,
              isStrokeCapRound: true,
              isStrokeJoinRound: true,
              dotData: FlDotData(
                show: showDots,
                // A ring in the surface colour keeps a dot legible where
                // two lines cross, without a border that reads as data.
                getDotPainter: (_, _, _, _) => FlDotCirclePainter(
                  radius: 4,
                  color: line.color,
                  strokeWidth: 2,
                  strokeColor: surface,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// A little above the tallest point, and never zero — a `maxY` of 0 makes
  /// `fl_chart` draw nothing at all rather than flat lines along the floor.
  double _axisCeiling() {
    var tallest = 0;
    for (final line in lines) {
      for (final cents in line.amountsCents) {
        if (cents > tallest) tallest = cents;
      }
    }
    return tallest == 0 ? 1 : tallest * 1.15;
  }

  /// Which points get a date under them: all of them up to six, otherwise
  /// the first, the last and two or three evenly spaced between — enough
  /// to read the axis, few enough that no two labels touch on a phone.
  static Set<int> _labelIndices(int count) {
    if (count <= 6) return {for (var i = 0; i < count; i++) i};
    final step = ((count - 1) / 3).ceil();
    return {
      for (var i = 0; i < count; i += step)
        // A label within half a step of the last one would sit on top of
        // it, so the last label wins that slot.
        if (count - 1 - i >= step / 2) i,
      count - 1,
    };
  }

  /// `3 Sep` for a day; `Sep` for a month, or `Sep 25` once the line crosses
  /// a year boundary and the month alone would be ambiguous.
  String _bucketLabel(DateTime bucket) => switch (granularity) {
    TrendGranularity.day => DateFormat.MMMd().format(bucket),
    TrendGranularity.month =>
      buckets.first.year == buckets.last.year
          ? DateFormat.MMM().format(bucket)
          : DateFormat('MMM yy').format(bucket),
  };
}

class _Legend extends StatelessWidget {
  const _Legend({required this.lines});

  final List<_Line> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        for (final line in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                // A short line key rather than the donut's dot: the mark on
                // the legend should look like the mark on the chart.
                Container(
                  width: 14,
                  height: 3,
                  decoration: BoxDecoration(
                    color: line.color,
                    borderRadius: BorderRadius.circular(1.5),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(line.name, style: theme.textTheme.bodyMedium),
                ),
                Text(
                  formatCents(line.totalCents),
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

/// FR-RPT-005 with nothing to show. E-22's two sentences, told apart the way
/// the donut tells them apart — off `databaseSummaryProvider`'s existing
/// count rather than a second query — but not in the donut's words, since
/// the two cards sit one above the other and the same sentence twice on one
/// screen reads as a stuck template.
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
              ? 'No spending to chart in this period.'
              : 'How each category moves over time appears here once you '
                    'have added an expense.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

/// FR-RPT-002's "Day" filter, on a chart of change over time: there was
/// spending, but only one point to plot it at. E-22's shape — what belongs
/// here, why it is empty, and the one action that fills it.
class _TooShort extends StatelessWidget {
  const _TooShort();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: _chartHeight,
      child: Center(
        child: Text(
          'A single day has no trend. Pick a week or longer to see one.',
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
                  _ => 'Could not load your spending over time.',
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
