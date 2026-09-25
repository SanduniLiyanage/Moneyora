import 'package:equatable/equatable.dart';
import 'package:fpdart/fpdart.dart';

import '../../../../core/errors/failures.dart';
import '../../../../core/ports/local_notifier.dart';
import '../../../../core/ports/notification_settings.dart';
import '../../../../core/usecases/usecase.dart';
import '../entities/recurring_rule.dart';
import '../entities/transaction.dart';

/// Keeps one pending reminder per recurring rule, for its next entry.
/// FR-SET-006, E-37.
///
/// Run whenever the rules or the reminder settings change — a rule posted
/// and moved on, paused, resumed or deleted, reminders turned on or off,
/// the time changed. Each run works out the whole set that should be
/// pending ([remindersFor]), cancels every pending reminder not in it, and
/// schedules every one that is, replacing by id. **Idempotent**: running it
/// twice leaves the phone exactly as running it once, so the watcher that
/// calls it never has to know what changed.
///
/// A reminder is a heads-up, not the posting: entries are still added by
/// the catch-up. So only a rule that will actually post gets one — active,
/// with a template, not past its end — and a reminder whose moment has
/// already gone is not scheduled at all rather than shown late.
class SyncRecurringReminders implements UseCase<int, ReminderSync> {
  /// Creates the use case.
  const SyncRecurringReminders(this._notifier);

  final LocalNotifier _notifier;

  /// What tapping a reminder carries: the app opens the rules list.
  static const String payload = 'recurring';

  /// Reconciles the pending reminders with [params]; returns how many are
  /// pending afterwards.
  @override
  Future<Either<Failure, int>> call(ReminderSync params) async {
    final wanted = remindersFor(params);
    final wantedIds = {for (final r in wanted) r.notification.id};

    final Set<int> pending;
    switch (await _notifier.scheduledIds()) {
      case Left(value: final failure):
        return Left(failure);
      case Right(value: final ids):
        pending = ids;
    }

    for (final id in pending) {
      if (!AppNotification.isRecurringReminder(id)) continue;
      if (wantedIds.contains(id)) continue;
      if (await _notifier.cancel(id) case Left(value: final failure)) {
        return Left(failure);
      }
    }
    for (final reminder in wanted) {
      final scheduled = await _notifier.schedule(
        reminder.notification,
        reminder.at,
      );
      if (scheduled case Left(value: final failure)) return Left(failure);
    }
    return Right(wanted.length);
  }

  /// Every reminder that should be pending for [sync], one per rule.
  ///
  /// Public and static so the rule — which rules, at what moment, in what
  /// words — is tested without a notifier.
  static List<ScheduledReminder> remindersFor(ReminderSync sync) {
    final settings = sync.settings;
    if (!settings.recurringRemindersEnabled) return const [];

    final reminders = <ScheduledReminder>[];
    for (final series in sync.series) {
      final rule = series.rule;
      final template = series.template;
      final id = rule.id;
      if (id == null || template == null) continue;
      // Paused, ended, and overdue rules have no next entry worth announcing:
      // an overdue one is waiting on something the user must fix, and the
      // rules list already says so.
      if (rule.statusOn(sync.now) != RecurrenceStatus.active) continue;

      final due = rule.nextDueDate;
      final minute = settings.reminderMinuteOfDay;
      final at = DateTime(
        due.year,
        due.month,
        due.day - settings.reminderDaysBefore,
        minute ~/ 60,
        minute % 60,
      );
      if (!at.isAfter(sync.now)) continue;

      reminders.add(
        ScheduledReminder(
          at: at,
          notification: AppNotification(
            id: AppNotification.recurringReminderBase + id,
            kind: NotificationKind.recurringReminder,
            title:
                '${_nameOf(template, sync.categoryNames)} is due '
                '${_when(settings.reminderDaysBefore)}',
            body: switch (template.type) {
              TransactionType.income =>
                'It is added to your income the next time you open '
                    'Moneyora on or after that day.',
              _ =>
                'It is added to your expenses the next time you open '
                    'Moneyora on or after that day.',
            },
            payload: payload,
          ),
        ),
      );
    }
    return reminders;
  }

  /// The template's category name, else its note. Amounts are left out on
  /// purpose, as the budget alerts leave them out: formatting money is
  /// `currency_utils.dart`'s job, which the domain does not reach.
  static String _nameOf(Transaction template, Map<int, String> names) =>
      names[template.categoryId] ?? template.note ?? 'A repeating entry';

  static String _when(int daysBefore) => switch (daysBefore) {
    0 => 'today',
    1 => 'tomorrow',
    _ => 'in $daysBefore days',
  };
}

/// What one sync works from.
class ReminderSync extends Equatable {
  /// Creates the input.
  const ReminderSync({
    required this.series,
    required this.settings,
    required this.categoryNames,
    required this.now,
  });

  /// Every rule, with its template — the rules list's read.
  final List<RecurringSeries> series;

  /// Whether reminders are on, and when they come.
  final NotificationSettings settings;

  /// Category names by id, for the reminder's title.
  final Map<int, String> categoryNames;

  /// The clock's now: a reminder due before it is not scheduled.
  final DateTime now;

  @override
  List<Object?> get props => [series, settings, categoryNames, now];
}

/// A notification and the moment it should appear.
class ScheduledReminder extends Equatable {
  /// Creates a scheduled reminder.
  const ScheduledReminder({required this.notification, required this.at});

  /// What it says.
  final AppNotification notification;

  /// When, local wall-clock time.
  final DateTime at;

  @override
  List<Object?> get props => [notification, at];
}
