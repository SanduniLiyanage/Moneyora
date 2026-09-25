import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/local_notifier.dart';
import 'package:moneyora/core/ports/notification_settings.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/usecases/sync_recurring_reminders.dart';

/// The phone's pending notifications, as the plugin keeps them: by id,
/// replaced on a second schedule.
class _Pending implements LocalNotifier {
  final scheduled = <int, (AppNotification, DateTime)>{};
  final cancelled = <int>[];
  Failure? failSchedule;

  @override
  Future<Either<Failure, Set<int>>> scheduledIds() async =>
      Right(scheduled.keys.toSet());

  @override
  Future<Either<Failure, Unit>> schedule(
    AppNotification notification,
    DateTime at,
  ) async {
    if (failSchedule case final f?) return Left(f);
    scheduled[notification.id] = (notification, at);
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> cancel(int id) async {
    cancelled.add(id);
    scheduled.remove(id);
    return const Right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  final now = DateTime(2026, 6, 20, 8);
  const on = NotificationSettings(recurringRemindersEnabled: true);
  const names = {1: 'Rent', 3: 'Salary'};
  const base = AppNotification.recurringReminderBase;

  RecurringSeries series({
    int id = 5,
    int categoryId = 1,
    TransactionType type = TransactionType.expense,
    DateTime? next,
    DateTime? end,
    bool active = true,
    bool hasTemplate = true,
    String? note,
  }) => RecurringSeries(
    rule: RecurringRule(
      id: id,
      templateTransactionId: hasTemplate ? 9 : null,
      frequency: RecurrenceFrequency.monthly,
      dayOfMonth: 5,
      startDate: DateTime(2026, 1, 5),
      nextDueDate: next ?? DateTime(2026, 7, 5),
      endDate: end,
      isActive: active,
    ),
    template: hasTemplate
        ? Transaction(
            id: 9,
            accountId: 1,
            categoryId: categoryId,
            amountCents: 100,
            type: type,
            date: DateTime(2026, 1, 5),
            note: note,
          )
        : null,
  );

  ReminderSync sync(
    List<RecurringSeries> all, {
    NotificationSettings settings = on,
    DateTime? at,
  }) => ReminderSync(
    series: all,
    settings: settings,
    categoryNames: names,
    now: at ?? now,
  );

  group('remindersFor', () {
    test('one reminder per active rule, the day before at 9:00 by default', () {
      final reminders = SyncRecurringReminders.remindersFor(sync([series()]));

      expect(reminders, hasLength(1));
      final r = reminders.single;
      expect(r.at, DateTime(2026, 7, 4, 9));
      expect(r.notification.id, base + 5);
      expect(r.notification.kind, NotificationKind.recurringReminder);
      expect(r.notification.title, 'Rent is due tomorrow');
      expect(r.notification.body, contains('added to your expenses'));
      expect(r.notification.payload, SyncRecurringReminders.payload);
    });

    test('the days before and the time are the settings', () {
      final at = SyncRecurringReminders.remindersFor(
        sync(
          [series()],
          settings: const NotificationSettings(
            recurringRemindersEnabled: true,
            reminderDaysBefore: 3,
            reminderMinuteOfDay: 18 * 60 + 30,
          ),
        ),
      ).single;
      expect(at.at, DateTime(2026, 7, 2, 18, 30));
      expect(at.notification.title, 'Rent is due in 3 days');
    });

    test('on the day itself says today', () {
      final r = SyncRecurringReminders.remindersFor(
        sync(
          [series()],
          settings: const NotificationSettings(
            recurringRemindersEnabled: true,
            reminderDaysBefore: 0,
          ),
        ),
      ).single;
      expect(r.at, DateTime(2026, 7, 5, 9));
      expect(r.notification.title, 'Rent is due today');
    });

    test('crosses a month boundary', () {
      final r = SyncRecurringReminders.remindersFor(
        sync([series(next: DateTime(2026, 8))]),
      ).single;
      expect(r.at, DateTime(2026, 7, 31, 9));
    });

    test('income says income', () {
      final r = SyncRecurringReminders.remindersFor(
        sync([series(categoryId: 3, type: TransactionType.income)]),
      ).single;
      expect(r.notification.title, 'Salary is due tomorrow');
      expect(r.notification.body, contains('added to your income'));
    });

    test('an unknown category falls back to the note, then a phrase', () {
      expect(
        SyncRecurringReminders.remindersFor(
          sync([series(categoryId: 99, note: 'Gym')]),
        ).single.notification.title,
        'Gym is due tomorrow',
      );
      expect(
        SyncRecurringReminders.remindersFor(sync([series(categoryId: 99)]))
            .single
            .notification
            .title,
        'A repeating entry is due tomorrow',
      );
    });

    test('nothing when reminders are off', () {
      expect(
        SyncRecurringReminders.remindersFor(
          sync([series()], settings: const NotificationSettings()),
        ),
        isEmpty,
      );
    });

    test('nothing for a paused, ended, overdue or template-less rule', () {
      expect(
        SyncRecurringReminders.remindersFor(
          sync([
            series(id: 1, active: false),
            series(id: 2, end: DateTime(2026, 6, 30)),
            series(id: 3, next: DateTime(2026, 6, 5)),
            series(id: 4, hasTemplate: false),
          ]),
        ),
        isEmpty,
      );
    });

    test('a reminder whose moment has passed is not scheduled late', () {
      // Due tomorrow; the day-before reminder was at 9:00 today, and it is
      // now 9:30.
      expect(
        SyncRecurringReminders.remindersFor(
          sync([
            series(next: DateTime(2026, 6, 21)),
          ], at: DateTime(2026, 6, 20, 9, 30)),
        ),
        isEmpty,
      );
      // At 8:00 it is still ahead.
      expect(
        SyncRecurringReminders.remindersFor(
          sync([series(next: DateTime(2026, 6, 21))]),
        ),
        hasLength(1),
      );
    });
  });

  group('the sync', () {
    test('schedules what is wanted and cancels only stale reminders', () async {
      final pending = _Pending();
      // A stale reminder for a deleted rule, and a budget alert's id that
      // is not the reminders' to touch.
      pending.scheduled[base + 77] = (
        const AppNotification(
          id: 0,
          kind: NotificationKind.recurringReminder,
          title: '',
          body: '',
        ),
        now,
      );
      const budgetId = AppNotification.budgetAlertBase + 1;
      pending.scheduled[budgetId] = (
        const AppNotification(
          id: budgetId,
          kind: NotificationKind.budgetAlert,
          title: '',
          body: '',
        ),
        now,
      );

      final result = await SyncRecurringReminders(pending)(
        sync([series(id: 5), series(id: 6, next: DateTime(2026, 7, 10))]),
      );

      expect(result, const Right<Failure, int>(2));
      expect(pending.cancelled, [base + 77]);
      expect(pending.scheduled.keys.toSet(), {base + 5, base + 6, budgetId});
    });

    test('running it twice leaves the same pending set', () async {
      final pending = _Pending();
      final use = SyncRecurringReminders(pending);
      final input = sync([series()]);

      await use(input);
      final first = Map.of(pending.scheduled);
      await use(input);

      expect(pending.scheduled, first);
      expect(pending.cancelled, isEmpty);
    });

    test('turning reminders off withdraws every one', () async {
      final pending = _Pending();
      final use = SyncRecurringReminders(pending);
      await use(sync([series(id: 5), series(id: 6)]));

      final result = await use(
        sync([
          series(id: 5),
          series(id: 6),
        ], settings: const NotificationSettings()),
      );

      expect(result, const Right<Failure, int>(0));
      expect(pending.scheduled, isEmpty);
    });

    test('a scheduling failure comes back as it is', () async {
      final pending = _Pending()
        ..failSchedule = const PermissionFailure('Could not schedule.');
      expect(
        await SyncRecurringReminders(pending)(sync([series()])),
        const Left<Failure, int>(PermissionFailure('Could not schedule.')),
      );
    });
  });
}
