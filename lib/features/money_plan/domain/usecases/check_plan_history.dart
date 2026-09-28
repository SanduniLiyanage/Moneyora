import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/monthly_spending_reader.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/lookback_window.dart';
import '../entities/plan_history.dart';

/// The window to measure, and today.
class PlanHistoryQuery extends Equatable {
  /// Creates a query.
  const PlanHistoryQuery({required this.window, required this.today});

  /// The months the generator would read.
  final LookbackWindow window;

  /// Today, so this month's spending can be counted apart.
  final DateTime today;

  @override
  List<Object?> get props => [
    window,
    DateTime(today.year, today.month, today.day),
  ];
}

/// Whether there is enough of the user's own spending to suggest a plan
/// from. FR-PLN-003, E-39.
///
/// Asked before the generator runs, so the wizard can say plainly why it
/// will not suggest a plan yet and offer to build one by hand, rather than
/// generating from a handful of expenses and presenting the result as
/// though it knew the user.
///
/// One read over the window and on to today, through the port the
/// generator's own statistics use, so the two count the same expenses.
class CheckPlanHistory implements UseCase<PlanHistory, PlanHistoryQuery> {
  /// Creates the use case.
  const CheckPlanHistory(this._reader);

  final MonthlySpendingReader _reader;

  @override
  Future<Either<Failure, PlanHistory>> call(PlanHistoryQuery params) async {
    final window = params.window;
    final today = params.today;
    final end = today.isAfter(window.to) ? today : window.to;
    final rows = await _reader.monthlySpendingByCategory(
      from: window.from,
      to: end,
    );
    return rows.map((rows) {
      var expenses = 0;
      var later = 0;
      final months = <DateTime>{};
      for (final r in rows) {
        if (window.indexOf(r.month) >= 0) {
          expenses += r.transactionCount;
          if (r.amountCents > 0) {
            months.add(DateTime(r.month.year, r.month.month));
          }
        } else if (r.month.isAfter(window.to)) {
          later += r.transactionCount;
        }
      }
      return PlanHistory(
        window: window,
        expenses: expenses,
        monthsWithSpending: months.length,
        expensesThisMonth: later,
        thisMonthEnds: DateTime(today.year, today.month + 1, 0),
      );
    });
  }
}
