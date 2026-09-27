/// Presentation state for the money plan feature.
///
/// Talks to use cases only — never a repository or datasource — so a screen
/// can be tested by overriding one provider in `injection.dart`.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/database/seed/dev_seed.dart';
import '../../../../core/errors/failures.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../injection.dart';
import '../../domain/entities/allocation_request.dart';
import '../../domain/entities/lookback_window.dart';
import '../../domain/entities/money_plan.dart';
import '../../domain/entities/money_plan_draft.dart';
import '../../domain/entities/plan_comparison.dart';
import '../../domain/entities/spending_patterns.dart';
import '../../domain/usecases/compare_plans.dart';
import '../../domain/usecases/respond_to_overspend.dart';
import '../../domain/usecases/save_plan.dart';
import '../../domain/usecases/update_allocation.dart';

/// When in the week and the month the money goes, over [LookbackWindow].
/// FR-PLN-006. A `Left` is the future's error, as [planDraftProvider]'s.
final spendingPatternsProvider = FutureProvider.autoDispose
    .family<SpendingPatterns, LookbackWindow>((ref, window) async {
      final detect = await ref.watch(detectSpendingPatternsProvider.future);
      final result = await detect(window);
      return result.match(
        Future<SpendingPatterns>.error,
        Future<SpendingPatterns>.value,
      );
    });

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

/// Loads the synthetic history from `dev_seed.dart`, in debug builds only.
///
/// That generator is 24 months of deliberately shaped data — a fixed cost, a
/// noisy one, one that spikes each April and December, one climbing 8% a
/// month, and one with three transactions that must score low confidence. It
/// is the Money Plan's test oracle and the demo dataset both.
///
/// It was written in Sprint 1 exactly so that Sprint 5 would not arrive with
/// eleven test expenses and no way to exercise the algorithm. It is offered
/// where that algorithm finds nothing to plan from — not on the transaction
/// list, which is where someone checks their real money.
///
/// Guarded by [kDebugMode] so it cannot ship, per `docs/ROADMAP.md`.
///
/// Loads at most once: the generator is seeded, so a second load wrote an
/// identical second copy of every row and doubled every total. It checks
/// first, and says which happened.
class DevSeedLoader extends AutoDisposeAsyncNotifier<SampleDataLoad?> {
  @override
  Future<SampleDataLoad?> build() async => null;

  /// Writes the sample history, unless it is already there, and returns
  /// what happened — null in a release build or when the write failed,
  /// which leaves the error in [state].
  Future<SampleDataLoad?> load() async {
    if (!kDebugMode) return null;
    state = const AsyncValue<SampleDataLoad?>.loading();

    state = await AsyncValue.guard(() async {
      final db = await ref.read(databaseProvider.future);
      if (await DevSeed.isLoaded(db)) return const SampleDataLoad(written: 0);
      final written = await DevSeed.populate(db);

      // The rows went in beneath the datasources, whose change streams
      // therefore stayed quiet. The shared bus is what every screen
      // listens to — the list, the accounts, the charts, the plan and the
      // home screen's count — so one signal refreshes all of them. The
      // cached balances and plan figures moved in the same transaction.
      ref.read(databaseChangeBusProvider).notify();
      return SampleDataLoad(written: written);
    });
    return state.valueOrNull;
  }
}

/// What a sample-data load did.
class SampleDataLoad {
  /// Creates the outcome.
  const SampleDataLoad({required this.written});

  /// How many transactions went in; 0 when the history was already there.
  final int written;

  /// True when nothing was written because it had been loaded before.
  bool get alreadyLoaded => written == 0;
}

/// Controller for the debug-only "load sample data" action.
final devSeedLoaderProvider =
    AutoDisposeAsyncNotifierProvider<DevSeedLoader, SampleDataLoad?>(
      DevSeedLoader.new,
    );
