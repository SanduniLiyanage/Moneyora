/// Presentation state for the money plan feature.
///
/// Talks to use cases only — never a repository or datasource — so a screen
/// can be tested by overriding one provider in `injection.dart`.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../injection.dart';
import '../../domain/entities/allocation_request.dart';
import '../../domain/entities/money_plan.dart';
import '../../domain/entities/money_plan_draft.dart';
import '../../domain/entities/plan_comparison.dart';
import '../../domain/usecases/compare_plans.dart';
import '../../domain/usecases/respond_to_overspend.dart';
import '../../domain/usecases/save_plan.dart';
import '../../domain/usecases/update_allocation.dart';

/// The generator's proposal for [request]. FR-PLN-007 to FR-PLN-010.
///
/// Thin wrapper over [AllocateBudget], keyed on the request the wizard
/// built. A `Left` completes the future with the [Failure] as its error, the
/// convention the analytics providers follow, so the review screen sees a
/// refusal — an inverted period, a savings target out of range — as
/// `AsyncValue.error` carrying the use case's own sentence.
///
/// `autoDispose`: one review screen reads it, and a draft is worth nothing
/// once the user has left it.
final planDraftProvider = FutureProvider.autoDispose
    .family<MoneyPlanDraft, AllocationRequest>((ref, request) async {
      final allocate = await ref.watch(allocateBudgetProvider.future);
      final result = await allocate(request);
      return result.match(
        Future<MoneyPlanDraft>.error,
        Future<MoneyPlanDraft>.value,
      );
    });

/// The active plan, live, or null when there is none. FR-PLN-013.
///
/// A stream over [WatchActivePlan], the shape `accountsProvider` uses: a
/// `Left` goes down the error channel so it arrives as `AsyncValue.error`,
/// because a `Failure` is a value, not an exception.
final activePlanProvider = StreamProvider.autoDispose<MoneyPlan?>((ref) {
  return Stream.fromFuture(ref.watch(watchActivePlanProvider.future))
      .asyncExpand((watch) => watch(const NoParams()))
      .transform(
        StreamTransformer<Either<Failure, MoneyPlan?>, MoneyPlan?>.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// Saves a reviewed draft, exposing the attempt as an [AsyncValue].
/// FR-PLN-001.
///
/// The same shape as `SaveAccountController`, for the same reason: a save
/// has three outcomes the screen must render, and `AsyncValue` has all
/// three. Returns the new plan id so the screen can move on to it.
class SavePlanController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Writes the plan; the failure — including `SavePlan`'s own refusals —
  /// is left in [state] for the screen to show.
  Future<int?> save(SavePlanRequest request) async {
    state = const AsyncValue<void>.loading();
    final savePlan = await ref.read(savePlanProvider.future);
    final result = await savePlan(request);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return null;
      },
      (id) {
        state = const AsyncValue<void>.data(null);
        return id;
      },
    );
  }
}

/// Controller for the review screen's save button.
final savePlanControllerProvider =
    AutoDisposeAsyncNotifierProvider<SavePlanController, void>(
      SavePlanController.new,
    );

/// Sets one allocation by hand. FR-PLN-011.
///
/// No invalidation on success: [activePlanProvider] is a live stream over
/// the change bus the write publishes to, so the recalculated rows are
/// already on their way.
class UpdateAllocationController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Returns true when it was written; the failure stays in [state].
  Future<bool> adjust(UpdateAllocationRequest request) async {
    state = const AsyncValue<void>.loading();
    final updateAllocation = await ref.read(updateAllocationProvider.future);
    final result = await updateAllocation(request);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return true;
      },
    );
  }
}

/// Controller for the saved-plan screen's adjustment dialog.
final updateAllocationControllerProvider =
    AutoDisposeAsyncNotifierProvider<UpdateAllocationController, void>(
      UpdateAllocationController.new,
    );

/// Applies one of FR-PLN-014's responses to an exceeded category.
///
/// Same shape as [UpdateAllocationController], for the same reason: the
/// rows come back through [activePlanProvider]'s stream, and the refusal —
/// the use case's own sentence — stays in [state] for the sheet to show.
class RespondToOverspendController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Returns true when it was written; the failure stays in [state].
  Future<bool> respond(OverspendRequest request) async {
    state = const AsyncValue<void>.loading();
    final respond = await ref.read(respondToOverspendProvider.future);
    final result = await respond(request);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return true;
      },
    );
  }
}

/// Controller for the saved-plan screen's overspend sheet.
final respondToOverspendControllerProvider =
    AutoDisposeAsyncNotifierProvider<RespondToOverspendController, void>(
      RespondToOverspendController.new,
    );

/// Every saved plan, live, newest first. FR-PLN-015.
///
/// The same stream shape as [activePlanProvider]: activation is a write on
/// the shared bus, so the list shows a switch without being told.
final plansProvider = StreamProvider.autoDispose<List<MoneyPlan>>((ref) {
  return Stream.fromFuture(ref.watch(watchPlansProvider.future))
      .asyncExpand((watch) => watch(const NoParams()))
      .transform(
        StreamTransformer<
          Either<Failure, List<MoneyPlan>>,
          List<MoneyPlan>
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// Two plans side by side. FR-PLN-015. A `Left` is the future's error, as
/// [planDraftProvider] does it, so the screen shows the use case's sentence.
final planComparisonProvider = FutureProvider.autoDispose
    .family<PlanComparison, ComparePlansRequest>((ref, request) async {
      final compare = await ref.watch(comparePlansProvider.future);
      final result = await compare(request);
      return result.match(
        Future<PlanComparison>.error,
        Future<PlanComparison>.value,
      );
    });

/// Makes a saved plan the tracked one. FR-PLN-015 — `ActivatePlan`'s first
/// caller from a screen.
class ActivatePlanController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Returns true when it was written; the failure stays in [state].
  Future<bool> activate(int planId) async {
    state = const AsyncValue<void>.loading();
    final activatePlan = await ref.read(activatePlanProvider.future);
    final result = await activatePlan(planId);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return true;
      },
    );
  }
}

/// Controller for the plan list's Activate action.
final activatePlanControllerProvider =
    AutoDisposeAsyncNotifierProvider<ActivatePlanController, void>(
      ActivatePlanController.new,
    );

/// Recounts a plan's spend from history. E-18's repair, reachable from the
/// plan list — `RecomputePlanSpending`'s first caller from a screen.
class RecomputePlanSpendingController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Returns true when it was written; the failure stays in [state].
  Future<bool> recount(int planId) async {
    state = const AsyncValue<void>.loading();
    final recompute = await ref.read(recomputePlanSpendingProvider.future);
    final result = await recompute(planId);
    return result.match(
      (failure) {
        state = AsyncValue<void>.error(failure, StackTrace.current);
        return false;
      },
      (_) {
        state = const AsyncValue<void>.data(null);
        return true;
      },
    );
  }
}

/// Controller for the plan list's Recount action.
final recomputePlanSpendingControllerProvider =
    AutoDisposeAsyncNotifierProvider<RecomputePlanSpendingController, void>(
      RecomputePlanSpendingController.new,
    );
