/// Schema version 4 — the schema FR-ACC-005 never had. E-34.
///
/// **`exchange_rates`.** The DBD stores a currency per account and no rate
/// anywhere (E-34, item 1). One row per ordered pair, keyed by the pair
/// rather than by "foreign currency against the base" so that changing the
/// base currency (FR-SET-003) does not silently change what every stored
/// rate means. A rate is an integer scaled by 10⁶ — the money-is-integers
/// rule (E-06) extended to the thing money is multiplied by.
///
/// **`transfers.credited_amount_cents`.** The header held one amount, the
/// debited one, and a cross-currency transfer has two (E-34, item 2). Added
/// nullable, because `ALTER TABLE ADD COLUMN` can declare `NOT NULL` only
/// with a constant default and the true value here is per row — then
/// backfilled from `amount_cents` in the very next statement, so that after
/// this migration no row is null. `v4_multi_currency_test.dart` asserts
/// that on pre-existing rows. The datasource always writes the column.
library;

/// The version this migration produces.
const int v4SchemaVersion = 4;

/// The statements, in order.
const List<String> v4Statements = <String>[
  '''
CREATE TABLE exchange_rates (
  from_currency TEXT    NOT NULL,
  to_currency   TEXT    NOT NULL,
  rate_micros   INTEGER NOT NULL CHECK(rate_micros > 0),
  updated_at    TEXT    NOT NULL,
  PRIMARY KEY (from_currency, to_currency),
  CHECK(from_currency <> to_currency)
)''',
  'ALTER TABLE transfers ADD COLUMN credited_amount_cents INTEGER '
      'CHECK(credited_amount_cents IS NULL OR credited_amount_cents > 0)',
  'UPDATE transfers SET credited_amount_cents = amount_cents',
];
