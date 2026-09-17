import 'package:equatable/equatable.dart';

/// How much of one currency a unit of another is worth. FR-ACC-005, E-34.
///
/// Lives in `core/ports/` rather than the settings feature, the way
/// [AccountType] does, because two features need it: settings edits rates
/// and accounts converts balances with them (FR-ACC-005). The settings
/// feature re-exports it from its entities, so inside that feature it reads
/// as its own.
///
/// [rateMicros] is an integer scaled by 10⁶: the money-is-integers rule
/// (E-06) extended to the thing money is multiplied by. `1 [fromCurrency]`
/// is worth `rateMicros / 1,000,000 [toCurrency]`. Keyed by the ordered
/// pair, never by "against the base", so that changing the base currency
/// cannot silently change what a stored rate means.
class ExchangeRate extends Equatable {
  /// Creates a rate.
  const ExchangeRate({
    required this.fromCurrency,
    required this.toCurrency,
    required this.rateMicros,
    required this.updatedAt,
  });

  /// The scale of [rateMicros]: one unit of the rate.
  static const int micro = 1000000;

  /// ISO 4217 code of the currency being converted from.
  final String fromCurrency;

  /// ISO 4217 code of the currency being converted to.
  final String toCurrency;

  /// The rate, scaled by [micro]. Always positive.
  final int rateMicros;

  /// When the user last set it.
  final DateTime updatedAt;

  /// The rate as a number, for display only. Never do arithmetic with this.
  double get rate => rateMicros / micro;

  /// Converts [cents] of [fromCurrency] into cents of [toCurrency].
  ///
  /// Rounded to the nearest cent, halves away from zero, over `BigInt` so a
  /// large balance at a large rate cannot overflow silently. Negative input
  /// converts to negative output: a credit card owing dollars owes rupees.
  int convert(int cents) {
    final product = BigInt.from(cents) * BigInt.from(rateMicros);
    final scale = BigInt.from(micro);
    final half = scale >> 1;
    final magnitude = (product.abs() + half) ~/ scale;
    return (product.isNegative ? -magnitude : magnitude).toInt();
  }

  @override
  List<Object?> get props => [fromCurrency, toCurrency, rateMicros, updatedAt];
}
