/// FR-RPT-002's Custom Interval, on a calendar that swipes between months.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/repositories/analytics_repository.dart';

/// Asks for a run of days between [first] and [last], starting on the
/// month of [initial] when there is one. Null when cancelled.
///
/// One month at a time, a sideways swipe for the next, and two taps for
/// the first and last day. Flutter's own range
/// picker scrolls every month in one long column on a phone, and a year back
/// was a long way down it.
Future<DateRange?> showIntervalPicker(
  BuildContext context, {
  DateRange? initial,
  required DateTime first,
  required DateTime last,
}) => showDialog<DateRange>(
  context: context,
  builder: (context) =>
      IntervalPickerDialog(initial: initial, first: first, last: last),
);

/// The dialog [showIntervalPicker] opens.
class IntervalPickerDialog extends StatefulWidget {
  /// Creates the dialog.
  const IntervalPickerDialog({
    super.key,
    this.initial,
    required this.first,
    required this.last,
  });

  /// The interval already chosen, shown selected.
  final DateRange? initial;

  /// The earliest day that can be chosen.
  final DateTime first;

  /// The latest day that can be chosen.
  final DateTime last;

  @override
  State<IntervalPickerDialog> createState() => _IntervalPickerDialogState();
}

class _IntervalPickerDialogState extends State<IntervalPickerDialog> {
  DateTime? _start;
  DateTime? _end;
  late final PageController _pages;
  late int _page;

  DateTime get _firstMonth => DateTime(widget.first.year, widget.first.month);

  int get _monthCount =>
      (widget.last.year - widget.first.year) * 12 +
      widget.last.month -
      widget.first.month +
      1;

  DateTime _monthAt(int page) =>
      DateTime(_firstMonth.year, _firstMonth.month + page);

  int _pageOf(DateTime date) =>
      ((date.year - _firstMonth.year) * 12 + date.month - _firstMonth.month)
          .clamp(0, _monthCount - 1);

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _start = initial == null ? null : DateUtils.dateOnly(initial.from);
    _end = initial == null ? null : DateUtils.dateOnly(initial.to);
    _page = _pageOf(initial?.to ?? widget.last);
    _pages = PageController(initialPage: _page);
  }

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// The first tap starts a new interval, the second ends it. A second tap
  /// before the first day ends it the other way round, rather than
  /// refusing: the two days are the interval either way.
  void _choose(DateTime day) => setState(() {
    final start = _start;
    if (start == null || _end != null) {
      _start = day;
      _end = null;
    } else if (day.isBefore(start)) {
      _start = day;
      _end = start;
    } else {
      _end = day;
    }
  });

  void _turn(int by) => _pages.animateToPage(
    _page + by,
    duration: const Duration(milliseconds: 250),
    curve: Curves.easeOut,
  );

  String get _summary {
    final start = _start;
    if (start == null) return 'Tap the first day';
    final end = _end;
    final format = DateFormat.yMMMd();
    if (end == null) return '${format.format(start)} – tap the last day';
    return '${format.format(start)} – ${format.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    final cell = MediaQuery.textScalerOf(context).scale(14) * 2.6;
    final start = _start;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Interval', style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(_summary, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: 'Previous month',
                  onPressed: _page > 0 ? () => _turn(-1) : null,
                ),
                Expanded(
                  child: Text(
                    DateFormat.yMMMM().format(_monthAt(_page)),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: 'Next month',
                  onPressed: _page < _monthCount - 1 ? () => _turn(1) : null,
                ),
              ],
            ),
            Row(
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        localizations.narrowWeekdays[(localizations
                                    .firstDayOfWeekIndex +
                                i) %
                            7],
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelMedium,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: cell * 6,
              child: PageView.builder(
                controller: _pages,
                itemCount: _monthCount,
                onPageChanged: (page) => setState(() => _page = page),
                itemBuilder: (context, page) => _Month(
                  month: _monthAt(page),
                  first: DateUtils.dateOnly(widget.first),
                  last: DateUtils.dateOnly(widget.last),
                  start: start,
                  end: _end,
                  cellHeight: cell,
                  firstDayOfWeek: localizations.firstDayOfWeekIndex,
                  onChoose: _choose,
                ),
              ),
            ),
            const SizedBox(height: 8),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  // One day is an interval too: the second tap is optional.
                  onPressed: start == null
                      ? null
                      : () =>
                            Navigator.of(context)
                                .pop(DateRange(from: start, to: _end ?? start)),
                  child: const Text('OK'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One month's days, seven to a row, with the chosen run marked.
class _Month extends StatelessWidget {
  const _Month({
    required this.month,
    required this.first,
    required this.last,
    required this.start,
    required this.end,
    required this.cellHeight,
    required this.firstDayOfWeek,
    required this.onChoose,
  });

  final DateTime month;
  final DateTime first;
  final DateTime last;
  final DateTime? start;
  final DateTime? end;
  final double cellHeight;

  /// 0 for Sunday, as [MaterialLocalizations.firstDayOfWeekIndex] has it.
  final int firstDayOfWeek;
  final ValueChanged<DateTime> onChoose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    // DateTime.weekday is 1 for Monday to 7 for Sunday; % 7 makes Sunday 0.
    final blanks = (month.weekday % 7 - firstDayOfWeek + 7) % 7;

    return Column(
      children: [
        for (var row = 0; row < 6; row++)
          SizedBox(
            height: cellHeight,
            child: Row(
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: switch (row * 7 + column - blanks + 1) {
                      final day when day >= 1 && day <= days => _Day(
                        date: DateTime(month.year, month.month, day),
                        enabled: _inBounds(
                          DateTime(month.year, month.month, day),
                        ),
                        state: _stateOf(DateTime(month.year, month.month, day)),
                        scheme: scheme,
                        style: theme.textTheme.bodyMedium!,
                        onChoose: onChoose,
                      ),
                      _ => const SizedBox.shrink(),
                    },
                  ),
              ],
            ),
          ),
      ],
    );
  }

  bool _inBounds(DateTime day) => !day.isBefore(first) && !day.isAfter(last);

  _DayState _stateOf(DateTime day) {
    final start = this.start;
    final end = this.end;
    if (start == null) return _DayState.none;
    if (DateUtils.isSameDay(day, start) ||
        (end != null && DateUtils.isSameDay(day, end))) {
      return _DayState.end;
    }
    if (end != null && day.isAfter(start) && day.isBefore(end)) {
      return _DayState.inside;
    }
    return _DayState.none;
  }
}

enum _DayState { none, inside, end }

class _Day extends StatelessWidget {
  const _Day({
    required this.date,
    required this.enabled,
    required this.state,
    required this.scheme,
    required this.style,
    required this.onChoose,
  });

  final DateTime date;
  final bool enabled;
  final _DayState state;
  final ColorScheme scheme;
  final TextStyle style;
  final ValueChanged<DateTime> onChoose;

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = switch (state) {
      _DayState.end => (scheme.primary, scheme.onPrimary),
      _DayState.inside => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _DayState.none => (
        null,
        enabled ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.38),
      ),
    };

    return Semantics(
      button: enabled,
      selected: state != _DayState.none,
      label: DateFormat.yMMMMd().format(date),
      excludeSemantics: true,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? () => onChoose(date) : null,
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              shape: state == _DayState.end
                  ? BoxShape.circle
                  : BoxShape.rectangle,
              borderRadius: state == _DayState.inside
                  ? BorderRadius.circular(8)
                  : null,
            ),
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${date.day}',
                  style: style.copyWith(color: foreground),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
