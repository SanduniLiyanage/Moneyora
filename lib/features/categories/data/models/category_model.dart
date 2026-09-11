/// Persistence mapping for [Category].
///
/// Follows the shape `account_model.dart` established: `Equatable` compares
/// `runtimeType`, so a model never equals an identical entity and
/// [CategoryModel.toEntity] exists to convert at the repository boundary.
/// Unlike accounts, `categories` carries no `created_at` column - nothing
/// reads one, so none is added.
library;

import '../../domain/entities/category.dart';

/// A [Category] that can be written to and read from SQLite.
class CategoryModel extends Category {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const CategoryModel({
    required super.name,
    required super.icon,
    required super.colorHex,
    required super.type,
    super.id,
    super.parentId,
    super.isDefault,
    super.sortOrder,
    this.userId = 1,
  });

  /// Wraps an entity so it can be written.
  factory CategoryModel.fromEntity(Category category, {int userId = 1}) =>
      CategoryModel(
        id: category.id,
        name: category.name,
        icon: category.icon,
        colorHex: category.colorHex,
        type: category.type,
        parentId: category.parentId,
        isDefault: category.isDefault,
        sortOrder: category.sortOrder,
        userId: userId,
      );

  /// Rebuilds a model from a `categories` row.
  factory CategoryModel.fromMap(Map<String, Object?> map) => CategoryModel(
    id: map['id'] as int?,
    name: map['name']! as String,
    icon: map['icon']! as String,
    colorHex: map['color']! as String,
    type: _decodeType(map['type']! as String),
    parentId: map['parent_id'] as int?,
    isDefault: map['is_default'] == 1,
    sortOrder: map['sort_order']! as int,
    userId: map['user_id']! as int,
  );

  /// The owning user. Single-user today; the column exists for FR-SET-009.
  final int userId;

  /// The row to write to `categories`.
  Map<String, Object?> toMap() => <String, Object?>{
    if (id != null) 'id': id,
    'user_id': userId,
    'name': name.trim(),
    'icon': icon,
    'color': colorHex,
    'type': type.storageValue,
    'parent_id': parentId,
    'is_default': isDefault ? 1 : 0,
    'sort_order': sortOrder,
  };

  /// The columns an edit may change.
  ///
  /// Omits `user_id` and `is_default` - neither is something an edit form
  /// offers, the same reasoning `AccountModel.toUpdateMap` applies to
  /// `current_balance_cents`.
  Map<String, Object?> toUpdateMap() => <String, Object?>{
    'name': name.trim(),
    'icon': icon,
    'color': colorHex,
    'type': type.storageValue,
    'parent_id': parentId,
    'sort_order': sortOrder,
  };

  /// A plain entity, safe to hand to the domain layer.
  Category toEntity() => Category(
    id: id,
    name: name,
    icon: icon,
    colorHex: colorHex,
    type: type,
    parentId: parentId,
    isDefault: isDefault,
    sortOrder: sortOrder,
  );

  /// Decodes the column's string, which is not the enum's `name`.
  static CategoryType _decodeType(String value) =>
      CategoryType.values.firstWhere(
        (t) => t.storageValue == value,
        orElse: () => throw FormatException('Unknown category type', value),
      );
}
