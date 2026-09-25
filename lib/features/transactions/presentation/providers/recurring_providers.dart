/// Presentation state for recurring rules. FR-EXP-008, FR-INC-004.
///
/// Talks to use cases only, as `transaction_providers.dart` does.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../injection.dart';
import '../../domain/entities/recurring_rule.dart';
import '../../domain/usecases/resume_recurring_rule.dart';
import 'recurring_catch_up.dart';

/// Every recurring rule with the entry it copies, kept live, in the list's
/// order as of today.
///
/// A `Left` goes down the error channel, as `transactionsProvider` does it,
/// so the screen handles it in its `.when`.
final recurringRulesProvider = StreamProvider<List<RecurringSeries>>((ref) {
  final today = ref.watch(clockProvider)();
  return Stream.fromFuture(ref.watch(watchRecurringRulesProvider.future))
      .asyncExpand((watch) => watch(today))
      .transform(
        StreamTransformer<
          Either<Failure, List<RecurringSeries>>,
          List<RecurringSeries>
        >.fromHandlers(
          handleData: (result, sink) => result.match(sink.addError, sink.add),
        ),
      );
});

/// The rules list's three actions: pause, resume, delete.
///
/// One controller for the three because the sheet offers them side by
/// side and shows one outcome at a time. Each returns true when it worked
/// and leaves the failure in [state] for the sheet to show — the use case's
/// own sentence, never one invented here.
class RecurringRuleActionsController extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  /// Stops [rule] posting.
  Future<bool> pause(RecurringRule rule) => _run(() async {
    final pause = await ref.read(pauseRecurringRuleProvider.future);
    return pause(rule.id!);
  });

  /// Starts [rule] posting again from today, then runs a catch-up so an
  /// entry due today is posted now rather than on the next launch.
  Future<bool> resume(RecurringRule rule) async {
    final resumed = await _run(() async {
      final resume = await ref.read(resumeRecurringRuleProvider.future);
      return resume(
        ResumeRequest(rule: rule, today: ref.read(clockProvider)()),
      );
    });
    if (resumed) ref.read(recurringCatchUpProvider.notifier).run();
    return resumed;
  }

  /// Deletes [rule], keeping every entry it posted (E-36).
  Future<bool> delete(RecurringRule rule) => _run(() async {
    final delete = await ref.read(deleteRecurringRuleProvider.future);
    return delete(rule.id!);
  });

  Future<bool> _run(Future<Either<Failure, Unit>> Function() action) async {
    state = const AsyncValue<void>.loading();
    final result = await action();
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

/// Controller for the rules list's detail sheet.
final recurringRuleActionsProvider =
    AutoDisposeAsyncNotifierProvider<RecurringRuleActionsController, void>(
      RecurringRuleActionsController.new,
    );
