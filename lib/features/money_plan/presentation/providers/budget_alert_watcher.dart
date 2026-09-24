/// Runs FR-SET-007's check whenever the active plan or the setting moves.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../injection.dart';
import '../../domain/usecases/check_budget_alerts.dart';
import 'money_plan_providers.dart';

/// Watches the active plan and the budget-alert setting, and hands each
/// change to [CheckBudgetAlerts]. FR-SET-007, E-35.
///
/// App-lifetime, started from `main.dart` beside the splash, because an
/// alert is about an expense entered on any screen — the entry screen, a
/// scanned receipt — not only about the plan screen being open.
///
/// **One check at a time.** The plan re-reads after every write, and two
/// quick expenses would otherwise run two checks side by side. The store
/// beneath is compare-and-set, so overlapping checks could not announce a
/// crossing twice anyway; running them in order keeps the notifications in
/// the order the spend happened, and keeps the second check from doing work
/// the first is about to make unnecessary.
///
/// A failed check is logged and dropped. There is nobody to show it to — no
/// screen asked — and the next write checks again from the stored level.
class BudgetAlertWatcher extends Notifier<void> {
  Future<void> _queue = Future<void>.value();

  @override
  void build() {
    ref
      ..listen(activePlanProvider, (_, _) => _check())
      ..listen(notificationSettingsProvider, (_, _) => _check());
  }

  void _check() {
    // Both must be known: a plan without the setting, or the setting
    // without a plan, has nothing to decide yet.
    final plan = ref.read(activePlanProvider).asData;
    final settings = ref.read(notificationSettingsProvider).asData;
    if (plan == null || settings == null) return;

    final params = BudgetAlertCheck(
      plan: plan.value,
      alertsEnabled: settings.value.budgetAlertsEnabled,
    );
    _queue = _queue
        .then((_) async {
          final check = await ref.read(checkBudgetAlertsProvider.future);
          final result = await check(params);
          result.match(
            (failure) => debugPrint('[budget-alerts] ${failure.message}'),
            (_) {},
          );
        })
        // Not a use case failure — those are values, handled above — but
        // the use case never being built, when the database it needs did
        // not open. Swallowed so one bad start does not end every check
        // queued after it: a failed future would skip each `then` for the
        // rest of the session.
        .catchError(
          (Object e) => debugPrint('[budget-alerts] check not run: $e'),
        );
  }

  /// Settles once every check queued so far has run. For tests, which
  /// otherwise have no way to know the tray has been written to.
  @visibleForTesting
  Future<void> get idle => _queue;
}

/// The running [BudgetAlertWatcher]. Listen to it to keep it alive.
final budgetAlertWatcherProvider = NotifierProvider<BudgetAlertWatcher, void>(
  BudgetAlertWatcher.new,
);
