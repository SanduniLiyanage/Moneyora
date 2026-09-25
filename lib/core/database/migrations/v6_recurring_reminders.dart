/// Schema version 6 — where FR-SET-006's recurring reminders keep their
/// setting. E-37.
///
/// The DBD's `users` row (§3.1) has no notification preference at all; v5
/// added the budget alerts' switch, and this adds the reminders': whether
/// they come, how many days before the entry, and at what time of day.
///
/// **What is not stored: the reminders themselves.** The platform keeps the
/// pending notifications, and the transactions feature re-derives the whole
/// set from the rules and these columns whenever either changes, so there
/// is no second record to drift from the rules it describes.
///
/// All three are constant defaults, so all three are `NOT NULL`:
/// - `recurring_reminders_enabled` 0 — off until the user turns it on,
///   which is where the permission is asked for, as v5's switch is;
/// - `recurring_reminder_days_before` 1 — the day before, the common case
///   for a bill: time to move money into the account it comes from;
/// - `recurring_reminder_minute` 540 — 9:00, minutes after midnight, so
///   the column holds no time zone and the reminder follows the phone's.
library;

/// The version this migration produces.
const int v6SchemaVersion = 6;

/// The statements, in order.
const List<String> v6Statements = <String>[
  'ALTER TABLE users '
      'ADD COLUMN recurring_reminders_enabled INTEGER NOT NULL DEFAULT 0 '
      'CHECK(recurring_reminders_enabled IN (0, 1))',
  'ALTER TABLE users '
      'ADD COLUMN recurring_reminder_days_before INTEGER NOT NULL DEFAULT 1 '
      'CHECK(recurring_reminder_days_before BETWEEN 0 AND 7)',
  'ALTER TABLE users '
      'ADD COLUMN recurring_reminder_minute INTEGER NOT NULL DEFAULT 540 '
      'CHECK(recurring_reminder_minute BETWEEN 0 AND 1439)',
];
