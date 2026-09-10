import 'package:equatable/equatable.dart';

/// Which side of the ledger a category classifies. FR-EXP-003, FR-INC-002.
enum CategoryType {
  /// Money going out - Food, Bills, Transport.
  expense('expense'),

  /// Money coming in - Salary, Gifts received.
  income('income');

  const CategoryType(this.storageValue);

  /// The exact string the schema's `CHECK` constraint permits.
  final String storageValue;
}

/// What an expense or income was for - Food, Bills, Salary. FR-EXP-004.
///
/// A **category** is *what* money was spent or earned on. An **account** is
/// *where* it sits, and a transfer touches neither (E-17).
class Category extends Equatable {
  /// Creates a category.
  const Category({
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.type,
    this.id,
    this.parentId,
    this.isDefault = false,
    this.sortOrder = 0,
  });

  /// Row id, null before it is saved.
  final int? id;

  /// What the user calls it.
  final String name;

  /// Icon key, e.g. `basket`.
  final String icon;

  /// `#RRGGBB`, for the chip and the donut chart.
  final String colorHex;

  /// Expense or income. A picker shows one set or the other, never both -
  /// the same reasoning as `CategoryOption.isExpense` in the catalog this
  /// slice replaces.
  final CategoryType type;

  /// The category this is a child of, or null for a top-level category.
  ///
  /// FR-EXP-005 caps hierarchy at one level: a category whose [parentId] is
  /// non-null may not itself be named as a parent. The schema cannot express
  /// that - `categories.parent_id` references `categories.id` with no depth
  /// limit - so the use cases enforce it.
  final int? parentId;

  /// Seeded by `default_seed.dart` (FR-EXP-003). Not otherwise protected:
  /// the same "refuse once it's in use" rule that guards a custom category
  /// guards a default one, rather than a separate lock nothing asked for.
  final bool isDefault;

  /// Display order within its type/parent. Lower sorts first.
  final int sortOrder;

  /// Whether this is a sub-category of another.
  bool get isChild => parentId != null;

  /// A copy with the given fields replaced.
  Category copyWith({
    int? id,
    String? name,
    String? icon,
    String? colorHex,
    CategoryType? type,
    int? parentId,
    bool? isDefault,
    int? sortOrder,
  }) => Category(
    id: id ?? this.id,
    name: name ?? this.name,
    icon: icon ?? this.icon,
    colorHex: colorHex ?? this.colorHex,
    type: type ?? this.type,
    parentId: parentId ?? this.parentId,
    isDefault: isDefault ?? this.isDefault,
    sortOrder: sortOrder ?? this.sortOrder,
  );

  @override
  List<Object?> get props => [
    id,
    name,
    icon,
    colorHex,
    type,
    parentId,
    isDefault,
    sortOrder,
  ];
}
