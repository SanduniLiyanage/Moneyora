import 'package:equatable/equatable.dart';

import 'lookback_window.dart';

/// How much of the user's own spending the generator has to learn from.
/// FR-PLN-003, E-39.
///
/// The generator learns from whole months before the current one
/// ([LookbackWindow.before]), so spending recorded this month does not count
/// yet; it is held apart as [expensesThisMonth] so the screen can say when
/// it will.
class PlanHistory extends Equatable {
  /// Creates the history's measure.
  const PlanHistory({
    required this.window,
    required this.expenses,
    required this.monthsWithSpending,
    required this.expensesThisMonth,
    required this.thisMonthEnds,
  });

  /// The fewest expenses in the window a suggested plan is built from.
  /// Fewer, and a handful of purchases decides every category's figure.
  static const int minExpenses = 10;

  /// The fewest whole months with spending a suggested plan is built from.
  static const int minMonths = 1;

  /// The months the generator would read.
  final LookbackWindow window;

  /// Expenses recorded in [window], split parts counted once per part.
  final int expenses;

  /// Months of [window] with any spending.
  final int monthsWithSpending;

  /// Expenses recorded since the window ended — this month's, so far.
  final int expensesThisMonth;

  /// The last day of the current month: when this month's spending joins
  /// the history.
  final DateTime thisMonthEnds;

  /// Whether the generator has enough to suggest a plan.
  bool get isEnough =>
      monthsWithSpending >= minMonths && expenses >= minExpenses;

  /// True when nothing at all has been recorded, in the window or since.
  bool get isEmpty => expenses == 0 && expensesThisMonth == 0;

  @override
  List<Object?> get props => [
    window,
    expenses,
    monthsWithSpending,
    expensesThisMonth,
    thisMonthEnds,
  ];
}
