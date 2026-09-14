import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/money_plan.dart';
import '../entities/plan_allocation.dart';
import '../repositories/money_plan_repository.dart';
import 'allocate_budget.dart';

/// One of FR-PLN-014's three responses to an exceeded category.
sealed class OverspendResponse extends Equatable {
  const OverspendResponse();

  /// Raise the category to what was spent and take the difference from the
  /// other categories in proportion to what each has left.
  const factory OverspendResponse.autoRedistribute() = AutoRedistribute;

  /// Raise the category to what was spent and take the whole difference
  /// from [fromCategoryId], the one the user chose.
  const factory OverspendResponse.manualAdjust({required int fromCategoryId}) =
      ManualAdjust;

  /// Leave this plan as it is and deduct the overspend from the category in
  /// the next plan.
  const factory OverspendResponse.carryOver() = CarryOver;

  @override
  List<Object?> get props => const [];
}

/// See [OverspendResponse.autoRedistribute].
class AutoRedistribute extends OverspendResponse {
  /// Creates the response.
  const AutoRedistribute();
}

/// See [OverspendResponse.manualAdjust].
class ManualAdjust extends OverspendResponse {
  /// Creates the response.
  const ManualAdjust({required this.fromCategoryId});

  /// The category the user chose to reduce.
  final int fromCategoryId;

  @override
  List<Object?> get props => [fromCategoryId];
}

/// See [OverspendResponse.carryOver].
class CarryOver extends OverspendResponse {
  /// Creates the response.
  const CarryOver();
}

/// Which plan, which exceeded category, and what to do about it.
class OverspendRequest extends Equatable {
  /// Creates a request.
  const OverspendRequest({
    required this.planId,
    required this.categoryId,
    required this.response,
  });

  /// The saved plan.
  final int planId;

  /// The category spent past its allocation.
  final int categoryId;

  /// The user's choice.
  final OverspendResponse response;

  @override
  List<Object?> get props => [planId, categoryId, response];
}

/// Applies one of the three responses to an exceeded category. FR-PLN-014.
///
/// The SRS names them and says what each does; the arithmetic is decided
/// here, and three things about it are not in the SRS:
///
/// * **"Exceeded" is spent past the allocation**, strictly — a category at
///   exactly its budget has nothing to respond to. (FR-PLN-013 colours it
///   red at exactly 100% because nothing is left; that is a different
///   question.)
/// * **Auto-Redistribute reduces the other categories in proportion to
///   what each has *left*, not to their allocations**, and refuses when
///   what is left does not cover the overspend. Reducing by allocation —
///   `UpdateAllocation`'s rule for FR-PLN-011 — could push a category
///   that is nearly spent below its own spend, creating the next overspend
///   to respond to; by what is left, no category is taken under what it
///   has already spent. The exceeded category is raised to exactly what
///   was spent, so it reads 100% and can be spent on no further. The total
///   is held.
/// * **Carry Over writes nothing to this plan's figures.** It records the
///   overspend on the row for the next plan to deduct
///   ([PlanAllocation.carryOverCents]); `AllocateBudget` reads it from
///   the plan that ended last before the new period and subtracts it. It
///   is the whole overspend at the time of choosing, not added to an
///   earlier carry-over — choosing again replaces the figure.
///
/// Manual Adjust is the user's own version of the first: the whole
/// overspend from the one category they picked, refused if that category
/// has not got it left.
class RespondToOverspend implements UseCase<MoneyPlan, OverspendRequest> {
  /// Creates the use case.
  const RespondToOverspend(this._repository);

  final MoneyPlanRepository _repository;

  @override
  Future<Either<Failure, MoneyPlan>> call(OverspendRequest params) async {
    final read = await _repository.getById(params.planId);
    return read.fold(Left.new, (plan) async {
      if (plan == null) {
        return Left(ValidationFailure('No plan with id ${params.planId}.'));
      }
      final failure = validate(plan, params);
      if (failure != null) return Left(failure);

      final rows = apply(plan.allocations, params);
      final written = await _repository.updateAllocations(plan.id!, rows);
      return written.map(
        (_) => MoneyPlan(
          id: plan.id,
          name: plan.name,
          period: plan.period,
          totalBudgetCents: plan.totalBudgetCents,
          isActive: plan.isActive,
          allocations: rows,
        ),
      );
    });
  }

  /// Why [request] cannot be applied to [plan], or null when it can.
  static ValidationFailure? validate(MoneyPlan plan, OverspendRequest request) {
    final row = _find(plan.allocations, request.categoryId);
    if (row == null) {
      return const ValidationFailure(
        'That category is not in this plan.',
        field: 'categoryId',
      );
    }
    final overspend = row.overspendCents;
    if (overspend == 0) {
      return const ValidationFailure(
        'This category is within its budget.',
        field: 'categoryId',
      );
    }
    return switch (request.response) {
      AutoRedistribute() =>
        _othersRemaining(plan.allocations, request.categoryId) < overspend
            ? const ValidationFailure(
                'The other categories do not have enough left between them '
                'to cover the overspend.',
                field: 'response',
              )
            : null,
      ManualAdjust(:final fromCategoryId) => switch (_find(
        plan.allocations,
        fromCategoryId,
      )) {
        null => const ValidationFailure(
          'That category is not in this plan.',
          field: 'fromCategoryId',
        ),
        _ when fromCategoryId == request.categoryId => const ValidationFailure(
          'Pick a different category to reduce.',
          field: 'fromCategoryId',
        ),
        final from when from.remainingCents < overspend =>
          const ValidationFailure(
            'That category does not have enough left to cover the overspend.',
            field: 'fromCategoryId',
          ),
        _ => null,
      },
      CarryOver() => null,
    };
  }

  /// [allocations] after [request], assuming [validate] passed. Order is
  /// preserved; the sum is unchanged.
  static List<PlanAllocation> apply(
    List<PlanAllocation> allocations,
    OverspendRequest request,
  ) => switch (request.response) {
    AutoRedistribute() => autoRedistribute(allocations, request.categoryId),
    ManualAdjust(:final fromCategoryId) => manualAdjust(
      allocations,
      request.categoryId,
      fromCategoryId: fromCategoryId,
    ),
    CarryOver() => carryOver(allocations, request.categoryId),
  };

  /// [categoryId] raised to its spend; the others reduced by the overspend
  /// in proportion to what each has left, summing exactly.
  static List<PlanAllocation> autoRedistribute(
    List<PlanAllocation> allocations,
    int categoryId,
  ) {
    final row = _find(allocations, categoryId)!;
    final overspend = row.overspendCents;
    final others = [
      for (final a in allocations)
        if (a.categoryId != categoryId) a,
    ];
    final shares = AllocateBudget.distribute([
      for (final a in others) a.remainingCents,
    ], overspend);
    final reduced = {
      for (var i = 0; i < others.length; i++)
        others[i].categoryId: others[i].allocatedCents - shares[i],
    };
    return [
      for (final a in allocations)
        if (a.categoryId == categoryId)
          a.withAllocated(a.spentCents)
        else
          a.withAllocated(reduced[a.categoryId]!),
    ];
  }

  /// [categoryId] raised to its spend; [fromCategoryId] reduced by the
  /// same amount; both marked as the user's.
  static List<PlanAllocation> manualAdjust(
    List<PlanAllocation> allocations,
    int categoryId, {
    required int fromCategoryId,
  }) {
    final overspend = _find(allocations, categoryId)!.overspendCents;
    return [
      for (final a in allocations)
        if (a.categoryId == categoryId)
          a.withAllocated(a.spentCents, byUser: true)
        else if (a.categoryId == fromCategoryId)
          a.withAllocated(a.allocatedCents - overspend, byUser: true)
        else
          a,
    ];
  }

  /// [categoryId] carrying its overspend into the next plan; nothing else
  /// changes.
  static List<PlanAllocation> carryOver(
    List<PlanAllocation> allocations,
    int categoryId,
  ) => [
    for (final a in allocations)
      if (a.categoryId == categoryId) a.withCarryOver(a.overspendCents) else a,
  ];

  static PlanAllocation? _find(List<PlanAllocation> rows, int categoryId) {
    for (final a in rows) {
      if (a.categoryId == categoryId) return a;
    }
    return null;
  }

  static int _othersRemaining(List<PlanAllocation> rows, int categoryId) => rows
      .where((a) => a.categoryId != categoryId)
      .fold(0, (sum, a) => sum + a.remainingCents);
}
