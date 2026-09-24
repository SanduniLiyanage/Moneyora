/// Schema version 5 — where FR-SET-007's budget alerts keep their state.
/// E-35.
///
/// **`users.budget_alerts_enabled`.** The DBD's `users` row (§3.1) has no
/// notification preference at all. Zero by default: alerts are off until
/// the user turns them on, which is where the platform's permission is
/// asked for.
///
/// **`plan_allocations.alerted_level`.** "Warn at 80%, alert at 100%" is an
/// event, and an event with nothing recording that it happened is repeated
/// on every re-read of the plan — every transaction write. The column holds
/// the threshold last announced for the row, as the percentage it names:
/// 0 (none), 80 or 100, so a row read in a SQL shell says what it means.
/// Zero for every existing row, which is the truth: nothing was ever
/// announced before this version.
///
/// Both are constant defaults, so both can be `NOT NULL` in an
/// `ALTER TABLE ADD COLUMN` — the case v2's `carry_over_cents` was and
/// v4's `credited_amount_cents` was not.
library;

/// The version this migration produces.
const int v5SchemaVersion = 5;

/// The statements, in order.
const List<String> v5Statements = <String>[
  'ALTER TABLE users '
      'ADD COLUMN budget_alerts_enabled INTEGER NOT NULL DEFAULT 0 '
      'CHECK(budget_alerts_enabled IN (0, 1))',
  'ALTER TABLE plan_allocations '
      'ADD COLUMN alerted_level INTEGER NOT NULL DEFAULT 0 '
      'CHECK(alerted_level IN (0, 80, 100))',
];
