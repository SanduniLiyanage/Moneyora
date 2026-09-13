import 'package:equatable/equatable.dart';

import 'category_statistics.dart';

/// How a category's spending behaves, for budgeting. FR-PLN-004.
///
/// Three values, matching `plan_allocations.expense_type`'s check
/// constraint; the data layer maps them to the stored strings.
enum ExpenseType {
  /// Recurs at much the same amount every month — rent, a subscription.
  fixed,

  /// Fluctuates month to month with no cycle to it — groceries, fuel.
  variable,

  /// Spikes in the same calendar month year after year — gifts in December.
  seasonal,
}

/// One category's [ExpenseType], and the evidence for it. FR-PLN-004.
///
/// Carries the [statistics] it was decided from rather than a category id,
/// because the allocator (FR-PLN-007) needs both — the class says which
/// formula, the statistics feed it.
class CategoryClassification extends Equatable {
  /// Creates a classification.
  const CategoryClassification({
    required this.statistics,
    required this.type,
    this.seasonalMonths = const [],
  });

  /// What the decision was made from.
  final CategoryStatistics statistics;

  /// The decision.
  final ExpenseType type;

  /// For [ExpenseType.seasonal], the calendar months (1–12) the spike
  /// recurs in, ascending — what lets the UI say *"you spend more every
  /// April"* (E-07). Empty otherwise.
  final List<int> seasonalMonths;

  /// The category this describes.
  int get categoryId => statistics.categoryId;

  /// The category's display name.
  String get name => statistics.name;

  @override
  List<Object?> get props => [statistics, type, seasonalMonths];
}
