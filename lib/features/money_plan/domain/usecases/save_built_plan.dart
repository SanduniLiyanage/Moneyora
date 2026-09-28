import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/confidence_score.dart';
import '../entities/money_plan.dart';
import '../entities/plan_allocation.dart';
import '../entities/plan_line.dart';
import '../entities/plan_period.dart';
import '../repositories/money_plan_repository.dart';

/// A plan the user built or edited line by line, and what to call it.
/// FR-PLN-011, E-39.
class BuiltPlanRequest extends Equatable {
  /// Creates a request.
  const BuiltPlanRequest({
    required this.name,
    required this.period,
    required this.lines,
    this.activate = true,
  });

  /// The plan's name.
  final String name;

  /// The days it covers.
  final PlanPeriod period;

  /// One per category the user considered. A line at zero is left out.
  final List<PlanLine> lines;

  /// Whether to start tracking it now, as `SavePlanRequest.activate`.
  final bool activate;

  @override
  List<Object?> get props => [name, period, lines, activate];
}

/// Saves a plan whose figures the user typed or changed. FR-PLN-011, E-39.
///
/// Two ways in, one save: a plan built by hand while there is too little
/// history for the generator, and a generated plan the user edited before
/// saving it. The total is what the lines add up to; the user sets the
/// figures, so nothing is recalculated behind them.
///
/// A line with no suggestion is saved as Low confidence, because nothing in
/// the history supports it — which is what Low means (FR-PLN-010) — and as
/// set by the user, which is how the screens tell it apart.
class SaveBuiltPlan implements UseCase<int, BuiltPlanRequest> {
  /// Creates the use case.
  const SaveBuiltPlan(this._repository);

  final MoneyPlanRepository _repository;

  @override
  Future<Either<Failure, int>> call(BuiltPlanRequest params) async {
    final failure = validate(params);
    if (failure != null) return Left(failure);

    final kept = [
      for (final line in params.lines)
        if (line.amountCents > 0) line,
    ];
    return _repository.save(
      MoneyPlan(
        name: params.name.trim(),
        period: params.period,
        totalBudgetCents: kept.fold(0, (sum, l) => sum + l.amountCents),
        isActive: params.activate,
        allocations: [
          for (final line in kept)
            PlanAllocation(
              categoryId: line.categoryId,
              categoryName: line.categoryName,
              allocatedCents: line.amountCents,
              confidence: line.suggestion?.confidence ?? ConfidenceLevel.low,
              expenseType: line.suggestion?.type,
              isUserModified: line.isSetByUser,
            ),
        ],
      ),
    );
  }

  /// Why [request] cannot be saved, or null when it can.
  static ValidationFailure? validate(BuiltPlanRequest request) {
    if (request.period.isInverted) {
      return const ValidationFailure(
        'The start of the plan is after its end.',
        field: 'period',
      );
    }
    if (request.lines.any((l) => l.amountCents < 0)) {
      return const ValidationFailure(
        'A budget cannot be less than nothing.',
        field: 'lines',
      );
    }
    final ids = request.lines.map((l) => l.categoryId).toList();
    if (ids.toSet().length != ids.length) {
      return const ValidationFailure(
        'A category can appear only once in a plan.',
        field: 'lines',
      );
    }
    if (!request.lines.any((l) => l.amountCents > 0)) {
      return const ValidationFailure(
        'Give at least one category an amount.',
        field: 'lines',
      );
    }
    if (request.name.trim().isEmpty) {
      return const ValidationFailure('Give the plan a name.', field: 'name');
    }
    return null;
  }
}
