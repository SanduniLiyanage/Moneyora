import 'package:equatable/equatable.dart';

/// Which notifications the user has turned on. FR-SET-007.
///
/// From the `users` row, read by the Money Plan, which may not import the
/// settings feature that owns the row (rule 4 of `check_architecture.sh`) —
/// so the value lives here, as [CalendarSettings] does, and
/// [NotificationSettingsReader] is the seam.
class NotificationSettings extends Equatable {
  /// Creates the settings.
  const NotificationSettings({
    this.budgetAlertsEnabled = false,
    this.recurringRemindersEnabled = false,
    this.reminderDaysBefore = 1,
    this.reminderMinuteOfDay = 9 * 60,
  });

  /// The most days ahead a reminder may come. A week: further out, a
  /// reminder is a calendar's job, and a weekly rule would be reminding
  /// about the entry after next.
  static const int maxReminderDaysBefore = 7;

  /// The schema's column defaults: everything off.
  ///
  /// Off because turning a notification on is where the platform's
  /// permission is asked for, and a permission prompt belongs to the moment
  /// the user chose the thing it is for — not to a launch that did not.
  static const NotificationSettings defaults = NotificationSettings();

  /// Whether a category crossing 80% and 100% of its plan allocation is
  /// announced. FR-SET-007.
  final bool budgetAlertsEnabled;

  /// Whether a recurring entry is announced before it is added.
  /// FR-SET-006, E-37.
  final bool recurringRemindersEnabled;

  /// How many days before the entry the reminder comes, 0 (the day itself)
  /// to [maxReminderDaysBefore]. FR-SET-006.
  final int reminderDaysBefore;

  /// The time of day it comes, as minutes after midnight, 0 to 1439.
  /// FR-SET-006.
  final int reminderMinuteOfDay;

  @override
  List<Object?> get props => [
    budgetAlertsEnabled,
    recurringRemindersEnabled,
    reminderDaysBefore,
    reminderMinuteOfDay,
  ];
}
