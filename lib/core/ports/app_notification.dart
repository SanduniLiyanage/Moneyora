import 'package:equatable/equatable.dart';

/// What a notification is about, which decides where the platform files it.
///
/// On Android each kind is its own notification channel, which the user can
/// silence in the phone's settings without silencing the others — so the
/// kind is part of the notification, not something the implementation
/// guesses from an id.
enum NotificationKind {
  /// A plan category crossing 80% or 100%. FR-SET-007.
  budgetAlert,

  /// A recurring entry about to be added. FR-SET-006.
  recurringReminder,
}

/// One notification the app wants the device to show. FR-SET-007.
///
/// A value in `core/ports/` rather than a plugin type, so the features that
/// decide *what* to say — the Money Plan today, recurring reminders next —
/// stay pure Dart, and [LocalNotifier]'s implementation is the only file
/// that knows how the platform is asked.
class AppNotification extends Equatable {
  /// Creates a notification.
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.payload,
  });

  /// Base of the id range budget alerts use, one id per allocation row.
  ///
  /// Showing a notification under an id already on screen replaces it, so
  /// the 100% alert takes the 80% one's place rather than stacking beneath
  /// it. The ranges are bits rather than a sequence so that later sources
  /// of notifications get their own without renumbering this one; an
  /// allocation id would have to pass 2³⁰ to reach the next range.
  static const int budgetAlertBase = 1 << 30;

  /// Base of the id range recurring reminders use, one id per rule.
  /// FR-SET-006.
  ///
  /// One pending reminder per rule — its next entry's — so scheduling the
  /// next one under the same id replaces the last. Below
  /// [budgetAlertBase], by the same bit rule: a rule id would have to pass
  /// 2²⁹ to reach the budget alerts.
  static const int recurringReminderBase = 1 << 29;

  /// Whether [id] belongs to the recurring reminders' range.
  static bool isRecurringReminder(int id) =>
      id >= recurringReminderBase && id < budgetAlertBase;

  /// The notification's id — the same id replaces, never duplicates.
  final int id;

  /// What it is about, and so which channel it is shown on.
  final NotificationKind kind;

  /// The line shown in bold.
  final String title;

  /// The line beneath it.
  final String body;

  /// What tapping it should open, as a token presentation understands.
  /// Null opens the app where it was.
  final String? payload;

  @override
  List<Object?> get props => [id, kind, title, body, payload];
}
