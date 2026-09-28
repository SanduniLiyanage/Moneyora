import 'package:equatable/equatable.dart';

import 'category_allocation.dart';
import 'category_classification.dart';
import 'confidence_score.dart';

/// What the generator suggested for one category, kept beside the figure
/// the user settles on so a saved row can still say where it came from.
/// FR-PLN-010, FR-PLN-011.
class PlanSuggestion extends Equatable {
  /// Creates a suggestion.
  const PlanSuggestion({
    required this.amountCents,
    required this.confidence,
    required this.type,
  });

  /// The generator's figure, in minor units.
  final int amountCents;

  /// How far the history behind it can be trusted.
  final ConfidenceLevel confidence;

  /// The category's class.
  final ExpenseType type;

  @override
  List<Object?> get props => [amountCents, confidence, type];
}

/// One category's line in a plan the user is building or editing.
/// FR-PLN-011, E-39.
///
/// A line from the generator carries its [suggestion]; one the user added
/// has none. Either way [amountCents] is what the user settled on.
class PlanLine extends Equatable {
  /// Creates a line.
  const PlanLine({
    required this.categoryId,
    required this.categoryName,
    required this.amountCents,
    this.suggestion,
  });

  /// A line holding the generator's own figure for [allocation].
  factory PlanLine.suggested(CategoryAllocation allocation) => PlanLine(
    categoryId: allocation.categoryId,
    categoryName: allocation.name,
    amountCents: allocation.allocationCents,
    suggestion: PlanSuggestion(
      amountCents: allocation.allocationCents,
      confidence: allocation.confidence.level,
      type: allocation.type,
    ),
  );

  /// The category budgeted.
  final int categoryId;

  /// Its name, for the screen.
  final String categoryName;

  /// The budget, in minor units. Zero leaves the category out of the plan.
  final int amountCents;

  /// What the generator suggested, or null for a line the user added.
  final PlanSuggestion? suggestion;

  /// True when the figure is the user's rather than the generator's.
  bool get isSetByUser =>
      suggestion == null || suggestion!.amountCents != amountCents;

  /// This line with a different [amountCents].
  PlanLine withAmount(int amountCents) => PlanLine(
    categoryId: categoryId,
    categoryName: categoryName,
    amountCents: amountCents,
    suggestion: suggestion,
  );

  @override
  List<Object?> get props => [
    categoryId,
    categoryName,
    amountCents,
    suggestion,
  ];
}
