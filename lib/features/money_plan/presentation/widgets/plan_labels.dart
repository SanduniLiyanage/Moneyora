/// How the plan's domain values read on screen.
///
/// Formatting is presentation's business, not the entities': `domain/` holds
/// the dates and enums, and how they read in a locale is `intl`'s.
library;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/currency_utils.dart';
import '../../domain/entities/allocation_progress.dart';
import '../../domain/entities/budget_mode.dart';
import '../../domain/entities/category_classification.dart';
import '../../domain/entities/confidence_score.dart';
import '../../domain/entities/plan_history.dart';
import '../../domain/entities/plan_period.dart';
import '../../domain/entities/spending_patterns.dart';

/// What [patterns] say, one sentence each, and which categories were
/// [leftOut] of them as bills or one-offs. FR-PLN-006.
///
/// Only a pattern past `PatternComparison.thresholdPercent` is named, and
/// when neither is the answer says so rather than saying nothing: "steady"
/// is a finding too.
List<String> spendingPatternLines(
  SpendingPatterns patterns, {
  List<String> leftOut = const [],
}) {
  final note = [
    if (leftOut.isNotEmpty)
      'Left out, as spent on a day or two a month: ${leftOut.join(', ')}.',
  ];
  if (!patterns.hasEnoughHistory) {
    return [
      'Too little spending in these months to see a pattern yet.',
      ...note,
    ];
  }
  final lines = [
    ?_patternLine(patterns.week, 'Weekdays', 'weekends'),
    ?_patternLine(
      patterns.month,
      'The first ten days of a month',
      'the last ten',
    ),
  ];
  return [
    if (lines.isEmpty)
      'Steady across the week and the month: no kind of day costs '
          '${PatternComparison.thresholdPercent}% more than another.'
    else
      ...lines,
    ...note,
  ];
}

String? _patternLine(PatternComparison c, String first, String second) {
  final lean = c.lean;
  if (lean == null) return null;
  final (high, low, highDaily, lowDaily) = switch (lean) {
    PatternLean.first => (first, second, c.firstDailyCents, c.secondDailyCents),
    PatternLean.second => (
      _capitalise(second),
      first.toLowerCase(),
      c.secondDailyCents,
      c.firstDailyCents,
    ),
  };
  final percent = c.percentMore;
  if (percent == null) {
    return '$high are when you spend: ${formatCents(highDaily)} a day, '
        'and nothing on $low.';
  }
  return '$high cost $percent% more a day than $low: '
      '${formatCents(highDaily)} against ${formatCents(lowDaily)}.';
}

String _capitalise(String s) => s[0].toUpperCase() + s.substring(1);

/// One line for [period]: `September 2026`, `7 – 13 Sep 2026`, `2027`.
///
/// A month is named as a month only when it *is* one: under FR-SET-004 a
/// month can start on the 25th, and "September 2026" for 25 September to
/// 24 October would be a wrong label that looks right, so that reads as a
/// span.
String planPeriodLabel(PlanPeriod period) => switch (period.type) {
  PlanPeriodType.day => DateFormat.yMMMMd().format(period.from),
  PlanPeriodType.month when period.from.day == 1 => DateFormat.yMMMM().format(
    period.from,
  ),
  PlanPeriodType.month => _span(period.from, period.to),
  PlanPeriodType.year => DateFormat.y().format(period.from),
  PlanPeriodType.week ||
  PlanPeriodType.customDays ||
  PlanPeriodType.customRange => _span(period.from, period.to),
};

String _span(DateTime from, DateTime to) {
  final start = from.year == to.year
      ? DateFormat.MMMd().format(from)
      : DateFormat.yMMMd().format(from);
  return '$start – ${DateFormat.yMMMd().format(to)}';
}

/// The chip text for one of FR-PLN-002's shapes.
String periodTypeLabel(PlanPeriodType type) => switch (type) {
  PlanPeriodType.day => 'Day',
  PlanPeriodType.week => 'Week',
  PlanPeriodType.month => 'Month',
  PlanPeriodType.year => 'Year',
  PlanPeriodType.customDays => 'Number of days',
  PlanPeriodType.customRange => 'Date range',
};

/// One line for how the total was decided. FR-PLN-008.
String budgetModeLabel(BudgetMode mode) => switch (mode) {
  UnconstrainedBudget() => 'From your spending history',
  UserTotalBudget() => 'Your total, shared proportionally',
  SuggestedBudget(:final savingsTargetPct) =>
    'Suggested from income, saving ${_percent(savingsTargetPct)}',
};

String _percent(double pct) =>
    pct == pct.roundToDouble() ? '${pct.round()}%' : '$pct%';

/// `Fixed`, `Variable`, `Seasonal`. FR-PLN-004.
String expenseTypeLabel(ExpenseType type) => switch (type) {
  ExpenseType.fixed => 'Fixed',
  ExpenseType.variable => 'Variable',
  ExpenseType.seasonal => 'Seasonal',
};

/// `High`, `Medium`, `Low`. FR-PLN-010.
String confidenceLabel(ConfidenceLevel level) => switch (level) {
  ConfidenceLevel.high => 'High',
  ConfidenceLevel.medium => 'Medium',
  ConfidenceLevel.low => 'Low',
};

/// Why the confidence is what it is — stated always, and required by E-07
/// when the lookback is what held it down.
String confidenceReason(ConfidenceScore score) {
  final months = '${score.dataPoints} month${score.dataPoints == 1 ? '' : 's'}';
  if (score.isCappedByLookback) {
    return 'Capped at Medium: ${score.lookbackMonths} months of history, '
        '24 needed for High';
  }
  final cv = score.coefficientOfVariation;
  final variance = cv < 0.25
      ? 'steady'
      : cv < 0.5
      ? 'varies'
      : 'varies a lot';
  return '$months of data, $variance';
}

/// `Sep` for month 9 — the seasonal months a category spikes in.
String monthAbbreviation(int month) =>
    DateFormat.MMM().format(DateTime(2000, month));

/// FR-PLN-013's colour for [status]: green, yellow, red — drawn from the
/// theme's semantic set rather than `Colors.*`, so both themes keep the
/// contrast `AppColors` was verified for. Green is the income colour,
/// yellow the accent, red the expense colour.
Color trackingColour(ThemeData theme, TrackingStatus status) {
  final colors = theme.extension<AppColors>()!;
  return switch (status) {
    TrackingStatus.onTrack => colors.income,
    TrackingStatus.warning => colors.accent,
    TrackingStatus.exceeded => colors.expense,
  };
}

/// One line under a row: `Rs1,000.00 spent · 33% · heading Rs500.00
/// under`. FR-PLN-013's percentage and projection.
///
/// The projection names the direction in words rather than with a sign,
/// and says "on budget" at exactly zero; before the period starts there
/// is nothing to project and the line stops at the percentage. Once the
/// period has ended the figure is final, not a forecast: "ended", not
/// "heading".
String trackingLabel(AllocationProgress p) {
  final head =
      '${formatCents(p.allocation.spentCents)} spent · ${p.percentUsed}%';
  final verb = p.ended ? 'ended' : 'heading';
  return switch (p.projectedDifferenceCents) {
    null => head,
    0 => '$head · $verb on budget',
    final d when d > 0 => '$head · $verb ${formatCents(d)} over',
    final d => '$head · $verb ${formatCents(-d)} under',
  };
}

/// How a comparison's difference reads: `Rs500.00 more`, `Rs500.00 less`,
/// `the same`. FR-PLN-015.
String differenceLabel(int cents) => switch (cents) {
  0 => 'the same',
  > 0 => '${formatCents(cents)} more',
  _ => '${formatCents(-cents)} less',
};

/// Why there is no suggested plan yet, in one or two sentences. E-39.
///
/// Says what is missing and when it will not be, so "not enough history"
/// reads as a stage the app is in rather than a fault.
String planHistoryExplanation(PlanHistory history) {
  String expenses(int n) => '$n expense${n == 1 ? '' : 's'}';
  final monthEnds = DateFormat.MMMMd().format(history.thisMonthEnds);
  if (history.isEmpty) {
    return 'You have not recorded any spending yet. Once there is a full '
        'month of it, Moneyora can suggest a plan from how you actually '
        'spend.';
  }
  if (history.expenses == 0) {
    return 'Moneyora learns from whole months, and this one is not over. '
        'Your ${expenses(history.expensesThisMonth)} this month start '
        'counting after $monthEnds.';
  }
  final months = history.window.months;
  return 'There ${history.expenses == 1 ? 'is' : 'are'} '
      '${expenses(history.expenses)} in the last '
      '${months == 1 ? 'month' : '$months months'}. Moneyora needs at least '
      '${PlanHistory.minExpenses} to suggest a plan you can rely on.';
}
