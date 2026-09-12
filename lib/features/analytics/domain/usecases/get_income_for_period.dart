import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/analytics_query.dart';
import '../repositories/analytics_repository.dart';

/// Total income over a period, for one account or all of them, in integer
/// minor units. FR-COP-008, FR-RPT-004.
///
/// Written once and consumed twice, the same way [AnalyticsRepository]'s
/// spending query is: it is what the Copilot's income tool wraps, and it is
/// what FR-RPT-004's income-vs-expense bars read for their income bar,
/// without a second query.
class GetIncomeForPeriod implements UseCase<int, AnalyticsQuery> {
  /// Creates the use case.
  const GetIncomeForPeriod(this._repository);

  final AnalyticsRepository _repository;

  @override
  Future<Either<Failure, int>> call(AnalyticsQuery params) async {
    final failure = validate(params.range);
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
