# Moneyora — Requirements Index

**Derived, non-authoritative.** Generated from `Moneyora_SRS_v1.0.pdf` (v1.0 Final,
20 June 2026). The PDF is the baseline. Where this file and the PDF differ, **the PDF
wins**. Amendments and corrections live in [`SPEC_ERRATA.md`](../SPEC_ERRATA.md), never
in this file.

**Purpose.** Every requirement ID in the SRS, with its text, in one flat greppable
table. Before citing an ID in a commit trailer or a doc comment, check it here. If it
is not in this table, it does not exist.

**Coverage.** 82 functional requirements across 9 groups, 28 non-functional
requirements across 5 groups. 110 total.

---

## Functional requirements

### FR-EXP — Expense Tracking (SRS §3.1)

| ID | Requirement |
|---|---|
| FR-EXP-001 | Record an expense with: amount, category, account, date, time, and optional text note. |
| FR-EXP-002 | Custom numeric keypad supporting operators `+`, `-`, `*`, `/` and equals for quick arithmetic during entry. |
| FR-EXP-003 | 15 default expense categories: Bills, Car, Clothes, Communications, Eating Out, Entertainment, Food, Gifts, Health, House, Pets, Sports, Taxi, Toiletry, Transport. |
| FR-EXP-004 | Users can create unlimited custom expense categories with user-defined name, icon (from built-in set), and color. |
| FR-EXP-005 | Hierarchical sub-categories (Parent Category → Child Sub-category, maximum 2 levels deep). |
| FR-EXP-006 | Display all expenses in a chronological list, grouped by date with collapsible date section headers showing daily totals. |
| FR-EXP-007 | Show a running balance per account and a combined total balance across all included accounts. |
| FR-EXP-008 | Support recurring expenses with frequencies: Daily, Weekly, Monthly, Yearly, and Custom interval (N days). |
| FR-EXP-009 | Allow attaching a photo or scanned receipt image to any expense transaction for future reference. |
| FR-EXP-010 | Support splitting a single expense entry across multiple categories with individual amounts summing to the total. |

### FR-INC — Income Tracking (SRS §3.2)

| ID | Requirement |
|---|---|
| FR-INC-001 | Record income with: amount, category, account, date, and optional note. |
| FR-INC-002 | 3 default income categories: Deposits, Salary, Savings. |
| FR-INC-003 | Allow creation of custom income categories. |
| FR-INC-004 | Support recurring income entries using the same frequency options as expenses. |
| FR-INC-005 | Visually distinguish income from expenses — income in green, expenses in red — in all list and chart views. |

### FR-ACC — Account Management (SRS §3.3)

| ID | Requirement |
|---|---|
| FR-ACC-001 | Support multiple named accounts of types: Cash, Bank Account, Credit Card, Digital Wallet, Cryptocurrency, and Custom. |
| FR-ACC-002 | Each account stores: name, icon (from 20+ built-in icons), currency, initial balance, initial balance date, and an "Include in Total Balance" toggle. |
| FR-ACC-003 | Display all accounts with current balances in a side-drawer panel accessible from the main screen. |
| FR-ACC-004 | Support account archiving — hiding accounts from active views without deleting transaction history. |
| FR-ACC-005 | Support multi-currency accounts with user-configurable exchange rates for balance conversion. |
| FR-ACC-006 | Provide 20+ built-in account icons including: Cash, AMEX, VISA, Mastercard, PayPal, Bitcoin, JCB, QIWI, Stripe, Discover, and others. |

> No FR-ACC requirement authorises **deleting** an account. See E-25.

### FR-TRF — Transfer Management (SRS §3.4)

| ID | Requirement |
|---|---|
| FR-TRF-001 | Allow users to transfer funds between any two active accounts. |
| FR-TRF-002 | Transfers recorded as a single atomic transaction: debit from source account, credit to destination account. |
| FR-TRF-003 | Allow adding a note and custom date to each transfer. |
| FR-TRF-004 | Transfers visually distinct in transaction lists — shown with a bidirectional arrow icon and labeled "From [Account]" / "To [Account]". |

### FR-PLN — Money Plan Generator (SRS §3.5)

| ID | Requirement |
|---|---|
| FR-PLN-001 | Provide a "Create Money Plan" feature accessible from the main navigation menu. |
| FR-PLN-002 | User selects plan period from: Day, Week, Month, Year, Custom number of days, or Custom date range. |
| FR-PLN-003 | Analyze expense history over a configurable lookback period (default 6 months; user-adjustable 1–24 months in Settings). |
| FR-PLN-004 | Automatically classify each category's expenses into Fixed (recurring, low variance), Variable (fluctuating), and Seasonal (periodic spikes). |
| FR-PLN-005 | Calculate and store per-category statistics: mean spend, median spend, standard deviation, min/max, transaction frequency, and trend direction. |
| FR-PLN-006 | Detect behavioral spending patterns: weekday vs weekend, beginning-of-month vs end-of-month, seasonal cycles, event-based spikes. |
| FR-PLN-007 | Budget allocation calculated using: exact recent average for fixed; weighted moving average (recent 3 months 60%, older 40%) for variable; seasonal multiplier where historical data shows a spike in the planned period; trend adjustment (+5–10% buffer if increasing, reduction if decreasing). |
| FR-PLN-008 | Two total budget modes: Option A — user sets a total and the app distributes proportionally; Option B — app suggests a total from historical income minus fixed expenses minus savings target. |
| FR-PLN-009 | Compute and display a daily allowance breakdown per category. |
| FR-PLN-010 | Display a confidence level (High / Medium / Low) per category allocation, based on data sufficiency and historical variance. |
| FR-PLN-011 | Allow users to manually adjust any generated allocation before saving, with other allocations recalculating to maintain the total budget. |
| FR-PLN-012 | Provide a "What-If" scenario tool: if Category A is reduced by X%, how much more can be allocated to Category B. |
| FR-PLN-013 | Track actual spending vs the active plan in real time: percentage used per category, projected overspend/underspend, colour indicators (Green on track, Yellow 80–99%, Red exceeded). |
| FR-PLN-014 | When a category budget is exceeded, offer three responses: Auto-Redistribute, Manual Adjust, or Carry Over. |
| FR-PLN-015 | Allow saving multiple named plans and comparing any two plans side by side. |

### FR-RCP — Receipt Scanner (SRS §3.6)

| ID | Requirement |
|---|---|
| FR-RCP-001 | Provide a "Scan Receipt" button accessible from both the main screen and the add-expense flow. |
| FR-RCP-002 | Support image input via device camera (live capture) or selection from photo gallery. |
| FR-RCP-003 | Perform offline image preprocessing: automatic deskew, contrast enhancement, binarization, noise reduction, and perspective correction. |
| FR-RCP-004 | Perform OCR using Google ML Kit Text Recognition v2 (offline-capable) to extract all text from the preprocessed image. |
| FR-RCP-005 | Parse OCR output to identify: merchant/store name, receipt date and time, individual line items (product name, quantity, unit price, total price), receipt total, tax/VAT amount if present, and receipt ID/number. |
| FR-RCP-006 | Handle multi-item receipts and parse each line item individually. |
| FR-RCP-007 | Categorize each extracted item using a three-layer system: (1) keyword dictionary, (2) user history, (3) merchant context bias. Each categorization receives a confidence score (0–100%). |
| FR-RCP-008 | Display a "Review & Confirm" screen: receipt thumbnail, parsed items with suggested categories, editable fields per item, ability to merge or split items, ability to discard incorrect items. |
| FR-RCP-009 | Create individual expense transactions for each confirmed item, linked under a single "Receipt Batch" record for traceability. |
| FR-RCP-010 | Provide a "Single Category" mode assigning one category to the entire receipt total rather than per-item categorization. |
| FR-RCP-011 | Handle edge cases with explicit flags: handwritten receipts (lower accuracy warning), damaged/faded receipts ("Low Confidence" badge), non-standard formats. |
| FR-RCP-012 | Store the original receipt image encrypted and linked to the resulting transaction(s). |
| FR-RCP-013 | Provide a searchable "Receipt History" view showing all previously scanned receipts with thumbnail, date, and total amount. |
| FR-RCP-014 | Allow re-scanning or re-processing a previously captured receipt image. |
| FR-RCP-015 | Implement learning from user corrections: when a user changes a suggested category, update the personal keyword dictionary for future scans. |

### FR-RPT — Analytics & Reporting (SRS §3.7)

| ID | Requirement |
|---|---|
| FR-RPT-001 | Display a donut/pie chart on the home screen showing expense distribution by category with percentage labels and category icons. |
| FR-RPT-002 | Support time period filters: Day, Week, Month, Year, All, Custom Interval, Choose Date. |
| FR-RPT-003 | Support account filter: All Accounts, or any specific single account. |
| FR-RPT-004 | Show income vs expense comparison bar charts with net savings highlighted. |
| FR-RPT-005 | Provide trend line charts showing per-category spending over time. |
| FR-RPT-006 | Calculate and display: total income, total expenses, net savings, average daily spend, largest spending category, and month-over-month change. |
| FR-RPT-007 | Support data export to CSV and PDF formats. |
| FR-RPT-008 | Provide a transaction search function filtering by amount range, category, note keyword, and date range. |
| FR-RPT-009 | Show a calendar heatmap view highlighting daily spending intensity. |

### FR-SET — Settings & Configuration (SRS §3.8)

| ID | Requirement |
|---|---|
| FR-SET-001 | Support Light Theme and Dark Theme with user toggle. |
| FR-SET-002 | Support multiple display languages (English default; framework ready for localization). |
| FR-SET-003 | Allow currency selection with LKR as default and support exchange rate configuration. |
| FR-SET-004 | Allow configuring first day of the week (Sunday/Monday) and first day of the month (1–28). |
| FR-SET-005 | Support passcode protection (4–6 digit PIN) and optional biometric authentication (Fingerprint / Face ID). |
| FR-SET-006 | Allow configuration of recurring expense/income reminder notifications. |
| FR-SET-007 | Provide budget alert notifications: warn at 80% usage and alert at 100% usage for any active plan category. |
| FR-SET-008 | Allow the user to set a monthly savings target percentage. |
| FR-SET-009 | Provide data management options: Create Backup, Restore Backup, Clear All Data. |
| FR-SET-010 | Allow optional Google Drive and Dropbox cloud synchronization configuration. |
| FR-SET-011 | Provide a "Copy Purchase ID" function for in-app purchase verification. |
| FR-SET-012 | Allow configuring the Money Plan analysis lookback period (default 6 months; range 1–24 months). |

> FR-SET-011 was withdrawn by E-12. It remains listed here because this index records the
> SRS baseline as written; the errata records the amendment.

> No FR-SET requirement covers multiple user profiles. See the note under
> "Known citation traps" below.

### FR-BAK — Backup & Synchronization (SRS §3.9)

| ID | Requirement |
|---|---|
| FR-BAK-001 | Create local encrypted backups in SQLite format, exportable as a `.mb` file (Moneyora backup). |
| FR-BAK-002 | Support automatic scheduled local backups (Daily / Weekly — user configurable). |
| FR-BAK-003 | Optionally integrate with Google Drive for cloud backup when internet is available. |
| FR-BAK-004 | Optionally integrate with Dropbox for cloud backup when internet is available. |
| FR-BAK-005 | Support cross-device data restore from any valid Moneyora backup file. |
| FR-BAK-006 | Display a backup reminder notification if no backup has been created in 7 days. |

---

## Non-functional requirements

### NFR-PER — Performance (SRS §5.1)

| ID | Metric | Target |
|---|---|---|
| NFR-PER-001 | App cold-start launch time | < 2 seconds |
| NFR-PER-002 | Expense entry from home screen | ≤ 3 taps to entry screen |
| NFR-PER-003 | Receipt scan processing (OCR + parse) | < 5 seconds for standard receipt |
| NFR-PER-004 | Money Plan generation (6 months data) | < 3 seconds |
| NFR-PER-005 | Chart rendering on home screen | < 1 second |
| NFR-PER-006 | Database queries (10,000 transactions) | < 100 ms per query |
| NFR-PER-007 | Backup creation (full data) | < 10 seconds for typical dataset |

### NFR-SEC — Security (SRS §5.2)

| ID | Requirement |
|---|---|
| NFR-SEC-001 | Database encrypted using AES-256 via SQLCipher at all times. |
| NFR-SEC-002 | Receipt images stored in encrypted app-private storage. |
| NFR-SEC-003 | Optional PIN protection: 4–6 digit, with 5-attempt lockout and exponential backoff. |
| NFR-SEC-004 | Optional biometric authentication (Fingerprint / Face ID). |
| NFR-SEC-005 | No financial data transmitted to any server without explicit user action. |
| NFR-SEC-006 | Cloud backups encrypted before upload. |
| NFR-SEC-007 | App shall not request unnecessary device permissions. |

### NFR-REL — Reliability & Availability (SRS §5.3)

| ID | Requirement |
|---|---|
| NFR-REL-001 | 100% core functionality available offline — zero internet dependency for basic use. |
| NFR-REL-002 | Zero data loss on unexpected app crashes — all transactions written atomically. |
| NFR-REL-003 | Auto-save: expense entries persisted immediately on confirmation. |
| NFR-REL-004 | Backup reminder if no backup has been created in 7 days. |
| NFR-REL-005 | Database migration support for all future app version upgrades. |

### NFR-MNT — Maintainability (SRS §5.4)

| ID | Requirement |
|---|---|
| NFR-MNT-001 | Clean Architecture pattern — strict separation of Presentation, Domain, Data layers. |
| NFR-MNT-002 | Minimum 75% unit test coverage for Domain layer (business logic). |
| NFR-MNT-003 | All public APIs documented with Dart doc comments. |
| NFR-MNT-004 | Comprehensive crash logging (Firebase Crashlytics or equivalent). |
| NFR-MNT-005 | Database schema versioned — migration scripts for every schema change. |

### NFR-PRT — Portability (SRS §5.5)

| ID | Requirement |
|---|---|
| NFR-PRT-001 | Single Flutter codebase targeting both iOS and Android. |
| NFR-PRT-002 | Responsive layout supporting screen widths 360–420 dp. |
| NFR-PRT-003 | Localization framework (`flutter_localizations`) integrated from the start. |
| NFR-PRT-004 | Backup files (`.sb` format) portable across iOS and Android devices. |

> NFR-PRT-004 says `.sb`; FR-BAK-001 says `.mb`. The SRS contradicts itself on the
> backup file extension. Unresolved in v1.0 — see errata.

---

## Requirement groups with no IDs

These appear in the SRS but carry no citable requirement identifier. **Do not invent
IDs for them.**

| SRS section | Content | Note |
|---|---|---|
| §2.4 | Design & implementation constraints (80 MB app size, offline-only core, AES-256 at rest, Clean Architecture, Dart 3.0+ null safety) | Bulleted constraints, no IDs. The 80 MB figure is cited by E-09. |
| §2.5 | Assumptions A1–A5 and dependencies D1–D5 | `A`/`D` prefixed, not `FR`/`NFR`. |
| §5.6 | Scalability targets (100,000 transactions, 50 custom categories, 20 accounts, 500 MB receipt images, 20 plans) | **A table with no requirement IDs.** Scalability targets are therefore uncitable as written. |
| §4.1–§4.4 | External interface requirements (UI, hardware, software, communication) | Bulleted and tabular, no IDs. |
| Appendix C | Risk register R1–R6 | `R` prefixed, not `NFR`. |

---

## Known citation traps

Cases where a plausible-looking citation is wrong. Each of these has been made at least
once in this repo.

| Trap | Reality |
|---|---|
| Citing an FR-ACC ID for account **deletion** | No FR-ACC requirement authorises deletion. FR-ACC-004 archiving is the SRS's mechanism. E-25 raises FR-ACC-007 for the narrow case. |
| Citing FR-ACC-004 for the **Include-in-Total** toggle | The toggle is a stored field under FR-ACC-002. FR-ACC-004 is archiving. |
| Citing FR-ACC-003 for anything other than the **side-drawer panel** | FR-ACC-003 is the side-drawer display, nothing else. |
| Citing FR-SET-009 for **multi-profile** support | FR-SET-009 is Create Backup / Restore Backup / Clear All Data. No requirement anywhere covers multiple user profiles. |
| Citing an FR-ACC ID for the **account selector** on the entry screen | FR-EXP-001 names `account` as a field of recording an expense. That is the correct citation. |
| Citing `NFR-PRT-002` for anything about receipts or app size | NFR-PRT-002 is responsive layout, 360–420 dp. |
| Citing a **scalability** target | §5.6 has no IDs. There is nothing to cite. |

---

## Cross-document conflicts

The SRS is the requirements baseline, but the SDD and DBD restate parts of it and do not
always agree. Where they conflict, none of them is silently authoritative — raise errata.

| Subject | SRS | SDD v1.0 | DBD v1.0 |
|---|---|---|---|
| Backup file extension | `.mb` (FR-BAK-001) / `.sb` (NFR-PRT-004) | — | — |
| Lookback column name | `plan_analysis_months` (§6.2) | — | `plan_lookback_months` (§3.1) — and the DBD's own ERD block at §2.1 uses `plan_analysis_months`, disagreeing with its own §3.1 |
| Table count | 10 entities in the §6.1 relationship diagram, but §6.2 only defines fields for 9 — `RecurringRule` is named as a relationship and never given a schema (E-03) | — | Cover says "10 Core Tables + 1 Migration Table", §1.2 text says "11 tables total", but §3.1–§3.12 define 12 schemas, and the ERD cover says "12 Tables" |
| Index count | — | 7 indexes (§5.1), named `idx_transactions_*` | 12 indexes (§5.1), named `idx_tx_*` — different names, not just different counts |
| Recurring rule FK | — | — | `transaction_id` (§2.1 ERD) vs `template_tx_id` (§3.6) |
| Passcode storage | 4–6 digit PIN, 5-attempt lockout (NFR-SEC-003, FR-SET-005) | — | `passcode_hash TEXT` — "SHA-256 hash of PIN" (§3.1), no salt column, no lockout-state column |
| Benchmark scale | 10,000 (NFR-PER-006) / 100,000 (§5.6) / 50,000 (Appendix C, R4) | — | 10,000 (§5.2 query targets) |
| Migration table name | — | `schema_version` (§5.3) | `schema_migrations` (§3.12) |
| Encryption key storage name | — | `db_encryption_key` (§5.4) | `moneyora_db_key` (§8.1) |

---

*Derived from `Moneyora_SRS_v1.0.pdf`, with cross-references to `Moneyora_SDD_v1.0.pdf`
and `Moneyora_DBD_v1.0.pdf`. Non-authoritative. Do not edit to correct the spec —
corrections belong in `SPEC_ERRATA.md`.*
