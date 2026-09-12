import 'package:equatable/equatable.dart';

/// How one category's spending moved between two periods.
///
/// The unit [ComparePeriods] returns: one row per category that had spending
/// in either period, carrying the later period's total minus the earlier
/// one's. Unlike [CategoryTotal.amountCents], [deltaCents] may be negative —
/// a category spent less in the later period than the earlier one is exactly
/// as real an answer as one spent more.
class CategoryDelta extends Equatable {
  /// Creates a delta for one category.
  const CategoryDelta({
    required this.categoryId,
    required this.name,
    required this.color,
    required this.deltaCents,
  });

  /// The category this delta belongs to.
  final int categoryId;

  /// The category's display name, e.g. `Food`.
  final String name;

  /// The category's colour as stored, e.g. `#FF7043`.
  final String color;

  /// The later period's total minus the earlier period's, in integer minor
  /// units (E-06). Positive means spending rose; negative means it fell.
  final int deltaCents;

  @override
  List<Object?> get props => [categoryId, name, color, deltaCents];
}
