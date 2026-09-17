import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/exchange_rate.dart';
import '../repositories/exchange_rate_repository.dart';

/// Stores a user-entered exchange rate. FR-SET-003, FR-ACC-005, E-34.
///
/// "User-configurable" in the SRS means a table the user edits, not a fetch:
/// the rate a bank actually applies is on the statement, and this is where
/// the user writes it down. Storing a pair that already has a rate replaces
/// it — there is one rate per pair, and the newest is the one that counts.
class SetExchangeRate implements UseCase<Unit, ExchangeRate> {
  /// Creates the use case.
  const SetExchangeRate(this._repository);

  final ExchangeRateRepository _repository;

  @override
  Future<Either<Failure, Unit>> call(ExchangeRate params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    return _repository.set(
      ExchangeRate(
        fromCurrency: _code(params.fromCurrency),
        toCurrency: _code(params.toCurrency),
        rateMicros: params.rateMicros,
        updatedAt: params.updatedAt,
      ),
    );
  }

  /// Returns the reason [rate] is invalid, or null if it is fine.
  ///
  /// Public and static so the rates screen can check as the user types,
  /// rather than discovering the problem only when Save fails. The schema
  /// refuses the same things with a constraint error; this produces a
  /// sentence.
  static ValidationFailure? validate(ExchangeRate rate) {
    final from = _code(rate.fromCurrency);
    final to = _code(rate.toCurrency);

    if (!_isCode(from)) {
      return const ValidationFailure(
        'Enter a three-letter currency code, like USD.',
        field: 'fromCurrency',
      );
    }
    if (!_isCode(to)) {
      return const ValidationFailure(
        'Enter a three-letter currency code, like LKR.',
        field: 'toCurrency',
      );
    }
    if (from == to) {
      return const ValidationFailure(
        'Choose two different currencies — a currency is always worth itself.',
        field: 'toCurrency',
      );
    }
    if (rate.rateMicros <= 0) {
      return const ValidationFailure(
        'Enter a rate greater than zero.',
        field: 'rate',
      );
    }
    return null;
  }

  static String _code(String raw) => raw.trim().toUpperCase();

  static bool _isCode(String code) =>
      code.length == 3 && RegExp(r'^[A-Z]{3}$').hasMatch(code);
}
