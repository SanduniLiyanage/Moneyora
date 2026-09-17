import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/exchange_rate_repository.dart';

/// Which pair to forget. Input to [RemoveExchangeRate].
class CurrencyPair extends Equatable {
  /// Creates a pair.
  const CurrencyPair({required this.fromCurrency, required this.toCurrency});

  /// ISO 4217 code converted from.
  final String fromCurrency;

  /// ISO 4217 code converted to.
  final String toCurrency;

  @override
  List<Object?> get props => [fromCurrency, toCurrency];
}

/// Forgets a stored exchange rate. FR-SET-003.
///
/// Removing a rate is safe by construction: an account whose currency has
/// no rate to the base falls back to E-25's behaviour — shown in its own
/// currency, left out of the total, and said to be left out (E-34). Nothing
/// stored is converted at write time, so nothing already written changes.
class RemoveExchangeRate implements UseCase<Unit, CurrencyPair> {
  /// Creates the use case.
  const RemoveExchangeRate(this._repository);

  final ExchangeRateRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(CurrencyPair params) => _repository.remove(
    fromCurrency: params.fromCurrency.trim().toUpperCase(),
    toCurrency: params.toCurrency.trim().toUpperCase(),
  );
}
