import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/trend_point.dart';

/// A [TrendPoint] as the bucketed aggregate query returns it. FR-RPT-005.
///
/// Read-only, like [CategoryTotalModel]: nothing writes a point, it is
/// derived from the rows every time it is asked for.
class TrendPointModel extends TrendPoint {
  /// Creates a model.
  const TrendPointModel({
    required super.bucket,
    required super.categoryId,
    required super.name,
    required super.color,
    required super.amountCents,
  });

  /// Reads one row of the aggregate.
  ///
  /// `bucket` arrives as a `YYYY-MM-DD` string whichever granularity cut it
  /// — the statement pads a month bucket out to its first day — so there is
  /// one decode here rather than one per granularity. It is [decodeIsoDay]
  /// rather than `DateTime.parse` because this model is built a few hundred
  /// times per query, not once: the general parser was measured at 7ms for
  /// 360 rows on the test VM, against 11ms for the SQL itself.
  ///
  /// `SUM()` returns `num` rather than `int` in SQLite's type system, so the
  /// cast is explicit for the same reason it is in [CategoryTotalModel].
  factory TrendPointModel.fromMap(Map<String, Object?> map) => TrendPointModel(
    bucket: decodeIsoDay(map['bucket']! as String),
    categoryId: map['category_id']! as int,
    name: map['name']! as String,
    color: map['color']! as String,
    amountCents: (map['total_cents']! as num).toInt(),
  );
}
