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
import '../../domain/entities/plan_period.dart';

/// One line for [period]: `September 2026`, `7 – 13 Sep 2026`, `2027`.
String planPeriodLabel(PlanPeriod period) => switch (period.type) {
  PlanPeriodType.day => DateFormat.yMMMMd().format(period.from),
  PlanPeriodType.month => DateFormat.yMMMM().format(period.from),
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
/// is nothing to project and the line stops at the percentage.
String trackingLabel(AllocationProgress p) {
  final head =
      '${formatCents(p.allocation.spentCents)} spent · ${p.percentUsed}%';
  return switch (p.projectedDifferenceCents) {
    null => head,
    0 => '$head · heading on budget',
    final d when d > 0 => '$head · heading ${formatCents(d)} over',
    final d => '$head · heading ${formatCents(-d)} under',
  };
}
