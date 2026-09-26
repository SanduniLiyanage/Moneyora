/// Keeps the backup reminder scheduled. FR-BAK-006.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../injection.dart';

/// Runs `ScheduleBackupReminder` on launch, after any change to the data,
/// and when asked to after a backup is saved.
///
/// The data matters to it in one way — whether there is anything to lose —
/// and the shared change bus is the one signal every write publishes, so
/// the first expense, a restore and a clear all reschedule it. App-lifetime,
/// started from `main.dart` beside the other watchers. One run at a time,
/// at most one waiting, as the recurring-reminder watcher does it: the run
/// is idempotent, so a burst of writes costs a few runs rather than one per
/// write.
class BackupReminderWatcher extends Notifier<void> {
  Future<void> _queue = Future<void>.value();
  bool _waiting = false;
  bool _disposed = false;
  StreamSubscription<void>? _changes;

  @override
  void build() {
    _changes = ref.watch(databaseChangeBusProvider).changes.listen((_) {
      sync();
    });
    ref.onDispose(() {
      _disposed = true;
      unawaited(_changes?.cancel());
    });
    sync();
  }

  /// Reschedules the reminder from what is stored now.
  void sync() {
    if (_waiting || _disposed) return;
    _waiting = true;
    _queue = _queue
        .then((_) async {
          _waiting = false;
          if (_disposed) return;
          final schedule = await ref.read(
            scheduleBackupReminderProvider.future,
          );
          final result = await schedule(ref.read(clockProvider)());
          result.match(
            (failure) => debugPrint('[backup-reminder] ${failure.message}'),
            (_) {},
          );
        })
        .catchError((Object e) {
          _waiting = false;
          debugPrint('[backup-reminder] not scheduled: $e');
        });
  }

  /// Settles once every run queued so far has finished. For tests.
  @visibleForTesting
  Future<void> get idle => _queue;
}

/// The running [BackupReminderWatcher]. Listen to it to keep it alive.
final backupReminderWatcherProvider =
    NotifierProvider<BackupReminderWatcher, void>(BackupReminderWatcher.new);
