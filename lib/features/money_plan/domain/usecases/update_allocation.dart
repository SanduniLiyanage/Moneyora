import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/money_plan.dart';
import '../entities/plan_allocation.dart';
import '../repositories/money_plan_repository.dart';
import 'allocate_budget.dart';

/// One category's allocation, set by hand. FR-PLN-011.
class UpdateAllocationRequest extends Equatable {
  /// Creates a request.
  const UpdateAllocationRequest({
    required this.planId,
    required this.categoryId,
    required this.allocatedCents,
  });

  /// The saved plan.
  final int planId;

  /// The category the user changed.
  final int categoryId;

  /// What they changed it to.
  final int allocatedCents;

  @override
  List<Object?> get props => [planId, categoryId, allocatedCents];
}

/// Sets one allocation by hand and recalculates the others to hold the
/// plan's total. FR-PLN-011.
///
/// The recalculation is [AllocateBudget.distribute] — the same proportional,
/// exact-sum arithmetic Option A uses — over the allocations that absorb
/// the change. Which ones absorb it is the decision here, in [rebalance].
class UpdateAllocation implements UseCase<MoneyPlan, UpdateAllocationRequest> {
  /// Creates the use case.
  const UpdateAllocation(this._repository);

  final MoneyPlanRepository _repository;

  @override
  Future<Either<Failure, MoneyPlan>> call(
    UpdateAllocationRequest params,
  ) async {
    if (params.allocatedCents < 0) {
      return const Left(
        ValidationFailure(
          'An allocation cannot be negative.',
          field: 'allocatedCents',
        ),
      );
    }

    final read = await _repository.getById(params.planId);
    return read.fold(Left.new, (plan) async {
      if (plan == null) {
        return Left(ValidationFailure('No plan with id ${params.planId}.'));
      }
      final failure = validate(plan, params);
      if (failure != null) return Left(failure);

      final rebalanced = rebalance(
        plan.allocations,
        categoryId: params.categoryId,
        allocatedCents: params.allocatedCents,
        totalCents: plan.totalBudgetCents,
      );
      final written = await _repository.updateAllocations(plan.id!, rebalanced);
      return written.map(
        (_) => MoneyPlan(
          id: plan.id,
          name: plan.name,
          period: plan.period,
          totalBudgetCents: plan.totalBudgetCents,
          isActive: plan.isActive,
          allocations: rebalanced,
        ),
      );
    });
  }

  /// Why [request] cannot be applied to [plan], or null when it can.
  static ValidationFailure? validate(
    MoneyPlan plan,
    UpdateAllocationRequest request,
  ) {
    if (!plan.allocations.any((a) => a.categoryId == request.categoryId)) {
      return const ValidationFailure(
        'That category is not in this plan.',
        field: 'categoryId',
      );
    }
    if (plan.allocations.length < 2) {
      return const ValidationFailure(
        'This is the only allocation in the plan, so nothing else can take '
        'up the difference.',
        field: 'categoryId',
      );
    }
    if (request.allocatedCents > plan.totalBudgetCents) {
      return const ValidationFailure(
        "An allocation cannot exceed the plan's total.",
        field: 'allocatedCents',
      );
    }
    return null;
  }

  /// [allocations] with [categoryId] set to [allocatedCents] and marked as
  /// the user's, and the rest recalculated so the sum is [totalCents].
  ///
  /// Who absorbs the difference: the allocations the user has **not**
  /// touched, proportionally to what they have — a second manual change must
  /// not quietly undo the first. Only when every other allocation is already
  /// the user's, or when the untouched ones cannot absorb it without going
  /// negative, does the difference spread across all the others; the total
  /// is held either way. Order is preserved.
  static List<PlanAllocation> rebalance(
    List<PlanAllocation> allocations, {
    required int categoryId,
    required int allocatedCents,
    required int totalCents,
  }) {
    final others = [
      for (final a in allocations)
        if (a.categoryId != categoryId) a,
    ];
    final untouched = [
      for (final a in others)
        if (!a.isUserModified) a,
    ];
    final held = others
        .where((a) => a.isUserModified)
        .fold(0, (sum, a) => sum + a.allocatedCents);

    final absorbing =
        untouched.isNotEmpty && totalCents - allocatedCents - held >= 0
        ? untouched
        : others;
    final remainder =
        totalCents - allocatedCents - (identical(absorbing, others) ? 0 : held);
    final shares = AllocateBudget.distribute([
      for (final a in absorbing) a.allocatedCents,
    ], remainder);
    final absorbed = {
      for (var i = 0; i < absorbing.length; i++)
        absorbing[i].categoryId: shares[i],
    };

    return [
      for (final a in allocations)
        if (a.categoryId == categoryId)
          a.withAllocated(allocatedCents, byUser: true)
        else if (absorbed.containsKey(a.categoryId))
          a.withAllocated(absorbed[a.categoryId]!)
        else
          a,
    ];
  }
}
