import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../repositories/analytics_repository.dart';

/// Total income over a period, in integer minor units. FR-COP-008.
///
/// Written once and consumed twice, the same way [AnalyticsRepository]'s
/// spending query is: it is what the Copilot's income tool wraps, and it is
/// available to any income-vs-expense screen the reports feature builds
/// (FR-RPT-004) without a second query.
class GetIncomeForPeriod implements UseCase<int, DateRange> {
  /// Creates the use case.
  const GetIncomeForPeriod(this._repository);

  final AnalyticsRepository _repository;

  @override
  Future<Either<Failure, int>> call(DateRange params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);
    return _repository.incomeForPeriod(params);
  }

  /// Returns the reason [range] cannot be reported on, or null if it is fine.
  ///
  /// Same rule as [AnalyticsRepository.spendingByCategory]'s use case: an
  /// inverted range is the one case worth catching before a query runs, since
  /// SQLite would otherwise answer it with a silent zero.
  static ValidationFailure? validate(DateRange range) {
    if (range.isInverted) {
      return const ValidationFailure(
        'The start of the period is after its end.',
        field: 'from',
      );
    }
    return null;
  }
}
