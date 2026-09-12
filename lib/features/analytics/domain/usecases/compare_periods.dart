import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/analytics_query.dart';
import '../entities/category_delta.dart';
import '../entities/category_total.dart';
import '../repositories/analytics_repository.dart';

/// The two periods to compare. Input to [ComparePeriods].
class ComparePeriodsParams extends Equatable {
  /// Creates the parameters for a comparison.
  const ComparePeriodsParams({required this.periodA, required this.periodB});

  /// The earlier (or baseline) period.
  final DateRange periodA;

  /// The later (or comparison) period.
  final DateRange periodB;

  @override
  List<Object?> get props => [periodA, periodB];
}

/// How spending by category moved between two periods. FR-COP-021.
///
/// Reuses [AnalyticsRepository.spendingByCategory] rather than a new query: a
/// delta is arithmetic on two totals that already exist, not a fact only SQL
/// can know, so this stays a use case combining an existing aggregate rather
/// than a second query computing the same numbers a different way (E-24).
class ComparePeriods
    implements UseCase<List<CategoryDelta>, ComparePeriodsParams> {
  /// Creates the use case.
  const ComparePeriods(this._repository);

  final AnalyticsRepository _repository;

  @override
  Future<Either<Failure, List<CategoryDelta>>> call(
    ComparePeriodsParams params,
  ) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    // Every account, both sides: FR-COP-021 compares two periods, and
    // narrowing one side by account would make the delta answer a question
    // nobody asked. FR-RPT-003's filter belongs to the screens, not here.
    final periodA = await _repository.spendingByCategory(
      AnalyticsQuery(range: params.periodA),
    );

    return periodA.match(Left.new, (totalsA) async {
      final periodB = await _repository.spendingByCategory(
        AnalyticsQuery(range: params.periodB),
      );
      return periodB.match(
        Left.new,
        (totalsB) => Right(_diff(totalsA, totalsB)),
      );
    });
  }

  /// Returns the reason the comparison cannot run, or null if it is fine.
  ///
  /// Each period is checked the same way [AnalyticsRepository.spendingByCategory]'s
  /// use case checks a single one — an inverted range reads as "nothing was
  /// spent" rather than as the mistake it is.
  static ValidationFailure? validate(ComparePeriodsParams params) {
    if (params.periodA.isInverted) {
      return const ValidationFailure(
        'The start of period A is after its end.',
        field: 'periodA',
      );
    }
    if (params.periodB.isInverted) {
      return const ValidationFailure(
        'The start of period B is after its end.',
        field: 'periodB',
      );
    }
    return null;
  }

  /// One delta per category present in either period, largest movement first.
  ///
  /// A category missing from one period is not missing data — it is zero for
  /// that period, the same "nothing appears" convention
  /// [AnalyticsRepository.spendingByCategory] already uses for a category
  /// with nothing spent.
  static List<CategoryDelta> _diff(
    List<CategoryTotal> periodA,
    List<CategoryTotal> periodB,
  ) {
    final before = {for (final t in periodA) t.categoryId: t};
    final after = {for (final t in periodB) t.categoryId: t};

    final deltas = [
      for (final id in {...before.keys, ...after.keys})
        CategoryDelta(
          categoryId: id,
          name: (after[id] ?? before[id])!.name,
          color: (after[id] ?? before[id])!.color,
          deltaCents:
              (after[id]?.amountCents ?? 0) - (before[id]?.amountCents ?? 0),
        ),
    ];

    deltas.sort((a, b) {
      final byMagnitude = b.deltaCents.abs().compareTo(a.deltaCents.abs());
      return byMagnitude != 0 ? byMagnitude : a.name.compareTo(b.name);
    });
    return deltas;
  }
}
