import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/analytics_query.dart';
import '../entities/category_total.dart';
import '../entities/period_summary.dart';
import '../repositories/analytics_repository.dart';

/// Total income, total expenses, net savings, average daily spend, the
/// largest spending category and the change against the period before.
/// FR-RPT-006.
///
/// Read from the aggregates the charts already use — spending by category,
/// income for the period — so the figures cannot disagree with the donut
/// and the bars drawn above them: the expense total *is* the donut's
/// categories added up, the largest category *is* its biggest slice. The
/// previous period is read with the same account filter, so the change
/// compares like with like.
class GetPeriodSummary implements UseCase<PeriodSummary, SummaryRequest> {
  /// Creates the use case.
  const GetPeriodSummary(this._repository);

  final AnalyticsRepository _repository;

  @override
  Future<Either<Failure, PeriodSummary>> call(SummaryRequest params) async {
    if (params.query.range.isInverted) {
      return const Left(
        ValidationFailure('The start of the period is after its end.'),
      );
    }

    final spending = await _repository.spendingByCategory(params.query);
    final income = await _repository.incomeForPeriod(params.query);
    final previous = params.previousRange == null
        ? null
        : await _repository.spendingByCategory(
            AnalyticsQuery(
              range: params.previousRange!,
              accountId: params.query.accountId,
            ),
          );

    return spending.flatMap(
      (totals) => income.flatMap((incomeCents) {
        final int? previousCents;
        switch (previous) {
          case null:
            previousCents = null;
          case Left(value: final failure):
            return Left(failure);
          case Right(value: final before):
            previousCents = _sum(before);
        }
        final expenseCents = _sum(totals);
        final days = params.daysElapsed;
        return Right(
          PeriodSummary(
            incomeCents: incomeCents,
            expenseCents: expenseCents,
            averageDailySpendCents: days == null || days < 1
                ? null
                : expenseCents ~/ days,
            largestCategory: _largest(totals),
            previousExpenseCents: previousCents,
          ),
        );
      }),
    );
  }

  static int _sum(List<CategoryTotal> totals) =>
      totals.fold(0, (sum, t) => sum + t.amountCents);

  /// The biggest total, the first by name on a tie, so the answer does not
  /// depend on the order the query happened to return.
  static CategoryTotal? _largest(List<CategoryTotal> totals) {
    CategoryTotal? best;
    for (final t in totals) {
      if (t.amountCents <= 0) continue;
      if (best == null ||
          t.amountCents > best.amountCents ||
          (t.amountCents == best.amountCents &&
              t.name.compareTo(best.name) < 0)) {
        best = t;
      }
    }
    return best;
  }
}

/// What to summarise. FR-RPT-006.
class SummaryRequest extends Equatable {
  /// Creates a request.
  const SummaryRequest({
    required this.query,
    required this.previousRange,
    required this.daysElapsed,
  });

  /// The period and account filter the charts use.
  final AnalyticsQuery query;

  /// The period before, to compare spending with; null for none.
  final DateRange? previousRange;

  /// Days of the period that have happened, today included — what the
  /// average divides by, so a month half over is not averaged over thirty
  /// days. Null when there is no sensible count (all time).
  final int? daysElapsed;

  @override
  List<Object?> get props => [query, previousRange, daysElapsed];
}
