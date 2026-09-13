import '../../../../core/utils/date_utils.dart';
import '../../domain/entities/daily_total.dart';

/// A [DailyTotal] as the per-day aggregate query returns it. FR-RPT-009.
///
/// Read-only, like [TrendPointModel]: derived from the rows every time it is
/// asked for.
class DailyTotalModel extends DailyTotal {
  /// Creates a model.
  const DailyTotalModel({required super.date, required super.amountCents});

  /// Reads one row of the aggregate. [decodeIsoDay] and the explicit `num`
  /// cast for the reasons [TrendPointModel.fromMap] gives.
  factory DailyTotalModel.fromMap(Map<String, Object?> map) => DailyTotalModel(
    date: decodeIsoDay(map['date']! as String),
    amountCents: (map['total_cents']! as num).toInt(),
  );
}
