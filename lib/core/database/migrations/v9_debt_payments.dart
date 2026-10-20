/// Schema version 9 — a payment between people, kept as a debt record of
/// its own. E-47.
///
/// A friend paying back part of what they owe was a debt either paid or
/// not. A payment is now a record like any other, running the other way,
/// so it offsets what the person owes (FR-DBT-005) and keeps its own day.
/// Marked as a payment so the list can say "Paid you" rather than "You
/// owe".
///
/// - `is_payment` — 1 for a payment, 0 for a debt; every existing row is a
///   debt.
///
/// Additive, per SDD §5.3: every existing debt upgrades intact, as a debt.
library;

/// The version this migration produces.
const int v9SchemaVersion = 9;

/// The statements, in order.
const List<String> v9Statements = <String>[
  'ALTER TABLE debts ADD COLUMN is_payment INTEGER NOT NULL DEFAULT 0 '
      'CHECK(is_payment IN (0, 1))',
];
