import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/daily_spending_reader.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/lookback_window.dart';
import '../entities/spending_patterns.dart';

/// Weekday against weekend, and a month's start against its end, over the
/// months a plan learns from. FR-PLN-006.
///
/// The same window the plan's statistics read (FR-PLN-003), so what the
/// review screen says about habits is about the history the figures above
/// it came from.
class DetectSpendingPatterns
    implements UseCase<SpendingPatterns, LookbackWindow> {
  /// Creates the use case.
  const DetectSpendingPatterns(this._reader);

  final DailySpendingReader _reader;

  @override
  Future<Either<Failure, SpendingPatterns>> call(LookbackWindow params) async {
    if (!params.isValid) {
      // ComputeCategoryStatistics' own sentence: one window, one rule.
      return const Left(
        ValidationFailure(
          'Look back over between 1 and 24 months.',
          field: 'months',
        ),
      );
    }
    final days = await _reader.dailySpending(from: params.from, to: params.to);
    return days.map((rows) => SpendingPatterns.from(params, rows));
  }
}
