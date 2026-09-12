import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/analytics_query.dart';
import '../entities/category_total.dart';
import '../repositories/analytics_repository.dart';

/// What was spent per category over a period, for one account or all of
/// them. FR-RPT-001, FR-RPT-002, FR-RPT-003.
///
/// The query beneath the donut chart, and the one the Copilot's first tool
/// wraps. It is written once and consumed twice on purpose: two callers
/// computing "spending by category" separately is two chances to disagree
/// about whether a transfer counts.
class GetSpendingByCategory
    implements UseCase<List<CategoryTotal>, AnalyticsQuery> {
  /// Creates the use case.
  const GetSpendingByCategory(this._repository);

  final AnalyticsRepository _repository;

  @override
  Future<Either<Failure, List<CategoryTotal>>> call(
    AnalyticsQuery params,
  ) async {
    final failure = validate(params.range);
    if (failure != null) return Left(failure);
    return _repository.spendingByCategory(params);
  }

  /// Returns the reason [range] cannot be reported on, or null if it is fine.
  ///
  /// Still takes the range rather than the whole [AnalyticsQuery]: the period
  /// is the only part of a query that can be wrong. An account id either
  /// names a row or selects nothing, which is an empty chart and a true one —
  /// and FR-RPT-003's picker can only offer accounts that exist.
  ///
  /// Public and static so a screen's period picker — and the Copilot's tool,
  /// whose dates come from a language model — can check without running a
  /// query. An inverted range is the one case worth catching: SQLite answers
  /// it with an empty result, which reads as "you spent nothing" rather than
  /// as the mistake it is.
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
