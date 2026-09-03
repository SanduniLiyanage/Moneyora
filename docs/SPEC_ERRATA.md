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
| [E-11](#e-11) | Medium | Category-grouped list view unspecified | Resolved |
| [E-12](#e-12) | Medium | FR-SET-011 copied from the reference app's paywall | Withdrawn |
| [E-13](#e-13) | Low | Two entry-screen affordances missing from SDD §4.1 | Resolved |
| [E-14](#e-14) | Low | SDD §10.1 pins a deprecated API and an unmaintained package | Resolved |
| [E-15](#e-15) | Medium | Transfer writes 3 rows with circular FKs, no wrapper | Resolved |
| [E-16](#e-16) | **Blocking** | Transfer debit and credit rows are indistinguishable | Resolved |
| [E-17](#e-17) | **Blocking** | `category_id NOT NULL` conflicts with transfers | Resolved |
| [E-18](#e-18) | Medium | `current_balance` stored, mutated in place, never reconciled | Resolved |
| [E-19](#e-19) | Medium | iOS claimed but unbuildable on the dev machine | Mitigated |
| [E-20](#e-20) | Medium | iOS 14 target impossible with ML Kit (needs 15.5) | Resolved |
| [E-21](#e-21) | High | Money Plan cannot run for a user with no history | Resolved |
| [E-22](#e-22) | Medium | No empty state specified for any surface | Resolved |
| [E-23](#e-23) | Medium | Deleting a transaction is irreversible | Resolved |

**E-02, E-03 and E-05 are amended** by the DBD audit — see
[Amendment A](#amendment-a). Read that before implementing any of them.

**E-11 to E-13** were raised on 2026-09-01 from a walkthrough of the reference
app (Monefy), against which the original requirements were gathered. They are
omissions rather than errors: the SRS describes what it describes correctly, but
missed behaviour that the reference app has and the stakeholder expects.

**E-21 to E-23** were raised on 2026-09-03 — see [Amendment B](#amendment-b).
They are omissions of the same kind, found by asking a different question: not
"is this specified correctly?" but "what happens on the first open?" The
baselines describe what the app *can do* and say almost nothing about how it
feels to start using, which for an app judged on first impression is the gap
that matters most.

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

The gate in `.github/workflows/ci.yml` checks a **debug** APK, which is not the
same artefact. Debug builds carry every ABI, unstripped symbols and ML Kit's
models; the first successful build measured **203 MB**. That ceiling was
originally set to 150 MB by guesswork and failed the moment a build reached it —
measure before asserting.

It is now a 280 MB tripwire for "someone committed something enormous", and is
explicitly not the SRS budget. The real 80 MB gate measures a **release** build,
split per ABI, and lands in Sprint 10 alongside store preparation.

---

<a id="e-10"></a>

## E-10 — Category limit contradiction

**Severity:** Low · **Affects:** FR-EXP-004 ("unlimited"), §5.6 ("up to 50 custom")

**Clarified:** FR-EXP-004 is the requirement — no limit is enforced in code.
§5.6's 50 is a **performance-tested ceiling**, not a cap: it states the scale at
which the category picker and donut chart are verified to stay inside
NFR-PER-005. Read §5.6 as "tested to 50", never "refuses the 51st".

---

<a id="e-11"></a>

## E-11 — The category-grouped list view is unspecified

**Severity:** Medium · **Affects:** FR-EXP-006, SDD SCR-005

FR-EXP-006 specifies only one list mode: *"a chronological list, grouped by date
with collapsible date section headers showing daily totals."* The reference app
has **two**, toggled by a control to the right of the balance bar:

| Mode | Groups by | Header shows | Specified? |
|---|---|---|---|
| Chronological | Date | Date + that day's net total | Yes — FR-EXP-006 |
| **By category** | Category | Icon, name, **transaction count badge**, category total | **No** |

In the second mode, expanding a category reveals its individual transactions
with note and date. The count badge is load-bearing: seeing *Food 1082* against
*House 14* communicates spending habits faster than any chart, and it is how a
user finds a miscategorised entry.

### Resolution — new requirement FR-EXP-011

> The system **shall** provide a category-grouped transaction list as an
> alternative to the chronological list, toggled from the home screen. Each
> group displays the category icon, name, transaction count, and period total,
> and expands to reveal its transactions.

Both modes read the same filtered set, so this is a presentation concern: one
use case, two widgets. Build it in Sprint 2 alongside the chronological list
while the query is fresh, not as a retrofit.

---

<a id="e-12"></a>

## E-12 — FR-SET-011 was copied from the reference app's paywall

**Severity:** Medium · **Affects:** FR-SET-011

FR-SET-011 requires *"a 'Copy Purchase ID' function for in-app purchase
verification."* That control exists in the reference app because it sells a paid
unlock, and support needs the ID to resolve entitlement disputes. It appears in
its settings screen directly above the sync options, which is presumably how it
reached the SRS.

Moneyora has no in-app purchase, no paid tier, and no support desk. The
requirement has no referent — implementing it would produce a button that copies
an identifier nothing consumes.

### Resolution — withdraw FR-SET-011

Withdrawn, not deferred. If monetisation is ever added, purchase-ID handling
comes with whichever billing SDK is chosen and would be specified then.

The general lesson is worth recording, because the same trap is live for the
rest of the settings screen: **a reference app's UI encodes its business model,
not only its features.** Copy the interaction patterns; check each individual
control against your own product before adopting it.

---

<a id="e-13"></a>

## E-13 — Two entry-screen affordances missing from the screen inventory

**Severity:** Low · **Affects:** SDD §4.1 SCR-002 / SCR-003

SDD §4.1 describes the add-expense and add-income screens as *"Custom keypad,
category row, account selector, note field."* The reference app's equivalent
screens carry two further controls, both of which implement requirements the SRS
already has but the SDD forgot to place:

1. **A recurring toggle**, top-right of the entry screen — the entry point for
   FR-EXP-008 and FR-INC-004. Without it those requirements have no UI at all.
2. **An inline `+` at the end of the category row**, creating a category without
   leaving the entry flow — FR-EXP-004 and FR-INC-003.

### Resolution

Add both to SCR-002 and SCR-003. The inline `+` matters more than it looks: it
is the difference between "I can add a category" and "I can add a category at
the moment I discover I need one", which is the only moment anyone ever wants
to. The Categories drawer keeps its own `+` for deliberate management.

---

<a id="e-14"></a>

## E-14 — SDD §10.1 pins a deprecated API and a thinly-maintained package

**Severity:** Low · **Affects:** SDD §10.1, §6.2

Two dependency choices in the baseline have aged out since it was written:

| Baseline | Issue | Replacement |
|---|---|---|
| `StateNotifier` (SDD §6.2) | Superseded in Riverpod 2.x by `Notifier` / `AsyncNotifier`; retained only for backward compatibility | `AsyncNotifier` |
| `dartz ^0.10.1` (SDD §10.1) | Broad Haskell port, thinly maintained | `fpdart` |

Neither is broken, and neither changes the architecture — the `Either` API is
near-identical and only import lines and a base class name move.

### Resolution — adopt both replacements

The deciding factor is not correctness but **what the code says about its
author**. A 2026 Flutter codebase built on a deprecated notifier and an
abandoned functional library reads as assembled from an old tutorial, whatever
its actual quality. Currency with the ecosystem is part of the work.

Applied in `lib/core/usecases/usecase.dart` and `scripts/bootstrap.ps1`. Every
`Either<Failure, T>` signature in `ARCHITECTURE.md` §3 is unchanged.

---

<a id="amendment-a"></a>

## Amendment A — DBD v1.0 audit (2026-09-01)

E-01 to E-14 were raised against the SRS and SDD only. `Moneyora_DBD_v1.0.pdf`
came to light afterwards. It is a dedicated Database Design Document from the
same generation session, and **it, not SRS §6.2, is the authoritative schema.**

Re-auditing against it amends three earlier findings and adds four.

### Amended

**E-03 — withdrawn.** DBD §3.6 defines `recurring_rules`. The finding was
correct against SRS §6.2, which omits the table, but the DBD supplies it. Its
design differs from the one proposed above: it stores a `template_tx_id`
pointing at a transaction to copy, rather than duplicating the fields onto the
rule.

One residual gap survives: the DBD's version has no `day_of_week` or
`day_of_month` column, so `frequency='monthly'` cannot express *which* day it
recurs on. Add both columns, keeping the 1–28 bound on `day_of_month` for the
reason given in E-03.

**E-02 — superseded, but read E-15 to E-17.** DBD §3.5 defines a `transfers`
table with `from_account_id` and `to_account_id`. Transfers are representable
after all, so the `to_account_id` column proposed for `transactions` is dropped.

The other half of E-02 stands and matters *more* under this design, not less:
**analytics must exclude `type='transfer'`.** The DBD creates two `transactions`
rows per transfer, so a query that forgets the exclusion double-counts every one
of them.

**E-05 — still open, different defect.** The DBD replaced the SDD's `STDDEV()`
query with one that does not use `STDDEV` — but which averages a column the
query never defines:

```sql
SELECT t.category_id, AVG(monthly_total) AS avg_monthly, ...
FROM transactions t
WHERE t.type = 'expense' AND t.date >= date('now','-6 months')
GROUP BY t.category_id, strftime('%Y-%m', t.date)
```

There is no `monthly_total` column on `transactions` and no subquery producing
one. It fails as written, exactly as the SDD version did. **The E-05 resolution
is unchanged:** fetch rows, aggregate in Dart.

### Confirmed across all three documents

**E-04** — no split table exists in the DBD either, so FR-EXP-010 remains
unimplementable. **E-06** — the DBD uses `REAL` for every monetary column,
matching SRS §6.2 and SDD §5. Three documents, one defect, three times; the
integer-cents override stands.

---

<a id="e-15"></a>

### E-15 — A transfer writes three rows across two tables with circular references

**Severity:** Medium · **Affects:** DBD §3.5

`transfers.from_tx_id` and `to_tx_id` are foreign keys into `transactions`,
while the rows they point at are the transfer's own two halves. Neither table
can be written first without the other's ids, so a transfer is necessarily:
insert two transaction rows, read back their ids, insert the transfer row.
Three writes, ordered, all-or-nothing.

FR-TRF-002 calls a transfer *"a single atomic transaction"* and NFR-REL-002
requires atomic writes, but the DBD specifies neither the ordering nor a
wrapper.

**Resolution:** every transfer write is wrapped in `BEGIN … COMMIT` inside the
datasource, in the order above. This is one of the few places where the
repository must expose an explicitly transactional method rather than three
separate calls. A partial write here leaves money that has left one account
without arriving in the other — the worst failure this application can produce.

---

<a id="e-16"></a>

### E-16 — The two halves of a transfer are indistinguishable

**Severity:** **Blocking** · **Affects:** DBD §3.4, §3.5

`transactions.amount` carries `CHECK(amount > 0)`, so every row is positive.
There is no sign column, no direction column, and both halves of a transfer
carry `type='transfer'`. Given a transfer row from `transactions` alone,
**nothing identifies it as the debit or the credit.**

Every balance calculation and every list view therefore has to join back to
`transfers` on `from_tx_id` / `to_tx_id` to discover which way the money moved.
The DBD's own "Account balance calculation" row in §5.2 does not mention that
join, which suggests the query behind it was never written.

**Resolution:** put the direction on the transaction row.

```sql
transfer_direction TEXT CHECK(transfer_direction IN ('out','in')),

CHECK (
  (type =  'transfer' AND transfer_direction IS NOT NULL)
  OR
  (type <> 'transfer' AND transfer_direction IS NULL)
)
```

Balance then reads from `transactions` alone, and `transfers` becomes what it
should have been — a header row for display and editing, not a table the
balance depends on.

---

<a id="e-17"></a>

### E-17 — `category_id` is NOT NULL, but transfers have no category

**Severity:** **Blocking** · **Affects:** DBD §3.4 against §3.5

`transactions.category_id` is `FK categories(id), NOT NULL`. A transfer between
your own accounts has no category — it is not spending. Yet §3.5 requires two
`transactions` rows per transfer, each of which must supply one.

As specified, the only way to insert a transfer is to invent a sentinel
category, which then leaks into the category list, the donut chart, and plan
allocations.

**Resolution:** make the column nullable and tie it to type with a constraint.

```sql
category_id INTEGER REFERENCES categories(id),

CHECK (
  (type =  'transfer' AND category_id IS NULL)
  OR
  (type <> 'transfer' AND category_id IS NOT NULL)
)
```

The constraint does the work the `NOT NULL` was there for, without lying about
what a transfer is.

---

<a id="e-18"></a>

### E-18 — `current_balance` is stored and incrementally mutated

**Severity:** Medium · **Affects:** DBD §3.2, §6.2

`accounts.current_balance` is a stored column, updated in place on every write:

```sql
UPDATE accounts SET current_balance = current_balance - ? WHERE id = ?;
```

Two problems compound. Any write path that forgets the update — an edit, a
delete, a receipt batch, a transfer, a restored backup — silently desynchronises
the balance from the transactions that produced it, with nothing in the schema
able to detect the drift. And because the column is `REAL` (E-06), repeated
increment accumulates floating-point error even when every path is correct.

The DBD specifies no reconciliation procedure.

**Resolution:** keep the column — recomputing from full history on every home
screen render will not meet NFR-PER-005 at 100,000 transactions — but treat it
strictly as a **cache**:

1. It is written **only** inside the same `BEGIN … COMMIT` as the transaction
   row that changes it. Never as a separate call.
2. `INTEGER` cents, per E-06, so every increment is exact.
3. A `RecomputeAccountBalance` use case re-derives it from
   `initial_balance_cents` plus all transactions, and runs on app start after a
   restore, and behind a Settings action.

Point 3 is the reconciliation the DBD lacks, and it doubles as the test oracle:
a property test asserting *cached == recomputed* after a random sequence of
writes catches every missed update path at once, which no amount of manual
testing reliably does.

---


<a id="e-19"></a>

## E-19 — iOS is claimed but cannot be tested on the development machine

**Severity:** Medium · **Affects:** SRS §2.3, NFR-PRT-001, SDD §1

SRS §2.3 targets *"iOS 14.0 or later"* and NFR-PRT-001 requires *"a single
Flutter codebase targeting both iOS and Android"*. The project is developed on
Windows, and iOS binaries can only be produced by Xcode, which runs solely on
macOS. There is no Windows toolchain, plugin, or workaround; a connected iPhone
is not even enumerated by `flutter devices`.

The developer's only iOS device is an iPhone 11, which for this purpose is
irrelevant — the constraint is the build host, not the target.

Left unaddressed, "iOS 14+" would be a requirement nothing had ever checked,
and the first attempt at an iOS build would land in Sprint 10 alongside store
submission, which is the worst possible moment to discover a plugin without an
iOS implementation.

### Resolution — compile on CI, and say plainly what that does and does not prove

A `build-ios` job runs `flutter build ios --no-codesign` on a `macos-latest`
runner for every pull request. GitHub provides macOS runners free for public
repositories.

**What a green tick proves:** the Dart compiles for iOS, every plugin resolves
an iOS implementation, the CocoaPods dependency graph is satisfiable, and the
Xcode project builds. That is genuinely the majority of what breaks
cross-platform, and it catches it on the PR that introduces it rather than in
Sprint 10.

**What it does not prove:** that the app runs. There is no simulator
interaction, no gesture testing, no camera, no biometric prompt, no manual QA
on any iOS device. Layout, scroll behaviour, safe-area insets, keyboard
handling and Cupertino-specific behaviour are all unverified.

The distinction has to be stated wherever the platform is claimed, because
"builds on iOS" and "works on iOS" are different assertions and only the first
is being made. `README.md` therefore describes the app as Android-tested and
iOS-compile-verified rather than simply cross-platform.

### Residual risk

Accepted, and it is not small: an iOS build that compiles can still be
unusable. Closing it requires physical access to a Mac and an iOS device for a
manual pass before any store submission. Until that happens, no claim stronger
than "compiles for iOS" is supportable.

Two features carry more iOS risk than the rest and should be checked first when
a Mac becomes available: the receipt scanner (camera permissions and ML Kit's
iOS path) and biometric authentication (Face ID differs materially from
Android's fingerprint flow).

---

<a id="e-20"></a>

## E-20 — The iOS 14 target is unachievable with the mandated OCR library

**Severity:** Medium · **Affects:** SRS §2.3, D2, SDD §10.1

SRS §2.3 sets the minimum platform at *"iOS 14.0 or later"*. Dependency D2 and
SDD §10.1 mandate `google_mlkit_text_recognition`, and FR-RCP-004 requires
Google ML Kit Text Recognition v2 specifically.

Those two requirements cannot both hold. The package's iOS podspec declares:

```ruby
s.platform = :ios, '15.5'
s.ios.deployment_target = '15.5'
```

CocoaPods refuses outright when an app's deployment target is lower than a
pod's, so an iOS 14 build does not merely warn — it cannot link. This surfaced
on the very first iOS build the project ever attempted, which is the argument
for having added that CI job (E-19) rather than deferring it to Sprint 10.

The generated Xcode project already carried 15.0, itself above the SRS figure,
so the specification's iOS 14 claim had never matched the code even before
ML Kit was considered.

### Resolution — raise the floor to iOS 15.5

`IPHONEOS_DEPLOYMENT_TARGET` moves to 15.5, the lowest value that satisfies
ML Kit. **SRS §2.3's iOS 14.0 is superseded.**

The cost is real but small: iOS 15.5 shipped in May 2022, and Apple's adoption
curve is steep enough that devices below it are a rounding error — every iPhone
back to the 6s runs iOS 15. The alternative was dropping on-device OCR, which
is one of the project's two headline features.

Android is unaffected. Its ML Kit path needs only API 21, well under the API 26
floor that SRS §2.3 sets there.

### Worth noting for later

Raising a deployment target is a one-line change now and a support problem
after release. If a future dependency demands iOS 16 or 17, the same conflict
recurs with real users on the other side of it. Check the iOS deployment
target in any PR that adds a plugin — the CI job will catch it, but knowing
why it failed saves an afternoon.

---

<a id="amendment-b"></a>

## Amendment B — first-run and usability audit (2026-09-03)

E-01 to E-20 were raised against correctness: contradictions between documents,
constructs the database cannot execute, claims the platform cannot meet. This
pass asked a different question — **what does a person see the first time they
open the app, and can they act on it without being taught?**

Three gaps surfaced. None is a contradiction; each is an absence. All three are
cheapest now, in Sprint 2, while the screens that would carry them are still
being written.

They are recorded here rather than fixed silently for the same reason as every
other entry: a gap found by deliberate audit is worth more, to anyone reading
this repository as evidence of judgement, than a feature that quietly appeared.

---

<a id="e-21"></a>

### E-21 — The Money Plan cannot run for a user with no history

**Severity:** High · **Affects:** SRS §7.1, FR-PLN-001, FR-PLN-008,
Appendix C risk R6

The plan generator derives every allocation from the user's own spending
history. It needs six months of it to classify a category, and twenty-four
before seasonal detection is honest (E-07). **A user who installs the app today
has none.**

The headline feature is therefore unavailable for the first six months of use —
well past the point at which most people decide whether to keep an app. SRS
Appendix C records this as risk R6, but its mitigation column names no
behaviour, and neither §7.1 nor any FR-PLN requirement says what the plan screen
does when the history is empty. FR-PLN-008 Option A allocates in proportion to
existing spending, which is the closest the baselines come to an answer and
still assumes the proportions already exist.

There is a second cost that is easy to miss: this is also the state a *reviewer*
sees. Someone opening the app to evaluate it meets the headline feature in a
condition indistinguishable from broken.

### Resolution — a ladder, and always say which rung you are on

| History held | Where the allocation comes from | Confidence |
|---|---|---|
| None | One question — monthly income — allocated across the seeded default categories on published baseline proportions | Low, every category |
| 1–5 months | Blend: the user's observed proportions weighted by how many months exist, baseline for the remainder | Low, rising to Medium |
| 6–23 months | The statistical engine as specified in §7.1 | Per category, per FR-PLN-007 |
| 24 months or more | As above, plus seasonal detection | Per category |

Two rules make the ladder work.

**Ask one question, not a survey.** Monthly income is the only input that cannot
be derived from transactions later. Every extra question is another chance to
abandon setup before the app has shown its value.

**Label the rung.** The plan reads *"Based on 0 months of your spending"*, and
that line updates as history accumulates. A starter plan presented as a
statistical one is a claim the user will eventually catch out; a starter plan
that visibly improves is a reason to keep using the app.

**New requirement FR-PLN-011** — cold-start plan.

---

<a id="e-22"></a>

### E-22 — No empty state is specified for any surface

**Severity:** Medium · **Affects:** SRS §4, FR-RPT-001, FR-EXP-006, FR-PLN-001

The SRS specifies what every screen shows when it has data, and never what it
shows when it has none. Zero transactions is not an edge case — it is the state
**every user is in on first open**, and one that any filter can produce
afterwards.

Left undefined it renders as a donut chart with no segments, a list with no rows
and a plan with no allocations: three blank screens, at exactly the moment a new
user is deciding whether the app works.

### Resolution — every collection defines two empty states, not one

The distinction matters more than the copy. Conflating them produces the
familiar bug of telling a user with four hundred transactions to *"add your
first expense"* because they picked a quiet date range.

| Surface | Nothing yet | Nothing matching the filter |
|---|---|---|
| Transaction list | "No transactions yet. Tap + to add your first." | "No transactions between 1 and 14 March. Change the dates or clear the filter." |
| Donut chart (FR-RPT-001) | "Your spending breakdown appears here once you have added an expense." | "No spending in this period." |
| Money Plan | "Answer one question and Moneyora will draft you a starter plan." (E-21) | — |
| Search (FR-RPT-008) | — | "No transactions match 'xyz'." |
| Accounts | Cannot occur — `default_seed.dart` seeds one Cash account, per FR-ACC-001 | — |

Each empty state carries three things: what belongs here, why it is empty, and
the single action that fills it. No apology, and no illustration standing in for
an explanation.

**New requirement NFR-USA-001** — recorded as a non-functional requirement
rather than under one feature, because it binds every surface in the app.

---

<a id="e-23"></a>

### E-23 — Deleting a transaction is irreversible

**Severity:** Medium · **Affects:** FR-EXP-006

FR-EXP-006 specifies deleting a transaction. Nothing specifies getting one back.

The delete is a permanent write against financial history, fired by one tap, on
a list where rows sit close together. A mis-tap destroys a record the user may
have no second copy of — the receipt is in a bin and the bank statement is a
week away.

### Resolution — a snackbar with Undo, five seconds, on every delete

The interaction is unremarkable. **The implementation detail is not, and it is
the reason this is worth recording rather than leaving to whoever writes the
screen.**

Do not delete and re-insert. It looks equivalent and is not:

- the restored row takes a **new `id`** from `AUTOINCREMENT`, so the
  `transaction_splits` children that cascaded away with it (E-04) cannot be
  reattached to their original parent, and any `receipt_scan_id` link is
  orphaned;
- `accounts.current_balance_cents` would be adjusted twice in opposite
  directions (E-18), doubling the number of paths that can miss one;
- a transfer is three rows across two tables (E-15), so all three ids would have
  to be reissued consistently or the header row points at rows that no longer
  exist.

**Defer the write instead.** Remove the row from the visible list immediately,
hold the pending delete in memory, and commit it inside its `BEGIN … COMMIT`
only once the undo window closes. If the app is killed mid-window then nothing
was deleted — the safe direction to fail when the data is someone's money.

**New requirement FR-EXP-012** — undo delete.

The same pattern generalises to accounts and categories, where the stakes are
higher still because deleting an account takes its transactions with it. That
belongs to Sprint 3 and is deliberately out of scope here.

---

## Traceability

Each resolution is implemented under its errata ID. Reference it alongside the
requirement in commit trailers and PR descriptions:

```
Refs: FR-TRF-002, E-02
```
