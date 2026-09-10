# Moneyora — Database Design Document v1.0

> **Derived, non-authoritative transcript** of `Moneyora_DBD_v1.0.pdf`.
> The PDF is the approved baseline. Where this file and the PDF differ, **the PDF wins**.
> Amendments live in [`SPEC_ERRATA.md`](../SPEC_ERRATA.md), never here.

| Field | Value |
|---|---|
| Document Version | 1.0 — Final |
| Date | 27 June 2026 |
| Based On | SRS v1.0 + SDD v1.0 (Both Approved) |
| Database Engine | SQLite 3.x with SQLCipher AES-256 Encryption |
| Access Layer | sqflite_sqlcipher (Flutter package) |
| Schema Version | v1 — Initial Production Schema |
| Tables | "10 Core Tables + 1 Migration Table" *(the document defines 12 — see §1.2 note)* |
| Total Indexes | 12 Performance Indexes |
| Status | APPROVED — READY FOR IMPLEMENTATION |

---

## 1. Introduction

### 1.1 Purpose

This DBD defines the complete data storage architecture for Moneyora: all table schemas,
relationships, constraints, indexes, migration strategy, encryption approach, and seed
data. It is the authoritative reference for all data layer implementation in Sprint 1 and
the foundation for the Domain entities and Repository contracts defined in the SDD v1.0.

### 1.2 Scope

- 10 core application tables + 1 migration tracking table = 11 tables total
- 12 performance indexes covering all common query patterns
- Complete foreign key relationships with cascade rules
- AES-256 encryption via SQLCipher on the entire database file
- Versioned migration scripts for every future schema change
- Default seed data: 18 categories + 200+ keyword dictionary entries
- All tables derived directly from SRS v1.0 functional requirements

> **Count conflict.** §3 defines twelve tables (users, accounts, categories, transactions,
> transfers, recurring_rules, money_plans, plan_allocations, receipt_scans, receipt_items,
> keyword_dictionary, schema_migrations) — eleven core plus one migration table, not ten
> plus one. The ERD cover states "12 Tables".

### 1.3 Design Principles

| Principle | Implementation |
|---|---|
| Offline-First | All data lives locally in SQLite. No cloud dependency for core features. |
| Encryption by Default | SQLCipher encrypts the entire `.db` file with AES-256. Applied at open time. |
| Referential Integrity | All foreign keys enforced with `FOREIGN KEY` pragma enabled on every connection. |
| Soft Deletes | No hard deletes for transactions or accounts — `is_archived` / `is_deleted` flags preserve history. |
| Versioned Schema | Every schema change increments the db version. Migration scripts are never destructive. |
| Audit Timestamps | Every table includes `created_at`. Mutable tables include `updated_at`. ISO 8601 text. |
| Additive Migrations | `ALTER TABLE ADD COLUMN` only. No `DROP COLUMN`, no `RENAME TABLE` in migrations. |

> **Soft Deletes** is the design principle that E-25's account-deletion finding runs
> against. No `is_deleted` column is defined on any table in §3.

---

## 2. Entity Relationship Diagram

### 2.1 Full ERD

The ERD block in the PDF lists each entity with its columns and PK/FK markers. Its
`accounts` block omits `color` and `sort_order` (both present in §3.2), and its
`recurring_rules` block names the FK `transaction_id` where §3.6 names it
`template_tx_id`. Read §3 for the schemas; the ERD block is a summary, not the source.

Its own `users` block also names the lookback column `plan_analysis_months`, which
disagrees with §3.1's `plan_lookback_months` two pages later — the same document naming
the same column two different ways.

### 2.2 Relationship Summary

| Parent Table | Child Table | Cardinality | On Delete | Description |
|---|---|---|---|---|
| users | accounts | 1 : N | CASCADE DELETE | One user owns many accounts |
| users | categories | 1 : N | CASCADE DELETE | One user owns many categories |
| users | money_plans | 1 : N | CASCADE DELETE | One user owns many plans |
| users | receipt_scans | 1 : N | CASCADE DELETE | One user owns many receipt scans |
| accounts | transactions | 1 : N | RESTRICT | One account has many transactions |
| categories | transactions | 1 : N | RESTRICT | One category has many transactions |
| transactions | recurring_rules | 1 : 0..1 | CASCADE DELETE | A transaction may have one recurrence rule |
| money_plans | plan_allocations | 1 : N | CASCADE DELETE | One plan has many category allocations |
| categories | plan_allocations | 1 : N | RESTRICT | One category used in many plan allocations |
| receipt_scans | receipt_items | 1 : N | CASCADE DELETE | One scan produces many line items |
| categories | receipt_items | 1 : N | SET NULL | Category suggested/confirmed for each item |
| categories | keyword_dictionary | 1 : N | CASCADE DELETE | Keywords map to categories |
| categories | categories (self) | 1 : N | SET NULL | Parent-child category hierarchy (max 2 levels) |

---

## 3. Table Schemas

### 3.1 users

Application-level user preferences and security settings. Single-user app — always
exactly one row.

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY | Always 1 (single user app) |
| passcode_hash | TEXT | NULLABLE | SHA-256 hash of PIN (null = no passcode) |
| biometric_enabled | INTEGER | DEFAULT 0, NOT NULL | 1=enabled, 0=disabled |
| theme | TEXT | DEFAULT 'light', NOT NULL | 'light' or 'dark' |
| language | TEXT | DEFAULT 'en', NOT NULL | ISO 639-1 language code |
| currency | TEXT | DEFAULT 'LKR', NOT NULL | ISO 4217 currency code |
| first_day_week | INTEGER | DEFAULT 0, NOT NULL | 0=Sunday, 1=Monday |
| first_day_month | INTEGER | DEFAULT 1, NOT NULL | Day 1-28 |
| savings_target_pct | REAL | DEFAULT 0.0, NOT NULL | Monthly savings target 0.0-100.0 |
| plan_lookback_months | INTEGER | DEFAULT 6, NOT NULL | Months of history for plan generation |
| created_at | TEXT | NOT NULL | ISO 8601 timestamp of first launch |

> Two problems here. The SRS §6.2 names the lookback column `plan_analysis_months`.
> And `passcode_hash` is specified as a **bare SHA-256** of a 4–6 digit PIN, with no salt
> column, no KDF and no iteration count — a 10,000-entry search space for a 4-digit PIN.
> There is also no column anywhere for the lockout state that NFR-SEC-003's exponential
> backoff requires.

### 3.2 accounts

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated account ID |
| user_id | INTEGER | FK users(id), NOT NULL | Owner (always 1 in single-user app) |
| name | TEXT | NOT NULL | User-defined account name e.g. 'Cash' |
| icon | TEXT | NOT NULL | Icon identifier string e.g. 'ic_cash' |
| color | TEXT | DEFAULT '#2E7D32' | Hex color for account display |
| currency | TEXT | DEFAULT 'LKR', NOT NULL | ISO 4217 code for this account |
| initial_balance | REAL | DEFAULT 0.0, NOT NULL | Opening balance when account created |
| current_balance | REAL | DEFAULT 0.0, NOT NULL | Computed balance (updated on each transaction) |
| initial_balance_date | TEXT | NOT NULL | ISO 8601 date of opening balance |
| include_in_total | INTEGER | DEFAULT 1, NOT NULL | 1=include in combined balance display |
| is_archived | INTEGER | DEFAULT 0, NOT NULL | 1=hidden from active views, 0=active |
| sort_order | INTEGER | DEFAULT 0 | Display order in account list |
| created_at | TEXT | NOT NULL | ISO 8601 creation timestamp |
| updated_at | TEXT | NOT NULL | ISO 8601 last update timestamp |

> `currency` exists per account, but no table anywhere stores exchange rates. FR-ACC-005's
> conversion has no schema support in v1.

### 3.3 categories

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated category ID |
| user_id | INTEGER | FK users(id), NOT NULL | Owner user |
| name | TEXT | NOT NULL | Category name e.g. 'Food', 'Salary' |
| icon | TEXT | NOT NULL | Icon identifier string |
| color | TEXT | NOT NULL | Hex color for chart display |
| type | TEXT | CHECK(type IN ('expense','income')) | Category type |
| parent_id | INTEGER | FK categories(id), NULLABLE | Parent category (null = top-level) |
| is_default | INTEGER | DEFAULT 0, NOT NULL | 1=system default, 0=user-created |
| sort_order | INTEGER | DEFAULT 0 | Display order within type |
| created_at | TEXT | NOT NULL | ISO 8601 creation timestamp |

> `parent_id` supports FR-EXP-005's two-level hierarchy, but nothing in the schema enforces
> the two-level maximum.

### 3.4 transactions

Central table. Every financial event — expense, income, or transfer — creates one row.

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| account_id | INTEGER | FK accounts(id), NOT NULL | Account this transaction belongs to |
| category_id | INTEGER | FK categories(id), NOT NULL | Category of this transaction |
| amount | REAL | NOT NULL, CHECK(amount > 0) | Transaction amount (always positive) |
| type | TEXT | CHECK(type IN ('expense','income','transfer')) | Transaction type |
| date | TEXT | NOT NULL | ISO 8601 date e.g. '2026-06-17' |
| time | TEXT | NULLABLE | HH:MM time of transaction |
| note | TEXT | NULLABLE | Optional user note |
| receipt_image_path | TEXT | NULLABLE | Path to attached receipt image |
| is_recurring | INTEGER | DEFAULT 0, NOT NULL | 1=generated by recurring rule |
| recurring_rule_id | INTEGER | FK recurring_rules(id), NULLABLE | Source recurring rule (if any) |
| receipt_batch_id | INTEGER | FK receipt_scans(id), NULLABLE | Receipt scan that created this (if any) |
| created_at | TEXT | NOT NULL | ISO 8601 insert timestamp |
| updated_at | TEXT | NOT NULL | ISO 8601 last edit timestamp |

> `amount REAL` — the codebase stores `*_cents INTEGER` instead. That deviation is errata-recorded.

### 3.5 transfers

Each transfer also creates two rows in `transactions` (one debit, one credit).

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated transfer ID |
| from_account_id | INTEGER | FK accounts(id), NOT NULL | Source account (debit) |
| to_account_id | INTEGER | FK accounts(id), NOT NULL | Destination account (credit) |
| amount | REAL | NOT NULL, CHECK(amount > 0) | Amount transferred |
| date | TEXT | NOT NULL | ISO 8601 date |
| note | TEXT | NULLABLE | Optional note |
| from_tx_id | INTEGER | FK transactions(id) | Debit transaction row created |
| to_tx_id | INTEGER | FK transactions(id) | Credit transaction row created |
| created_at | TEXT | NOT NULL | ISO 8601 creation timestamp |

> A single `amount` column with no currency field. Cross-currency transfers under
> FR-TRF-001 have no representation here.

### 3.6 recurring_rules

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| template_tx_id | INTEGER | FK transactions(id), NOT NULL | Template transaction to copy |
| frequency | TEXT | CHECK(frequency IN ('daily','weekly','monthly','yearly','custom')) | Recurrence type |
| interval_days | INTEGER | NULLABLE | Used when frequency='custom' |
| start_date | TEXT | NOT NULL | First occurrence date |
| end_date | TEXT | NULLABLE | Stop after this date (null=forever) |
| next_due_date | TEXT | NOT NULL | Date of next transaction to generate |
| is_active | INTEGER | DEFAULT 1, NOT NULL | 1=active, 0=paused |
| created_at | TEXT | NOT NULL | ISO 8601 creation timestamp |

### 3.7 money_plans

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated plan ID |
| user_id | INTEGER | FK users(id), NOT NULL | Owner user |
| name | TEXT | NOT NULL | Plan name e.g. 'June Monthly Plan' |
| period_type | TEXT | CHECK(period_type IN ('day','week','month','year','custom')) | Time period type |
| start_date | TEXT | NOT NULL | Plan start date ISO 8601 |
| end_date | TEXT | NOT NULL | Plan end date ISO 8601 |
| total_budget | REAL | NULLABLE | Total budget cap (null=sum of allocations) |
| is_active | INTEGER | DEFAULT 0, NOT NULL | 1=currently active plan, 0=saved/archived |
| created_at | TEXT | NOT NULL | ISO 8601 creation timestamp |

### 3.8 plan_allocations

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| plan_id | INTEGER | FK money_plans(id), NOT NULL | Parent plan |
| category_id | INTEGER | FK categories(id), NOT NULL | Category being allocated |
| allocated_amount | REAL | NOT NULL, CHECK(allocated_amount >= 0) | Budget allocated for this category |
| spent_amount | REAL | DEFAULT 0.0, NOT NULL | Actual spent (updated on each transaction) |
| confidence_level | TEXT | CHECK(confidence_level IN ('High','Medium','Low')) | AI prediction confidence |
| expense_type | TEXT | CHECK(expense_type IN ('Fixed','Variable','Seasonal')) | AI classification |
| is_user_modified | INTEGER | DEFAULT 0, NOT NULL | 1=user manually adjusted this allocation |
| notes | TEXT | NULLABLE | AI suggestion notes for this category |

> `expense_type` appears here but not in the SRS §6.2 version of this table.

### 3.9 receipt_scans

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated scan ID |
| user_id | INTEGER | FK users(id), NOT NULL | Owner user |
| image_path | TEXT | NOT NULL | Encrypted file path on device |
| merchant_name | TEXT | NULLABLE | Detected merchant/store name |
| receipt_date | TEXT | NULLABLE | Date printed on receipt (ISO 8601) |
| total_amount | REAL | NULLABLE | Total amount detected on receipt |
| tax_amount | REAL | NULLABLE | Tax / VAT amount detected |
| confidence_score | INTEGER | CHECK(confidence_score BETWEEN 0 AND 100) | Overall OCR confidence 0-100 |
| status | TEXT | CHECK(status IN ('pending','confirmed','rejected')) | Scan confirmation status |
| item_count | INTEGER | DEFAULT 0, NOT NULL | Number of line items detected |
| created_at | TEXT | NOT NULL | ISO 8601 scan timestamp |

> FR-RCP-005 requires parsing a **receipt ID/number**. No column stores it.

### 3.10 receipt_items

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated item ID |
| receipt_scan_id | INTEGER | FK receipt_scans(id), NOT NULL | Parent receipt scan |
| name | TEXT | NOT NULL | Item description from OCR |
| quantity | REAL | DEFAULT 1.0, NOT NULL | Quantity (e.g. 2 for 2x items) |
| unit_price | REAL | NULLABLE | Price per unit (if detected) |
| total_price | REAL | NOT NULL, CHECK(total_price >= 0) | Line total for this item |
| suggested_category_id | INTEGER | FK categories(id), NULLABLE | AI-suggested category |
| confirmed_category_id | INTEGER | FK categories(id), NULLABLE | User-confirmed final category |
| confidence_score | INTEGER | CHECK(confidence_score BETWEEN 0 AND 100) | Categorization confidence |
| transaction_id | INTEGER | FK transactions(id), NULLABLE | Created transaction (after confirmation) |
| is_discarded | INTEGER | DEFAULT 0, NOT NULL | 1=user removed this item |

### 3.11 keyword_dictionary

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| keyword | TEXT | NOT NULL | Keyword to match (lowercase) |
| category_id | INTEGER | FK categories(id), NOT NULL | Target category for this keyword |
| match_type | TEXT | CHECK(match_type IN ('exact','contains','startswith')) | How to match the keyword |
| priority | INTEGER | DEFAULT 5, CHECK(priority BETWEEN 1 AND 10) | Match priority — user entries=10 |
| usage_count | INTEGER | DEFAULT 0, NOT NULL | Times this mapping was applied |
| is_user_defined | INTEGER | DEFAULT 0, NOT NULL | 1=user-created, 0=system default |
| created_at | TEXT | NOT NULL | ISO 8601 creation timestamp |

### 3.12 schema_migrations

| Column | Type | Constraints | Description |
|---|---|---|---|
| id | INTEGER | PRIMARY KEY AUTOINCREMENT | Auto-generated ID |
| version | INTEGER | UNIQUE, NOT NULL | Schema version number (matches db version) |
| description | TEXT | NOT NULL | Human-readable migration description |
| applied_at | TEXT | NOT NULL | ISO 8601 timestamp when migration ran |
| checksum | TEXT | NULLABLE | SHA-256 of migration SQL for integrity check |

> The SDD §5.3 calls this table `schema_version`. Conflict.

---

## 4. Relationships & Constraints

### 4.1 Foreign Key Configuration

SQLite does not enforce foreign keys by default. Execute on every connection open:

```sql
PRAGMA foreign_keys = ON;
PRAGMA journal_mode = WAL;      -- Write-Ahead Logging for better concurrency
PRAGMA synchronous = NORMAL;    -- Balance between safety and performance
```

### 4.2 Check Constraints Summary

| Column | Constraint |
|---|---|
| transactions.type | IN ('expense', 'income', 'transfer') |
| transactions.amount | > 0 |
| categories.type | IN ('expense', 'income') |
| plan_allocations.allocated_amount | >= 0 |
| plan_allocations.confidence_level | IN ('High', 'Medium', 'Low') |
| plan_allocations.expense_type | IN ('Fixed', 'Variable', 'Seasonal') |
| receipt_scans.confidence_score | BETWEEN 0 AND 100 |
| receipt_scans.status | IN ('pending', 'confirmed', 'rejected') |
| receipt_items.total_price | >= 0 |
| receipt_items.confidence_score | BETWEEN 0 AND 100 |
| keyword_dictionary.match_type | IN ('exact', 'contains', 'startswith') |
| keyword_dictionary.priority | BETWEEN 1 AND 10 |
| recurring_rules.frequency | IN ('daily', 'weekly', 'monthly', 'yearly', 'custom') |
| transfers.amount | > 0 |
| users.first_day_week | IN (0, 1) |
| users.first_day_month | BETWEEN 1 AND 28 |

### 4.3 Unique Constraints

| Table | Unique Columns | Reason |
|---|---|---|
| accounts | user_id + name | No duplicate account names per user |
| categories | user_id + name + type | No duplicate category names per type per user |
| money_plans | user_id + name | No duplicate plan names per user |
| keyword_dictionary | keyword + category_id | No duplicate keyword-category mappings |
| schema_migrations | version | Each migration version applied only once |
| plan_allocations | plan_id + category_id | One allocation per category per plan |

---

## 5. Indexing Strategy

### 5.1 Index Definitions

All indexes created in migration version 1.

```sql
-- Core transaction query indexes
CREATE INDEX idx_tx_date          ON transactions(date);
CREATE INDEX idx_tx_account_date  ON transactions(account_id, date);
CREATE INDEX idx_tx_category      ON transactions(category_id);
CREATE INDEX idx_tx_type_date     ON transactions(type, date);
CREATE INDEX idx_tx_batch         ON transactions(receipt_batch_id);

-- Account & category indexes
CREATE INDEX idx_accounts_user    ON accounts(user_id, is_archived);
CREATE INDEX idx_cat_user_type    ON categories(user_id, type);

-- Plan tracking indexes
CREATE INDEX idx_plan_alloc_plan  ON plan_allocations(plan_id);
CREATE INDEX idx_plan_alloc_cat   ON plan_allocations(category_id);

-- Receipt scanner indexes
CREATE INDEX idx_receipt_items    ON receipt_items(receipt_scan_id);
CREATE INDEX idx_receipt_status   ON receipt_scans(status, created_at);

-- Keyword lookup index (critical for OCR speed)
CREATE INDEX idx_keyword_lookup   ON keyword_dictionary(keyword, priority DESC);
```

### 5.2 Query-to-Index Mapping

| Query | Index Used | Target Performance |
|---|---|---|
| Home screen chart (date range) | idx_tx_account_date | < 5 ms for 10k rows |
| Category totals for pie chart | idx_tx_category | < 5 ms for 10k rows |
| Transaction list (filtered by date) | idx_tx_date | < 3 ms for 10k rows |
| Expense vs income split | idx_tx_type_date | < 5 ms for 10k rows |
| Money plan analysis (6 months) | idx_tx_category + idx_tx_date | < 50 ms for 10k rows |
| Plan vs actual tracking | idx_plan_alloc_plan | < 2 ms |
| Receipt items for a scan | idx_receipt_items | < 1 ms |
| Keyword categorization (OCR) | idx_keyword_lookup | < 1 ms per keyword |
| Account balance calculation | idx_accounts_user | < 2 ms |

> These per-query targets are far tighter than NFR-PER-006's 100 ms and carry no
> requirement IDs of their own.

---

## 6. Data Flow & Access Patterns

### 6.1 Data Flow

`UI / ViewModel → Use Case (Domain) → Repository Impl (Data) → SQLite + SQLCipher`.
Optional branches: ML Kit OCR on-device; Cloud AI (Gemini/OpenAI); Exchange Rate API
(optional, cached). The core path is 100% offline.

### 6.2 Common Query Patterns

**Add Expense**

```sql
BEGIN TRANSACTION;
INSERT INTO transactions (account_id, category_id, amount, type, date, ...) VALUES (...);
UPDATE accounts SET current_balance = current_balance - ? WHERE id = ?;
UPDATE plan_allocations SET spent_amount = spent_amount + ?
  WHERE plan_id = (SELECT id FROM money_plans WHERE is_active=1)
    AND category_id = ?;
COMMIT;
```

**Home Screen Chart Data**

```sql
SELECT c.name, c.color, c.icon, SUM(t.amount) as total
FROM transactions t JOIN categories c ON t.category_id = c.id
WHERE t.account_id = ? AND t.type = 'expense'
  AND t.date BETWEEN ? AND ?
GROUP BY t.category_id
ORDER BY total DESC;
```

**Money Plan Analysis**

```sql
SELECT t.category_id,
       AVG(monthly_total) as avg_monthly,
       (strftime('%Y-%m', t.date)) as month
FROM transactions t
WHERE t.type='expense'
  AND t.date >= date('now', '-6 months')
GROUP BY t.category_id, strftime('%Y-%m', t.date)
ORDER BY t.category_id, month;
```

**Plan vs Actual Progress**

```sql
SELECT pa.category_id, c.name, c.icon,
       pa.allocated_amount,
       pa.spent_amount,
       ROUND(pa.spent_amount * 100.0 / pa.allocated_amount, 1) as pct_used,
       pa.confidence_level
FROM plan_allocations pa
JOIN categories c ON pa.category_id = c.id
WHERE pa.plan_id = ?
ORDER BY pct_used DESC;
```

**Receipt OCR Keyword Lookup**

```sql
SELECT kd.category_id, kd.priority, c.name
FROM keyword_dictionary kd
JOIN categories c ON kd.category_id = c.id
WHERE (kd.match_type = 'exact'      AND kd.keyword = lower(?))
   OR (kd.match_type = 'contains'   AND lower(?) LIKE '%' || kd.keyword || '%')
   OR (kd.match_type = 'startswith' AND lower(?) LIKE kd.keyword || '%')
ORDER BY kd.priority DESC
LIMIT 1;
```

---

## 7. Migration Strategy

### 7.1 Migration Architecture

- The SQLite `user_version` PRAGMA tracks the current schema version
- On every app launch, `DatabaseHelper.onUpgrade()` is called if version increased
- Each migration is a single Dart function: `Future migrateVxToVy(Database db)`
- Migrations are additive only — never DROP COLUMN or DROP TABLE
- Every migration inserts a row into `schema_migrations` upon completion
- Migrations run in sequence — v1→v2→v3, never v1→v3 directly

### 7.2 Migration Script v1 — Initial Schema

```dart
// migration_v1.dart — Creates all tables and indexes
Future migrateV0ToV1(Database db) async {
  await db.execute('PRAGMA foreign_keys = ON;');
  await db.execute('PRAGMA journal_mode = WAL;');

  await db.execute('''
    CREATE TABLE IF NOT EXISTS users (
      id INTEGER PRIMARY KEY,
      passcode_hash TEXT,
      biometric_enabled INTEGER DEFAULT 0 NOT NULL,
      theme TEXT DEFAULT 'light' NOT NULL,
      language TEXT DEFAULT 'en' NOT NULL,
      currency TEXT DEFAULT 'LKR' NOT NULL,
      first_day_week INTEGER DEFAULT 0 NOT NULL
        CHECK(first_day_week IN (0,1)),
      first_day_month INTEGER DEFAULT 1 NOT NULL
        CHECK(first_day_month BETWEEN 1 AND 28),
      savings_target_pct REAL DEFAULT 0.0 NOT NULL,
      plan_lookback_months INTEGER DEFAULT 6 NOT NULL,
      created_at TEXT NOT NULL
    );
  ''');
  // ... (all CREATE TABLE statements) ...

  await db.execute('CREATE INDEX idx_tx_date ON transactions(date);');
  // ... (all CREATE INDEX statements) ...

  await _seedDefaultUser(db);
  await _seedDefaultCategories(db);
  await _seedKeywordDictionary(db);

  await db.insert('schema_migrations', {
    'version': 1,
    'description': 'Initial schema — all tables, indexes, seed data',
    'applied_at': DateTime.now().toIso8601String(),
  });
}
```

### 7.3 Future Migration Template

```dart
// migration_v2.dart — Example: adding a new column
Future migrateV1ToV2(Database db) async {
  // SAFE: ADD COLUMN is always backward compatible
  await db.execute('ALTER TABLE transactions ADD COLUMN tags TEXT;');

  await db.insert('schema_migrations', {
    'version': 2,
    'description': 'Added tags column to transactions',
    'applied_at': DateTime.now().toIso8601String(),
  });
}

// NEVER do this:
// await db.execute('DROP COLUMN xyz');        // FORBIDDEN
// await db.execute('DROP TABLE accounts');    // FORBIDDEN
// await db.execute('ALTER TABLE RENAME');     // FORBIDDEN in migrations
```

---

## 8. Encryption & Security

### 8.1 SQLCipher Setup

The entire SQLite file is encrypted with AES-256-CBC via SQLCipher. Encryption is
transparent — all SQL queries work identically.

```dart
// pubspec.yaml
//   sqflite_sqlcipher: ^2.2.0
//   flutter_secure_storage: ^9.0.0

Future _openEncryptedDB() async {
  final storage = FlutterSecureStorage();
  String? key = await storage.read(key: 'moneyora_db_key');
  if (key == null) {
    final bytes = List.generate(32, (_) => Random.secure().nextInt(256));
    key = base64Url.encode(bytes);
    await storage.write(key: 'moneyora_db_key', value: key);
  }
  final dbPath = await getDatabasesPath();
  return openDatabase(
    join(dbPath, 'moneyora.db'),
    password: key,            // <-- SQLCipher AES-256 key
    version: 1,
    onCreate: _onCreate,
    onUpgrade: _onUpgrade,
    onOpen: (db) async {
      await db.execute('PRAGMA foreign_keys = ON;');
      await db.execute('PRAGMA journal_mode = WAL;');
    },
  );
}
```

> Storage key is `moneyora_db_key` here, `db_encryption_key` in SDD §5.4. Conflict.

### 8.2 Key Management

| Aspect | Implementation |
|---|---|
| Key Generation | 32 random bytes via Dart's `Random.secure()` — cryptographically secure |
| Key Storage | iOS: Keychain (via flutter_secure_storage) — Android: Android Keystore |
| Key Encoding | Base64URL encoded before storage — URL-safe, no special characters |
| Key Rotation | Not implemented in v1 — planned for v2 (requires re-keying the DB) |
| Key Backup | Key is NOT included in data backups — intentional (backup is useless without device) |
| Lost Key Recovery | If key is lost (factory reset without backup), data is unrecoverable — by design |

> "Key is NOT included in data backups" and FR-BAK-005's cross-device restore need to be
> read together: the backup file must be independently decryptable, or restore cannot work.

---

## 9. Default Seed Data

### 9.1 Default Categories

Inserted by `_seedDefaultCategories()` on first launch (migration v1). 18 defaults
matching SRS FR-EXP-003 (15 expense) and FR-INC-002 (3 income).

| ID | Name | Type | Icon Key | Default Color | is_default |
|---|---|---|---|---|---|
| 1 | Bills | expense | ic_bills | #E53935 | 1 |
| 2 | Car | expense | ic_car | #FB8C00 | 1 |
| 3 | Clothes | expense | ic_clothes | #8E24AA | 1 |
| 4 | Communications | expense | ic_phone | #039BE5 | 1 |
| 5 | Eating Out | expense | ic_restaurant | #F4511E | 1 |
| 6 | Entertainment | expense | ic_entertainment | #E91E63 | 1 |
| 7 | Food | expense | ic_food | #43A047 | 1 |
| 8 | Gifts | expense | ic_gift | #FFB300 | 1 |
| 9 | Health | expense | ic_health | #E53935 | 1 |
| 10 | House | expense | ic_house | #3949AB | 1 |
| 11 | Pets | expense | ic_pet | #00897B | 1 |
| 12 | Sports | expense | ic_sports | #7CB342 | 1 |
| 13 | Taxi | expense | ic_taxi | #FFD600 | 1 |
| 14 | Toiletry | expense | ic_toiletry | #26C6DA | 1 |
| 15 | Transport | expense | ic_transport | #5E35B1 | 1 |
| 16 | Deposits | income | ic_deposit | #2E7D32 | 1 |
| 17 | Salary | income | ic_salary | #1B5E20 | 1 |
| 18 | Savings | income | ic_piggy | #00695C | 1 |

> Bills and Health share `#E53935`. In a donut chart keyed by colour, two categories with
> the same colour are indistinguishable.

### 9.2 Default Keyword Dictionary Sample

200+ entries seeded on first launch; full list in
`lib/core/database/seed/keyword_seed.dart`. Representative sample:

| Keyword | Maps To Category | Match Type | Priority |
|---|---|---|---|
| rice | Food | contains | 5 |
| bread | Food | contains | 5 |
| milk | Food | contains | 5 |
| noodles | Food | contains | 5 |
| restaurant | Eating Out | contains | 5 |
| kfc | Eating Out | exact | 5 |
| mcdonalds | Eating Out | contains | 5 |
| petrol | Car | contains | 5 |
| fuel | Car | contains | 5 |
| diesel | Car | contains | 5 |
| bus | Transport | exact | 5 |
| train | Transport | contains | 5 |
| uber | Taxi | exact | 5 |
| pickme | Taxi | exact | 5 |
| panadol | Health | contains | 5 |
| pharmacy | Health | contains | 5 |
| medicine | Health | contains | 5 |
| shampoo | Toiletry | contains | 5 |
| soap | Toiletry | contains | 5 |
| electricity | Bills | contains | 5 |
| water bill | Bills | contains | 5 |
| netflix | Entertainment | exact | 5 |
| spotify | Entertainment | exact | 5 |
| dialog | Communications | exact | 5 |
| mobitel | Communications | exact | 5 |
| salary | Salary | contains | 5 |
| deposit | Deposits | contains | 5 |
| savings | Savings | contains | 5 |

> `fuel` and `diesel` map to Car while `bus`/`train` map to Transport, but SRS Appendix A
> lists "fuel" under **both** Car and Transport. Ambiguous by construction.

---

*Moneyora DBD v1.0 | Generated 27 June 2026 | Status: APPROVED FOR IMPLEMENTATION.
Transcribed to Markdown; the PDF remains the baseline.*
