import 'package:equatable/equatable.dart';

import 'category_classification.dart';
import 'category_statistics.dart';
import 'confidence_score.dart';

/// What one category is allocated for a plan period, how it got there, and
/// how far to trust it. FR-PLN-007, FR-PLN-009, FR-PLN-010.
///
/// Every factor is carried so the wizard can explain the number —
/// *"Rs 45,000 a month, ×1.08 because this is rising"* — rather than show a
/// figure the user cannot interrogate.
class CategoryAllocation extends Equatable {
  /// Creates an allocation.
  const CategoryAllocation({
    required this.classification,
    required this.baseMonthlyCents,
    required this.seasonalFactor,
    required this.trendFactor,
    required this.allocationCents,
    required this.dailyAllowanceCents,
    required this.confidence,
  });

  /// The class and statistics the allocation was derived from.
  final CategoryClassification classification;

  /// The monthly figure before any adjustment: the recent average for a
  /// Fixed category, the weighted moving average otherwise.
  final int baseMonthlyCents;

  /// How much the seasonal months in the period raised the allocation over
  /// the base — *"×6 this month against your usual"* — weighted across the
  /// months covered; 1.0 when none of them is a spike month.
  final double seasonalFactor;

  /// 1.08 rising, 0.95 falling, 1.0 flat — by the trend, whatever the class.
  final double trendFactor;

  /// The allocation for the whole period, after every factor and, under a
  /// total-budget mode, after scaling to the total.
  final int allocationCents;

  /// [allocationCents] per day of the period, floored — following it every
  /// day cannot overspend the allocation. FR-PLN-009.
  final int dailyAllowanceCents;

  /// How far to trust the figure, and why. FR-PLN-010. Unchanged by the
  /// total-budget modes: scaling to a total says nothing about the data.
  final ConfidenceScore confidence;

  /// The category.
  int get categoryId => classification.categoryId;

  /// The category's display name.
  String get name => classification.name;

  /// Fixed, Variable or Seasonal.
  ExpenseType get type => classification.type;

  /// The statistics beneath it.
  CategoryStatistics get statistics => classification.statistics;

  /// This allocation at [allocationCents] instead, the daily allowance
  /// following it. The total-budget modes scale through here.
  CategoryAllocation withAllocation(int allocationCents, {required int days}) =>
      CategoryAllocation(
        classification: classification,
        baseMonthlyCents: baseMonthlyCents,
        seasonalFactor: seasonalFactor,
        trendFactor: trendFactor,
        allocationCents: allocationCents,
        dailyAllowanceCents: days > 0 ? allocationCents ~/ days : 0,
        confidence: confidence,
      );

  @override
  List<Object?> get props => [
    classification,
    baseMonthlyCents,
    seasonalFactor,
    trendFactor,
    allocationCents,
    dailyAllowanceCents,
    confidence,
  ];
}
