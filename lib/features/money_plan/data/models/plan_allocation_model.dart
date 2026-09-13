import '../../domain/entities/category_classification.dart';
import '../../domain/entities/confidence_score.dart';
import '../../domain/entities/plan_allocation.dart';

/// Persistence mapping for [PlanAllocation]. FR-PLN-007, FR-PLN-010.
///
/// The stored strings for [ConfidenceLevel] and [ExpenseType] live here,
/// not on the enums: what the schema calls them is the data layer's
/// business, and the domain does not know there is a schema. They are the
/// enum names as `v1_initial.dart` wrote them — lowercase, like every other
/// check constraint in the schema (the DBD capitalised them, and called the
/// class column `expense_type`; the schema as built is what is mapped).
class PlanAllocationModel extends PlanAllocation {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const PlanAllocationModel({
    required super.categoryId,
    required super.allocatedCents,
    required super.confidence,
    super.id,
    super.categoryName,
    super.spentCents,
    super.expenseType,
    super.isUserModified,
    super.notes,
  });

  /// Wraps an entity so it can be written.
  factory PlanAllocationModel.fromEntity(PlanAllocation a) =>
      PlanAllocationModel(
        id: a.id,
        categoryId: a.categoryId,
        categoryName: a.categoryName,
        allocatedCents: a.allocatedCents,
        spentCents: a.spentCents,
        confidence: a.confidence,
        expenseType: a.expenseType,
        isUserModified: a.isUserModified,
        notes: a.notes,
      );

  /// Rebuilds a model from a `plan_allocations` row joined to `categories`
  /// for its `category_name`.
  factory PlanAllocationModel.fromMap(Map<String, Object?> map) =>
      PlanAllocationModel(
        id: map['id'] as int?,
        categoryId: map['category_id']! as int,
        categoryName: map['category_name'] as String?,
        allocatedCents: map['allocated_amount_cents']! as int,
        spentCents: map['spent_amount_cents']! as int,
        confidence: decodeConfidence(map['confidence_level']! as String),
        expenseType: switch (map['expense_class']) {
          final String s => decodeExpenseType(s),
          _ => null,
        },
        isUserModified: map['is_user_modified'] == 1,
        notes: map['notes'] as String?,
      );

  /// The row to insert under [planId]. `spent_amount_cents` starts at 0 and
  /// is moved by FR-PLN-013, never written here.
  Map<String, Object?> toMap(int planId) => {
    'plan_id': planId,
    'category_id': categoryId,
    'allocated_amount_cents': allocatedCents,
    'spent_amount_cents': spentCents,
    'confidence_level': encodeConfidence(confidence),
    'expense_class': expenseType == null
        ? null
        : encodeExpenseType(expenseType!),
    'is_user_modified': isUserModified ? 1 : 0,
    'notes': notes,
  };

  /// The columns FR-PLN-011 rewrites.
  Map<String, Object?> toAllocationUpdateMap() => {
    'allocated_amount_cents': allocatedCents,
    'is_user_modified': isUserModified ? 1 : 0,
  };

  /// `confidence_level`'s stored form.
  static String encodeConfidence(ConfidenceLevel level) => level.name;

  /// [ConfidenceLevel] from its stored form.
  static ConfidenceLevel decodeConfidence(String value) =>
      ConfidenceLevel.values.byName(value);

  /// `expense_class`'s stored form.
  static String encodeExpenseType(ExpenseType type) => type.name;

  /// [ExpenseType] from its stored form.
  static ExpenseType decodeExpenseType(String value) =>
      ExpenseType.values.byName(value);

  /// Converts back at the repository boundary: Equatable compares
  /// `runtimeType`, so a model handed upward never equals an entity.
  PlanAllocation toEntity() => PlanAllocation(
    id: id,
    categoryId: categoryId,
    categoryName: categoryName,
    allocatedCents: allocatedCents,
    spentCents: spentCents,
    confidence: confidence,
    expenseType: expenseType,
    isUserModified: isUserModified,
    notes: notes,
  );
}
