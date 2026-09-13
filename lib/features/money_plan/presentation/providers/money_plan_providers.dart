/// Presentation state for the money plan feature.
///
/// Talks to use cases only — never a repository or datasource — so a screen
/// can be tested by overriding one provider in `injection.dart`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../injection.dart';
import '../../domain/entities/allocation_request.dart';
import '../../domain/entities/money_plan_draft.dart';

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
