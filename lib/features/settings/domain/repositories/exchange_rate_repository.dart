import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../entities/exchange_rate.dart';

/// What the settings feature needs from the `exchange_rates` table. E-34.
abstract interface class ExchangeRateRepository {
  /// Every stored rate, kept live.
  Stream<Either<Failure, List<ExchangeRate>>> watch();

  /// Stores [rate], replacing any rate already held for the same pair.
  Future<Either<Failure, Unit>> set(ExchangeRate rate);

  /// Forgets the rate for the pair. Not an error if there was none.
  Future<Either<Failure, Unit>> remove({
    required String fromCurrency,
    required String toCurrency,
  });
}
