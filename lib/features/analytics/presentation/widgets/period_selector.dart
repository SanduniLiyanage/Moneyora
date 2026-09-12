/// The analytics period picker. FR-RPT-002.
///
/// Day, Week, Month, Year, All and Custom Interval are the chips; "Choose
/// Date" is the calendar button beside them, because it re-anchors whichever
/// of the first four is selected rather than being a seventh thing to select.
///
/// It lives inside the donut chart's card rather than on a screen of its own:
/// SDD SCR-001 puts the chart on the home screen, and a filter that is one
/// scroll away from what it filters is a filter nobody touches.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../domain/entities/period_selection.dart';
import '../../domain/repositories/analytics_repository.dart';
import '../providers/analytics_providers.dart';

/// The earliest date any analytics picker offers — the same floor
/// `add_transaction_page.dart` and `account_form_page.dart` already use.
final DateTime _pickerFloor = DateTime(2000);

/// A one-line description of [selection], for the caption above a chart.
///
/// Here rather than on [PeriodSelection] because it is a formatting concern:
/// `domain/` holds the dates, and how a date reads in a given locale is
/// `intl`'s business and presentation's.
String periodLabel(PeriodSelection selection) {
  final range = selection.range;
  return switch (selection.period) {
    AnalyticsPeriod.day => DateFormat.yMMMMd().format(range.from),
    AnalyticsPeriod.month => DateFormat.yMMMM().format(range.from),
    AnalyticsPeriod.year => DateFormat.y().format(range.from),
    AnalyticsPeriod.all => 'All time',
    // A week and a custom interval are both two dates, and the year is worth
    // stating once rather than twice when both ends share it.
    AnalyticsPeriod.week ||
    AnalyticsPeriod.custom => _spanLabel(range.from, range.to),
  };
}

String _spanLabel(DateTime from, DateTime to) {
  final sameYear = from.year == to.year;
  final start = sameYear
      ? DateFormat.MMMd().format(from)
      : DateFormat.yMMMd().format(from);
  return '$start – ${DateFormat.yMMMd().format(to)}';
}

/// The period chips plus the "Choose Date" button, writing to
/// [analyticsPeriodProvider].
class PeriodSelector extends ConsumerWidget {
  /// Creates the selector.
  const PeriodSelector({super.key});

  static const List<(String, AnalyticsPeriod)> _chips = [
    ('Day', AnalyticsPeriod.day),
    ('Week', AnalyticsPeriod.week),
    ('Month', AnalyticsPeriod.month),
    ('Year', AnalyticsPeriod.year),
    ('All', AnalyticsPeriod.all),
    ('Custom', AnalyticsPeriod.custom),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(analyticsPeriodProvider);

    return Row(
      children: [
        Expanded(
          // Six chips overflow any phone, the same reason
          // `transaction_list_page.dart`'s type filter scrolls.
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final (label, period) in _chips)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: selection.period == period,
                      onSelected: (_) => _select(context, ref, period),
                    ),
                  ),
              ],
            ),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.event_outlined),
          tooltip: 'Choose date',
          // Disabled for All and Custom: neither is anchored to a date, so
          // offering to move an anchor they ignore would do nothing visible.
          onPressed: switch (selection.period) {
            AnalyticsPeriod.all || AnalyticsPeriod.custom => null,
            _ => () => _chooseDate(context, ref, selection),
          },
        ),
      ],
    );
  }

  Future<void> _select(
    BuildContext context,
    WidgetRef ref,
    AnalyticsPeriod period,
  ) async {
    // Custom means nothing until an interval exists, so the chip opens the
    // picker — including when it is already selected, which is the only way
    // to change an interval once it is set.
    if (period == AnalyticsPeriod.custom) {
      await _chooseRange(context, ref, ref.read(analyticsPeriodProvider));
      return;
    }
    ref
        .read(analyticsPeriodProvider.notifier)
        .update((it) => it.withPeriod(period));
  }

  Future<void> _chooseDate(
    BuildContext context,
    WidgetRef ref,
    PeriodSelection selection,
  ) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selection.anchor,
      firstDate: _pickerFloor,
      // No future dates, because no transaction can carry one — the same
      // bound the entry screen's picker uses, for the same reason.
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    ref
        .read(analyticsPeriodProvider.notifier)
        .update((it) => it.withAnchor(picked));
  }

  Future<void> _chooseRange(
    BuildContext context,
    WidgetRef ref,
    PeriodSelection selection,
  ) async {
    final existing = selection.customRange;
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: existing == null
          ? null
          : DateTimeRange(start: existing.from, end: existing.to),
      firstDate: _pickerFloor,
      lastDate: DateTime.now(),
    );
    // Cancelled: leave the selection exactly as it was, rather than switching
    // to a Custom period with no interval behind it.
    if (picked == null) return;
    ref
        .read(analyticsPeriodProvider.notifier)
        .update(
          (it) =>
              it.withCustomRange(DateRange(from: picked.start, to: picked.end)),
        );
  }
}
