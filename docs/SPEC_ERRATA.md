# Moneyora — Specification Errata 01

Raised 2026-09-01, against **SRS v1.0** (approved 2026-06-20) and
**SDD v1.0** (approved 2026-06-21).

Both baselines stay as approved. This document records every deviation, why it
exists, and what supersedes it. When SRS v1.1 / SDD v1.1 are issued at milestone
M2, these entries fold into them and this file becomes history.

**Where a baseline and this file disagree, this file wins.** Implementation
follows the Resolution sections.

---

## Summary

| ID | Severity | Area | Status |
|---|---|---|---|
| [E-01](#e-01) | High | Brand palette contradicts stakeholder instruction | Resolved |
| [E-02](#e-02) | **Blocking** | Transfers unrepresentable in schema | Resolved |
| [E-03](#e-03) | **Blocking** | `recurring_rules` table undefined | Resolved |
| [E-04](#e-04) | **Blocking** | Split expenses have no schema | Resolved |
| [E-05](#e-05) | **Blocking** | `STDDEV()` is not a SQLite function | Resolved |
| [E-06](#e-06) | High | Money stored as `REAL` | Resolved (pre-existing) |
| [E-07](#e-07) | Medium | Seasonal detection over-claims on short history | Resolved |
| [E-08](#e-08) | Low | Backup file extension contradiction | Resolved |
| [E-09](#e-09) | Low | App-size figures contradict | Clarified |
| [E-10](#e-10) | Low | Category limit contradiction | Clarified |

---

<a id="e-01"></a>

## E-01 — Brand palette contradicts the stakeholder instruction

**Severity:** High · **Affects:** SRS §4.1

SRS §4.1 specifies *"Material Design 3 … with custom green branding"*. The
stakeholder had explicitly rejected green during requirements gathering, on the
grounds that it would read as a copy of Monefy, the reference app. The
instruction did not reach the document.

### Resolution — indigo brand, semantic colours unchanged

Semantic colours are retained exactly as SRS §4.1 defines them. Green for
money-in and red for money-out is a cross-cultural finance convention, not a
Monefy trait; changing it would cost comprehension for no gain. Only the
**brand identity** colour changes.

| Token | Light | Dark | Role |
|---|---|---|---|
| `brand` | `#3F51B5` | `#7986CB` | App bar, primary FAB, AI and plan features |
| `brandContainer` | `#E8EAF6` | `#283593` | Selected chips, plan cards |
| `accent` | `#FFB300` | `#FFCA28` | Highlights, active nav, progress fill |
| `income` | `#2E7D32` | `#66BB6A` | Income amounts, `+` FAB |
| `expense` | `#C62828` | `#EF5350` | Expense amounts, `−` FAB |
| `transfer` | `#00897B` | `#4DB6AC` | Transfer rows, bidirectional icon |
| `surface` | `#FAFAFA` | `#121212` | Page background |
| `onSurface` | `#1C1B1F` | `#E6E1E5` | Body text |

Indigo sits far from both income-green and expense-red on the colour wheel, so
generated donut-chart category colours never collide with the semantic pair.

These pairings are chosen to meet the 4.5:1 contrast floor in SRS §4.1, but
**verify each one with a contrast checker when `core/theme/` is written.** Do
not take the table on trust — contrast depends on the exact surface a token
lands on, and the dark-mode values in particular need checking against
`#121212` rather than against pure black.

---

<a id="e-02"></a>

## E-02 — Transfers cannot be represented in the schema

**Severity:** Blocking · **Affects:** SRS §6.2 `transactions`, FR-TRF-002

FR-TRF-002 requires a transfer to be *"a single atomic transaction: debit from
source account, credit to destination account."* The `transactions` table
defines exactly one `account_id`. There is nowhere to record the destination, so
no conforming implementation is possible.

### Resolution — add a nullable `to_account_id`

One row per transfer, which makes the atomicity requirement trivially
satisfiable: a single `INSERT` either lands or does not. The paired-row
alternative — two linked rows — needs a transaction wrapper and leaves the door
open to orphaned halves after a crash, directly against NFR-REL-002.

```sql
to_account_id INTEGER REFERENCES accounts(id),  -- NULL unless type='transfer'

CHECK (
  (type =  'transfer' AND to_account_id IS NOT NULL AND to_account_id <> account_id)
  OR
  (type <> 'transfer' AND to_account_id IS NULL)
)
```

Account balance therefore becomes:

```sql
SELECT
  COALESCE(SUM(CASE WHEN type='income'   AND account_id    = :a THEN amount_cents END), 0)
+ COALESCE(SUM(CASE WHEN type='transfer' AND to_account_id = :a THEN amount_cents END), 0)
- COALESCE(SUM(CASE WHEN type='expense'  AND account_id    = :a THEN amount_cents END), 0)
- COALESCE(SUM(CASE WHEN type='transfer' AND account_id    = :a THEN amount_cents END), 0)
FROM transactions;
```

**Analytics queries must exclude `type='transfer'`.** Moving your own money
between your own accounts is neither income nor expense, and counting it
inflates both totals. This is the most common bug in personal-finance apps, and
it is invisible until someone with two accounts looks at their monthly summary
and finds they apparently earned and spent an extra Rs 50,000.

---

<a id="e-03"></a>

## E-03 — `recurring_rules` table is never defined

**Severity:** Blocking · **Affects:** SRS §6.1, §6.2, FR-EXP-008, FR-INC-004

`transactions.recurring_rule_id` references it. The ER overview in §6.1 names
it. FR-EXP-008 and FR-INC-004 require it. §6.2 never defines it — a dangling
foreign key.

### Resolution — define the table

```sql
CREATE TABLE recurring_rules (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  frequency       TEXT NOT NULL CHECK(frequency IN
                    ('daily','weekly','monthly','yearly','custom_days')),
  interval_days   INTEGER,          -- required iff frequency='custom_days'
  day_of_week     INTEGER,          -- 0-6, for weekly
  day_of_month    INTEGER,          -- 1-28, for monthly
  start_date      TEXT NOT NULL,
  end_date        TEXT,             -- NULL = open ended
  next_due_date   TEXT NOT NULL,
  last_created_at TEXT,
  is_active       INTEGER NOT NULL DEFAULT 1,
  CHECK (frequency <> 'custom_days' OR interval_days IS NOT NULL)
);

CREATE INDEX idx_recurring_next_due ON recurring_rules(next_due_date, is_active);
```

`day_of_month` caps at 28 deliberately. A rule set for the 31st silently skips
February; capping removes the edge case instead of requiring code to handle it.
This matches FR-SET-004, which already bounds the first-day-of-month setting to
1–28.

---

<a id="e-04"></a>

## E-04 — Split expenses have no schema

**Severity:** Blocking · **Affects:** SRS §6.2, FR-EXP-010

FR-EXP-010 requires splitting one expense across multiple categories with
amounts summing to the total. A single `category_id` per row cannot express it.

### Resolution — a child table, written only when a split exists

```sql
CREATE TABLE transaction_splits (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  transaction_id INTEGER NOT NULL REFERENCES transactions(id) ON DELETE CASCADE,
  category_id    INTEGER NOT NULL REFERENCES categories(id),
  amount_cents   INTEGER NOT NULL CHECK(amount_cents > 0),
  note           TEXT
);

CREATE INDEX idx_splits_transaction ON transaction_splits(transaction_id);
CREATE INDEX idx_splits_category    ON transaction_splits(category_id);
```

The unsplit case keeps `transactions.category_id` and writes no split rows, so
the common path stays a single insert and every existing query is untouched.
When a split does exist, `transactions.category_id` holds the **dominant**
category — the largest share — so list views and the donut chart still render
without a join.

**The sum invariant is enforced in the domain layer, not by SQL.** SQLite cannot
express "children must sum to parent" as a constraint. `AddTransaction` returns
`Left(ValidationFailure)` when split amounts do not reconcile with the parent
total, and that rule needs a unit test before the split UI is built.

---

<a id="e-05"></a>

## E-05 — `STDDEV()` is not a SQLite function

**Severity:** Blocking · **Affects:** SDD §5.2 "Money Plan Analysis"

The documented query is:

```sql
SELECT category_id, AVG(amount), STDDEV(amount), COUNT(*) ...
```

SQLite ships no `STDDEV`. The query throws at runtime. It also underpins the
Fixed / Variable / Seasonal classification in SRS §7.1, so the plan generator —
the headline feature — cannot work as specified.

### Resolution — compute statistics in Dart

The datasource returns **rows**; `domain/` computes mean, median, standard
deviation, min, max and trend. Clean Architecture wants it there regardless:
dispersion is business logic, not storage. It is also what makes the plan engine
testable with no database attached, which is how NFR-MNT-002's 75% domain
coverage floor gets met without a fight.

```sql
-- data layer: fetch, do not aggregate
SELECT category_id, amount_cents, date
FROM transactions
WHERE type = 'expense' AND date >= :lookbackStart
ORDER BY category_id, date;
```

Use the **sample** standard deviation, with the `n−1` denominator. The
population formula understates dispersion on small samples — exactly the case
this app faces — which would inflate confidence scores precisely where they are
least trustworthy.

---

<a id="e-06"></a>

## E-06 — Money stored as `REAL`

**Severity:** High · **Affects:** SRS §6.2 (every amount column), SDD §5

Identified and overridden before this errata was raised; see
[`ARCHITECTURE.md` §6.1](ARCHITECTURE.md). Recorded here so that every SRS
deviation is traceable from one place.

**Resolution:** every monetary column is `INTEGER` minor units, suffixed
`_cents`: `amount_cents`, `initial_balance_cents`, `current_balance_cents`,
`allocated_amount_cents`, `spent_amount_cents`, `total_budget_cents`,
`unit_price_cents`, `total_price_cents`, `tax_amount_cents`.

---

<a id="e-07"></a>

## E-07 — Seasonal detection over-claims on short history

**Severity:** Medium · **Affects:** SRS §7.1 Phase 1, SDD §7.1

Both baselines classify a category as Seasonal when *"FFT analysis reveals
periodic spikes"*. Under the default 6-month lookback (FR-PLN-003) that is six
monthly data points. An FFT over six samples cannot resolve an annual cycle: by
Nyquist you need at least two full periods, so roughly 24 months. On six points
it returns noise, and the app would label random variation "seasonal" and adjust
a real budget on the strength of it.

This compounds risk **R6** in SRS Appendix C, where insufficient history is
already rated *High* likelihood.

### Resolution — gate on data volume, and use an explainable method

1. **Seasonal classification requires ≥ 24 months** of history for that
   category. Below the threshold it is never assigned; the category falls
   through to Fixed or Variable.
2. Replace FFT with a **month-of-year index**: for each calendar month compute
   `mean(month) / mean(all months)`. Flag Seasonal when an index exceeds 1.5
   **and** recurs in the same month across at least two years.
3. When lookback < 24 months, cap that category's confidence at **MEDIUM** and
   state the reason in the UI, which is what FR-PLN-010's "data sufficiency"
   basis is for.

The second point is worth more than the accuracy argument: a month-of-year index
is explainable to the user — *"you spend more every April"* — and FFT output is
not. A budget the user cannot interrogate is a budget they will not trust.

---

<a id="e-08"></a>

## E-08 — Backup file extension contradiction

**Severity:** Low · **Affects:** FR-BAK-001 (`.mb`), NFR-PRT-004 (`.sb`)

The two requirements name different extensions for the same artefact.

**Resolution:** neither — use **`.mora`**. `.mb` is the registered extension for
Autodesk Maya binaries and would contend for the Windows file association on any
machine with Maya installed. `.sb` appears to be an editing artefact; nothing in
either document explains it. `.mora` is unclaimed and self-evidently Moneyora's.

---

<a id="e-09"></a>

## E-09 — App-size figures contradict

**Severity:** Low · **Affects:** SRS §2.3, §2.4, A1

§2.4 mandates *"total app size MUST remain under 80 MB"*; §2.3 states *"150 MB
app base"*; A1 assumes *"at least 150 MB free storage"*.

**Clarified — the figures measure different things, and all three stand:**

| Figure | Measures | Binding on |
|---|---|---|
| 80 MB | Release APK / AAB **download** size | Store listing; release CI gate |
| 150 MB | **Installed** footprint: extracted binary, ML Kit model, seed data | A1's free-space assumption |

The gate currently in `.github/workflows/ci.yml` checks a **debug** APK against
150 MB. Debug builds carry unstripped symbols and every ABI, so they run far
larger than release; the 80 MB figure applies to a release build only and gets
its own gate in Sprint 10.

---

<a id="e-10"></a>

## E-10 — Category limit contradiction

**Severity:** Low · **Affects:** FR-EXP-004 ("unlimited"), §5.6 ("up to 50 custom")

**Clarified:** FR-EXP-004 is the requirement — no limit is enforced in code.
§5.6's 50 is a **performance-tested ceiling**, not a cap: it states the scale at
which the category picker and donut chart are verified to stay inside
NFR-PER-005. Read §5.6 as "tested to 50", never "refuses the 51st".

---

## Traceability

Each resolution is implemented under its errata ID. Reference it alongside the
requirement in commit trailers and PR descriptions:

```
Refs: FR-TRF-002, E-02
```
