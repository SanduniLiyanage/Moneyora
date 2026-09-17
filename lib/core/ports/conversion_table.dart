import 'package:equatable/equatable.dart';

import 'exchange_rate.dart';

/// The base currency and every rate the user has entered, as one value.
/// FR-ACC-005, FR-SET-003, E-34.
///
/// What a total needs in order to add accounts held in different
/// currencies: which currency the answer is in, and how to get each balance
/// there. Both come from the settings feature; both are read by the accounts
/// feature and the transfer screen. So the value lives in `core/ports/`, the
/// way [ExchangeRate] does, and [ConversionReader] is the seam.
class ConversionTable extends Equatable {
  /// Creates a table.
  const ConversionTable({required this.baseCurrency, this.rates = const []});

  /// ISO 4217 code of the currency totals are expressed in. Upper case.
  final String baseCurrency;

  /// Every rate the user has entered, in any direction.
  final List<ExchangeRate> rates;

  /// The stored rate from [fromCurrency] to [toCurrency], if there is one.
  ExchangeRate? rateFor({
    required String fromCurrency,
    required String toCurrency,
  }) {
    final from = _code(fromCurrency);
    final to = _code(toCurrency);
    for (final rate in rates) {
      if (rate.fromCurrency == from && rate.toCurrency == to) return rate;
    }
    return null;
  }

  /// Converts [cents] of [currency] into [baseCurrency], or null when there
  /// is no rate to convert at.
  ///
  /// Null is the E-25 fallback, not an error: an account without a rate is
  /// shown in its own currency and left out of the total, and the screen
  /// says so (E-34). A balance already in the base currency needs no rate.
  int? toBase(int cents, String currency) {
    final code = _code(currency);
    if (code == baseCurrency) return cents;
    return rateFor(
      fromCurrency: code,
      toCurrency: baseCurrency,
    )?.convert(cents);
  }

  static String _code(String raw) => raw.trim().toUpperCase();

  @override
  List<Object?> get props => [baseCurrency, rates];
}
