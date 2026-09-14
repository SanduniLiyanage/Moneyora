import 'package:equatable/equatable.dart';

import 'category_classification.dart';
import 'confidence_score.dart';

/// One category's row of a saved plan. FR-PLN-007, FR-PLN-010, FR-PLN-011,
/// FR-PLN-014.
///
/// What `plan_allocations` holds: the figure, its provenance (class and
/// confidence, so the screen can still say why), whether the user changed
/// it, the spend cache FR-PLN-013 maintains, and the overspend the user
/// chose to carry into the next plan. Not the statistics — those are
/// re-derived from history whenever a plan is generated, and a saved plan
/// is a decision, not a dataset.
class PlanAllocation extends Equatable {
  /// Creates an allocation row.
  const PlanAllocation({
    required this.categoryId,
    required this.allocatedCents,
    required this.confidence,
    this.id,
    this.categoryName,
    this.spentCents = 0,
    this.carryOverCents = 0,
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

  /// What has been spent against it so far. FR-PLN-013's cache, recounted
  /// from history when the plan becomes active.
  final int spentCents;

  /// The overspend the user chose to deduct from this category in the next
  /// plan — FR-PLN-014's Carry Over. Zero until they choose it; the whole
  /// overspend at the time they did, not a running sum.
  final int carryOverCents;

  /// FR-PLN-010's level.
  final ConfidenceLevel confidence;

  /// FR-PLN-004's class, when the generator decided one.
  final ExpenseType? expenseType;

  /// True once the user has changed [allocatedCents] by hand. FR-PLN-011.
  final bool isUserModified;

  /// Free text, e.g. a suggestion note.
  final String? notes;

  /// What has been spent beyond the allocation; zero when within it.
  int get overspendCents =>
      spentCents > allocatedCents ? spentCents - allocatedCents : 0;

  /// What is left to spend; zero once exceeded.
  int get remainingCents =>
      allocatedCents > spentCents ? allocatedCents - spentCents : 0;

  /// This row at [allocatedCents] instead, marked as changed by the user
  /// when [byUser].
  PlanAllocation withAllocated(int allocatedCents, {bool byUser = false}) =>
      PlanAllocation(
        id: id,
        categoryId: categoryId,
        categoryName: categoryName,
        allocatedCents: allocatedCents,
        spentCents: spentCents,
        carryOverCents: carryOverCents,
        confidence: confidence,
        expenseType: expenseType,
        isUserModified: isUserModified || byUser,
        notes: notes,
      );

  /// This row carrying [carryOverCents] into the next plan. FR-PLN-014.
  PlanAllocation withCarryOver(int carryOverCents) => PlanAllocation(
    id: id,
    categoryId: categoryId,
    categoryName: categoryName,
    allocatedCents: allocatedCents,
    spentCents: spentCents,
    carryOverCents: carryOverCents,
    confidence: confidence,
    expenseType: expenseType,
    isUserModified: isUserModified,
    notes: notes,
  );

  @override
  List<Object?> get props => [
    id,
    categoryId,
    categoryName,
    allocatedCents,
    spentCents,
    carryOverCents,
    confidence,
    expenseType,
    isUserModified,
    notes,
  ];
}
