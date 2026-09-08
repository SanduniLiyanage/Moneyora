import '../../domain/entities/category_total.dart';

/// A [CategoryTotal] as the aggregate query returns it.
///
/// Read-only: there is no `toMap`, because nothing writes a total. It is
/// derived from the rows every time it is asked for, which is the only way it
/// cannot drift from them.
class CategoryTotalModel extends CategoryTotal {
  /// Creates a model.
  const CategoryTotalModel({
    required super.categoryId,
    required super.name,
    required super.color,
    required super.amountCents,
  });

  /// Reads one row of the aggregate.
  ///
  /// `SUM()` returns `num` rather than `int` in SQLite's type system, so the
  /// cast is explicit: an implicit one would be the single place in this app
  /// where money could become a double.
  factory CategoryTotalModel.fromMap(Map<String, Object?> map) =>
      CategoryTotalModel(
        categoryId: map['category_id']! as int,
        name: map['name']! as String,
        color: map['color']! as String,
        amountCents: (map['total_cents']! as num).toInt(),
      );
}
