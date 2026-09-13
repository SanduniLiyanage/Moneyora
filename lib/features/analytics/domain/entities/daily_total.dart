import 'package:equatable/equatable.dart';

/// What was spent on one day, every category added together. FR-RPT-009.
///
/// The unit `AnalyticsRepository.dailySpendingTotals` returns. Sparse, like
/// `TrendPoint`: a day with nothing spent has no row, and `GetSpendingCalendar`
/// is what fills the month in.
class DailyTotal extends Equatable {
  /// Creates a total.
  const DailyTotal({required this.date, required this.amountCents});

  /// The calendar day, at midnight.
  final DateTime date;

  /// What was spent that day, in integer minor units (E-06). Always positive.
  final int amountCents;

  @override
  List<Object?> get props => [date, amountCents];
}
