import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/exchange_rate.dart';
import '../repositories/exchange_rate_repository.dart';

/// Every stored exchange rate, kept live. FR-SET-003.
class WatchExchangeRates
    implements StreamUseCase<List<ExchangeRate>, NoParams> {
  /// Creates the use case.
  const WatchExchangeRates(this._repository);

  final ExchangeRateRepository _repository;

  @override
  Stream<Either<Failure, List<ExchangeRate>>> call(NoParams params) =>
      _repository.watch();
}
