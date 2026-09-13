import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/monthly_spending_reader.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/category_statistics.dart';
import '../entities/lookback_window.dart';

/// Per-category statistics over a lookback window. FR-PLN-005, FR-PLN-003.
///
/// The first stage of the plan generator, and the one the classifier, the
/// allocator and the confidence score all read from. Reads monthly totals
/// through [MonthlySpendingReader] — the trend lines' own month query — and
/// does every piece of arithmetic here, in Dart (E-05).
///
/// A category absent from a month is zero there, not missing, the same rule
/// the trend lines apply: a quiet month is evidence about variance, and
/// dropping it would make every sparse category look steady.
class ComputeCategoryStatistics
    implements UseCase<List<CategoryStatistics>, LookbackWindow> {
  /// Creates the use case over a [MonthlySpendingReader].
  const ComputeCategoryStatistics(this._reader);

  final MonthlySpendingReader _reader;

  @override
  Future<Either<Failure, List<CategoryStatistics>>> call(
    LookbackWindow params,
  ) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    final rows = await _reader.monthlySpendingByCategory(
      from: params.from,
      to: params.to,
    );
    return rows.map((sparse) => _describe(sparse, params));
  }

  /// Why [window] cannot be looked back over, or null when it can.
  ///
  /// Public and static so the Settings control FR-PLN-003 puts the length
  /// behind can refuse a value before anything runs.
  static ValidationFailure? validate(LookbackWindow window) {
    if (!window.isValid) {
      return const ValidationFailure(
        'Look back over between 1 and 24 months.',
        field: 'months',
      );
    }
    return null;
  }

  /// One entry per category with any spending, every month filled, largest
  /// mean first. Ties break by name, so the order is stable run to run.
  static List<CategoryStatistics> _describe(
    List<MonthlySpending> rows,
    LookbackWindow window,
  ) {
    final totals = <int, List<int>>{};
    final counts = <int, int>{};
    final names = <int, String>{};

    for (final row in rows) {
      final column = window.indexOf(row.month);
      // A month outside the window can only come from a reader answering a
      // different question than it was asked; dropping it trusts the window.
      if (column < 0) continue;
      names.putIfAbsent(row.categoryId, () => row.name);
      totals.putIfAbsent(
        row.categoryId,
        () => List.filled(window.months, 0),
      )[column] += row.amountCents;
      counts[row.categoryId] =
          (counts[row.categoryId] ?? 0) + row.transactionCount;
    }

    final statistics = [
      for (final MapEntry(key: id, value: series) in totals.entries)
        CategoryStatistics.of(
          categoryId: id,
          name: names[id]!,
          monthlyTotalsCents: series,
          transactionCount: counts[id]!,
        ),
    ];
    statistics.sort((a, b) {
      final byMean = b.meanCents.compareTo(a.meanCents);
      return byMean != 0 ? byMean : a.name.compareTo(b.name);
    });
    return statistics;
  }
}
