/// Daily spending intensity over one calendar month. FR-RPT-009.
///
/// Reads the period picker's *anchor* and the account filter, not the
/// selected period: a heatmap is a grid of days, and this card always draws
/// the whole calendar month the anchor falls in, whichever of FR-RPT-002's
/// seven filters is selected. The card says so in its subtitle, so a reader
/// under a Year or a Week filter knows why this chart did not move. The
/// account filter does reach it, for the reason it reaches the bars and the
/// lines.
///
/// Every cell is `AppColors.expense` at one of five opacities, shaded against
/// the largest day in the displayed month, so no category colour renders here
/// and `SPEC_ERRATA.md`'s colour-collision check stays closed.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../../../injection.dart';
import '../../domain/entities/spending_calendar.dart';
import '../providers/analytics_providers.dart';

/// Height of every non-grid state, so the card does not jump as data resolves.
const double _placeholderHeight = 200;

/// Monday-first, matching `DateRange.week`'s default; FR-SET-004 makes this
/// configurable in Sprint 7 and this is where that setting would land.
const int _firstWeekday = DateTime.monday;

/// One calendar month of daily spending, shaded by intensity. FR-RPT-009.
class SpendingHeatmap extends ConsumerWidget {
  /// Creates the chart.
  const SpendingHeatmap({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final query = ref.watch(spendingCalendarQueryProvider);
    final calendar = ref.watch(spendingCalendarProvider(query));
    final monthName = DateFormat.yMMMM().format(
      DateTime(query.year, query.month),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily spending', style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(
              '$monthName · always the whole month',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 16),
            switch (calendar) {
              AsyncError(:final error) => _Problem(error: error),
              AsyncData(:final value) => _Month(calendar: value),
              _ => const SizedBox(
                height: _placeholderHeight,
                child: Center(child: CircularProgressIndicator()),
              ),
            },
          ],
        ),
      ),
    );
  }
}

/// The fill for a cell at [level], 0 being a quiet day.
Color cellColorFor(BuildContext context, int level) {
  final theme = Theme.of(context);
  if (level == 0) return theme.colorScheme.onSurface.withValues(alpha: 0.06);
  final expense = theme.extension<AppColors>()!.expense;
  return expense.withValues(alpha: level / SpendingCalendar.levels);
}

class _Month extends StatelessWidget {
  const _Month({required this.calendar});

  final SpendingCalendar calendar;

  @override
  Widget build(BuildContext context) {
    if (calendar.isEmpty) return const _NoSpending();

    return Column(
      children: [
        _Grid(calendar: calendar),
        const SizedBox(height: 12),
        _Summary(calendar: calendar),
        const SizedBox(height: 8),
        const _Legend(),
      ],
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.calendar});

  final SpendingCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );
    final first = DateTime(calendar.year, calendar.month);
    final leading = (first.weekday - _firstWeekday + 7) % 7;
    final slots = leading + calendar.dayCount;
    final rows = (slots / 7).ceil();

    return Column(
      children: [
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Text(
                  // Any Monday will do as the origin for weekday names.
                  DateFormat.E().format(DateTime(2026, 9, 7 + i)),
                  textAlign: TextAlign.center,
                  style: labelStyle,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(
                  child: switch (r * 7 + c - leading + 1) {
                    final day when day >= 1 && day <= calendar.dayCount =>
                      _Cell(day: day, calendar: calendar),
                    _ => const AspectRatio(aspectRatio: 1),
                  },
                ),
            ],
          ),
      ],
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({required this.day, required this.calendar});

  final int day;
  final SpendingCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = calendar.levelOf(day);
    final cents = calendar.amountOn(day);
    final date = DateTime(calendar.year, calendar.month, day);

    final cell = Padding(
      padding: const EdgeInsets.all(2),
      child: AspectRatio(
        aspectRatio: 1,
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: cellColorFor(context, level),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            '$day',
            style: theme.textTheme.labelSmall?.copyWith(
              // Past the midpoint the fill is dark enough that the surface's
              // own text colour disappears into it.
              color: level >= 3
                  ? Colors.white
                  : theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
        ),
      ),
    );

    if (cents == 0) return cell;
    return Tooltip(
      message: '${DateFormat.MMMd().format(date)} · ${formatCents(cents)}',
      child: cell,
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.calendar});

  final SpendingCalendar calendar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    var busiest = 1;
    for (var d = 2; d <= calendar.dayCount; d++) {
      if (calendar.amountOn(d) > calendar.amountOn(busiest)) busiest = d;
    }
    final busiestDate = DateTime(calendar.year, calendar.month, busiest);

    return Row(
      children: [
        Expanded(
          child: Text(
            'Total ${formatCents(calendar.totalCents)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Text(
          'Busiest ${DateFormat.MMMd().format(busiestDate)}, '
          '${formatCents(calendar.maxCents)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text('Less', style: style),
        const SizedBox(width: 6),
        for (var level = 0; level <= SpendingCalendar.levels; level++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: cellColorFor(context, level),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 6),
        Text('More', style: style),
      ],
    );
  }
}

/// FR-RPT-009 with nothing to show. E-22's two sentences, told apart off
/// `databaseSummaryProvider`'s count the way the other three cards do, in
/// this card's own words.
class _NoSpending extends ConsumerWidget {
  const _NoSpending();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final summary = ref.watch(databaseSummaryProvider);
    final hasAnyTransactions = summary.valueOrNull?.transactions != 0;

    return SizedBox(
      height: _placeholderHeight,
      child: Center(
        child: Text(
          hasAnyTransactions
              ? 'No spending in this month.'
              : 'Which days you spend most on appears here once you have '
                    'added an expense.',
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
      height: _placeholderHeight,
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
                switch (error) {
                  final Failure failure => failure.message,
                  _ => 'Could not load your daily spending.',
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
