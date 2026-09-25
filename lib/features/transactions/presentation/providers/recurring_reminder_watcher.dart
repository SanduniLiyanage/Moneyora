/// Keeps the phone's pending recurring reminders in step with the rules.
/// FR-SET-006, E-37.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ports/category_reader.dart';
import '../../../../injection.dart';
import '../../domain/usecases/sync_recurring_reminders.dart';
import 'recurring_providers.dart';
import 'transaction_providers.dart';

/// Runs [SyncRecurringReminders] whenever something it reads changes: the
/// rules (a catch-up moving a due date, a pause, a delete), the reminder
/// settings, or the category names a reminder's title uses.
///
/// App-lifetime, started from `main.dart` beside the budget-alert watcher,
/// for its reason: a rule changes on screens that know nothing of
/// reminders. **One sync at a time, and at most one waiting**, as the
/// catch-up runner does it — and the waiting one reads the state when it
/// starts, not when it was queued, so a burst of changes costs two syncs
/// however long it is. The sync is idempotent, so a spare run is harmless.
///
/// A failed sync is logged and dropped; the next change syncs again from
/// scratch.
class RecurringReminderWatcher extends Notifier<void> {
  Future<void> _queue = Future<void>.value();
  bool _waiting = false;
  bool _disposed = false;

  @override
  void build() {
    ref
      ..onDispose(() => _disposed = true)
      ..listen(recurringRulesProvider, (_, _) => _sync())
      ..listen(notificationSettingsProvider, (_, _) => _sync())
      ..listen(entryCategoriesProvider, (_, _) => _sync());
  }

  void _sync() {
    if (_waiting || _disposed) return;
    _waiting = true;
    _queue = _queue
        .then((_) async {
          _waiting = false;
          if (_disposed) return;
          // Both must be known: rules with no settings, or settings with no
          // rules, would withdraw reminders that are right.
          final rules = ref.read(recurringRulesProvider).asData;
          final settings = ref.read(notificationSettingsProvider).asData;
          if (rules == null || settings == null) return;
          final names = {
            for (final c
                in ref.read(entryCategoriesProvider).valueOrNull ??
                    const <CategoryOption>[])
              c.id: c.name,
          };

          final result = await ref.read(syncRecurringRemindersProvider)(
            ReminderSync(
              series: rules.value,
              settings: settings.value,
              categoryNames: names,
              now: ref.read(clockProvider)(),
            ),
          );
          result.match(
            (failure) => debugPrint('[reminders] ${failure.message}'),
            (_) {},
          );
        })
        // Not a use case failure — those are values — but a provider that
        // could not be read. Swallowed so it does not end every sync queued
        // after it.
        .catchError((Object e) {
          _waiting = false;
          debugPrint('[reminders] sync not run: $e');
        });
  }

  /// Settles once every sync queued so far has run. For tests.
  @visibleForTesting
  Future<void> get idle => _queue;
}

/// The running [RecurringReminderWatcher]. Listen to it to keep it alive.
final recurringReminderWatcherProvider =
    NotifierProvider<RecurringReminderWatcher, void>(
      RecurringReminderWatcher.new,
    );
