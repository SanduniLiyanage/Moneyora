/// Schema version 7 — money owed, either way. E-42.
///
/// The SRS has no debts: a loan to a friend or a bill someone else paid was
/// recordable only as an expense or an income, which is wrong both times —
/// the money is still yours, or still not yours, until it is paid back. One
/// table, read and written only by `features/debts/`.
///
/// **Not tied to an account or a transaction.** A debt is a promise, not a
/// movement of money; when it is paid, the money moves through whichever
/// account it moves through, recorded there as any income or expense is.
/// Linking the two would make "mark as paid" write a transaction the user
/// may already have recorded.
///
/// - `direction` — `owed_to_me` (they owe the user) or `i_owe`.
/// - `person` — who; required, so a list of debts reads as people.
/// - `amount_cents` — positive, the direction carries the sign.
/// - `incurred_on`, `due_on`, `paid_on` — `YYYY-MM-DD` days, as every date
///   column is. A null `paid_on` is a debt still open, which is what the
///   list is mostly about, hence the one index.
/// - `note` — what it was for: "Dinner at the Curry Leaf, split 3 ways".
library;

/// The version this migration produces.
const int v7SchemaVersion = 7;

/// The statements, in order.
const List<String> v7Statements = <String>[
  '''
CREATE TABLE debts (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  direction    TEXT    NOT NULL CHECK(direction IN ('owed_to_me','i_owe')),
  person       TEXT    NOT NULL CHECK(length(trim(person)) > 0),
  amount_cents INTEGER NOT NULL CHECK(amount_cents > 0),
  note         TEXT,
  incurred_on  TEXT    NOT NULL,
  due_on       TEXT,
  paid_on      TEXT,
  created_at   TEXT    NOT NULL,
  updated_at   TEXT    NOT NULL
)''',
  'CREATE INDEX idx_debts_paid_on ON debts(paid_on)',
];
