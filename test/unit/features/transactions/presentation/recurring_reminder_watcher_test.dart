import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:moneyora/core/errors/failures.dart';
import 'package:moneyora/core/ports/category_reader.dart';
import 'package:moneyora/core/ports/local_notifier.dart';
import 'package:moneyora/core/ports/notification_settings.dart';
import 'package:moneyora/features/transactions/domain/entities/recurring_rule.dart';
import 'package:moneyora/features/transactions/domain/entities/transaction.dart';
import 'package:moneyora/features/transactions/domain/usecases/sync_recurring_reminders.dart';
import 'package:moneyora/features/transactions/presentation/providers/recurring_providers.dart';
import 'package:moneyora/features/transactions/presentation/providers/recurring_reminder_watcher.dart';
import 'package:moneyora/features/transactions/presentation/providers/transaction_providers.dart';
import 'package:moneyora/injection.dart';

/// The phone's pending notifications, by id.
class _Pending implements LocalNotifier {
  final scheduled = <int, DateTime>{};

  @override
  Future<Either<Failure, Set<int>>> scheduledIds() async =>
      Right(scheduled.keys.toSet());

  @override
  Future<Either<Failure, Unit>> schedule(
    AppNotification notification,
    DateTime at,
  ) async {
    scheduled[notification.id] = at;
    return const Right(unit);
  }

  @override
  Future<Either<Failure, Unit>> cancel(int id) async {
    scheduled.remove(id);
    return const Right(unit);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

/// FR-SET-006: the pending reminders follow the rules and the settings.
void main() {
  late _Pending pending;
  late StreamController<List<RecurringSeries>> rules;
  late StreamController<NotificationSettings> settings;
  late ProviderContainer container;

  const base = AppNotification.recurringReminderBase;
  final now = DateTime(2026, 6, 20, 8);

  RecurringSeries series(int id, {bool active = true}) => RecurringSeries(
    rule: RecurringRule(
      id: id,
      templateTransactionId: 9,
      frequency: RecurrenceFrequency.monthly,
      dayOfMonth: 5,
      startDate: DateTime(2026, 1, 5),
      nextDueDate: DateTime(2026, 7, 5),
      isActive: active,
    ),
    template: Transaction(
      id: 9,
      accountId: 1,
      categoryId: 1,
      amountCents: 100,
      type: TransactionType.expense,
      date: DateTime(2026, 1, 5),
    ),
  );

  setUp(() {
    pending = _Pending();
    rules = StreamController();
    settings = StreamController();
    container = ProviderContainer(
      overrides: [
        clockProvider.overrideWithValue(() => now),
        recurringRulesProvider.overrideWith((ref) => rules.stream),
        notificationSettingsProvider.overrideWith((ref) => settings.stream),
        entryCategoriesProvider.overrideWith(
          (ref) => Stream.value(const [
            CategoryOption(
              id: 1,
              name: 'Rent',
              icon: 'home',
              colorHex: '#C62828',
              isExpense: true,
            ),
          ]),
        ),
        syncRecurringRemindersProvider.overrideWithValue(
          SyncRecurringReminders(pending),
        ),
      ],
    )..listen(recurringReminderWatcherProvider, (_, _) {});
  });

  tearDown(() async {
    container.dispose();
    await rules.close();
    await settings.close();
  });

  Future<void> settle() async {
    await pumpEventQueue();
    await container.read(recurringReminderWatcherProvider.notifier).idle;
    await pumpEventQueue();
  }

  test(
    'does nothing until both the rules and the settings are known',
    () async {
      rules.add([series(5)]);
      await settle();
      expect(pending.scheduled, isEmpty);

      settings.add(const NotificationSettings(recurringRemindersEnabled: true));
      await settle();
      expect(pending.scheduled, {base + 5: DateTime(2026, 7, 4, 9)});
    },
  );

  test('follows the rules: a paused rule loses its reminder', () async {
    settings.add(const NotificationSettings(recurringRemindersEnabled: true));
    rules.add([series(5), series(6)]);
    await settle();
    expect(pending.scheduled.keys, unorderedEquals([base + 5, base + 6]));

    rules.add([series(5), series(6, active: false)]);
    await settle();
    expect(pending.scheduled.keys, [base + 5]);
  });

  test(
    'follows the settings: off withdraws them, a new time moves them',
    () async {
      rules.add([series(5)]);
      settings.add(const NotificationSettings(recurringRemindersEnabled: true));
      await settle();

      settings.add(
        const NotificationSettings(
          recurringRemindersEnabled: true,
          reminderDaysBefore: 0,
          reminderMinuteOfDay: 7 * 60,
        ),
      );
      await settle();
      expect(pending.scheduled, {base + 5: DateTime(2026, 7, 5, 7)});

      settings.add(const NotificationSettings());
      await settle();
      expect(pending.scheduled, isEmpty);
    },
  );
}
