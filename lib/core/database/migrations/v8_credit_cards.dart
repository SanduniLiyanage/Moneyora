/// Schema version 8 — a credit card's terms. E-43.
///
/// FR-ACC-001 has a Credit Card account type, and FR-ACC-002 stores for it
/// what every account has: a name, a currency, an opening balance. What
/// makes a card a card — how much may be owed on it, when the statement is
/// cut, when payment is due, what owing costs — was nowhere. Four columns
/// on `accounts`, all nullable: null on every other kind of account, and
/// on a card until the user enters them.
///
/// - `credit_limit_cents` — above zero when set.
/// - `statement_day`, `payment_due_day` — a day of the month, 1 to 31; a
///   month shorter than the day uses its last.
/// - `apr_basis_points` — the yearly interest rate in hundredths of a
///   percent (2450 is 24.50%), an integer for the reason money is (E-06).
///
/// Additive, per SDD §5.3: every existing account upgrades with its
/// balance intact and the four columns null.
library;

/// The version this migration produces.
const int v8SchemaVersion = 8;

/// The statements, in order.
const List<String> v8Statements = <String>[
  'ALTER TABLE accounts ADD COLUMN credit_limit_cents INTEGER '
      'CHECK(credit_limit_cents IS NULL OR credit_limit_cents > 0)',
  'ALTER TABLE accounts ADD COLUMN statement_day INTEGER '
      'CHECK(statement_day IS NULL OR statement_day BETWEEN 1 AND 31)',
  'ALTER TABLE accounts ADD COLUMN payment_due_day INTEGER '
      'CHECK(payment_due_day IS NULL OR payment_due_day BETWEEN 1 AND 31)',
  'ALTER TABLE accounts ADD COLUMN apr_basis_points INTEGER '
      'CHECK(apr_basis_points IS NULL OR apr_basis_points BETWEEN 0 AND 10000)',
];
