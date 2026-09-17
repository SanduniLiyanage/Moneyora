/// Persistence mapping for [ExchangeRate], following `user_settings_model.dart`.
library;

import '../../domain/entities/exchange_rate.dart';

/// An [ExchangeRate] that can be written to and read from `exchange_rates`.
class ExchangeRateModel extends ExchangeRate {
  /// Creates a model directly. Prefer [fromEntity] or [fromMap].
  const ExchangeRateModel({
    required super.fromCurrency,
    required super.toCurrency,
    required super.rateMicros,
    required super.updatedAt,
  });

  /// Wraps an entity so it can be written.
  factory ExchangeRateModel.fromEntity(ExchangeRate rate) => ExchangeRateModel(
    fromCurrency: rate.fromCurrency,
    toCurrency: rate.toCurrency,
    rateMicros: rate.rateMicros,
    updatedAt: rate.updatedAt,
  );

  /// Rebuilds a model from an `exchange_rates` row.
  factory ExchangeRateModel.fromMap(Map<String, Object?> map) =>
      ExchangeRateModel(
        fromCurrency: map['from_currency']! as String,
        toCurrency: map['to_currency']! as String,
        rateMicros: map['rate_micros']! as int,
        updatedAt: DateTime.parse(map['updated_at']! as String),
      );

  /// The row to write.
  Map<String, Object?> toMap() => <String, Object?>{
    'from_currency': fromCurrency,
    'to_currency': toCurrency,
    'rate_micros': rateMicros,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// A plain entity, safe to hand to the domain layer.
  ExchangeRate toEntity() => ExchangeRate(
    fromCurrency: fromCurrency,
    toCurrency: toCurrency,
    rateMicros: rateMicros,
    updatedAt: updatedAt,
  );
}
