# Moneyora — Session Handoff

State of the project as of **2026-09-14**, `main` at `32119e3`, after **80
merged pull requests** (#2–#81; #1 was closed unmerged). **Sprint 5's
wizard is complete and live tracking's write path is in**: the engine
([PR #66](https://github.com/SanduniLiyanage/Moneyora/pull/66),
[#68](https://github.com/SanduniLiyanage/Moneyora/pull/68),
[#70](https://github.com/SanduniLiyanage/Moneyora/pull/70),
[#72](https://github.com/SanduniLiyanage/Moneyora/pull/72)), the saved
plan ([PR #74](https://github.com/SanduniLiyanage/Moneyora/pull/74)), the
wizard ([PR #77](https://github.com/SanduniLiyanage/Moneyora/pull/77),
[#79](https://github.com/SanduniLiyanage/Moneyora/pull/79)) and the
first slice of FR-PLN-013 — the plan's spend kept inside the expense
write ([PR #81](https://github.com/SanduniLiyanage/Moneyora/pull/81)) —
all merged during this window; what remains of the sprint is the
tracking screen, FR-PLN-014 and FR-PLN-015. See "This session" below.

### The numbers, measured — and the only place they live

Every figure below was produced by running the command beside it on `main`
at `32119e3`, with PR #81 merged.
**This section is the single source of truth for counts.** `README.md` and
`ARCHITECTURE.md` link here rather than restating them: a number kept in one
place goes stale once, and a number kept in three places goes stale three
times and then disagrees with itself, which is worse than being merely out
of date.

| Figure | Value | Command |
|---|---|---|
| Tests | **1166 passing** | `flutter test` |
| Analyzer | **0 issues** | `flutter analyze` |
| Layer boundaries | **clean, exit 0** | `bash scripts/check_architecture.sh` |
| Requirement citations | **clean, exit 0** | `bash scripts/check_citations.sh` |
| Domain line coverage | **not remeasured this session** — was 96.9% at `8e5085d`; `lcov` isn't on this machine, only in CI | `flutter test --coverage`, then CI's `lcov --extract coverage/lcov.info '*/domain/*'` |
| Schema | **13 tables, 11 indexes** | `grep -c 'CREATE TABLE' lib/core/database/migrations/v1_initial.dart` |
| Dart files | 147 in `lib/`, 85 in `test/` | `find lib -name '*.dart' \| wc -l` |

Tests by area: 1136 at `a47b977` (PR #79, merged) plus 30 net new from
live tracking's write path — 18 in
`transaction_local_datasource_test.dart`, one new group appended and
**no existing assertion changed** (385 lines added, none removed): an
expense in the period moves its category's row and is rolled back with
the row when a split fails; outside the period, both period ends, a
category the plan has no row for, income and a transfer; a split by its
parts; an amount edit, a category edit moving spend between two rows, a
date edit out of and into the period, a split edit; delete and split
delete; no active plan; the active plan rather than an inactive one on
the same period; and a seeded random-write property test against a Dart
recount oracle. 9 in `money_plan_local_datasource_test.dart` for
`recomputeSpent` (no history, the incremental figure, a split by parts,
income/transfers/out-of-period, corruption repair, the mid-month
activation gap, a missing plan, the change signal, and the SQL recount
agreeing with the cache after a random sequence); 1 in
`money_plan_repository_impl_test.dart` plus one assertion added to its
failure-mapping case; 2 in `recompute_plan_spending_test.dart`. **No
assertion was removed.**

Before that: 1114 at `b84b01c` (PR #77, merged) plus 22 net new from
the wizard's second half — 11 in `test/widget/active_plan_page_test.dart`
(loading, no plan → the wizard, the populated plan, a failure reading;
adjusting: the write and the recalculated rows arriving through the
stream with the total held, the over-total refusal, an unparseable amount,
cancel; what-if: the default answer, the percentage followed and refused
past 100, the same category twice), 4 in
`test/widget/plan_save_flow_test.dart` (save → named, activated, on the
saved plan, back goes home; the blank-name refusal; a failure beneath;
cancel) and 7 in `what_if_test.dart`. `app_shell_test.dart`'s leave-again
loop gained "Your plan". **No assertion was removed.**

Before that: 1099 at `507229b` (PR #74, merged) plus 15 net new from
the wizard's first screens — 8 in `test/widget/plan_review_page_test.dart`
(loading, every figure and factor on a populated draft, the E-07 cap reason
at 12 months, Option B's income and savings, Option A's total, the empty
state, the inverted-period refusal in the use case's words, a failure
beneath) and 6 in `test/widget/money_plan_page_test.dart` (the defaults
and the request handed on, number-of-days, week and year, the empty-total
and out-of-range-savings refusals, zero days), plus 1 in
`app_shell_test.dart` reaching the wizard from home. That file's "planned
screen names its sprint" case moved from Money Plan to Scan Receipt, and
its leave-again loop names "Create Money Plan". **No assertion was
removed.**

Before that: 1045 at `4bbae30` (PR #72, merged) plus 54 net new from
the saved plan — 18 in `money_plan_local_datasource_test.dart` against real
SQLite (the round trip with category names, atomicity of a save, of the
deactivation it carries and of an allocation update, the one-active
invariant after every write, the change signal, the shared bus surviving
dispose); 8 in `money_plan_repository_impl_test.dart` (failure mapping,
the stream on listen, on change, on failure, on cancel); 5 in
`money_plan_model_test.dart` (every stored string both ways, a full round
trip); 14 in `update_allocation_test.dart` (`rebalance` alone, then the
use case); 5 in `save_plan_test.dart`; 4 in
`test/integration/save_plan_seed_test.dart` (seed → draft → save → read
back → switch → adjust → stream follows). `plan_period_test.dart` gained
the period types and factories, and one assertion moved from entity
equality to the two dates because a period now carries its shape. **No
assertion was removed.**

Before that: 1020 at `893e673` (PR #70, merged) plus 25 net new from
FR-PLN-010 — 15 in `score_confidence_test.dart` (the level ordering, months
not rows, the count threshold at 9/10 and 3/4, the CV threshold at
0.2492/0.2503 and 0.4995/0.5005 on constructed series, the E-07 cap at 12
and 23 vs 24 months and that it never raises) and 10 in
`test/integration/score_confidence_seed_test.dart` against `dev_seed` at
24 and 6 months, including that Option A scaling leaves the score
unchanged. **No assertion changed or was removed.**

Before that: 946 at `afe2f3b` (PR #68, merged) plus 74 net new from
FR-PLN-007/008/009 — 40 in `allocate_budget_formulas_test.dart` (each
formula alone: the recent average, the weighted moving average at and
below three months, the seasonal multiplier, the trend factor, proportional
distribution summing exactly, and `allocate` composed per category); 17 in
`allocate_budget_test.dart` (the three modes over the real statistics and
classifier stages); 8 in `plan_period_test.dart`; 11 in
`test/integration/allocate_budget_seed_test.dart` against `dev_seed`; and 3
repository tests for the `IncomeReader` port. The repository test's fake
gained an `accountId` record on its income call. **No assertion changed or
was removed.**

Before that: 920 at `76ebe8c` (PR #66, merged) plus 26 net new from
FR-PLN-004 — 17 in `classify_categories_test.dart` (the Fixed line at its
edges, the E-07 gate at 6 and 23 months, recurrence, the strict reading,
the 1.5 index at its edge, the use case over the real statistics stage) and
9 in `test/integration/category_classification_seed_test.dart` against
`dev_seed` at both 24 and 6 months. **No assertion changed or was
removed.**

Before that: 874 at `d7a3416` (PR #64, merged) plus 46 net new from
FR-PLN-005 — 16 in `category_statistics_test.dart` (the arithmetic: mean,
median, sample deviation, CV, active months, the trend band); 7 in
`lookback_window_test.dart`; 10 in `compute_category_statistics_test.dart`
(validation, densifying, ordering, the failure passing through); 8 in
`test/integration/category_statistics_seed_test.dart` against `dev_seed`
through the real pipeline; 1 datasource test for the new count column; and
4 repository tests for the port. Three existing fakes gained a
`transactionCount`; **no assertion changed or was removed.**

Before that: 839 at `c72abc5` (PR #62, merged) plus 35 net new from
FR-RPT-009 — 12 in `test/widget/spending_heatmap_test.dart` (one cell per
day, the shading against the month's largest day, the tooltip, the summary
line, the anchor's month over every account, a Year *not* changing the month,
the anchor changing it, the account narrowing, and the loading, quiet-month,
first-use and failure states); 7 in `get_spending_calendar_test.dart`; 5 in
`spending_calendar_test.dart` for the intensity buckets; 7 added to
`analytics_local_datasource_test.dart` against real SQLite (one row per day,
sparsity, both edges, E-04, E-02, the account filter, and agreement with
`spendingTrend(day)` folded); 2 in the repository test; and 1 benchmark.
`app_shell_test.dart`'s fixed drag to "Coming next" became
`scrollUntilVisible`; every other fake gained a `dailySpendingTotals` that
throws `UnimplementedError`. **No assertion changed or was removed.**

Before that: 774 at `0d2277a` (PR #60, merged) plus 65 net new from
FR-RPT-005 — 20 in `test/widget/spending_trend_lines_test.dart` (one line per
category, the legend's totals, dense zeros, the category colour, the "Other"
fold and its colour, axis labels by day, by month and across a year boundary,
compact money on the axis, the shared filters including the account
narrowing, and the loading, quiet-period, first-use, single-day, failure and
inverted-range states); 13 in `get_spending_trend_test.dart` (the granularity
rule at its edges, the account passing through, dense series, ordering and
tie-breaking, the empty and out-of-range cases, validation); 8 in
`trend_point_test.dart` for the bucket arithmetic; 9 added to
`analytics_local_datasource_test.dart` against real in-memory SQLite (daily
and monthly cuts, sparsity, E-02, E-04 landing in the parent's bucket, the
account filter, that the trend adds up to `spendingByCategory` for the same
query, and Bills flat across the seed's twelve months); 3 in the repository
test; 5 each for `decodeIsoDay` and `formatCentsCompact`; and 1 benchmark.

`app_shell_test.dart` was changed rather than added to, again: it needed
`getSpendingTrendProvider` overridden — a third chart card that spins on a
real database is a third way for `pumpAndSettle` never to return — and its
fixed scroll offset became `scrollUntilVisible`, so the next chart card does
not move the summary card out of reach a third time. Its assertions are
unchanged. Every other existing fake gained a `spendingTrend` that throws
`UnimplementedError`, the same way they already treat the aggregate they do
not script; **no assertion changed or was removed**.

## This session — live tracking's write path ([PR #81](https://github.com/SanduniLiyanage/Moneyora/pull/81), merged as `32119e3`)

**FR-PLN-013, slice 1: `plan_allocations.spent_amount_cents` is now
kept, and kept the way `accounts.current_balance_cents` is (E-18).**
`TransactionLocalDataSourceImpl` moves it on add, edit and delete of an
expense, inside the same database transaction as the row —
`_applyPlanSpend`, beside `_applyBalance` — for the active plan whose
period holds the row's date, matched by category. One statement: the
plan is a subquery (`is_active = 1 AND start_date <= ? AND end_date >=
?`), so no active plan, a date outside the period and a category the
plan has no row for are all no-ops by construction, not errors. No
screen changes; `ActivePlanPage` still does not show the figure.

**Decided, and the reasoning is in `_applyPlanSpend`'s doc comment:**

- **Expense only.** FR-PLN-013 tracks "actual spending vs. the active
  plan". Income is not spending, a transfer is neither (E-02), and a plan
  allocates expense categories.
- **A split by its parts, never its parent (E-04).** The parent carries
  the dominant category and the whole amount; counting it would put a
  split's Transport share on Food. The parts are the rows
  `analytics_local_datasource.dart`'s `_spendingParts` counts, so the
  plan and the reports agree on what was spent. `_requireRow` now loads
  a split's parts when `is_split = 1` so an edit or delete can reverse
  them; unsplit rows cost no second query.
- **Edit is reverse-then-apply, in full**, as balances are: the old row
  is taken out against the plan holding the *old* date, the new row put
  in against the plan holding the new one — which is what moves spend
  between two categories when the category changes, and in or out of the
  plan when the date does.
- **One transaction, not eventual consistency.** A second write is a
  write something can skip, and the cost here is a plan screen saying "on
  track" over an expense the list screen already shows.
- **No new change signal.** `MoneyPlanLocalDataSourceImpl` was already
  on the shared bus (PR #74), so `WatchActivePlan` re-reads on every
  transaction write.

**The recount is built and called by nothing**, the way
`RecomputeAccountBalance` was before Settings called it:
`MoneyPlanLocalDataSource.recomputeSpent(planId)` (one `UPDATE` with a
correlated subquery over the same union the analytics datasource uses),
`MoneyPlanRepository.recomputeSpent`, the `RecomputePlanSpending` use
case, `recomputePlanSpendingProvider`. Its oracle runs both ways: the
transactions datasource's property test recounts in Dart, and the plan
datasource's runs the SQL recount after a random sequence and asserts it
changes nothing.

**Known and deliberate gap — the first thing slice 2 should close.** The
cache is exact for a plan across the writes made *while it is active*. A
plan saved on the 14th over a month that began on the 1st starts at 0 and
has never counted the first two weeks; editing or deleting one of those
rows then reverses a figure that was never applied, and the row can go
negative. The `activate` and `insert`-with-`activate` writes in the plan
datasource should call `_recomputeSpentWithin` inside their own
transaction — two lines, and the test "counts the expenses a plan was
activated after" is already the oracle. It was left unwired because this
slice's scope was the write path and an unreferenced repair, matching
E-18's history; wire it before the screen shows the number.

---

## This session — save, the saved plan, adjustment and what-if ([PR #79](https://github.com/SanduniLiyanage/Moneyora/pull/79), merged as `a47b977`)

**The wizard's second half.** Save on `PlanReviewPage` names the plan
(defaulting to its period), writes it activated through
`savePlanControllerProvider`, and lands on `ActivePlanPage`
(`/plan/active`) with home beneath it — `go(home)` then
`push(activePlan)`, so back leaves to home rather than to a review of a
draft already saved. `ActivePlanPage` watches `activePlanProvider` (a
stream over `WatchActivePlan` in the `accountsProvider` shape), says when
there is no active plan and offers the wizard, and is on the home list as
**Your plan**. Spend against the plan is not shown yet — FR-PLN-013.

**FR-PLN-011 adjusts here, on the saved rows**, as decided in PR #77's
session: tap a row, set a figure, `updateAllocationControllerProvider
.adjust(...)`; the recalculated others come back through the stream, not
local state, because the datasource fires the shared bus on the write.
Refusals are `UpdateAllocation`'s own sentences.

**FR-PLN-012 is a preview, not a write — decided.** The requirement is a
question ("how much more *can* go to B"), and answering it is not doing
it: moving the freed cents from A to B while holding every other row is
not a single `UpdateAllocation`, which spreads a change proportionally
across the *untouched* rows — setting A down would hand most of the freed
cents to the largest rows, not to B. A two-category "move" write would be
new domain and persistence logic. `WhatIf.reduce` reuses
`UpdateAllocation.rebalance` with every row but B treated as held — the
same arithmetic the write would use, the total held — and returns a
`WhatIfResult` without writing; the sheet says it is a preview, and the
user acts on it through FR-PLN-011. If a later slice wants "apply", it
needs a repository write that sets two rows and holds the rest, and the
tests in `what_if_test.dart` are its oracle.

**One mechanic:** the controller's method is `adjust`, not `update` —
`AsyncNotifier` already defines `update`.

---

## This session — the wizard's first screens ([PR #77](https://github.com/SanduniLiyanage/Moneyora/pull/77), merged as `b84b01c`)

**FR-PLN-001, FR-PLN-002, FR-PLN-008, and the review of FR-PLN-007 to 010's
draft.** "Create Money Plan" on the home screen's navigation list opens
`MoneyPlanPage` (`/plan`): six period chips anchored on a date, three
budget modes, "Generate plan". It builds an `AllocationRequest` and pushes
it to `PlanReviewPage` (`/plan/review`), which watches
`planDraftProvider(request)` over `allocateBudgetProvider` and shows the
draft — every card with its allocation, daily allowance, class, confidence,
base, seasonal and trend factors, spike months, and the confidence's
reason. No save button, no FR-PLN-011, no FR-PLN-012, no new domain logic.

**Decided: FR-PLN-011 adjusts the saved plan, not the draft.**
`UpdateAllocation` already holds the total, persists `is_user_modified`
and writes atomically against real rows; a second copy of `rebalance` over
an unsaved draft in presentation state would be one nothing tests against
the database, and the two would drift. So the next slice's Save persists
the draft and lands on the saved plan, where adjustments happen. Saving
first costs the user nothing visible.

**The lookback is `LookbackWindow.before(now)` at the default six months**,
the clock read once in `initState` (injectable), and stated on the screen
— "Based on the last 6 months of spending." — until FR-PLN-003's setting
exists in Sprint 7. Under six months nothing is Seasonal and nothing is
High (E-07), and the review says why on each card:
`confidenceReason` gives "6 months of data, steady" normally and "Capped
at Medium: 12 months of history, 24 needed for High" when
`ConfidenceScore.isCappedByLookback` — E-07's requirement that the reason
be stated.

**Two mechanics worth knowing.** `RadioGroup` is used rather than
`RadioListTile.groupValue`, which Flutter 3.47 deprecates. And the review
route takes its request as `extra` and opens the first step when reached
without one — the same shape `accountForm` uses for a deep link.

**Also this window:** [E-32](SPEC_ERRATA.md) records the four places the
plan tables as built depart from the DBD (PR #76). The schema is
authoritative; no code changed.

---

## This session — the saved plan ([PR #74](https://github.com/SanduniLiyanage/Moneyora/pull/74), merged as `507229b`)

**The feature's first writes.** `SavePlan` turns a reviewed
`MoneyPlanDraft` into a `money_plans` row and its `plan_allocations` rows;
`WatchActivePlan` reads the active one back live; `ActivatePlan` switches
between saved plans; `UpdateAllocation` is FR-PLN-011. Repository,
datasource and models follow the accounts feature's shape, and the
datasource sits on the shared change bus so a plan watcher hears the
transaction writes FR-PLN-013 will need. No screens.

**One active plan, held by the data layer — the decision the wizard
depends on.** Saving with `activate` (the default: the SDD's last step is
"saved & activated") and `ActivatePlan` both clear every other plan's flag
**in the same transaction** as they set this one's. Asking callers to
deactivate first is two transactions with a moment between them in which
no plan, or two, is active, and a rule every caller has to remember; this
way it is an invariant the datasource keeps and its tests assert after
every write, including that a failed save rolls the deactivation back.
`activate: false` is FR-PLN-015's "save for later" and leaves the active
plan alone. There is no deactivate use case on purpose: choosing another
plan is how the user stops tracking this one.

**Every multi-row write is one transaction**, as `MakeTransfer`'s is, and
tested on real SQLite: an allocation naming a category that does not
exist leaves no plan row; an update naming a category not in the plan
rewrites nothing; activating a missing id leaves the previous plan active.

**FR-PLN-011's rebalance** reuses `AllocateBudget.distribute`. The
allocations the user has *not* touched absorb a change first, so a second
manual adjustment does not undo the first; only when none can does it
spread across all the others. The total is held either way. Refused: a
negative amount, one over the total, a category not in the plan, and a
plan with a single allocation.

**The stored strings live in the models and map to the schema as
`v1_initial.dart` built it, not to the DBD**: lowercase `'high'` /
`'fixed'` (like every other check constraint in the schema), the column is
`expense_class`, `total_budget_cents` is `NOT NULL` (the unconstrained mode
stores the sum), and `period_type` carries `custom_days` / `custom_range`.
`PlanPeriod` gained a `type` and the `day` / `week` / `year` factories so a
saved plan can say which of FR-PLN-002's shapes it was. Worth an errata
line if the DBD is ever reconciled; the schema was already the departure.

---

## This session — the confidence score ([PR #72](https://github.com/SanduniLiyanage/Moneyora/pull/72), merged as `4bbae30`)

**FR-PLN-010**, the fourth and last engine stage of Sprint 5:
`ScoreConfidence.score(statistics, window)` gives every
`CategoryAllocation` a `ConfidenceScore` — High / Medium / Low, the level
the data alone earned, the data points and CV it read, the lookback —
attached by `AllocateBudget.allocate`, so `MoneyPlanDraft` is complete for
the wizard. Pure arithmetic (E-05); nothing new to read.

**"Data points" are `activeMonths`, not `transactionCount` — decided, and
nothing after this stage may quietly redefine it.** An allocation is a
monthly figure estimated from monthly totals, so its support is the number
of monthly observations: Food's 521 rows are 24 observations. Rows within a
month make that month less noisy, which the CV already reflects; counted
as data points they would let a category bought daily reach High on one
month of history. Two consequences, both wanted: `activeMonths` never
exceeds the window, so High (ten or more) is unreachable under the
six-month default — which is what E-07 requires anyway, so the two rules
agree rather than the cap doing the sufficiency rule's work; and the cap
is only *binding* for windows of 10–23 months, where it is tested.

**The bands** are the SDD's, with strict `<` on the CV, and E-07's cap is
a `min` applied after them. **On the seed at 24 months:** Bills High
(24 months, CV 0.001), Food High (on 24 months, not on 521 rows), Pets Low
(3 months). **At six months** nothing is High; Bills and Food are Medium
*earned* on count, not imposed by the cap.

**Two things the bands do, recorded rather than changed** — both would
take a different CV, and both are a decision for whoever next touches the
statistics stage, not a quiet fix:

- **Car reads Low at 24 months** (CV 0.52). The SDD's CV is not detrended,
  so a clean 8%/month climb on 72 rows is "high variance". A CV of the
  residuals around the regression line would read it as steady-and-rising.
- **Every Seasonal category reads Low.** Two spikes that clear 1.5× the
  mean put the CV past 0.16 by construction (PR #68), and usually far past
  0.50 (Gifts: 2.15). The multiplier already accounts for the spikes; the
  band still counts them as variance. A CV excluding the seasonal months
  would be the matching remedy.

Confidence is attached, not applied: no figure changes. Pets still gets
its 8% buffer (the SDD applies it unconditionally); the Low score is what
tells the user not to trust it.

---

## This session — the allocator ([PR #70](https://github.com/SanduniLiyanage/Moneyora/pull/70), merged as `893e673`)

**FR-PLN-007, FR-PLN-008, FR-PLN-009**, the third slice of Sprint 5:
`AllocateBudget` turns an `AllocationRequest` (a `PlanPeriod`, a
`LookbackWindow`, a `BudgetMode`) into a `MoneyPlanDraft` — one
`CategoryAllocation` per category with its base, seasonal factor, trend
factor, period allocation and daily allowance, and a total. Arithmetic on
the classifier's output (E-05); the one read of its own is income for
Option B, through an `IncomeReader` port over the existing query.
Confidence and the wizard are not started.

**Decided here, and worth knowing before the next slice:**

- **Fixed = mean of the last 3 months**, not the lookback mean. The SRS's
  Phase 2 pseudocode says `average(last 3 occurrences)`; the case it
  matters for is a fixed cost that stepped (rent that went up four months
  ago). Same `recentMonths` the Variable formula's 60% part uses.
- **Trend buffer is flat ×1.08 / ×0.95** (the SRS's numbers), applied by
  `statistics.trend` and never by class — the six-month Car (Fixed and
  rising) gets it, asserted in unit and seed tests.
- **A seasonal month is budgeted at what it costs**: the overall mean ×
  E-07's index, *not* the recency-weighted base × index. The first draft
  did the latter and put Gifts' December at 6.1M against Decembers of
  12.7M, because the WMA sat in a quiet summer — caught by printing the
  seed figures, fixed, and a test now proves the spike budget does not
  move with the recent months.
- **A period is the months it touches, weighted by the share covered**
  (`PlanPeriod.monthCoverage`): one monthly statistic serves all six of
  FR-PLN-002's period shapes, and a week across a month boundary carries a
  spike multiplier on the spike month's days only.
- **Option A sums to the total exactly** (largest-remainder rounding);
  **Option B** is income − savings target − Fixed at face value, the rest
  shared proportionally, refused when fixed costs and savings exceed
  income; an **unconstrained** third mode is what both build on (SRS Phase
  3, DBD's nullable `total_budget`). Daily allowance is floored.

**Two things for later slices:** Gifts' quiet months are budgeted at the
WMA, which includes its spikes — the spec applies the multiplier only when
a spike is in the planned period, and this follows it; the wizard may want
to say so, or the index could apply in every month (below 1 in quiet
ones), a one-line change. And over 6 months **Food is Fixed** (CV under
0.15 on Mar–Aug), a second close call for the confidence slice.

---

## This session — the classifier ([PR #68](https://github.com/SanduniLiyanage/Moneyora/pull/68), merged as `afe2f3b`)

**FR-PLN-004**, the second slice of Sprint 5: `ClassifyCategories` turns a
`LookbackWindow` into one `CategoryClassification` per category — Fixed /
Variable / Seasonal, the months a seasonal spike recurs in, and the
statistics it was decided from. Pure arithmetic over PR #66's output (E-05).
Allocation, confidence and the wizard are not started.

**The two findings PR #66 left were decided, not guessed:**

- **Food (CV 0.157) reads Variable; the SDD's 0.15 line is unchanged.**
  Fixed means "budget the exact recent average" (FR-PLN-007), and a
  *monthly* total that holds within 15% is one where that is safe however
  many rows make it up — the plan is a per-period budget, so monthly-total
  variance is the variance that matters. Near the line the two allocations
  converge anyway, so a borderline call costs little, which is the reason
  not to move the line for one fixture. `ClassifyCategories.fixedCvCeiling`
  carries the reasoning.
- **Pets is classified from its three rows** (Variable). No confidence
  check was invented here; FR-PLN-010 is where trust is decided.

**Seasonal is E-07 read strictly.** Gated on the full 24 months (23 is
refused); the month-of-year index is `total / mean(all)` above 1.5, and
*recurring* means every occurrence of that calendar month clears it on its
own — one enormous December and one ordinary one do not average into a
cycle. Gifts is Seasonal `[4, 12]` at 24 months and Variable at 6 on the
same rows: both halves of the rule, on the seed.

**Order is Seasonal → Fixed → Variable, and it cannot change a verdict**:
two months that each clear 1.5× the mean put the CV of 24 months at about
0.16 or more. Checked, and stated in the doc comment rather than the
opposite.

**One finding for the allocator (FR-PLN-007):** over six months, Car's 8%
climb has CV 0.145 and reads **Fixed with a rising trend**. CV cannot see a
monotone drift over a short window; the trend can. The trend buffer must be
applied by `statistics.trend`, not by class, or this case gets none.
Asserted in the seed test so it is not rediscovered by surprise.

---

## This session — the per-category statistics ([PR #66](https://github.com/SanduniLiyanage/Moneyora/pull/66), merged as `76ebe8c`)

**FR-PLN-005**, the first slice of Sprint 5: `ComputeCategoryStatistics`
turns a `LookbackWindow` (1–24 whole months, FR-PLN-003) into one
`CategoryStatistics` per category — mean, median, **sample** standard
deviation, min, max, transaction count, months active, a least-squares
slope and a `TrendDirection`. Nothing past it (classification, allocation,
confidence, the wizard) is started.

**Over monthly totals, in Dart (E-05).** The datasource returns rows and the
domain does the arithmetic; the rows are per-category *monthly totals*, not
transactions, because a budget is set per period.

**No new SQL statement.** `spendingTrend` at month granularity already gave
the totals, so the trend lines' statement gained `COUNT(*) AS
transaction_count`, `TrendPoint` carries it, and `AnalyticsRepositoryImpl`
now also implements `MonthlySpendingReader` in `core/ports/` — the seam the
Copilot already reads `spendingByCategory` through. `money_plan` depends on
the port, never on `analytics` (rule 4).

**Against the seed, end to end** (`test/integration/`, real SQLite →
datasource → port → use case): Bills CV 0.001 and flat, Gifts' Decembers
several times its mean, Car rising at 7% of its mean a month, Pets three
transactions in two years. Two findings for the classification slice:

- **Food's CV over monthly totals is 0.157** — near-daily noise averages out
  per month, and it lands a hair above the 0.15 Fixed line. The seed's doc
  says Food should read Variable; at month granularity that is a close
  call, and the classifier should know it before choosing its threshold or
  its basis.
- **Pets reads "rising" on three transactions.** Trend on noise; the
  confidence gate (FR-PLN-010) is what discounts it, and the trend
  adjustment (FR-PLN-007) should not run before that gate does.

**Decided here, worth knowing:** `LookbackWindow.before(date)` is the whole
months *before* the one `date` falls in — a plan generated mid-month does
not count the partial month. The trend is flat inside ±2% of the mean per
month (`CategoryStatistics.flatBand`). Amounts on the entity are integer
cents; `stdDevCents` and `slopeCentsPerMonth` are a dispersion and a rate
and stay `double`.

---

## This session — the calendar heatmap ([PR #64](https://github.com/SanduniLiyanage/Moneyora/pull/64), merged as `d7a3416`)

**FR-RPT-009**, the fifth and last of Sprint 4's charts: one calendar month
of daily spending, shaded by intensity, fourth on the home screen below the
trend lines. It closes Sprint 4.

**All three questions this file left open for it were decided up front
rather than re-derived, and the code follows those decisions.**

*What it shows for a period that is not a month.* Always the calendar month
the picker's **anchor** falls in, whichever of the seven shapes is selected.
`spendingCalendarQueryProvider` derives from `analyticsPeriodProvider.anchor`
and the account filter, not from `analyticsRangeProvider`, so switching the
chips to Year or Week does not re-ask and does not change the grid; choosing
a date does. The card's subtitle reads `September 2026 · always the whole
month` so a reader knows why this card did not move with the others. The
decision lives in the use case's parameter type: `GetSpendingCalendar` takes
a `SpendingCalendarQuery` (year, month, account), so a caller *cannot* ask it
for a year.

*Which aggregate.* A new `AnalyticsLocalDataSource.dailySpendingTotals` —
one row per day, no `categories` join — assembled from the same
`_spendingParts` fragment as the other three statements, so the E-02/E-04
invariants and the `{account}` hole still live in one place. Measured once
against `spendingTrend(day)` folded per day in Dart, on the 10,000-row
fixture: **1.6ms against 6.8ms**, host VM, comparative only. The benchmark
times both on every CI run. The account filter reaches it (FR-RPT-003).

*The intensity ceiling.* Relative to the largest day in the displayed month:
`SpendingCalendar.levelOf` splits `0 < amount ≤ maxCents` into five even
buckets, so the busiest day is always the darkest cell and a quiet month still
reads as a distribution. Cells are `AppColors.expense` at 20/40/60/80/100%
opacity; a day with nothing spent is `onSurface` at 6%. No category colour
renders, so **the colour-collision check was redone for this surface and is
closed with the chart set complete** — the errata entry records it.

**The chart itself.** A Monday-first seven-column grid (the same default as
`DateRange.week`; FR-SET-004's setting lands there in Sprint 7), day numbers
in each cell, a tooltip with the date and amount on any spent day, a summary
line (month total, busiest day) and a Less→More legend. E-22's two empty
states are told apart off `databaseSummaryProvider`'s count as the other
cards do, in this card's own words. Per this session's brief, the
`RepaintBoundary` PNG check was skipped; the widget tests stand in for it.

**Composed into `HomePage` from `app_router.dart`** below the lines, via a
fourth nullable parameter — `features/home/` still imports no feature.

`dart format`, `flutter analyze` (0 issues), `flutter test` (874
passing, up from 839), `check_architecture.sh` and `check_citations.sh` were
all clean, CI was green on all three jobs, and it merged as `d7a3416`.

### Previous session — the trend lines ([PR #62](https://github.com/SanduniLiyanage/Moneyora/pull/62), merged as `c72abc5`)

**FR-RPT-005**, the fourth of Sprint 4's five charts: per-category spending
over time, one line per category, under the same filter row as the donut and
the bars.

**It answered both questions this file left open for it — and one of them
not with either of the options as framed.**

*`ComparePeriods` repeatedly, or a use case that does not exist yet?* A new
use case, but not for the reason the framing suggests. `ComparePeriods`
returns *deltas*, and a line plots *levels*, so it is the wrong shape before
cost enters into it — and per point it is two `spendingByCategory` queries
(46 for a two-year monthly line). The cheaper-looking middle option,
`spendingByCategory` once per bucket, was **measured, not assumed**, on the
10,000-row benchmark fixture: within a few milliseconds of one bucketed
statement on the host VM (about 21ms against about 16ms for 24 months). The
VM is the flattering venue for the loop, though — it pays no platform-channel
round trip per call, and a device pays one *per point* (24 monthly, up to 92
daily) against one for the statement. A chart whose query cost grows with the
number of points it draws is the shape NFR-PER-006 exists to refuse. So:
`AnalyticsLocalDataSource.spendingTrend`, one `GROUP BY bucket, category`
statement, **assembled from the same expense fragment as
`spendingByCategory`** (`_spendingParts`; both statements are `{parts}` holes
filled from it) so the E-02/E-04 invariants still live in exactly one place.
Grouped on the id first and joined to `categories` after, which measured
about 30% cheaper than grouping on the joined name. The benchmark times both
paths on every CI run, so the reasoning stays a number.

Two things surfaced while measuring, both fixed in the same slice.
`DateTime.parse` on the 360 rows a two-year line returns cost 7ms on the VM
against 11ms for the SQL itself — it is a general ISO-8601 parser built on a
regular expression — so `decodeIsoDay` now sits beside `encodeIsoDay` in
`date_utils.dart` and slices the fixed-width string instead. And the first
spike's figures (9.5ms against 15.4ms) came from a fixture with no splits;
they are not the ones in the code's comments. The committed numbers are the
benchmark's own.

*Does the account filter reach it?* Yes. `GetSpendingTrend` takes
`AnalyticsQuery` like the other two; `ComparePeriods` is untouched, stays
FR-COP-021's (all-accounts by design), and is **still called by nothing** —
the "what is idle" list below has been wrong once before for going stale
silently, so: after PR #62 it is the one remaining aggregate without a caller,
and its caller is the Copilot tool, not a chart.

**Granularity is the use case's decision**, from the span: day up to
`maxDailySpanDays` (92, about a quarter), month beyond. A Week or a Month from
the picker plots a point per day; a Year or All plots one per month; a custom
interval falls whichever side its length puts it. **No week bucket, on
purpose**: FR-SET-004 makes the first weekday user-configurable in Sprint 7,
and a week cut in SQL (`strftime('%W')` is Monday-first, always) would ignore
that setting silently. The series is *dense* — a month with no Food spending
is a point at zero, not a break in the line — the same "missing is zero" rule
`ComparePeriods` applies to a category absent from one period.

**The colour-collision check was redone for this surface and stays closed.**
`SPEC_ERRATA.md` named this as the one place that could reopen it. It does
not: the chart draws per-category *spending*, the statement is assembled from
the `type = 'expense'` fragment the donut uses, so an income category is never
selected and its colour never rendered. Past five categories the tail folds
into an "Other" line in `colorScheme.outline` at reduced alpha — not a
category colour. The entry records this and notes the heatmap draws daily
totals on a sequential ramp, so it cannot reopen it either.

**The chart itself.** 2px lines in the category's own colour via
`categoryColorFor` (light/dark aware); dots with a surface-colour ring only up
to twelve points, so a year shows where its months are and a month is not a
bead chain. A legend is always present — a line key, the name, the period's
total — with text in text colours, never the series colour. The y-axis is in
a compact money form (`formatCentsCompact`, in `currency_utils.dart` because
that is the only file allowed to turn cents into a string); x-axis labels are
fitted inside the axis so the first and last are not cut in half. A touch
tooltip names the category and amount. E-22's two empty states are told apart
off `databaseSummaryProvider`'s count as the donut does, but in different
words — the same sentence twice on one screen reads as a stuck template — and
a single Day period is refused as a trend in a sentence ("A single day has no
trend. Pick a week or longer to see one.") rather than drawn as one dot. It was
rendered to PNG in light and dark, week, month and year, through a throwaway
`RepaintBoundary.toImage` test before it went up; that test is not in the
tree.

**Composed into `HomePage` from `app_router.dart`** below the bars, via a
third nullable parameter — `features/home/` still imports no feature.

`dart format`, `flutter analyze --fatal-infos --fatal-warnings` (0 issues),
`flutter test` (839 passing, up from 774), `check_architecture.sh` and
`check_citations.sh` were all clean, CI was green on all three jobs, and it
merged as `c72abc5`.

**Not in this slice, deliberately:** the heatmap, a week granularity (above),
and FR-RPT-006's summary figures.

### Previous session — the income-vs-expense bars ([PR #60](https://github.com/SanduniLiyanage/Moneyora/pull/60), merged as `0d2277a`)

**FR-RPT-004**, the third of Sprint 4's five charts, and the first caller
`GetIncomeForPeriod` has had since PR #54 built and wired it.

**It answered both questions this file left open for it.**

*Does the account filter apply to income?* It has to. A chart whose expense
bar is narrowed to one account and whose income bar is not subtracts one
account's spending from every account's income and calls the difference
savings. So `incomeForPeriod` takes the same filter, through the same
`{account}` substitution `_spendingByCategory` already uses, and
`SpendingQuery` is now **`AnalyticsQuery`** — a mechanical rename, with no
behaviour moved, because the object is no longer only spending's question. The
datasource test asserts both aggregates narrowing to the same account, which
is the specific failure worth guarding.

*The colour-collision check* is now **resolved in `SPEC_ERRATA.md`** rather
than still flagged. The entry asked whoever built Sprint 4's charts to verify
against the actual chart set: the bars draw two *totals*, not a category
breakdown, so no category colour renders on them at all (they use
`AppColors.income`/`AppColors.expense`, whose contrast `app_colors_test.dart`
measures on every run), and the donut draws expense categories only. Neither
surface can put Bills/Deposits, Entertainment/Salary or Gifts/Savings
together. The entry now also names what would reopen it: FR-RPT-005's trend
lines, if a line per category ever plots both kinds at once.

**No third aggregate.** The expense side is the spending rows added up, not a
new query — `spendingByCategoryTotalsProvider` is keyed on the identical
`AnalyticsQuery` the donut uses, so the bars read a cached answer. The filters
render once, on the donut's card above; both charts watch the same providers,
so one change moves both and neither can be left showing the period the user
navigated away from. A second copy of the controls would be two widgets for
one piece of state.

**Net savings is stated in words.** FR-RPT-004 asks for it "highlighted", and
the gap between two bars is not a figure anyone reads off a chart. A deficit
says "Overspent" with a positive amount rather than a negative saving, which
is a decoding exercise; breaking even is savings of nothing, not overspending.

**Composed into `HomePage` from `app_router.dart`**, the same way the donut
and `AccountDrawer` are, via a second nullable parameter —
`features/home/` still does not import `features/analytics/`
(`check_architecture.sh` rule 4).

`dart format`, `flutter analyze` (0 issues), `flutter test` (774 passing, up
from 752), `check_architecture.sh` and `check_citations.sh` were all clean, CI
was green on all three jobs, and it merged as `0d2277a`.

**Not in this slice, deliberately:** trend lines and the heatmap. FR-RPT-006's
summary figures (average daily spend, largest category, month-over-month) are
not Sprint 4 chart work either, despite overlapping these two aggregates.

### Previous session — the account filter ([PR #58](https://github.com/SanduniLiyanage/Moneyora/pull/58), merged as `40c61cd`)

With FR-RPT-002 merged as `cdc1ae3`, `ROADMAP.md`'s Sprint 4 order puts the
account filter next: **FR-RPT-003, "All Accounts, or any specific single
account."**

**All Accounts is `null`.** Not a sentinel id, not an `allAccounts` flag
beside an id — the requirement offers exactly two things, and a flag would
allow a fourth state (all accounts *and* an id) that means nothing.
`SpendingQuery.accountId` is an `int?`.

**This one reaches the SQL, where FR-RPT-002 did not.** The period was the
only filter, so `DateRange` could be `GetSpendingByCategory`'s whole
parameter. Two filters that travel together are one question, so the use case
now takes `SpendingQuery` (`domain/entities/spending_query.dart`), the
repository method takes it too, and `AnalyticsLocalDataSource.spendingByCategory`
gained an `int? accountId`.

The statement keeps **one body with an `{account}` hole** in it, substituted
for `AND t.account_id = ?` or for nothing, rather than growing into two whole
statements. The E-02 (transfers) and E-04 (splits) invariants are the hard
part of that query and a second copy of them is a second place for them to
drift apart. The substituted text is a constant and the id stays a bound
parameter, so nothing is built from input.

**Two traps, both tested against real in-memory SQLite.** A split's parts
carry no account of their own, so the filter follows the parent row — which is
what says where the money left from; filtering to the parent's account returns
the parts, and to any other account returns nothing. And transfers stay
excluded either way: `account_id` is the column both halves of a transfer
carry, so this is the one place the filter could plausibly have resurrected
them, asserted from both sides.

**`validate` still takes the range, not the whole query.** The period is the
only part of a query that can be wrong. An account id either names a row or
selects nothing, which is an empty chart and a true one — and the picker can
only offer accounts that exist.

**Two callers deliberately ask for every account.**
`SpendingByCategoryReader` (the Copilot's port) answers questions about
spending, not about where money sat, and `ComparePeriods` would answer a
question nobody asked if one side of a two-period delta were narrowed. Both
pass a bare `SpendingQuery(range: ...)`.

**Providers.** `analyticsAccountFilterProvider` (a `StateProvider<int?>`) and
`spendingQueryProvider`, which combines it with `analyticsRangeProvider` so
every surface keys the `family` on one identical `SpendingQuery`.
`accountOptionsProvider` reads the existing `AccountReader` port — the same
one `entryAccountsProvider` uses — so `features/analytics/` still does not
import `features/accounts/` (`check_architecture.sh` rule 4).

**UI.** `AccountFilter` is a dropdown under the period chips, not a second
chip row: the period chips are a closed set of six a user reads at a glance,
while accounts are user data of unknown length, and `transfer_page.dart`
already renders accounts this way. It opens on **All accounts**, because the
chart it filters is a home-screen summary and one that silently omits an
account is a wrong total that looks right. An id that names no account (the
filtered account archived or deleted) falls back to All accounts rather than
tripping `DropdownButton`'s assertion, and a failing account read leaves the
chart itself drawing — the accounts are the filter's options, not the chart's
data.

`dart format`, `flutter analyze` (0 issues), `flutter test` (752 passing, up
from 728), `check_architecture.sh` and `check_citations.sh` were all clean, CI
was green on all three jobs, and it merged as `40c61cd`.

**Not in this slice, deliberately:** the remaining three charts. Sprint 4's
two filters are now both shared infrastructure the bars, trend lines and
heatmap will each watch.

### Previous session — period filters ([PR #56](https://github.com/SanduniLiyanage/Moneyora/pull/56), merged as `cdc1ae3`)

With [PR #55](https://github.com/SanduniLiyanage/Moneyora/pull/55) merged as
`05c5e9d`, the donut chart is on the home screen and its only period is the
current calendar month. `ROADMAP.md`'s Sprint 4 order puts the period filters
next, and `currentMonthRangeProvider`'s own doc comment names the swap: a
`StateProvider` in place of the hard-coded month.

**FR-RPT-002 names seven filters — Day, Week, Month, Year, All, Custom
Interval, Choose Date — which are not seven modes.** Six of them choose a
*shape* of period; "Choose Date" chooses which date that shape wraps around.
So the state is one `AnalyticsPeriod` plus one anchor, plus the interval
behind Custom: `PeriodSelection` in
`features/analytics/domain/entities/period_selection.dart`, whose `range`
getter is a pure function of those three fields. Modelling "Choose Date" as a
seventh shape would have meant a mode that answers "which week?" with nothing,
and modelling it as a seventh chip would have meant a chip that cannot be
*selected*, only pressed.

**No query, repository method or use case changed.** A period filter is a
different argument to the same question, so `GetSpendingByCategory` and the
`spendingByCategory` SQL are untouched; what is new is four factories beside
the `DateRange.month` that already existed — `day`, `week`, `year`,
`allTime`. `DateRange.week` takes a `firstWeekday` defaulting to Monday
because FR-SET-004 makes the first day of the week user-configurable
(Sunday/Monday) in Sprint 7; the parameter is where that setting lands, and
until then there is one caller passing the default. `allTime` is a closed
range (2000 to 2100) rather than a nullable one, so "All" costs no branch in
the query, the repository or the use case and still runs on the `date` index.

**Providers.** `currentMonthRangeProvider` is gone, replaced by
`analyticsPeriodProvider` (a `StateProvider<PeriodSelection>`, the picker's
only writer) and `analyticsRangeProvider` (derived, so every surface watching
the same period keys the `family` on one identical `DateRange` rather than
two that mean the same thing). `spendingByCategoryTotalsProvider` did not
change.

**An inverted custom interval is passed through, not corrected.**
`GetSpendingByCategory.validate` already refuses one — its doc comment says
it is public and static precisely so "a screen's period picker" can use it —
and the chart renders that `ValidationFailure`'s own sentence. Swapping the
ends silently would turn a mistake into a plausible-looking answer, which is
the same reasoning that put the check in the use case in the first place. In
practice `showDateRangePicker` cannot produce one; the path exists because
the state can hold one and the failure should be legible if it ever does.

**The picker is a chip row inside the donut's own card** (`PeriodSelector`,
`features/analytics/presentation/widgets/period_selector.dart`), horizontally
scrolling for the same reason `transaction_list_page.dart`'s type filter is —
six chips overflow a 360dp phone. "Choose Date" is the calendar `IconButton`
beside them, disabled for All and Custom because neither is anchored to a
date and offering to move an anchor they ignore would do nothing visible.
Tapping **Custom** always opens `showDateRangePicker`, even when Custom is
already selected — it is the only way to change an interval once set — and
cancelling either picker leaves the selection exactly as it was rather than
switching to a Custom period with no interval behind it. Both pickers use the
`DateTime(2000)`-to-today bounds the entry and account screens already use.

No separate report screen: SDD SCR-001 puts the chart on the home screen, and
a filter one scroll away from what it filters is a filter nobody touches.
`features/home/` still does not import `features/analytics/` — the selector
rides inside `SpendingDonutChart`, which `app_router.dart` already composes.

`dart format`, `flutter analyze` (0 issues), `flutter test` (728 passing, up
from 686), `check_architecture.sh` and `check_citations.sh` were all clean,
CI was green on all three jobs (Analyze & Test, Build Android APK, Build iOS),
and it merged as `cdc1ae3`.

**Not in this slice, deliberately:** the account filter (FR-RPT-003) and the
remaining three charts. The period state is shared infrastructure the bars,
trend lines and heatmap will each watch, which is why it is a provider pair
rather than something the donut owns.

### Previous session — the spending-by-category donut chart ([PR #55](https://github.com/SanduniLiyanage/Moneyora/pull/55), merged as `05c5e9d`)

With [PR #54](https://github.com/SanduniLiyanage/Moneyora/pull/54) merged, all
three analytics use cases and the cold-start/benchmark items are closed out.
`ROADMAP.md`'s Sprint 4 section places the charts next, in the order **donut,
period filters, income-vs-expense bars, trend lines, heatmap** — and names the
donut specifically as the one SDD SCR-001 draws on the home screen itself,
not a separate report screen. This session built that one chart and nothing
past it, per this session's own instruction not to build all five at once.

**`SpendingDonutChart`** (`lib/features/analytics/presentation/`) is the first
caller of `GetSpendingByCategory` — built, wired and tested since PR #52-54,
called by nothing until now. `presentation/providers/analytics_providers.dart`
adds three providers: `currentMonthRangeProvider` (the chart's only period for
this slice — a plain `Provider<DateRange>`, since nothing can change it yet;
FR-RPT-002's filters are next), `spendingByCategoryTotalsProvider` (wraps the
use case, `FutureProvider.autoDispose.family<List<CategoryTotal>, DateRange>`),
and `categoryOptionsProvider` (wraps `CategoryReader.watchAll()` — the same
port `entryCategoriesProvider` already reads, chosen because `CategoryTotal`
carries a colour but no icon, and FR-RPT-001 asks for icons on the chart; this
avoids adding a column to a query the Copilot's tool also reads, per E-24's
reasoning applied to a reader instead of a use case).

A `Left` completes the future with the `Failure` as its error rather than
being `throw`n — `Failure` is a value, not an exception (`ARCHITECTURE.md`
§3), the same convention `accountsProvider`'s `sink.addError` already follows
for a stream, and what keeps `only_throw_errors` clean here.

Past six categories the tail folds into one "Other" slice — a part-to-whole
chart stops being legible well before it, and this is also the
presentation-side answer to [E-10](SPEC_ERRATA.md)/NFR-PER-005's "tested to
50, never refuses the 51st": the chart itself never draws more than six real
wedges no matter how many categories exist, so that stress case does not wait
for the device session to be safe. [SPEC_ERRATA.md's flagged colour-collision
check](SPEC_ERRATA.md) (Bills/Deposits, Entertainment/Salary, Gifts/Savings
sharing colours) was verified against this actual chart: FR-RPT-001 shows
*expense* distribution only, and the three collisions are all
expense/income pairs, so none can render together here. The income-vs-expense
bars chart still needs its own check when that slice is built.

**Empty state follows [E-22](SPEC_ERRATA.md)'s two sentences**, not one: a
user with zero transactions ever sees "Your spending breakdown appears here
once you have added an expense," while a user with history but a quiet month
sees "No spending in this period." instead. Which applies is read off the
existing `databaseSummaryProvider` transaction count rather than a second
spending query — a known simplification (that count includes income and
transfer rows, not expenses specifically) accepted rather than adding a
second aggregate query just to disambiguate a wording choice.

The chart is composed into `HomePage` from `core/router/app_router.dart`, the
same way `AccountDrawer` already is, via a new nullable `spendingChart`
parameter — `features/home/` still does not import `features/analytics/`
(`check_architecture.sh` rule 4). That pushed real page content below the
fold on the 800×600 widget-test surface for the first time: `app_shell_test.dart`'s
"Coming next" taps now scroll the list first (`find.text`'s default
`skipOffstage: true` cannot see a tile that needs scrolling to reach), and its
`ProviderScope`s needed overrides for the two new providers, the same kind
`databaseSummaryProvider` already had and for the same reason — a real
database never resolves inside a widget test's fake-async zone.

`dart format`, `flutter analyze` (0 issues), `flutter test` (686 passing, up
from 680 — `spending_donut_chart_test.dart`'s loading/data/"Other"-fold/both-
empty-states/failure cases), `check_architecture.sh` and `check_citations.sh`
were all clean, and it merged as `05c5e9d`.

**Not in that slice, deliberately:** a period picker (FR-RPT-002, done this
session, below), the account filter (FR-RPT-003), and the other four charts.
`ROADMAP.md`'s Sprint 4 section has the order the remaining ones follow.

### Previous session — `get_income_for_period` and `compare_periods` ([PR #54](https://github.com/SanduniLiyanage/Moneyora/pull/54), merged as `9510a93`)

With [PR #53](https://github.com/SanduniLiyanage/Moneyora/pull/53) merged, the
10k-row query benchmark is closed out. `ROADMAP.md`'s Sprint 4 section places
the two remaining aggregates next, ahead of the charts, and [E-24](SPEC_ERRATA.md)
requires both to be analytics use cases first and Copilot tools second — the
same shape `GetSpendingByCategory` already has.

**`GetIncomeForPeriod`** (FR-COP-008) totals income over a `DateRange`, the
same period type `GetSpendingByCategory` takes. `AnalyticsRepository` gained
one method, `incomeForPeriod`, fulfilled by one new query in
`AnalyticsLocalDataSourceImpl` — a plain `SUM(amount_cents) WHERE type =
'income'`, `COALESCE`d to 0 because a bare `SUM` with no matching rows is
`NULL` in SQLite and there is no `GROUP BY` here to make the row disappear the
way `spendingByCategory` does instead. Income is never split (E-04's split
table exists for FR-EXP-010's expenses only), so there is no `UNION` to write.

**`ComparePeriods`** (FR-COP-021) returns one `CategoryDelta` — categoryId,
name, colour, `deltaCents` — per category present in either of two periods,
largest movement first. It adds no query at all: it calls
`AnalyticsRepository.spendingByCategory` for each period and diffs the two
results in the domain layer, on the reasoning in E-24 that a delta is
arithmetic on totals that already exist, not a second fact only SQL can know.
A category missing from one period is treated as zero for it, the same
"nothing appears" convention `spendingByCategory` already uses for a category
with nothing spent. The first period's failure short-circuits before the
second query runs, the same fail-fast shape `ArchiveAccount` and the category
use cases already use via fpdart's `.match`.

Both use cases got their own `validate` (an inverted range/period is rejected
before any query, same as `GetSpendingByCategory`'s), and both got DI
providers in `injection.dart` — `getIncomeForPeriodProvider`,
`comparePeriodsProvider` — wired but not yet called by anything, the same
state `getSpendingByCategoryProvider` was in before this sprint's chart work
starts. No Copilot tool and no chart were touched; `features/analytics/
presentation/` is still empty in all three subdirectories.

`dart format`, `flutter analyze` (0 issues), `flutter test` (680 passing, up
from 657 — 23 new: the two use cases' own test files, plus cases added to the
existing datasource and repository tests for `incomeForPeriod`),
`check_architecture.sh` and `check_citations.sh` are all clean.
Merged as `9510a93`.

### Session before that — the 10k-row query benchmark ([PR #53](https://github.com/SanduniLiyanage/Moneyora/pull/53), merged as `221020f`)

With [PR #52](https://github.com/SanduniLiyanage/Moneyora/pull/52) merged,
NFR-PER-001's cold start is closed out. `ROADMAP.md`'s Sprint 4 section places
the 10k-row query benchmark next, ahead of the two remaining aggregates
(`get_income_for_period`, `compare_periods`) and the charts — "fixing indexes
here is cheap; in Sprint 9 it is not."

`test/perf/analytics_query_benchmark_test.dart` seeds an in-memory database
(real v1 schema, real indexes) with 10,000 transactions — 9,500 plain expenses
plus 500 split parents with two parts each, so both branches of
`spendingByCategory`'s `UNION` run against real volume rather than the
handful of rows the correctness tests in
`analytics_local_datasource_test.dart` use — then times the query with a
`Stopwatch` over five runs after one untimed warm-up.

**Result on this host machine's `flutter test` VM: ~16ms min/avg at 10,000
transactions.** Printed, not asserted, and labelled "host machine VM,
comparative — not NFR-PER-006 evidence" in the test's own output — per
[E-28](SPEC_ERRATA.md), no VM or emulator number may be cited as satisfying
the 100ms/10,000-row target; that confirmation stays device-only, on the
batched checklist below. The one real assertion is a generous sanity ceiling
(<1s) aimed at the actual risk the roadmap names: a dropped or missing index
turning this query into a table scan, which shows up as a multiple, not a
margin, even on host timing — so this is the cheap-to-catch failure it exists
to catch, not a step toward the NFR figure itself.

No production code changed — this is a test-only addition. `flutter analyze`
(0 issues), `flutter test` (657 passing, up from 656), `check_architecture.sh`
and `check_citations.sh` are all clean. Merged as `221020f`.

### Session before that — NFR-PER-001's cold start, re-measured ([PR #52](https://github.com/SanduniLiyanage/Moneyora/pull/52), merged as `e0ebf15`)

Sprint 4 — analytics — opened with the roadmap's own first item: NFR-PER-001's
cold start, "fixed before the charts, not after," diagnosed in
[E-28](SPEC_ERRATA.md) as a main-thread block — the database opening during
the first frame, ~10s and 608 skipped frames.

Before writing that fix, it was re-measured against the code as it exists
now, on a **release** build (debug and profile both JIT-compile and are not
the comparison to trust), with `adb logcat` bracketing the launch, twice:

- `SQLiteConnection: Database keying operation returned:0` — the database
  actually opening — appears **after** `ActivityTaskManager: Displayed`, not
  before, in both runs.
- `sqflite_sqlcipher`'s Android implementation already dispatches every
  database call to its own background `HandlerThread`, confirmed reading the
  plugin's own source rather than assumed.
- `injection.dart`'s `databaseProvider` is a `FutureProvider` that `HomePage`
  renders a spinner against via `AsyncValue` while it resolves — the same
  shape it has had since Sprint 1.

**There was no main-thread database block left to fix.** Most likely this was
true of an earlier version of the code, before the current `HomePage`/
`FutureProvider` shape existed, and the diagnosis in `SPEC_ERRATA.md` was
never re-checked against the refactors that followed — the same failure mode
this file's own "what is idle" section warns about elsewhere: a claim that
survives the change that falsifies it, because nothing fails when it does.

What the trace shows instead: 32–123 frames skipped in the app's own process
in the moments before `Displayed`, which is Flutter engine attach and
native-plugin registration cost (eight native plugins), not application code
with a thread to move it off of. `Displayed` measured 7.9s, 9.9s and 19s
(`--profile`, discounted) across three runs on this session's
nested-virtualised emulator — **comparative only**, per [E-28](SPEC_ERRATA.md)'s
own rule, and still a long way from the 2s target, but not fixable by
relocating work that was never on the main thread.

**What shipped instead is the half of the original prescription that still
held:** the native launch background was being dropped the instant Flutter
drew anything, spinner included, leaving a bare `AppBar` over blank space for
the rest of a genuinely slow engine start-up. `flutter_native_splash` now
holds it — `FlutterNativeSplash.preserve`/`.remove` in `main.dart`, keyed to
`databaseProvider` resolving either way — in brand indigo
(`AppColors.light`/`dark.brand`; no logo image, because no logo asset exists
in this repo yet). `main.dart` now builds an explicit `ProviderContainer` and
hands it to `MoneyoraApp` via `UncontrolledProviderScope`, so the splash
lifecycle lives entirely in the composition root — `app.dart`, `HomePage` and
their widget tests are untouched.

`docs/SPEC_ERRATA.md` (E-28's 2026-09-12 addendum) and this sprint's entry in
`docs/ROADMAP.md` carry the measured evidence and the corrected claim, rather
than leaving the stale diagnosis standing next to code that no longer matches
it.

`flutter analyze` (0 issues), `flutter test` (656 passing, unchanged —
`main.dart` isn't unit-testable the way the rest of the app is; verified on
the emulator instead), `check_architecture.sh` and `check_citations.sh` are
all clean. Built and ran a release APK on the emulator — also closing out the
"release APK never installed" gap this file has carried since the R8 fix —
confirmed no crash and the home screen renders correctly. Merged as
`e0ebf15`.

### Earlier still — retiring `entry_catalog.dart` ([PR #51](https://github.com/SanduniLiyanage/Moneyora/pull/51), merged as `008633e`)

E-27's resolution, next after [PR #50](https://github.com/SanduniLiyanage/Moneyora/pull/50)
gave the inline `+` its write path. The read the created row landed in was
still `core/database/entry_catalog.dart` — a raw-SQL future that predated the
categories and accounts slices — refreshed by hand rather than replaced.

- **`core/ports/category_reader.dart`, `core/ports/account_reader.dart`** —
  two new ports, the same "contract two features share" role
  `SpendingByCategoryReader` plays for analytics/the Copilot: `features/
  transactions/` may not import `features/categories/` or `features/
  accounts/` (`check_architecture.sh` rule 4), so these are the seam. Each
  carries its own narrow DTO — `CategoryOption`/`AccountOption`, moved here
  from the deleted file — rather than the feature's own entity, the same
  restraint `CategoryWriter` already applies to writes.
- **`CategoryRepositoryImpl`/`AccountRepositoryImpl`** now fulfil
  `CategoryReader`/`AccountReader` directly (`watchAll()`, mapping the entity
  down to the option), the exact shape `AnalyticsRepositoryImpl` already uses
  for `SpendingByCategoryReader` — one object behind the read, not a second
  path to the same rows. `injection.dart` wires each through a private,
  concretely-typed `_...RepositoryImplProvider`, mirroring the analytics
  provider's own comment about why that indirection exists.
- **`transaction_providers.dart`**: `entryCatalogProvider` is gone, replaced
  by `entryCategoriesProvider`/`entryAccountsProvider` — live `StreamProvider`s
  over the new ports, the same shape `categoriesProvider`/`accountsProvider`
  already have in their own features. Live means no more manual refresh: the
  three `ref.invalidate(entryCatalogProvider)` calls (after a transfer, after
  the inline `+`, after loading the dev seed) are all deleted, since each
  underlying repository already publishes to the change signal these streams
  watch.
- **`add_transaction_page.dart`, `transfer_page.dart`,
  `transaction_list_page.dart`** — all three read sites switched from the
  one-shot catalog to the two live providers. The entry screen's inline `+`
  still has to wait for its new category to actually arrive before selecting
  it (the stream update is asynchronous, not instantaneous) — that wait is
  now a manual `ref.listenManual` rather than `ref.read(future)`, since a
  `StreamProvider`'s cached value can already be stale by the time a write
  completes.
- **`core/database/entry_catalog.dart` is deleted**, along with its test
  file. Two dangling doc-comment references to it (in
  `category_local_datasource.dart` and `category.dart`) were updated rather
  than left pointing at a file that no longer exists.
- **Tests**: `watchAll()` gets its own cases in
  `category_repository_impl_test.dart` and `account_repository_impl_test.dart`
  (mapping to the option type, excluding archived accounts, and proving it is
  the same live read `watch()` is), plus one identity test per port in
  `injection_test.dart` proving a write through the use case comes back out
  of the port — the same shape PR #50's inline-`+` identity test used.
  `transactions_flow_test.dart` and `transfer_screen_test.dart` swap their
  `entryCatalogProvider` overrides for the two new providers; the inline-`+`
  group's mutable-catalog fixture becomes a `StreamController` so a created
  category can still be pushed through after the fact.

`flutter analyze` (0 issues), `flutter test` (656 passing, up from 655),
`check_architecture.sh` and `check_citations.sh` were all clean, and it
merged as `008633e`.

**Sprint 3.5 is now fully complete.** FR-EXP-011's category-grouped
*transaction* list toggle remains a separate requirement against
`transaction_list_page.dart`, not part of this slice (E-11 raises it against
FR-EXP-006 and SDD SCR-005) — see "What is next" below.

### Previous session — the entry screen's inline category `+` (PR #50, merged)

E-13's inline `+`: a "New" chip on the entry screen's category row opens a
small bottom sheet, writes through the new `CategoryWriter` port and
`QuickAddCategory` (a thin adapter over `AddCategory`, so a category created
inline can never drift from one created through `CategoryFormPage` on what
counts as valid), and selects the result without leaving the entry screen.
Full detail is in that PR's own description and in `git log` rather than
repeated here — this summary exists only because this session's work builds
directly on it. Merged as `87df4da`.

### Session before that — the categories management screen (PR #49, merged)

Picked up where PR #47 left off: `domain/`, `data/` and
`presentation/providers` were done, and `presentation/pages` were empty.
That session built `category_form_page.dart` (create/edit, one screen for
both), `category_list_page.dart` (the Expense/Income tabbed management
screen), the `core/widgets/category_icons.dart`/`core/theme/category_palette.dart`
catalogues the icon and colour pickers draw from, and the `categories`/
`categoryForm` routes. Merged as `aee7d51`.

---

## What this is

An offline-first personal finance app in Flutter, targeting Android 8.0+ and
iOS 15.5+. Two headline features distinguish it from a plain expense tracker:

- **Money Plan Generator** — builds a budget from the user's own spending
  history using statistics (weighted moving average, trend detection, seasonal
  adjustment). Runs entirely on-device.
- **Receipt Scanner** — ML Kit OCR on-device, with a three-layer keyword
  categoriser that learns from corrections.

A solo project, built to production discipline rather than demo discipline:
commit messages, PR history and CI are part of the deliverable, not overhead
around it. That is why several conventions below are stricter than a project
this size would normally need.

Guidance here is written to be followed exactly. A PR link arrives with the
terminal commands that go with it, and no step is done until `flutter analyze`,
`flutter test` and `check_architecture.sh` are all green.

---

## Where the specifications live, and why they cannot be trusted alone

`docs/specs/` holds four documents generated by Kimi from a requirements
conversation: SRS v1.0, SDD v1.0, DBD v1.0 and an ERD. They are the approved
baseline and are **left exactly as approved**.

They also contradict each other and themselves. The first audit, before any
schema was written, turned up twenty defects, four of which blocked Sprint 1
outright. Later passes kept finding more — reading a baseline for the first
time, auditing the code's own citations against one, and most recently
transcribing all four baselines to Markdown so they could be grepped rather
than opened as PDFs.

**[`SPEC_ERRATA.md`](SPEC_ERRATA.md) carries its own current count and status
in its own summary table — not repeated here.** The previous version of this
paragraph hardcoded "28 entries" two sentences after stating that the errata
file is the source of truth for its own counts, which is the exact failure
this convention exists to stop: a number that has to be remembered to be kept
in sync goes stale the first time it isn't.

**Where a baseline and the errata disagree, the errata wins.** The ones that
shape the code most:

| ID | What it changed |
|---|---|
| E-01 | Brand is **indigo**, not the SRS's green — green would read as a copy of Monefy, the reference app |
| E-04 | `transaction_splits` table invented; no baseline defined one, leaving FR-EXP-010 unbuildable |
| E-05 | Statistics are computed **in Dart**, not SQL — `STDDEV()` does not exist in SQLite |
| E-06 | Money is `INTEGER` minor units (`*_cents`) everywhere; all three baselines said `REAL` |
| E-07 | Seasonal detection needs **24 months**, not the 6 the SRS assumed — FFT over six points is noise |
| E-16 | `transfer_direction` column: without it nothing says which way a transfer moved |
| E-17 | `category_id` is nullable — a transfer has no category, and `NOT NULL` made one uninsertable |
| E-19 | iOS is **compile-verified only**; it has never run on a device |
| E-20 | iOS floor is 15.5, not 14 — ML Kit requires it |
| E-25 | Four FR-ACC citations named the wrong requirements; **FR-ACC-007** raised for `DeleteAccount`, which had none. FR-ACC-005 deferred to Sprint 7 |
| E-27 | `entry_catalog.dart` sat outside a feature slice on purpose — **deleted this session**, its reads moved behind `CategoryReader`/`AccountReader`, which is what stopped "interim" becoming permanent |
| E-28 | NFR-PER-006 cannot be verified here. Emulator timings are **comparative, never conformant**; no sprint blocks on the borrowed device |

When implementing anything, check the errata for its requirement ID first.
E-25 is the reason to check rather than copy a neighbouring file's citation:
the wrong IDs in the accounts slice were all copied from each other.

---

## What is built

**Sprints 1 through 3 are complete**, Sprints 1 and 2 verified running on an
Android emulator. PR #28 landed the accounts domain and data layers, and the
screens followed — the side panel (FR-ACC-003), the create-and-edit form with
its icon catalogue (FR-ACC-001, 002, 006), archiving, restoring and deleting
(FR-ACC-004, FR-ACC-007), and the transfer screen (FR-TRF-001 to 003). The last
two pieces — the entry screen's account selector (FR-EXP-001) and FR-TRF-004's
`From`/`To` row labels — landed last: `add_transaction_page.dart` now offers a
`_AccountPicker` matching the category chips beside it, and
`transaction_list_page.dart` names a transfer row's counterparty instead of
printing the literal word "Transfer". That label needed one data-layer
addition alongside the presentation work: `transactions.account_id` only ever
named the side a row belongs to (E-16), so the counterparty comes from
`transfers` — the header row E-15 already writes to link both halves — read
via a join in `TransactionLocalDataSourceImpl.list` and carried up through a
new `Transaction.counterpartyAccountId` field.

**Sprint 3.5 — categories — is complete**, bar FR-EXP-011. Added 2026-09-10
and slotted between Sprints 3 and 4: FR-EXP-004, FR-EXP-005 and FR-EXP-011
had been scheduled in no sprint at all, while analytics, the Money Plan and
the receipt scanner all depend on categories being something the user
controls. That was a defect in the plan rather than in the SRS, so it is
fixed in [`ROADMAP.md`](ROADMAP.md) and deliberately raised no errata entry.

**`domain/`, `data/`, `presentation/providers` and `presentation/pages`
are done and wired** (PRs #44, #46, #47, #49) — `Category`, `CategoryRepository`,
the four use cases, `CategoryLocalDataSourceImpl`, `CategoryRepositoryImpl`,
`category_providers.dart`, `injection.dart` entries for all of it (proven
reachable in `injection_test.dart` the same way the transactions slice is),
and `CategoryListPage`/`CategoryFormPage`, reachable from the home screen's
"Coming next" list. A user can create, rename, re-icon, re-colour, re-parent
and delete a category through the app. PR #50 added a fifth write path in:
the entry screen's inline `+`, through the `CategoryWriter` port and
`QuickAddCategory`. **PR #51 finished the slice**:
[E-27](SPEC_ERRATA.md)'s retirement of `entry_catalog.dart` is done — the
entry screen's category chips and both screens' account pickers all read
`CategoryReader`/`AccountReader` now, the same ports the inline `+`'s write
uses on the other side.

**Sprint 4 — analytics — has domain, data, both filters and four of its
five charts.** The cold-start splash (PR #52), the query benchmark (PR #53)
and the aggregates — `GetSpendingByCategory`, `GetIncomeForPeriod`,
`ComparePeriods` (PR #54) and `GetSpendingTrend` (PR #62), with
`AnalyticsRepository`/`AnalyticsLocalDataSourceImpl` underneath — are in and
tested; the benchmark proves the category-total and the bucketed trend
queries both stay fast at 10,000 rows on this host's VM (see the sessions
above). `features/analytics/presentation/` holds the donut (PR #55), the
period and account filters (PR #56, #58), the income-vs-expense bars (PR #60)
the trend lines (PR #62) and the calendar heatmap (PR #64), all composed
into `HomePage` from `app_router.dart`. **Sprint 4 is complete.**
NFR-PER-001's item is done — it lived in `main.dart`,
not the feature, so it did not need the feature's own layers to exist first.

Running ahead of its sprint, **all three of the Copilot's layers** are built:
the agent loop and its contracts, the first tool, the Gemini datasource and the
ask screen at `/copilot`. What it has never had is a run against the live API.
See [`COPILOT.md`](COPILOT.md) for what it is scoped to and why.

```
lib/
├── core/
│   ├── database/
│   │   ├── migrations/v1_initial.dart   13 tables, 11 indexes, errata-corrected
│   │   ├── database_change_bus.dart     one "something was written" signal
│   │   ├── database_helper.dart         SQLCipher open + migration runner
│   │   ├── database_summary.dart        row counts (SQL lives here, not in DI)
│   │   ├── encryption_key_store.dart    AES-256 key -> platform keychain
│   │   └── seed/
│   │       ├── default_seed.dart        15 expense + 3 income categories
│   │       └── dev_seed.dart            >500 synthetic transactions, 24 months
│   ├── errors/          Failure + Exception hierarchies
│   ├── network/         network_info.dart      — the abstract check
│   │                    connectivity_network_info.dart — its implementation
│   ├── ports/           contracts two features share (see ARCHITECTURE §5)
│   ├── router/          go_router, 10 routes: 7 real screens, 3 stubs
│   ├── theme/           indigo/amber, contrast-verified light + dark
│   ├── usecases/        UseCase<T, Params> base
│   ├── utils/           currency_utils, date_utils, amount_expression
│   └── widgets/         account_icons.dart — E-26's 25-icon catalogue
├── features/
│   ├── accounts/        full slice: panel, form, icons, archive, delete
│   │                    + account_totals.dart, the entity carrying E-25's
│   │                    "what the total left out" line
│   ├── analytics/       domain + data for all 3 aggregates; presentation/
│   │                    has the donut chart, its first caller. Sprint 4.
│   ├── categories/      full slice: list/management screen, create-and-edit
│   │                    form with icon + colour pickers and parent dropdown
│   ├── copilot/         all three layers. The only http in the application
│   ├── home/            Sprint 1 proof screen, still the home route
│   └── transactions/    full slice: keypad entry, list, filter, edit, undo
├── app.dart          MaterialApp.router
├── injection.dart    Riverpod providers = the DI container
└── main.dart         ProviderScope
```

**Not started — scaffold directories with zero `.dart` files:** `auth/`,
`backup/`, `money_plan/`, `receipt_scanner/`, `settings/`, plus
`core/constants/` and `core/extensions/`. An empty directory is *not started*;
none of these is in progress. `categories/` is now a complete slice, the same
status as `accounts/` and `transactions/` — `presentation/widgets` is still
empty, but that is not a gap: everything the screens need lives in
`presentation/pages` and the `core/widgets`/`core/theme` catalogues, the same
shape `accounts/` settled on.

The three routes with no screen behind them are `moneyPlan`, `scanReceipt` and
`settings`, which are stubs. The seven real ones are `home`, `transactions`,
`copilot`, `transfer`, `accountForm`, `categories` and `categoryForm`.

Test and coverage figures are in **the table at the top of this file**, which
is the only place they are written down. CI runs format, analyze, the
citation check, tests, the 75% domain coverage floor, the architecture
boundary check, an Android debug and release APK build, and an iOS compile —
all three jobs blocking. See the Environment section below for the release
build's own history.

The ten uncovered domain lines sit at five sites, verified at `7c917a7`: the
unreachable `default` arms in `transaction_repository.dart` and
`analytics_repository.dart`, `copyWith` on `category_total.dart` and
`tool_exchange.dart`, and one guard in `run_copilot_query.dart`.

`ArchiveParams`' const constructor comes and goes from that list between runs
with no change to the file — a const constructor evaluated at compile time can
report either way — so do not read a one-line move in this figure as a
regression. An earlier version of this paragraph also said "five" when it meant
five *sites* and ten *lines*. Coverage is measured the way CI measures it —
`lcov --extract coverage/lcov.info '*/domain/*'` — so this is the number the
gate prints, not a differently-scoped one.

### The dev seed is a test oracle, not filler

`dev_seed.dart` generates over 500 transactions across 24 months — the figure
was carried as "~700" for a while, but `dev_seed_test.dart` only asserts
`greaterThan(500)`, so 500 is what is actually guaranteed. It generates
deliberately shaped data so Sprint 5 can assert the
classifier reaches the right verdict rather than merely running: Bills is a
fixed cost (CV < 0.15), Food is noisy, Gifts spikes each April and December,
Car climbs 8% a month, Pets has three transactions total and must score LOW
confidence. It is seeded and deterministic — a fixture whose output moves per
run cannot be an oracle.

---

## What is next

**Sprint 5's wizard is complete and live tracking's write path is in.**
The engine (PRs #66–#72), the saved plan (PR #74), the wizard (PRs #77,
#79) and FR-PLN-013's first slice (PR #81) are merged and `main` is clean
at `32119e3`. What remains of the sprint is **FR-PLN-013's second slice**,
the screen: `PlanAllocation.spentCents` is now a real number, kept inside
every expense write and re-read through `WatchActivePlan` on the shared
bus, so `ActivePlanPage`'s side is a percentage per row, a projection to
the period's end and the three colours (green on track, yellow 80–99%,
red exceeded). **Do first, before the number is shown:** wire the recount
into activation — `activate` and `insert`-with-`activate` in
`money_plan_local_datasource.dart` call `_recomputeSpentWithin` in their
own transaction — so a plan saved mid-period counts the expenses already
in it (see "This session" for why this is the one gap the incremental
write cannot close). Then FR-PLN-014's three overspend responses and
FR-PLN-015's plan list and comparison (`ActivatePlan` is built and called
by nothing yet; `RecomputePlanSpending` likewise, its Settings caller is
Sprint 7's). Two Sprint 4 leftovers are *not* blockers for it:

- **FR-RPT-006's summary figures** were never scheduled as a chart and are
  still open; and `ComparePeriods` is still called by nothing — its caller is
  the Copilot's `compare_periods` tool, tracked in `ROADMAP.md`'s Copilot
  table.
- **The heatmap's first weekday is Monday**, hard-coded in
  `spending_heatmap.dart`'s `_firstWeekday` beside `DateRange.week`'s
  default; FR-SET-004 makes it configurable in Sprint 7 and both are where
  that setting lands.

**FR-EXP-011's category-grouped list toggle is not Sprint 4 work**, despite
the name inviting the mix-up. `ROADMAP.md`'s own Sprint 3.5 section lists it
as one of that sprint's deliverables (E-11 raises it against FR-EXP-006 and
SDD SCR-005), and it is still open — PR #51 closed out everything else in
Sprint 3.5 but not this. It belongs to `transaction_list_page.dart`, and
picking it up is independent of anything Sprint 4 builds.

- **The account-picker widgets across `add_transaction_page.dart` and
  `transfer_page.dart` are near-duplicates** now that both read the same
  `AccountOption` shape from `entryAccountsProvider` — `_AccountPicker` in
  one and `_AccountField` in the other render the same list two different
  ways (chips vs. a dropdown) for different reasons (the entry screen picks
  one account, the transfer screen needs two with balances and currencies
  visible for E-25's refusal), so this is a "notice it, don't merge it
  reflexively" item rather than a scheduled deliverable.

One thing worth deciding rather than assuming: whether a category the entry
screen's inline `+` creates should default `sortOrder` to sit after the
existing set, and whether re-ordering categories (drag-to-reorder on the list
screen) is in scope for FR-EXP-004 or a later polish pass — neither use case
nor screen makes a claim about it today, and the list currently renders in
whatever order `WatchCategories` returns them. `QuickAddCategory` leaves
`sortOrder` at its default (0), matching what `CategoryFormPage` already does
for every new category — not a new answer to the open question, just the
existing one applied consistently.

**The release build is fixed** (see Environment below and
[E-09](SPEC_ERRATA.md)), and this session installed and ran one on the
emulator for the first time (see "This session" above) — it launches, and the
home screen renders correctly with real data. Still open: an actual **device**
install, which stays on the batched checklist below.

**Sprint 3 is now finished** — the accounts side, the transfer screen, the
entry screen's account selector and the transfer row labels are all built.

Every screen in this slice shows its use case's own refusal rather than
inventing one, and the widget tests assert on those exact sentences — so a rule
cannot drift between a screen and the thing that enforces it. Four are live:
`ArchiveAccount` will not archive the last usable account, `DeleteAccount` will
not delete one with transactions, and `MakeTransfer` refuses both a transfer to
the account it came from and one between two currencies (E-25, until
FR-ACC-005 lands in Sprint 7).

The panel is composed in `core/router/app_router.dart` and passed to
`HomePage` as a widget, rather than imported by the home screen. A feature
importing another feature is what rule 4 of `check_architecture.sh` forbids,
and the router already names every feature's pages — so it is where the app is
assembled, the way `injection.dart` is the only file allowed to name a
concrete `data/` class. Any later screen needing another feature's widget goes
the same way.

**One thing is built, tested, wired into DI and still called by nothing:
`RecomputeAccountBalance`.** Not on app start, not after a restore, not from a
screen — its only references are `injection.dart`'s
`recomputeAccountBalanceProvider` and the tests.

This paragraph used to name three such things, including `MakeTransfer` and the
datasource's `createTransfer`. That stopped being true when the transfer screen
landed in PR #38: `transfer_page.dart` and `transaction_providers.dart` both
call `MakeTransfer` now. The claim survived the PR that falsified it, which is
worth noticing — a "what is idle" list is exactly the kind of prose that goes
stale silently, because nothing fails when it does.

`RecomputeAccountBalance` stays manual-only on purpose, and the reasoning is in
the [E-18 addendum](SPEC_ERRATA.md). Reconciliation is `O(all transactions)` per
account; putting a full-history scan on the launch path is the opposite of what
Sprint 4 does to NFR-PER-001. It gets its caller from the Settings action in
Sprint 7 and from the restore path in Sprint 8.

Be precise about what that leaves open. E-18's *cache correctness* is satisfied
— every balance change happens inside the same transaction as the row that
caused it, and `_recomputeWithin` re-derives on edit — so drift cannot
accumulate through the app's own write paths. What has no reachable repair is
drift arriving from outside them: a restored backup, a crash mid-write, a
database edited by hand. Until Sprint 7, that repair is built and unreachable,
which is not the same as done.

Its oracle already exists as a property test in
`transaction_local_datasource_test.dart`: after a random sequence of writes, the
cached balance must equal the balance recomputed from history.

Sprint 3 is planned as eight independently mergeable slices. Three things
decided while planning it are worth knowing before touching the code:

- **FR-ACC-005 is deferred to Sprint 7** (E-25). Sprint 3 displays each
  account's currency and does not convert between currencies. Two interim
  guards follow from that and are not optional: cross-currency transfers are
  refused in `MakeTransfer.validate`, and the Total Balance sums LKR accounts
  only and says on screen what it excluded.
- **`FR-ACC-007` is new** (E-25), raised for `DeleteAccount`, which shipped in
  PR #28 citing FR-ACC-003 — the account side-drawer, an unrelated screen.
- **Account balances follow transaction writes, via a shared change bus.**
  `AccountRepositoryImpl.watch` listens to `accountLocalDataSource.changes`,
  but an expense or a transfer moves `current_balance_cents` from the
  *transactions* datasource. `core/database/database_change_bus.dart` is the
  one signal both publish to; `injection.dart` owns it and hands it to each.
  A datasource given a bus never closes it — the first one disposed would
  otherwise silence the rest — and a datasource given none makes a private
  one, which is how every unit test constructs them.

**Sprint 3.5 — categories — is complete** (PRs #44, #46, #47, #49, #50, plus
this session's PR #51); see [`ROADMAP.md`](ROADMAP.md). FR-EXP-004 (custom
categories) and FR-EXP-005 (the two-level hierarchy) have a screen, not just
use cases and a repository; E-13's inline `+` has both a write path
(`CategoryWriter`) and, as of this session, a matching read
(`CategoryReader`/`AccountReader`); and [E-27](SPEC_ERRATA.md)'s
`entry_catalog.dart` retirement is done. FR-EXP-011 (the category-grouped
*transaction* list) is a separate requirement against
`transaction_list_page.dart`, not this slice — see "What is next" above for
why that is worth stating plainly.

**Then Sprint 4 — analytics.** Its first query is already in:
`GetSpendingByCategory`, with the datasource, the repository and the DI wiring,
tested against `dev_seed`'s 24 months for the E-02 and E-04 traps.

Four notes for that work:

- **The cold start is fixed before the charts.** The database opens during the
  first frame and stalls the UI for roughly ten seconds (`Skipped 608 frames` in
  logcat). NFR-PER-001 requires a sub-2-second cold start, so the app misses it
  by a factor of five on the first thing anyone sees. It needs a splash screen
  and an off-main-thread open. This is a main-thread block, so it reproduces
  anywhere and the fix is verifiable on the emulator — it does **not** wait for
  the borrowed phone.
- **The 10k-row benchmark is comparative, not conformant.** Seed 10,000 rows and
  measure **query time, not frame time**. Per [E-28](SPEC_ERRATA.md), the
  emulator can prove an index is present and being used and that a change made a
  query faster — a missing index is a multiple, not a margin — but no emulator
  number may be cited as satisfying NFR-PER-006. Label every figure *"emulator,
  comparative"*.
- **`get_income_for_period` and `compare_periods` are Sprint 4 deliverables**,
  not Copilot work. [E-24](SPEC_ERRATA.md) requires each to be an analytics use
  case first and a tool second, so no aggregate is written twice and reporting
  logic stays out of the chat feature.
- The category-total query is what the Copilot's spending tool reads, through
  `core/ports/spending_by_category_reader.dart`. Change what counts as
  spending in one place and both move together — that is the point.

**The Copilot is a parallel workstream, not a sprint.** All three layers are
built and reachable at `/copilot` from the home screen: the agent loop, the
spending tool over the real database, the Gemini datasource, the egress guard,
and the ask screen with its key entry.

What remains is not code, and **it does not need the borrowed phone.** It needs
the Gemini API key typed into the screen and one real question asked — on the
**emulator**, which has network access. This was carried as "on a running
device" for a while, which parked the last unproven part of the feature behind
hardware for no reason. Do it in the next emulator session.

Until then the feature is unproven against the live API: the wire format is
built to the documented shape and covered by tests, but no test can tell you
Google accepts it. It does not jump ahead of Sprint 5 or Sprint 6 — two of its
five specified tools wrap features those sprints build, which is recorded as
[E-24](SPEC_ERRATA.md).

## The device session — one batched checklist

Physical Android access is **occasional and by arrangement**, not on demand. So
everything that genuinely needs real hardware is collected here, in order, to be
done in one sitting. **No sprint blocks on this list** ([E-28](SPEC_ERRATA.md)).

The rule for what belongs here: **if it can be done on the emulator, it is not
on this list.** Two things were on it and have been taken off — the Copilot's
live-API question (the emulator has network) and the cold-start *fix* (there
turned out to be no main-thread block to move, and the splash screen that
shipped instead was fully verifiable on the emulator too). Only the confirmed
cold-start *number* remains.

Do these in order; each later step benefits from the seed loaded in step 2.

**Before you go — prepare on the emulator, so the phone time is measurement
only:**

- [ ] Build and install a **release** APK, not debug. Debug builds carry every
      ABI and unstripped symbols, and their timings are not the ones the NFRs
      are about. **This works now** — fixed per [E-09](SPEC_ERRATA.md) and
      confirmed running on the emulator this session — so this step is
      installing the same build onto the physical device, not fixing it.
- [ ] Have the 10k-row seed ready to load, and know how you will time a query.
- [ ] Charge the phone and keep it plugged in during timing.

**On the device:**

1. [ ] **Record the machine before recording any number.** Device model,
       Android version, RAM, release-or-debug build, and whether it is plugged
       in. An unattributed "47 ms" proves nothing; thermal and governor state
       move timings more than most code changes do.
2. [ ] **Load the 10k-row seed** and run the analytics query benchmark. These
       are the figures that can be cited against **NFR-PER-006** (<100 ms per
       query at 10,000 transactions). Record query time, not frame time.
3. [ ] **Cold-start timing** for **NFR-PER-001** (<2 s). Kill the app fully
       first — a warm start measures nothing. Do this *after* the Sprint 4
       splash-screen fix, or you are only confirming the bug.
4. [ ] **NFR-PER-005** — the category picker and donut chart at 50 categories,
       per [E-10](SPEC_ERRATA.md)'s "tested to 50, never refuses the 51st".
5. [ ] **The Copilot demo recording.** The live-API *proof* happens earlier on
       the emulator; what needs the phone is a recording that looks like an app
       rather than a desktop window.
6. [ ] **General walkthrough** on real hardware: add an expense on a real
       keyboard, a transfer, archive and delete an account, scroll a long list,
       rotate the screen, and check the dark theme in real light.
7. [ ] **Write every number straight into this file** before handing the phone
       back, with its machine attributes attached. A figure remembered is a
       figure lost.

**Not on this list, and deliberately:** anything iOS. That needs a Mac as well
as a device and is a separate, unscheduled problem — see
[E-19](SPEC_ERRATA.md).

### Seeing the app with real data

The transaction list's empty state carries a **Load 24 months of sample data**
button in debug builds. It runs `dev_seed.dart`, which until PR #27 nothing in
the app could reach — the fixture existed for tests alone, which is half of
what Sprint 1 built it for.

## Environment — the traps, all of which have already bitten

Windows 11, Flutter 3.47.2 at `D:\dev\flutter`, Android SDK at
`D:\dev\android-sdk`.

**`PUB_CACHE` must stay on `C:`**, the same drive as the repository. Kotlin's
incremental compiler resolves plugin sources with a *relative* path, and
Windows has none between two drive letters. The symptom is hundreds of lines
of `Could not close incremental caches`; the cause appears only in a
*suppressed* exception. This cost an evening. See `SETUP.md` §0.1.

**`cmdline-tools` is pinned to 20.0** at `cmdline-tools/latest`. Version 23.0.0
replaced `sdkmanager` with a shim that splits package names on `;` and crashes
under Gradle. 23.0.0 is parked at `cmdline-tools/23.0-broken` — use it for
installs with the `/` separator (`platforms/android-37`), because 20.0 is too
old to see newer packages. Every build prints an "inconsistent location"
warning as a result; it is cosmetic.

**`compileSdk` stays at Flutter's default (36).** API 37 ships as "37.0" — a
decimal API level AGP 9.1.0 cannot resolve. `flutter_secure_storage` is pinned
to 10.3.1 because version 11 demands 37. CI passed with 37 while every local
build failed, since GitHub's runners carry an integer `android-37` — a green
tick that held only on the CI image.

**The release build was broken for 38 pull requests, and CI could not see it.**
Fixed 2026-09-10; the history is worth keeping because the shape of it will
recur. `flutter build apk --release` failed at R8 — ML Kit references
script-specific recognisers it does not depend on — while every CI check stayed
green, because **CI built a debug APK and debug does not run R8.** The minifier
had never executed on this project.

`android/app/proguard-rules.pro` now carries `-dontwarn` for the four unused
script packages, and CI builds a release APK. Sizes, per
[E-09](SPEC_ERRATA.md): **arm64-v8a 35.9 MB against an 80 MB budget**, with ML
Kit included.

**A release APK ran on the emulator for the first time this session** (Sprint
4's NFR-PER-001 re-measurement — see "This session" above): it launches, the
home screen renders with real data, and nothing in R8's minification broke
the JNI-backed plugins this app leans on. "Compiles in release" is no longer
the only claim available — only the physical-device install remains, on the
batched checklist below.

**`kotlin.incremental=false`** in `android/gradle.properties`. It bought
nothing here and repeatedly corrupted its own caches.

**Interrupting a Gradle build with Ctrl+C corrupts state** and costs a full
rebuild. During the build phase `q` does nothing — only Ctrl+C works, so
simply do not. A cold build is 8–12 minutes.

---

## Workflow

`main` is the only permanent branch, protected, and requires all three CI
checks. GitHub Flow: short-lived `feat/…`, `fix/…`, `docs/…`, `ci/…` branches,
PR, squash-merge, delete.

`gh` is installed and authenticated. The cycle:

```powershell
git switch -c feat/thing
# work
git add -A ; git commit ; git push -u origin HEAD
gh pr create --fill
gh pr checks --watch
gh pr merge --squash --delete-branch
git pull
```

Use `git branch -D` (capital D) locally — squash-merge means `-d` always
refuses.

**Wait for CI before merging.** Merging early has already stranded commits
once and let a failure onto `main` once.

Before claiming anything is done:

```powershell
dart format .
flutter analyze
flutter test
bash scripts/check_architecture.sh
```

The architecture check has caught real violations, including SQL that had
drifted into `injection.dart`.

### Running the app

```powershell
flutter emulators --launch moneyora
flutter run
```

Then `r` hot-reloads in under a second. `q` quits — press it *before* closing
the emulator window.

---

## Conventions that are not negotiable

- **Dependencies point inward.** `domain/` imports nothing but `dart:*`,
  `fpdart` and `equatable`. Enforced by `scripts/check_architecture.sh`.
- **Money is `int` cents.** `double` appears in exactly one place:
  `parseToCents`, on the input boundary, rounded away immediately.
- **SQL lives only in `data/datasources/` or `core/database/`.**
- **`data/` throws; repositories catch and return `Left(Failure)`.** No
  `try`/`catch` above `data/`.
- **Every requirement-implementing commit names its ID** — `Refs: FR-PLN-007`,
  and the errata ID too where one applies.
- Commit messages explain **why**, not what. The diff already says what.
