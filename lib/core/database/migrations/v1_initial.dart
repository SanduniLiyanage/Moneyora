/// Schema version 1 — the initial Moneyora database.
///
/// Implements SRS §6.2 and DBD v1.0 §3, **as corrected by**
/// `docs/SPEC_ERRATA.md`. Where the baselines and the errata disagree the
/// errata wins, and every such deviation is marked inline with its ID so the
/// reason is one search away rather than lost.
///
/// Two conventions run through the whole schema:
///
/// * **Money is `INTEGER` minor units** (`*_cents`), never `REAL` — E-06.
///   All three baseline documents specify `REAL`; IEEE-754 cannot represent
///   0.10 exactly, so repeated addition drifts and a plan's "spent" total
///   stops matching the transactions that produced it.
/// * **Dates are ISO-8601 `TEXT`** (`YYYY-MM-DD`), times are `HH:MM`. SQLite
///   has no date type, and ISO-8601 sorts correctly as a string, which is what
///   makes the date-range indexes work.
library;

/// The version this migration brings the database to.
const int v1SchemaVersion = 1;

/// Tracks which migrations have run. Read before anything else on open.
///
/// SRS NFR-MNT-005 requires versioned schema migrations; SDD §5.3 names this
/// table for multi-step upgrades.
const String createSchemaMigrations = '''
CREATE TABLE IF NOT EXISTS schema_migrations (
  version     INTEGER PRIMARY KEY,
  applied_at  TEXT NOT NULL
)''';

/// Single-row settings table. SRS §6.2.
///
/// Moneyora is single-user, but the row exists so settings have somewhere to
/// live and so a future multi-profile feature does not need a migration that
/// backfills a user_id onto every other table.
const String _createUsers = '''
CREATE TABLE users (
  id                   INTEGER PRIMARY KEY,
  passcode_hash        TEXT,
  biometric_enabled    INTEGER NOT NULL DEFAULT 0,
  theme                TEXT    NOT NULL DEFAULT 'system'
                       CHECK(theme IN ('light','dark','system')),
  language             TEXT    NOT NULL DEFAULT 'en',
  currency             TEXT    NOT NULL DEFAULT 'LKR',
  first_day_week       INTEGER NOT NULL DEFAULT 0
                       CHECK(first_day_week BETWEEN 0 AND 6),
  first_day_month      INTEGER NOT NULL DEFAULT 1
                       CHECK(first_day_month BETWEEN 1 AND 28),
  savings_target_pct   REAL    NOT NULL DEFAULT 0.0
                       CHECK(savings_target_pct BETWEEN 0 AND 100),
  plan_analysis_months INTEGER NOT NULL DEFAULT 6
                       CHECK(plan_analysis_months BETWEEN 1 AND 24),
  created_at           TEXT    NOT NULL
)''';

/// FR-ACC-001..006.
///
/// `current_balance_cents` is a **cache**, not the source of truth — E-18.
/// It is written only inside the same transaction as the row that changes it,
/// and `RecomputeAccountBalance` re-derives it from history. Never update it
/// from a separate call.
const String _createAccounts = '''
CREATE TABLE accounts (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id                INTEGER NOT NULL REFERENCES users(id),
  name                   TEXT    NOT NULL,
  icon                   TEXT    NOT NULL,
  type                   TEXT    NOT NULL DEFAULT 'cash'
                         CHECK(type IN ('cash','bank','credit_card',
                                        'digital_wallet','crypto','custom')),
  currency               TEXT    NOT NULL DEFAULT 'LKR',
  initial_balance_cents  INTEGER NOT NULL DEFAULT 0,
  current_balance_cents  INTEGER NOT NULL DEFAULT 0,
  initial_balance_date   TEXT    NOT NULL,
  include_in_total       INTEGER NOT NULL DEFAULT 1,
  is_archived            INTEGER NOT NULL DEFAULT 0,
  created_at             TEXT    NOT NULL
)''';

/// FR-EXP-003..005, FR-INC-002..003.
///
/// `parent_id` gives the two-level hierarchy of FR-EXP-005. Depth is enforced
/// in the domain layer: SQLite cannot express "a parent may not itself have a
/// parent" as a constraint.
const String _createCategories = '''
CREATE TABLE categories (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id     INTEGER NOT NULL REFERENCES users(id),
  name        TEXT    NOT NULL,
  icon        TEXT    NOT NULL,
  color       TEXT    NOT NULL,
  type        TEXT    NOT NULL CHECK(type IN ('expense','income')),
  parent_id   INTEGER REFERENCES categories(id),
  is_default  INTEGER NOT NULL DEFAULT 0,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  UNIQUE(user_id, name, type)
)''';

/// The central table. FR-EXP-001, FR-INC-001, FR-TRF-002.
///
/// Two errata land here, both concerning transfers:
///
/// * **E-17** — `category_id` is nullable. The DBD marks it `NOT NULL`, but a
///   transfer between your own accounts has no category, so inserting one
///   would require inventing a sentinel category that then appears in the
///   donut chart. The CHECK enforces what the NOT NULL was reaching for.
/// * **E-16** — `transfer_direction` exists because `amount_cents` is always
///   positive and both halves of a transfer carry `type='transfer'`. Without
///   it, nothing on the row says whether money left or arrived, and every
///   balance query would have to join `transfers` to find out.
const String _createTransactions = '''
CREATE TABLE transactions (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  account_id         INTEGER NOT NULL REFERENCES accounts(id),
  category_id        INTEGER REFERENCES categories(id),
  amount_cents       INTEGER NOT NULL CHECK(amount_cents > 0),
  type               TEXT    NOT NULL
                     CHECK(type IN ('expense','income','transfer')),
  transfer_direction TEXT CHECK(transfer_direction IN ('out','in')),
  date               TEXT    NOT NULL,
  time               TEXT,
  note               TEXT,
  receipt_image_path TEXT,
  is_recurring       INTEGER NOT NULL DEFAULT 0,
  recurring_rule_id  INTEGER REFERENCES recurring_rules(id),
  receipt_scan_id    INTEGER REFERENCES receipt_scans(id),
  is_split           INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT    NOT NULL,
  updated_at         TEXT    NOT NULL,

  -- E-17: a transfer has no category; everything else must have one.
  CHECK (
    (type =  'transfer' AND category_id IS NULL)
    OR
    (type <> 'transfer' AND category_id IS NOT NULL)
  ),

  -- E-16: direction is present exactly when the row is half of a transfer.
  CHECK (
    (type =  'transfer' AND transfer_direction IS NOT NULL)
    OR
    (type <> 'transfer' AND transfer_direction IS NULL)
  )
)''';

/// FR-TRF-001..004. Header row for a transfer; DBD §3.5.
///
/// The two `transactions` rows carry the money and the balances; this row
/// carries the relationship, so the UI can show "From Cash / To Payment card"
/// and edit or delete both halves together.
///
/// **E-15** — `from_tx_id` and `to_tx_id` point at rows that do not exist
/// until the transfer is being written, so the insert order is: both
/// transaction rows, then this one. All three writes go inside a single
/// `BEGIN … COMMIT`. A partial write here leaves money that has left one
/// account without arriving in the other.
const String _createTransfers = '''
CREATE TABLE transfers (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  from_account_id INTEGER NOT NULL REFERENCES accounts(id),
  to_account_id   INTEGER NOT NULL REFERENCES accounts(id),
  amount_cents    INTEGER NOT NULL CHECK(amount_cents > 0),
  date            TEXT    NOT NULL,
  note            TEXT,
  from_tx_id      INTEGER NOT NULL REFERENCES transactions(id),
  to_tx_id        INTEGER NOT NULL REFERENCES transactions(id),
  created_at      TEXT    NOT NULL,
  CHECK(from_account_id <> to_account_id)
)''';

/// FR-EXP-010 — splitting one expense across several categories.
///
/// **E-04**: no baseline document defines this table, so the requirement was
/// unimplementable as specified.
///
/// Written only when a split exists. The unsplit case keeps
/// `transactions.category_id` and writes no rows here, so the common path
/// stays a single insert. When a split does exist, `transactions.category_id`
/// holds the **dominant** share so list views and the donut chart still render
/// without a join, and `transactions.is_split` flags that detail lives here.
///
/// The sum invariant — children total the parent — is enforced by
/// `AddTransaction`, since SQLite cannot express it.
const String _createTransactionSplits = '''
CREATE TABLE transaction_splits (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  transaction_id INTEGER NOT NULL
                 REFERENCES transactions(id) ON DELETE CASCADE,
  category_id    INTEGER NOT NULL REFERENCES categories(id),
  amount_cents   INTEGER NOT NULL CHECK(amount_cents > 0),
  note           TEXT
)''';

/// FR-EXP-008, FR-INC-004.
///
/// **E-03 / Amendment A**: the SRS references this table without defining it;
/// the DBD defines it but with no way to say *which* day a monthly rule fires.
/// `day_of_week` and `day_of_month` are added here for that reason.
///
/// `day_of_month` is capped at 28 deliberately: a rule set for the 31st would
/// silently skip February. Capping removes the edge case rather than asking
/// every caller to handle it, and it matches FR-SET-004's 1–28 bound on the
/// first-day-of-month setting.
const String _createRecurringRules = '''
CREATE TABLE recurring_rules (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  template_tx_id  INTEGER REFERENCES transactions(id),
  frequency       TEXT    NOT NULL
                  CHECK(frequency IN ('daily','weekly','monthly',
                                      'yearly','custom_days')),
  interval_days   INTEGER,
  day_of_week     INTEGER CHECK(day_of_week BETWEEN 0 AND 6),
  day_of_month    INTEGER CHECK(day_of_month BETWEEN 1 AND 28),
  start_date      TEXT    NOT NULL,
  end_date        TEXT,
  next_due_date   TEXT    NOT NULL,
  last_created_at TEXT,
  is_active       INTEGER NOT NULL DEFAULT 1,
  CHECK (frequency <> 'custom_days' OR interval_days IS NOT NULL)
)''';

/// FR-PLN-001..015. A saved budget plan.
const String _createMoneyPlans = '''
CREATE TABLE money_plans (
  id                 INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id            INTEGER NOT NULL REFERENCES users(id),
  name               TEXT    NOT NULL,
  period_type        TEXT    NOT NULL
                     CHECK(period_type IN ('day','week','month','year',
                                           'custom_days','custom_range')),
  start_date         TEXT    NOT NULL,
  end_date           TEXT    NOT NULL,
  total_budget_cents INTEGER NOT NULL CHECK(total_budget_cents >= 0),
  is_active          INTEGER NOT NULL DEFAULT 0,
  created_at         TEXT    NOT NULL,
  CHECK(end_date >= start_date)
)''';

/// FR-PLN-007, FR-PLN-010. Per-category allocation within a plan.
///
/// `expense_class` records the Fixed / Variable / Seasonal decision from
/// SRS §7.1 so the UI can explain *why* an allocation is what it is, rather
/// than presenting a number with no provenance.
///
/// `spent_amount_cents` is a cache with the same rules as
/// `accounts.current_balance_cents` — see E-18.
const String _createPlanAllocations = '''
CREATE TABLE plan_allocations (
  id                     INTEGER PRIMARY KEY AUTOINCREMENT,
  plan_id                INTEGER NOT NULL
                         REFERENCES money_plans(id) ON DELETE CASCADE,
  category_id            INTEGER NOT NULL REFERENCES categories(id),
  allocated_amount_cents INTEGER NOT NULL CHECK(allocated_amount_cents >= 0),
  spent_amount_cents     INTEGER NOT NULL DEFAULT 0,
  confidence_level       TEXT    NOT NULL
                         CHECK(confidence_level IN ('high','medium','low')),
  expense_class          TEXT
                         CHECK(expense_class IN ('fixed','variable','seasonal')),
  is_user_modified       INTEGER NOT NULL DEFAULT 0,
  notes                  TEXT,
  UNIQUE(plan_id, category_id)
)''';

/// FR-RCP-005, FR-RCP-012, FR-RCP-013. One scanned receipt.
const String _createReceiptScans = '''
CREATE TABLE receipt_scans (
  id                INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id           INTEGER NOT NULL REFERENCES users(id),
  image_path        TEXT    NOT NULL,
  merchant_name     TEXT,
  merchant_type     TEXT,
  receipt_date      TEXT,
  total_amount_cents INTEGER,
  tax_amount_cents  INTEGER,
  confidence_score  INTEGER NOT NULL DEFAULT 0
                    CHECK(confidence_score BETWEEN 0 AND 100),
  status            TEXT    NOT NULL DEFAULT 'pending'
                    CHECK(status IN ('pending','confirmed','rejected')),
  created_at        TEXT    NOT NULL
)''';

/// FR-RCP-006..009. One parsed line item from a receipt.
const String _createReceiptItems = '''
CREATE TABLE receipt_items (
  id                    INTEGER PRIMARY KEY AUTOINCREMENT,
  receipt_scan_id       INTEGER NOT NULL
                        REFERENCES receipt_scans(id) ON DELETE CASCADE,
  name                  TEXT    NOT NULL,
  quantity              REAL    NOT NULL DEFAULT 1.0,
  unit_price_cents      INTEGER,
  total_price_cents     INTEGER NOT NULL CHECK(total_price_cents >= 0),
  suggested_category_id INTEGER REFERENCES categories(id),
  confirmed_category_id INTEGER REFERENCES categories(id),
  confidence_score      INTEGER NOT NULL DEFAULT 0
                        CHECK(confidence_score BETWEEN 0 AND 100)
)''';

/// FR-RCP-007, FR-RCP-015. The three-layer categoriser's memory.
///
/// User-defined entries take priority 10 so a correction always beats a
/// built-in keyword — that is what makes FR-RCP-015's "learn from corrections"
/// observable to the user on the very next scan.
const String _createKeywordDictionary = '''
CREATE TABLE keyword_dictionary (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  keyword         TEXT    NOT NULL,
  category_id     INTEGER NOT NULL REFERENCES categories(id),
  match_type      TEXT    NOT NULL DEFAULT 'contains'
                  CHECK(match_type IN ('exact','contains','startswith')),
  priority        INTEGER NOT NULL DEFAULT 5,
  usage_count     INTEGER NOT NULL DEFAULT 0,
  is_user_defined INTEGER NOT NULL DEFAULT 0,
  UNIQUE(keyword, category_id)
)''';

/// Indexes.
///
/// The seven from SDD §5.1, plus three the errata's new tables need. Each
/// exists to serve a query named in SDD §5.2 — an index with no query behind
/// it costs write throughput and buys nothing.
const List<String> _createIndexes = <String>[
  // Date-range scans: home chart, list filters, analytics. SDD §5.2.
  'CREATE INDEX idx_tx_date ON transactions(date)',
  // Per-account views and balance recomputation.
  'CREATE INDEX idx_tx_account_date ON transactions(account_id, date)',
  // Category analytics and plan-vs-actual tracking.
  'CREATE INDEX idx_tx_category ON transactions(category_id)',
  // Expense/income separation with a date bound — the donut chart's query.
  'CREATE INDEX idx_tx_type_date ON transactions(type, date)',
  // Pulling every transaction a receipt scan produced.
  'CREATE INDEX idx_tx_receipt_scan ON transactions(receipt_scan_id)',
  // Plan detail lookups.
  'CREATE INDEX idx_plan_allocations_plan ON plan_allocations(plan_id)',
  // Receipt batch queries.
  'CREATE INDEX idx_receipt_items_scan ON receipt_items(receipt_scan_id)',
  // OCR categorisation speed: keyword lookup, highest priority first.
  'CREATE INDEX idx_keyword_dict_keyword ON keyword_dictionary(keyword, priority DESC)',
  // E-04: fetching a split's parts, and category analytics across splits.
  'CREATE INDEX idx_splits_transaction ON transaction_splits(transaction_id)',
  'CREATE INDEX idx_splits_category ON transaction_splits(category_id)',
  // E-03: the daily "what is due?" sweep.
  'CREATE INDEX idx_recurring_next_due ON recurring_rules(next_due_date, is_active)',
];

/// Every statement for schema v1, in dependency order.
///
/// Order matters: SQLite resolves foreign keys at execution time when
/// `PRAGMA foreign_keys = ON`, so a table must exist before another
/// references it. `transactions` and `recurring_rules` reference each other,
/// which SQLite tolerates because the constraint is checked on write, not on
/// create — `transactions` is created first and `recurring_rules` follows.
const List<String> v1Statements = <String>[
  createSchemaMigrations,
  _createUsers,
  _createAccounts,
  _createCategories,
  _createReceiptScans,
  _createTransactions,
  _createRecurringRules,
  _createTransfers,
  _createTransactionSplits,
  _createMoneyPlans,
  _createPlanAllocations,
  _createReceiptItems,
  _createKeywordDictionary,
  ..._createIndexes,
];
