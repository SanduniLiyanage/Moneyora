/// Schema version 9 — a payment between people, kept as a debt record of
/// its own, and the account a debt's money moved through. E-47.
///
/// A friend paying back part of what they owe was a debt either paid or
/// not. A payment is now a record like any other, running the other way,
/// so it offsets what the person owes (FR-DBT-005) and keeps its own day.
/// Marked as a payment so the list can say "Paid you" rather than "You
/// owe".
///
/// And a debt may now name the account its money moved through
/// (FR-DBT-009), which E-42 had ruled out. The movement is a ledger row
/// of its own, `type = 'transfer'` with no `transfers` header, tied to the
/// debt: it moves the account's balance, is counted when the balance is
/// recalculated and shows in the account's history, and is never income
/// or spending (E-02).
///
/// - `debts.is_payment` — 1 for a payment, 0 for a debt; every existing row
///   is a debt.
/// - `debts.account_id` — the account the money left when the user lent it,
///   or arrived in when they borrowed it; null for none, as every existing
///   debt has.
/// - `debts.paid_account_id` — the account it was paid back through; null
///   for none.
/// - `transactions.debt_id` — on a debt's money movement, the debt; null on
///   every other row, so every existing transaction upgrades as it was.
///
/// Additive, per SDD §5.3: every existing debt, account and transaction
/// upgrades intact, and no balance moves.
library;

/// The version this migration produces.
const int v9SchemaVersion = 9;

/// The statements, in order.
const List<String> v9Statements = <String>[
  'ALTER TABLE debts ADD COLUMN is_payment INTEGER NOT NULL DEFAULT 0 '
      'CHECK(is_payment IN (0, 1))',
  'ALTER TABLE debts ADD COLUMN account_id INTEGER REFERENCES accounts(id)',
  'ALTER TABLE debts ADD COLUMN paid_account_id INTEGER '
      'REFERENCES accounts(id)',
  'ALTER TABLE transactions ADD COLUMN debt_id INTEGER REFERENCES debts(id)',
  'CREATE INDEX idx_transactions_debt_id ON transactions(debt_id)',
];
