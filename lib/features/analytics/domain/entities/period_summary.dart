import 'package:equatable/equatable.dart';

import 'category_total.dart';

/// The headline figures for a period. FR-RPT-006.
///
/// Integer minor units throughout, as every amount is (E-06); the one
/// ratio, the change against the previous period, is a whole percentage
/// computed in integers and rounded toward zero.
class PeriodSummary extends Equatable {
  /// Creates a summary.
  const PeriodSummary({
    required this.incomeCents,
    required this.expenseCents,
    required this.averageDailySpendCents,
    required this.largestCategory,
    required this.previousExpenseCents,
  });

  /// Money in over the period.
  final int incomeCents;

  /// Money out over the period, transfers excluded (E-02).
  final int expenseCents;

  /// [incomeCents] less [expenseCents]; negative when more went out.
  int get netSavingsCents => incomeCents - expenseCents;

  /// Spending per day over the days of the period that have happened, or
  /// null when there are none to divide by — all time, or a period that has
  /// not started.
  final int? averageDailySpendCents;

  /// Where the most went, or null when nothing was spent.
  final CategoryTotal? largestCategory;

  /// Spending in the period before, or null when there is no period before
  /// (all time).
  final int? previousExpenseCents;

  /// The change in spending against the period before, as a whole
  /// percentage — or null when there is nothing to compare with: no period
  /// before, or nothing spent in it, where any change is infinite.
  int? get expenseChangePercent {
    final before = previousExpenseCents;
    if (before == null || before == 0) return null;
    return (expenseCents - before) * 100 ~/ before;
  }

  @override
  List<Object?> get props => [
    incomeCents,
    expenseCents,
    averageDailySpendCents,
    largestCategory,
    previousExpenseCents,
  ];
}
