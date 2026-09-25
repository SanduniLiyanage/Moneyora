/// Posts the recurring entries that have fallen due, on launch and on
/// resume. FR-EXP-008, FR-INC-004.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../injection.dart';

/// Runs `PostDueRecurringTransactions` once when the app starts and again
/// every time it comes back to the foreground.
///
/// App-lifetime, started from `main.dart` beside the budget-alert watcher.
/// **Resume as well as launch**, because Android keeps a backgrounded app
/// alive for days: a rent due on the 5th must not wait for the process to
/// die and be relaunched. The due query is one indexed range that is empty
/// on nearly every call, so running it on each resume costs nothing worth
/// saving.
///
/// **One run at a time, and at most one waiting.** A resume while a run is
/// in flight queues one more, which will see anything the first has not;
/// a second resume while that one waits adds nothing. Runs overlapping
/// could not post an entry twice anyway — the store is compare-and-set —
/// but running them in order keeps a lost race from being logged as a
/// failure for no reason.
///
/// Off the first frame: nothing awaits this, and its first read waits on
/// the database like every other provider (NFR-PER-001).
///
/// What a run could not post is logged in debug and otherwise left where
/// it is — due, untouched, retried on the next run. No screen asked, so
/// there is nobody to show it to; the rules list shows an overdue rule.
class RecurringCatchUp extends Notifier<void> {
  Future<void> _queue = Future<void>.value();
  bool _waiting = false;
  bool _disposed = false;

  @override
  void build() {
    final lifecycle = AppLifecycleListener(onResume: run);
    ref.onDispose(() {
      _disposed = true;
      lifecycle.dispose();
    });
    run();
  }

  /// Queues a catch-up, unless one is already waiting to start.
  void run() {
    if (_waiting || _disposed) return;
    _waiting = true;
    _queue = _queue
        .then((_) async {
          _waiting = false;
          // A run queued before the app's container went cannot read from
          // it now, and has nobody left to post for.
          if (_disposed) return;
          final postDue = await ref.read(
            postDueRecurringTransactionsProvider.future,
          );
          if (_disposed) return;
          final result = await postDue(ref.read(clockProvider)());
          result.match(
            (failure) => debugPrint('[recurring] ${failure.message}'),
            (report) {
              for (final skipped in report.failures) {
                debugPrint(
                  '[recurring] rule ${skipped.ruleId} left due: '
                  '${skipped.failure.message}',
                );
              }
            },
          );
        })
        // Not a use case failure — those are values, handled above — but
        // the use case never being built, when the database did not open.
        // Swallowed so one bad start does not end every run queued after
        // it, which a failed future would.
        .catchError((Object e) {
          _waiting = false;
          debugPrint('[recurring] catch-up not run: $e');
        });
  }

  /// Settles once every run queued so far has finished. For tests.
  @visibleForTesting
  Future<void> get idle => _queue;
}

/// The running [RecurringCatchUp]. Listen to it to keep it alive.
final recurringCatchUpProvider = NotifierProvider<RecurringCatchUp, void>(
  RecurringCatchUp.new,
);
