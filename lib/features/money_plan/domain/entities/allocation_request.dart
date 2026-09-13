import 'package:equatable/equatable.dart';

import 'budget_mode.dart';
import 'lookback_window.dart';
import 'plan_period.dart';

/// What the generator is asked for: a period to plan, a history to plan it
/// from, and how to decide the total. FR-PLN-002, FR-PLN-003, FR-PLN-008.
class AllocationRequest extends Equatable {
  /// Creates a request.
  const AllocationRequest({
    required this.period,
    required this.lookback,
    this.mode = const BudgetMode.unconstrained(),
  });

  /// The days to plan.
  final PlanPeriod period;

  /// The months to learn from.
  final LookbackWindow lookback;

  /// How the total is decided.
  final BudgetMode mode;

  @override
  List<Object?> get props => [period, lookback, mode];
}
