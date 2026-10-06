/// The home screen's spending ring, in the reference app's shape: each
/// category's icon and share around the ring, income and spending in its
/// middle. FR-RPT-001.
library;

import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/category_reader.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/category_palette.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../core/widgets/category_icons.dart';
import '../../../../injection.dart';
import '../../domain/entities/category_total.dart';
import '../../domain/entities/period_summary.dart';
import '../providers/analytics_providers.dart';
import 'period_stepper.dart';

/// Beyond this many categories, the smallest fold into one "Other".
///
/// Seven bubbles fit round the ring on a 320dp phone without touching; the
/// eighth would sit on a neighbour. Categories with nothing spent are never
/// drawn — the owner's call, for the same room.
const int _maxSlices = 6;

/// Spending by category over the chosen period and account, with the period
/// between ‹ and › above it. A sideways swipe steps the period.
/// FR-RPT-001, FR-RPT-002, FR-RPT-003.
///
/// Composed into home by `core/router/app_router.dart`, because
/// `features/home/` may not import this feature.
class SpendingOverview extends ConsumerWidget {
  /// Creates the overview.
  const SpendingOverview({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(analyticsQueryProvider);
    final totals = ref.watch(spendingByCategoryTotalsProvider(query));
    final categories = ref.watch(categoryOptionsProvider);
    final summary = ref.watch(periodSummaryProvider).valueOrNull;

    return PeriodSwipe(
      child: Column(
        children: [
          const PeriodStepper(),
          Expanded(
            child: switch ((totals, categories)) {
              (AsyncError(:final error), _) ||
              (_, AsyncError(:final error)) => _Problem(error: error),
              (AsyncData(value: final spent), AsyncData(value: final known)) =>
                _Ring(
                  slices: _slicesOf(spent, known, Theme.of(context)),
                  summary: summary,
                ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

/// One category's part of the ring.
class _Slice {
  const _Slice({
    required this.name,
    required this.icon,
    required this.color,
    required this.amountCents,
  });

  final String name;
  final IconData icon;
  final Color color;
  final int amountCents;
}

List<_Slice> _slicesOf(
  List<CategoryTotal> totals,
  List<CategoryOption> categories,
  ThemeData theme,
) {
  final iconByCategory = {for (final c in categories) c.id: c.icon};
  final spent = totals.where((t) => t.amountCents > 0).toList();
  return [
    for (final total in spent.take(_maxSlices))
      _Slice(
        name: total.name,
        icon: categoryIconFor(iconByCategory[total.categoryId] ?? ''),
        color: categoryColorFor(total.color, theme.brightness),
        amountCents: total.amountCents,
      ),
    if (spent.length > _maxSlices)
      _Slice(
        name: 'Other',
        icon: Icons.more_horiz,
        color: _grey(theme, 0.45),
        amountCents: spent
            .skip(_maxSlices)
            .fold(0, (sum, t) => sum + t.amountCents),
      ),
  ];
}

String _percent(int part, int whole) {
  if (whole == 0) return '0%';
  final percent = part * 100 / whole;
  return percent < 1 ? '<1%' : '${percent.round()}%';
}

/// A grey of [strength] over the page, opaque so the bubble on it can pick
/// its icon colour. The theme's outline colours are near black here.
Color _grey(ThemeData theme, double strength) => Color.alphaBlend(
  theme.colorScheme.onSurface.withValues(alpha: strength),
  theme.colorScheme.surface,
);

/// White or black over [background], whichever reads.
Color _onColor(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black : Colors.white;

class _Ring extends ConsumerWidget {
  const _Ring({required this.slices, required this.summary});

  final List<_Slice> slices;

  /// The period's income and spending, for the middle; null while loading.
  final PeriodSummary? summary;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.extension<AppColors>()!;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = theme.textTheme.labelMedium!;
    final total = slices.fold(0, (sum, s) => sum + s.amountCents);

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final side = math.min(width, height);
        final centre = Offset(width / 2, height / 2);

        // A bubble and its percentage under it, sized to the room there is.
        final bubble = (side * 0.12).clamp(28.0, 44.0);
        final labelHeight = scaler.scale(labelStyle.fontSize ?? 12) * 1.4;
        final boxWidth = bubble * 1.9;
        final orbit = side / 2 - bubble / 2 - labelHeight - 2;
        final outer = orbit - bubble / 2 - 6;
        final thickness = outer * 0.3;
        final hole = outer - thickness;

        // No room for a ring at all: the two totals still say something.
        if (outer < 32) {
          return Center(
            child: _Totals(summary: summary, colors: colors),
          );
        }

        final middles = <double>[];
        var before = 0;
        for (final slice in slices) {
          middles.add(_midAngle(before, slice.amountCents, total));
          before += slice.amountCents;
        }
        final angles = _spread(
          middles,
          minimumGap: 2 * math.asin(math.min(1, (boxWidth / 2 + 2) / orbit)),
        );

        final hasAnyTransactions =
            ref.watch(databaseSummaryProvider).valueOrNull?.transactions != 0;

        // The bubbles say only an icon and a share; this says the rest to a
        // screen reader.
        final described = [
          for (final s in slices)
            '${s.name} ${_percent(s.amountCents, total)}, '
                '${formatCents(s.amountCents)}',
        ].join('; ');

        return Semantics(
          container: true,
          label: slices.isEmpty
              ? 'No spending in this period'
              : 'Spending by category: $described',
          child: Stack(
            children: [
              Positioned.fill(
                child: ExcludeSemantics(
                  child: PieChart(
                    PieChartData(
                      startDegreeOffset: -90,
                      sectionsSpace: slices.length > 1 ? 2 : 0,
                      centerSpaceRadius: hole,
                      sections: [
                        if (slices.isEmpty)
                          PieChartSectionData(
                            value: 1,
                            color: _grey(theme, 0.12),
                            radius: thickness,
                            showTitle: false,
                          ),
                        for (final slice in slices)
                          PieChartSectionData(
                            value: slice.amountCents.toDouble(),
                            color: slice.color,
                            radius: thickness,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                // Inside the hole, whatever the font: the box is the hole's
                // width and a little over its radius high.
                child: SizedBox(
                  width: hole * 1.7,
                  height: hole * 1.2,
                  child: _Totals(summary: summary, colors: colors),
                ),
              ),
              for (var i = 0; i < slices.length; i++)
                Positioned(
                  left: centre.dx + orbit * math.cos(angles[i]) - boxWidth / 2,
                  // The share on the side away from the ring: above a bubble
                  // in the top half, under one in the bottom half.
                  top:
                      centre.dy +
                      orbit * math.sin(angles[i]) -
                      bubble / 2 -
                      (math.sin(angles[i]) < 0 ? labelHeight : 0),
                  width: boxWidth,
                  child: ExcludeSemantics(
                    child: _Bubble(
                      slice: slices[i],
                      size: bubble,
                      label: _percent(slices[i].amountCents, total),
                      labelStyle: labelStyle,
                      labelHeight: labelHeight,
                      labelAbove: math.sin(angles[i]) < 0,
                    ),
                  ),
                ),
              if (slices.isEmpty)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 0,
                  child: Text(
                    // E-22: nothing in this period and nothing ever are two
                    // different sentences.
                    hasAnyTransactions
                        ? 'No spending in this period.'
                        : 'Tap − to record your first expense.',
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The middle of [amountCents]'s arc, in radians from three o'clock,
  /// clockwise, with the ring starting at twelve as the chart draws it.
  static double _midAngle(int before, int amountCents, int total) {
    if (total == 0) return -math.pi / 2;
    final middle = (before + amountCents / 2) / total;
    return -math.pi / 2 + middle * 2 * math.pi;
  }

  /// [angles], pushed apart until neighbours are at least [minimumGap]
  /// apart, so two small categories side by side do not draw their bubbles
  /// on top of each other. Each moves as little as it can.
  static List<double> _spread(
    List<double> angles, {
    required double minimumGap,
  }) {
    if (angles.length < 2) return angles;
    final spread = [...angles];
    for (var i = 1; i < spread.length; i++) {
      if (spread[i] - spread[i - 1] < minimumGap) {
        spread[i] = spread[i - 1] + minimumGap;
      }
    }
    // Pushed past the first bubble on the way round: pull back the other way.
    final limit = spread.first + 2 * math.pi - minimumGap;
    if (spread.last > limit) {
      spread[spread.length - 1] = limit;
      for (var i = spread.length - 2; i >= 0; i--) {
        if (spread[i + 1] - spread[i] < minimumGap) {
          spread[i] = spread[i + 1] - minimumGap;
        }
      }
    }
    return spread;
  }
}

/// Income over spending, in their colours, in the ring's middle.
class _Totals extends StatelessWidget {
  const _Totals({required this.summary, required this.colors});

  final PeriodSummary? summary;
  final AppColors colors;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700);
    final summary = this.summary;

    Widget line(String text, Color color) =>
        Text(text, maxLines: 1, style: style?.copyWith(color: color));

    // Shrinks as one, so a long income never ends up larger than the
    // spending under it, and both stay inside whatever room they are given.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          line(
            summary == null ? '…' : formatCents(summary.incomeCents),
            colors.income,
          ),
          const SizedBox(height: 4),
          line(
            summary == null ? '…' : formatCents(summary.expenseCents),
            colors.expense,
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    required this.slice,
    required this.size,
    required this.label,
    required this.labelStyle,
    required this.labelHeight,
    required this.labelAbove,
  });

  final _Slice slice;
  final double size;
  final String label;
  final TextStyle labelStyle;

  /// The share's height, fixed so the ring's geometry can count on it.
  final double labelHeight;

  /// Whether the share sits above the bubble rather than under it.
  final bool labelAbove;

  @override
  Widget build(BuildContext context) {
    final share = SizedBox(
      height: labelHeight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, style: labelStyle),
      ),
    );
    final circle = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: slice.color, shape: BoxShape.circle),
      child: Icon(slice.icon, size: size * 0.58, color: _onColor(slice.color)),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: labelAbove ? [share, circle] : [circle, share],
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          // A Failure carries its own message precisely so the UI never has
          // to invent one.
          switch (error) {
            final Failure failure => failure.message,
            _ => 'Could not load your spending.',
          },
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
      ),
    );
  }
}
