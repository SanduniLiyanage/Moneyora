/// Stepping the analytics period back and on: ‹ and › around its name, and a
/// sideways swipe. FR-RPT-002.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ports/calendar_settings.dart';
import '../../../../injection.dart';
import '../../domain/entities/period_selection.dart';
import '../providers/analytics_providers.dart';
import 'period_selector.dart';

/// The period one step back or on from the current one, or null when there
/// is none: all time has no neighbours, and a period that starts after
/// today holds nothing that could have been recorded yet.
PeriodSelection? _stepped(WidgetRef ref, {required bool forward}) {
  final current = ref.read(analyticsPeriodProvider);
  final stepped = forward ? current.next : current.previous;
  if (stepped == null || !forward) return stepped;

  final calendar =
      ref.read(calendarSettingsProvider).asData?.value ??
      CalendarSettings.defaults;
  final today = ref.read(clockProvider)();
  final starts = stepped.rangeWith(calendar).from;
  return starts.isAfter(DateTime(today.year, today.month, today.day))
      ? null
      : stepped;
}

/// Moves the period one step, as a swipe or an arrow asks. Returns whether
/// it moved.
bool stepPeriod(WidgetRef ref, {required bool forward}) {
  final stepped = _stepped(ref, forward: forward);
  if (stepped == null) return false;
  ref.read(analyticsPeriodProvider.notifier).state = stepped;
  return true;
}

/// The period's name between ‹ and ›.
///
/// The arrows are the way to step for anyone who does not swipe, or cannot:
/// a gesture with no visible control is one a screen reader never finds.
class PeriodStepper extends ConsumerWidget {
  /// Creates the stepper.
  const PeriodStepper({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selection = ref.watch(analyticsPeriodProvider);
    final range = ref.watch(analyticsRangeProvider);
    // Watched for the rebuild, read through the helper for the answer.
    ref.watch(calendarSettingsProvider);
    final canGoBack = _stepped(ref, forward: false) != null;
    final canGoOn = _stepped(ref, forward: true) != null;

    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous period',
          onPressed: canGoBack ? () => stepPeriod(ref, forward: false) : null,
        ),
        Expanded(
          child: Text(
            periodLabel(selection, range),
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium,
          ),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next period',
          onPressed: canGoOn ? () => stepPeriod(ref, forward: true) : null,
        ),
      ],
    );
  }
}

/// [child], where a sideways swipe steps the period: towards the left for
/// the next one, towards the right for the one before, as pages turn.
class PeriodSwipe extends ConsumerWidget {
  /// Creates the swipe area around [child].
  const PeriodSwipe({super.key, required this.child});

  /// What the swipe is over.
  final Widget child;

  /// Slower than this is a hand resting, not a swipe.
  static const double _minimumVelocity = 250;

  @override
  Widget build(BuildContext context, WidgetRef ref) => GestureDetector(
    // Opaque, so the space between the chart's parts swipes too.
    behavior: HitTestBehavior.opaque,
    onHorizontalDragEnd: (details) {
      final velocity = details.primaryVelocity ?? 0;
      if (velocity.abs() < _minimumVelocity) return;
      stepPeriod(ref, forward: velocity < 0);
    },
    child: child,
  );
}
