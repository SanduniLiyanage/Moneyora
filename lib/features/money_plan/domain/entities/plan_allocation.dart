import 'package:equatable/equatable.dart';

import 'category_classification.dart';
import 'confidence_score.dart';

/// One category's row of a saved plan. FR-PLN-007, FR-PLN-010, FR-PLN-011.
///
/// What `plan_allocations` holds: the figure, its provenance (class and
/// confidence, so the screen can still say why), whether the user changed
/// it, and the spend cache FR-PLN-013 will maintain. Not the statistics —
/// those are re-derived from history whenever a plan is generated, and a
/// saved plan is a decision, not a dataset.
class PlanAllocation extends Equatable {
  /// Creates an allocation row.
  const PlanAllocation({
    required this.categoryId,
    required this.allocatedCents,
    required this.confidence,
    this.id,
    this.categoryName,
    this.spentCents = 0,
    this.expenseType,
    this.isUserModified = false,
    this.notes,
  });

  /// Row id, null until saved.
  final int? id;

  /// The category budgeted.
  final int categoryId;

  /// The category's display name — read with the row, never written.
  final String? categoryName;

  /// The budget for the plan's whole period.
  final int allocatedCents;

  /// What has been spent against it so far. FR-PLN-013's cache; 0 on save.
  final int spentCents;

  /// FR-PLN-010's level.
  final ConfidenceLevel confidence;

  /// FR-PLN-004's class, when the generator decided one.
  final ExpenseType? expenseType;

  /// True once the user has changed [allocatedCents] by hand. FR-PLN-011.
  final bool isUserModified;

  /// Free text, e.g. a suggestion note.
  final String? notes;

  /// This row at [allocatedCents] instead, marked as changed by the user
  /// when [byUser].
  PlanAllocation withAllocated(int allocatedCents, {bool byUser = false}) =>
      PlanAllocation(
        id: id,
        categoryId: categoryId,
        categoryName: categoryName,
        allocatedCents: allocatedCents,
        spentCents: spentCents,
        confidence: confidence,
        expenseType: expenseType,
        isUserModified: isUserModified || byUser,
        notes: notes,
      );

  @override
  List<Object?> get props => [
    id,
    categoryId,
    categoryName,
    allocatedCents,
    spentCents,
    confidence,
    expenseType,
    isUserModified,
    notes,
  ];
}
