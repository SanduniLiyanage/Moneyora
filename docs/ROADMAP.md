# Moneyora — Build Roadmap

Follows the SRS 8.1 sprint plan, with the ordering adjustments that matter in
practice. **15 weeks, 11 sprints.**

It was 14 weeks and 10 sprints until 2026-09-10, when auditing the plan against
the code found that FR-EXP-004 (custom categories), FR-EXP-005 (the two-level
hierarchy) and FR-EXP-011 (the category-grouped list) were scheduled in no
sprint at all. Category management is a core feature of an expense tracker and
its absence is more visible on opening the app than a missing chart, so it gets
**Sprint 3.5**, not a corner of Sprint 4. That pushes everything after it back
one week.

This is a defect in **this plan**, not in the SRS, which specifies all three
requirements correctly. It is therefore fixed here and deliberately **not**
recorded in [`SPEC_ERRATA.md`](SPEC_ERRATA.md): that register is for the
baselines being wrong, and stretching it to cover scheduling mistakes would
make every entry in it mean less.

**Why 3.5 rather than renumbering.** "Sprint 5" means the Money Plan Generator
in `SPEC_ERRATA.md` E-24, in `COPILOT.md`, and in the deferral notes on
FR-COP-009 and FR-COP-020. Shifting every number by one would silently
invalidate those cross-references, including several in the errata, to save a
decimal point.

---

## The one change I'd make to the SRS plan

**Build a seed-data generator in Sprint 1, not later.**

The Money Plan Generator (Sprint 5) analyses *24 months of transaction history*
— the SRS assumed six, but seasonal detection over six points is noise, so E-07
raised the floor.
If you have not planned for that, you arrive at Sprint 5 with a working app
containing eleven test expenses and no way to exercise the algorithm — and you
end up hand-entering hundreds of rows, or worse, shipping an untested engine.

So in Sprint 1, alongside the schema, write:

`lib/core/database/seed/dev_seed.dart` — generates **over 500** synthetic
transactions across 24 months with *deliberately shaped* patterns:

- a **fixed** category (Bills: same amount, monthly, CV < 0.15)
- a **variable** category (Food: noisy daily spend)
- a **seasonal** category (Gifts: spikes each April and December)
- a **trending** category (Car: rising ~8%/month)
- a **sparse** category (Pets: 3 transactions total -> must score LOW confidence)

That fixture set is simultaneously your dev data, your algorithm test oracle,
and your demo dataset. Gate it behind `kDebugMode` so it never ships.

**Built in Sprint 1, and it is seeded and deterministic** — a fixture whose
output moves between runs cannot be an oracle. The 24-month span lets you test
both halves of the E-07 rule: run the engine over a 6-month window and Gifts
must come back Variable; run it over 24 and the same data must come back
Seasonal.

---

## Sprint 1 — Foundation (Weeks 1–2) — done

Schema, theme, router stubs, error hierarchy, DI, CI. PRs #6–#15. Current
test/coverage figures live in [`HANDOFF.md`](HANDOFF.md), not here.

## Sprint 2 — Transactions (Weeks 3–4) — done

Full vertical slice: entity, repository, five use cases, keypad entry
(FR-EXP-002), date-grouped list, E-22's empty states, E-23's undo. PRs #16,
#20, #22–#26.

Deferred out of this sprint on purpose: the account selector, to Sprint 3
(there was only one account to choose between); E-13's inline category `+`,
to Sprint 3.5, alongside FR-EXP-004 which it depends on.

## Sprint 3 — Accounts & transfers (Week 5) — done

Account CRUD, archiving, the balance side panel, atomic transfers
(FR-TRF-002 — debit and credit in one sqflite transaction). PRs #28, #33–#38,
#42. FR-ACC-007 (`DeleteAccount`'s missing requirement) and the accounts
slice's citation fixes are [E-25](SPEC_ERRATA.md).

**FR-ACC-005 (multi-currency conversion) is deferred to Sprint 7**, below.
Sprint 3 ships per-account currency *display* only; the three interim rules
this leaves in place (base currency, cross-currency transfer refusal, what
the Total Balance excludes) are recorded in [E-25](SPEC_ERRATA.md), not
repeated here.

## Sprint 3.5 — Categories (Week 6) — **new, and next after Sprint 3**

Added 2026-09-10. FR-EXP-004 and FR-EXP-005 were in no sprint in this file,
while three later features — analytics, the Money Plan and the receipt scanner
— all depend on categories being a first-class thing the user controls.

FR-EXP-003's fifteen expense and three income defaults are **already satisfied**
by `default_seed.dart`. What is missing is everything a user does to them.

Full vertical slice, domain first, in the usual order:

- **FR-EXP-004 — custom categories.** Create, rename, recolour, re-icon,
  delete. No limit is enforced: per [E-10](SPEC_ERRATA.md), §5.6's "50" is a
  performance-tested ceiling, not a cap.
- **FR-EXP-005 — the two-level hierarchy.** Parent and child only. The schema
  already carries `categories.parent_id`; nothing reads it yet.
- **E-13's inline `+`** on the entry screen, deferred out of Sprint 2 with this
  sprint named as its home. It needs a write path through the categories
  repository, which is the reason it could not land earlier.
- **FR-EXP-011 — the category-grouped list view**
  ([E-11](SPEC_ERRATA.md)). Scheduled here rather than in Sprint 4 because it
  groups the transaction list by category identity, which is this slice's
  subject, not the chart's. **Done late**, after Sprint 8
  ([PR #123](https://github.com/SanduniLiyanage/Moneyora/pull/123)): a
  toggle on the Transactions app bar, and `CategoryGroup.group` as a pure
  regrouping of the rows the date list already shows.
- **Delete `core/database/entry_catalog.dart`** and move its two reads behind
  this slice's repository. This is [E-27](SPEC_ERRATA.md)'s resolution and a
  deliverable of this sprint, not an aspiration attached to it. A read that
  bypasses the slice its writes go through is two sources of truth.

Deleting a category that transactions reference is the trap here, and it is
`DeleteAccount`'s problem again: refuse, or reassign, but never orphan. Follow
[FR-ACC-007](SPEC_ERRATA.md)'s precedent — the use case decides and returns its
own refusal, and the screen shows that sentence rather than inventing one.

**Done when:** a category can be created mid-entry from the keypad screen, a
child category rolls up to its parent in the list, `entry_catalog.dart` is
gone, and the whole slice's use cases have passing tests.

## Sprint 4 — Analytics (Week 7)

Donut chart, period filters, income-vs-expense bars, trend lines, heatmap.

### First, before any chart: NFR-PER-001's cold start — done, see the errata

This was believed to be a main-thread block — the database opening during the
first frame — and was scheduled here ahead of the charts on that basis.
Re-measured at the start of this sprint, with `adb logcat` bracketing a
release-build launch: the database opens **after** the first frame, not
during it, in the code as it now stands ([E-28](SPEC_ERRATA.md)'s 2026-09-12
addendum has the trace). `sqflite_sqlcipher` already runs the open on its own
background thread, and `injection.dart`'s `databaseProvider` is watched
through an `AsyncValue` that renders a spinner while it resolves — there was
no block left to move off the main thread.

What the addendum leaves as real: cold start is still slow
(7–10s, emulator, comparative) because of generic Flutter-engine and
native-plugin start-up cost, not application code, and the native launch
background was being dropped at the first frame regardless — leaving a bare
`AppBar` over blank space for the rest of the wait. **Done:** a splash screen
(`flutter_native_splash`, held via `FlutterNativeSplash.preserve`/`.remove` in
`main.dart` until `databaseProvider` resolves) so that wait reads as branded
rather than broken. **Not done, because it was never true:** moving the
database off the main thread. Only the *confirmed sub-2-second figure* still
waits for the device session ([E-28](SPEC_ERRATA.md)).

### Then the query benchmark — done on the VM, comparative, not conformant

NFR-PER-006 says under 100 ms per query at 10,000 transactions. Seed 10,000
rows and measure **query time, not frame time**. Fixing indexes here is cheap;
in Sprint 9 it is not.

Label every number *"emulator, comparative"* — or, as built,
*"host machine VM, comparative"*: `test/perf/analytics_query_benchmark_test.dart`
runs the benchmark on the `flutter test` VM rather than an emulator, which
still establishes that an index is present and being used and that a change
made a query faster or slower — a missing index is a multiple, not a margin —
but **no VM, emulator or CI figure may be cited as satisfying NFR-PER-006.**
Absolute confirmation is in the device session checklist in
[`HANDOFF.md`](HANDOFF.md). **Sprint 4 does not block on the device.**

### The queries

**The category-total use case is already built** — `GetSpendingByCategory`,
its datasource, its repository and its DI wiring, tested against the seed for
the E-02 (transfers) and E-04 (splits) traps. It is what the donut chart
renders *and* what the Copilot's spending tool reads, through
`core/ports/spending_by_category_reader.dart`: written once, consumed twice.

**The two remaining aggregates are also built**, as of the same session that
closed the query benchmark out:

- **`GetIncomeForPeriod`** (FR-COP-008, and FR-RPT-002's income-vs-expense
  bars — the same aggregate serves both). One new method on
  `AnalyticsRepository`/`AnalyticsLocalDataSourceImpl`: a plain `SUM` over
  income rows, since income is never split.
- **`ComparePeriods`** (FR-COP-021). No new query at all — it calls
  `spendingByCategory` for each period and diffs the results in the domain
  layer, since a delta is arithmetic on totals that already exist. This
  paragraph used to add "and the trend lines"; they did not end up using it
  (see FR-RPT-005 below — a delta is the wrong shape for a line), so it is
  the Copilot tool's use case and nothing else's.

[E-24](SPEC_ERRATA.md) required both to land as **analytics use cases first
and Copilot tools second**, so the tool is a genuine wrapper and no aggregate
query is written twice; that is what was built, in
`lib/features/analytics/domain/usecases/`. The tool wrappers themselves are
not — they are Copilot-workstream items, not Sprint 4 ones, and are tracked in
the Copilot table below.

Then the charts themselves.

### The donut chart — done ([PR #55](https://github.com/SanduniLiyanage/Moneyora/pull/55), merged as `05c5e9d`)

First of the five, per the order at the top of this section, and the one
SDD SCR-001 draws on the home screen itself rather than a separate report
screen. `SpendingDonutChart` (`lib/features/analytics/presentation/`) is the
first caller of `GetSpendingByCategory`, unchanged from how PR #52–54 left
it. Icons come from `CategoryReader` — the same port
`entryCategoriesProvider` already reads — rather than adding a column to a
query two features share; past six categories the tail folds into "Other",
which is both a legibility limit and the presentation-side answer to
[E-10](SPEC_ERRATA.md)/NFR-PER-005's "tested to 50, never refuses the
51st". Empty state follows [E-22](SPEC_ERRATA.md)'s two sentences,
disambiguated off the existing `databaseSummaryProvider` count rather than
a second query. Composed into `HomePage` from `app_router.dart`, the same
way `AccountDrawer` is.

It shipped with no period picker — its only period was the current calendar
month — which is what the item below replaced.

### Period filters (FR-RPT-002) — done ([PR #56](https://github.com/SanduniLiyanage/Moneyora/pull/56), merged as `cdc1ae3`)

Day, Week, Month, Year, All, Custom Interval and Choose Date, all seven,
replacing `currentMonthRangeProvider`'s hard-coded month with
`analyticsPeriodProvider` — the `StateProvider` that provider's own doc
comment said the filter work would swap it for.

The seven filters are not seven modes. Six choose a *shape* of period and
"Choose Date" chooses which date that shape wraps around, so the state is one
`AnalyticsPeriod` plus one anchor (`PeriodSelection`, in `domain/entities/`),
and the `DateRange` is a pure function of the pair. `DateRange` gained `day`,
`week`, `year` and `allTime` beside the `month` factory it already had; no
query, repository method or use case changed, because a filter is a different
argument to the same question. `DateRange.week` takes a `firstWeekday` that
defaults to Monday — FR-SET-004 makes that user-configurable in Sprint 7, and
the parameter is where that setting will land.

An inverted custom interval is passed through rather than silently swapped:
`GetSpendingByCategory.validate` already refuses one, in the words its doc
comment says are there for "a screen's period picker", and the chart shows
that refusal instead of an empty donut that reads as "you spent nothing".

The picker is a chip row inside the donut's own card (the pattern
`transaction_list_page.dart`'s type filter already uses) rather than a screen
of its own — SDD SCR-001 puts the chart on the home screen, and a filter one
scroll away from what it filters is a filter nobody touches.

### The account filter (FR-RPT-003) — done ([PR #58](https://github.com/SanduniLiyanage/Moneyora/pull/58), merged as `40c61cd`)

"All Accounts, or any specific single account", which is an `int?` and not a
sentinel id or an `allAccounts` flag beside one — a flag would allow a fourth
state, all accounts *and* an id, that means nothing.

A wider change than FR-RPT-002 was. The period was the only filter, so
`DateRange` could be the use case's whole parameter; two filters that travel
together are one question, so `GetSpendingByCategory` now takes a
`SpendingQuery` — and unlike the dates, the account has to reach the SQL.
`_spendingByCategory` keeps one body with an `{account}` hole in it rather
than growing a second whole statement: the E-02 and E-04 invariants are the
hard part of that query, and a second copy of them is a second place for them
to drift apart. The substituted text is a constant and the id stays a bound
parameter.

Two traps, both tested against real in-memory SQLite. A **split's parts carry
no account of their own**, so the filter follows the parent row, which is what
says where the money left from. **Transfers stay excluded either way** —
`account_id` is the column both halves carry, so that is the one place this
filter could plausibly have resurrected them.

`SpendingByCategoryReader` (the Copilot's port) and `ComparePeriods` both ask
for every account: the port answers questions about spending, not about where
money sat, and narrowing one side of a two-period delta would answer a
question nobody asked.

`AccountFilter` is a dropdown under the period chips — a closed set of six
chips is read at a glance, while accounts are user data of unknown length, and
`transfer_page.dart` already renders them this way. Accounts come from the
existing `AccountReader` port, so `features/analytics/` still does not import
`features/accounts/`. It opens on All accounts, because the chart is a
home-screen summary and one that silently omits an account is a wrong total
that looks right.

### Income-vs-expense bars (FR-RPT-004) — done ([PR #60](https://github.com/SanduniLiyanage/Moneyora/pull/60), merged as `0d2277a`)

Two bars over the same period and account the donut uses, with net savings
highlighted. `GetIncomeForPeriod`, built and wired in PR #54, finally has a
caller.

**This is the chart that forced FR-RPT-003's open question.** A chart whose
expense bar is narrowed to one account and whose income bar is not subtracts
one account's spending from every account's income and calls the difference
savings, so `incomeForPeriod` takes the account filter too — through the same
`{account}` substitution `_spendingByCategory` already uses. `SpendingQuery`
became `AnalyticsQuery` in the same change, because it is no longer only
spending's question.

**No third aggregate.** The expense side is the spending rows added up;
`spendingByCategoryTotalsProvider` is keyed on the identical `AnalyticsQuery`,
so the bars read the answer the donut already asked for. The filters render
once, on the donut's card, and both charts watch the same providers.

Net savings is stated as a labelled figure rather than left as the gap between
two bars, and a deficit says "Overspent" with a positive amount.

**[SPEC_ERRATA.md](SPEC_ERRATA.md)'s colour-collision check is resolved** in
that entry, against the chart set as built rather than as guessed at: the bars
draw two totals and no category colour renders on them, the donut draws expense
categories only, so Bills/Deposits, Entertainment/Salary and Gifts/Savings
cannot appear together on either. The entry names what would reopen it —
trend lines, if a line per category ever plots both kinds at once.

### Trend lines (FR-RPT-005) — done ([PR #62](https://github.com/SanduniLiyanage/Moneyora/pull/62), merged as `c72abc5`)

Per-category spending over time, one line per category, over the same period
and account as the two charts above.

**Not over `ComparePeriods`, which this file had pencilled in.** A delta is
the wrong shape for a line — a line plots levels — and calling it once per
point costs two `spendingByCategory` queries per point. The cheaper-looking
middle option, `spendingByCategory` once per bucket, was measured rather than
assumed: on the 10,000-row benchmark fixture it is within a few milliseconds
of one bucketed statement on the host VM, which pays no platform-channel
round trip per call. On a device the loop pays one per point (24 for a
two-year monthly line, up to 92 for a daily one) and the statement pays one,
so the statement is the option whose cost does not grow with the number of
points. That is `AnalyticsLocalDataSource.spendingTrend`, **assembled from
the same expense fragment as `spendingByCategory`** so the E-02/E-04
invariants still live in one place, and `GetSpendingTrend` above it. The
benchmark now times both paths on every CI run.

**The account filter reaches it**, for the same reason it reached the bars:
a chart under the filter row that quietly ignored the account would look
filtered and not be. `GetSpendingTrend` takes `AnalyticsQuery`; `ComparePeriods`
is untouched and still called by nothing.

Granularity is the use case's decision, from the span: day up to about a
quarter, month beyond it. No week bucket, on purpose — FR-SET-004 makes the
first weekday configurable in Sprint 7 and a week cut in SQL would ignore it.
A single Day period is refused as a trend in a sentence rather than drawn as
one dot. Past five categories the tail folds into "Other", as the donut does
past six.

**[SPEC_ERRATA.md](SPEC_ERRATA.md)'s colour-collision check was redone for
this surface and stays closed**: the chart draws expense categories only, the
same rows the donut draws, so an income colour never renders on it.

### The calendar heatmap (FR-RPT-009) — done ([PR #64](https://github.com/SanduniLiyanage/Moneyora/pull/64), merged as `d7a3416`)

"A calendar heatmap view highlighting daily spending intensity" — the last of
the five. **Sprint 4 is closed.**

**Always a calendar month.** The donut, the bars and the lines take the
selected period as their window; a heatmap is a grid of days, and a Year or
All under it is a different picture, not a longer one. So this card draws
the month the picker's *anchor* falls in, whatever shape is selected — the
chips change nothing on it, "Choose Date" does — and its subtitle says so.
`GetSpendingCalendar` takes a month, not an `AnalyticsQuery`, so the decision
is in the type. The account filter reaches it, as it reached the bars and
the lines.

**Its own daily statement, measured.** `dailySpendingTotals` is a fourth
statement over the same `_spendingParts` fragment — one row per day, no
`categories` join — chosen over `spendingTrend(day)` folded per day in Dart
on the benchmark fixture: 1.6ms against 6.8ms on the host VM, comparative.
`analytics_query_benchmark_test.dart` times both on every run.

**Intensity relative to the displayed month.** Five buckets on
`AppColors.expense` at rising opacity, the busiest day in view always the
darkest. No category colour renders, so
**[SPEC_ERRATA.md](SPEC_ERRATA.md)'s colour-collision check is closed with
the chart set complete.**

**Left open, on purpose:** FR-RPT-006's summary figures (never scheduled as
a chart; built in Sprint 8's
[PR #122](https://github.com/SanduniLiyanage/Moneyora/pull/122)) and a user-configurable first weekday (FR-SET-004, Sprint 7 — the
heatmap's `_firstWeekday` and `DateRange.week`'s default are where it lands).

## Sprint 5 — Money Plan Generator (Weeks 8–9) — the headline feature

Order: statistics -> classification -> allocation -> confidence -> wizard UI ->
live tracking. Test each stage against the seed fixtures before moving on.
Budget an extra 2–3 days for the seasonal detection; it is the fiddliest
part of the spec and the easiest to get subtly wrong — and per
[E-07](SPEC_ERRATA.md) it is a month-of-year index, not the FFT the SDD names.

### Statistics (FR-PLN-005) — done ([PR #66](https://github.com/SanduniLiyanage/Moneyora/pull/66), merged as `76ebe8c`)

`ComputeCategoryStatistics` over a 1–24 month `LookbackWindow`: mean,
median, sample standard deviation, min, max, transaction count and a
least-squares trend per category, all over monthly totals and all in Dart
(E-05). It reads the trend lines' month query through a
`MonthlySpendingReader` port in `core/` — no second statement, no
cross-feature import. Proven against `dev_seed` end to end; the two
findings the classifier inherits (Food's CV is 0.157 at month granularity;
Pets trends on three rows) are in [`HANDOFF.md`](HANDOFF.md).

### Classification (FR-PLN-004) — done ([PR #68](https://github.com/SanduniLiyanage/Moneyora/pull/68), merged as `afe2f3b`)

`ClassifyCategories` over `CategoryStatistics`: Fixed at the SDD's CV < 0.15
(kept unchanged — Food's 0.157 reads Variable, reasoning in
[`HANDOFF.md`](HANDOFF.md)), Seasonal by E-07's month-of-year index read
strictly and gated on the full 24 months, Variable otherwise. Proven on
`dev_seed` at 24 and 6 months. No confidence check — that is FR-PLN-010's.
One finding for the allocator: over six months Car reads Fixed *and*
rising, so the trend buffer goes by trend, not class.

### Allocation (FR-PLN-007, FR-PLN-008, FR-PLN-009) — done ([PR #70](https://github.com/SanduniLiyanage/Moneyora/pull/70), merged as `893e673`)

`AllocateBudget` over `CategoryClassification`: Fixed at the mean of the
last three months, Variable and Seasonal at the 60/40 weighted moving
average, a seasonal month at what it historically costs (the overall mean
× E-07's index — not the weighted base × index, which under-budgeted the
seed's December by half before it was caught), the trend buffer by trend
and never by class, a period as the months it touches weighted by share.
Three modes: unconstrained, the user's total (summing exactly), the
suggested total (income − savings − fixed). Daily allowance floored.
Reasoning in [`HANDOFF.md`](HANDOFF.md).

### Confidence (FR-PLN-010) — done ([PR #72](https://github.com/SanduniLiyanage/Moneyora/pull/72), merged as `4bbae30`)

`ScoreConfidence` over `CategoryAllocation.statistics`: the SDD's bands
with E-07's cap at Medium below 24 months. **"Data points" are active
months, not rows** — an allocation is a monthly figure, its support is
monthly observations — and that is settled; the reasoning is in
[`HANDOFF.md`](HANDOFF.md). On the seed: Bills and Food High at 24 months,
Pets Low, nothing High at six. Recorded, not changed: Car reads Low
because the CV includes its climb, and every Seasonal category reads Low
because its spikes are its variance.

### The saved plan (FR-PLN-001, 011, 013, 015) — done ([PR #74](https://github.com/SanduniLiyanage/Moneyora/pull/74), merged as `507229b`)

The feature's first writes: `SavePlan`, `WatchActivePlan`, `ActivatePlan`,
`UpdateAllocation` over a repository, a datasource on the shared change
bus, and models that map the stored strings to the schema as built. One
active plan at a time, held in the datasource's transactions; every
multi-row write atomic and proven on real SQLite. Reasoning in
[`HANDOFF.md`](HANDOFF.md).

### The wizard's first screens (FR-PLN-001, 002, 008) — done ([PR #77](https://github.com/SanduniLiyanage/Moneyora/pull/77), merged as `b84b01c`)

"Create Money Plan" from the home screen, the period picker with the
budget-mode choice, and the review of the generated draft with every
factor and reason on each card — E-07's cap stated where it applies. The
lookback is the six-month default until Sprint 7. Decided here:
FR-PLN-011 adjusts the *saved* plan, so Save comes before adjustment
(reasoning in [`HANDOFF.md`](HANDOFF.md)).

### Save, the saved plan, adjustment and what-if (FR-PLN-011, 012) — done ([PR #79](https://github.com/SanduniLiyanage/Moneyora/pull/79), merged as `a47b977`)

Save names and activates the plan and lands on the saved-plan screen,
where FR-PLN-011 adjusts the saved rows through the live stream and
FR-PLN-012 answers "reduce A by X%, how much more for B" as a preview —
the same `rebalance` arithmetic, nothing written (reasoning in
[`HANDOFF.md`](HANDOFF.md)).

### Live tracking's write path (FR-PLN-013, slice 1) — done ([PR #81](https://github.com/SanduniLiyanage/Moneyora/pull/81), merged as `32119e3`)

The transactions datasource moves `plan_allocations.spent_amount_cents`
inside the same transaction as the expense row, the way it moves account
balances (E-18): add, edit and delete, the active plan whose period
holds the date, matched by category, a split by its parts (E-04). Income
and transfers never touch it; no active plan, an out-of-period date or an
unallocated category is a no-op. The recount (`RecomputePlanSpending`)
is built, tested against the cache both ways, and called by nothing.
Reasoning in [`HANDOFF.md`](HANDOFF.md).

### The tracking screen (FR-PLN-013, slice 2) — done ([PR #83](https://github.com/SanduniLiyanage/Moneyora/pull/83), merged as `8917bf0`)

First the recount wired into activation, so a plan saved mid-period
counts what is already in it; then `AllocationProgress` — the percentage
floored, green below 80%, yellow to just under 100%, red at 100% and
above, the projection by elapsed days — drawn on `ActivePlanPage` over
the live stream. Reasoning in [`HANDOFF.md`](HANDOFF.md).

### The three overspend responses (FR-PLN-014) — done ([PR #84](https://github.com/SanduniLiyanage/Moneyora/pull/84), merged as `00702c8`)

`RespondToOverspend`: Auto-Redistribute by what the other categories have
*left*, Manual Adjust from the one the user picks, Carry Over recorded on
the row and deducted by the generator from the plan that follows. Schema
v2 adds the column the DBD lacked ([E-33](SPEC_ERRATA.md)). Reasoning in
[`HANDOFF.md`](HANDOFF.md).

### The plan list and comparison (FR-PLN-015) — done ([PR #85](https://github.com/SanduniLiyanage/Moneyora/pull/85), merged as `a2104fe`)

Every saved plan, the active one switched by tap, a recount action, and
any two compared side by side without scaling to a common period. The
first screen callers of `ActivatePlan` and `RecomputePlanSpending`.
"Track it now" on save keeps a plan for later. Reasoning in
[`HANDOFF.md`](HANDOFF.md).

**Sprint 5 is complete.** FR-PLN-003's Settings control is Sprint 7's;
FR-PLN-006's behavioural patterns were never scheduled; they landed after
Sprint 8 ([PR #126](https://github.com/SanduniLiyanage/Moneyora/pull/126)).

## Sprint 6 — Receipt Scanner (Weeks 10–11)

Camera -> preprocess -> ML Kit -> parse -> categorise -> review -> save -> learn.
**Collect 20–30 real receipt photos in week 1 of the sprint** (varied lighting,
crumpled, faded, handwritten) and build a fixture suite from them. Target is
>70% categorisation accuracy (M5); you cannot claim a number without a test set.

## Sprint 7 — Settings, auth, notifications (Week 12) — done

PIN + biometrics + lockout backoff, dark theme toggle, recurring reminders,
budget alerts at 80% / 100%.

**Plus FR-ACC-005, deferred here from Sprint 3.** Multi-currency accounts with
user-configurable exchange rates: a `exchange_rates` table behind a **v4
migration** (this said v2 until Sprint 6 closed; v2 and v3 were spent on E-33
and E-31 in the meantime, and v4 follows the same additive pattern with the
same upgrade-with-rows-intact test), a base-currency setting, and conversion
applied wherever balances are summed. The settings themselves need no new
table: the DBD's single-row `users` table has carried the theme, currency,
first-weekday and lookback columns since v1. It lands here because the rate table is user-editable and its
screen is a settings screen, and because a migration is safer in a sprint that
is not also shipping five new pages.

Landing it removes three interim rules from Sprint 3, all named in
[E-25](SPEC_ERRATA.md): the LKR base-currency constant, the same-currency guard
in `MakeTransfer.validate`, and the Total Balance's exclusion of
foreign-currency accounts. Delete all three in the same commit that adds
conversion, or the app will refuse transfers it is now capable of making.

### The settings shell and E-18's Settings action — done ([PR #104](https://github.com/SanduniLiyanage/Moneyora/pull/104))

E-18's reconciliation is reachable: Settings › Data › "Recalculate account
balances" asks first, then runs `RecomputeAllAccountBalances`, the sweep
that re-derives every account in one transaction. For most of Sprints 3–6
`RecomputeAccountBalance` was built, tested, wired into `injection.dart` and
called by **nothing** — not on app start, not from any screen — and this
file once said it "had no caller outside app start", which described a
narrower gap than the real one.

It stays manual-only on purpose. Reconciliation is `O(all transactions)` per
account, and putting a full-history scan on the launch path is the opposite of
what Sprint 4 does to NFR-PER-001. The restore path is its other caller,
and that arrives with the restore in Sprint 8 — see the
[E-18 addendum](SPEC_ERRATA.md). The `settings` route was the last
placeholder in the router; the settings screen is a shell whose sections
arrive with the requirements that fill them.

### The theme toggle (FR-SET-001) — done ([PR #105](https://github.com/SanduniLiyanage/Moneyora/pull/105))

The first preference, and the pattern every later one reuses. The settings
feature now has its full vertical slice: `UserSettings` is the `users` row as
a value (every preference column; the two lock-screen columns are excluded on
purpose — see the entity), `SettingsRepository` is three methods (`get`,
`save`, `watch`) however many preferences arrive, and a setting is one use
case that reads the row, changes one field and saves it back. `SetTheme` is
the first; FR-SET-003's currency, FR-SET-004's first weekday, FR-SET-008's
savings target and FR-SET-012's lookback each add a use case and a row on
the screen, not a repository method or a column.

The app root reads `themeModeProvider` and nothing else changed above the
providers: the settings screen writes, the `MaterialApp` above it follows,
and the widget test asserts on the brightness actually drawn. The
datasource shares the `DatabaseChangeBus` for a reason that is one slice
ahead — FR-ACC-005's base currency lives in the same row, and every summed
balance on screen has to follow a change to it.

### Exchange rates and the base currency (FR-SET-003, E-34) — done ([PR #106](https://github.com/SanduniLiyanage/Moneyora/pull/106))

The plumbing half of FR-ACC-005, landed first because it changes no
behaviour anywhere: schema v4 (`exchange_rates`, and
`transfers.credited_amount_cents` backfilled from `amount_cents`), the
`ExchangeRate` value in `core/ports/` with the conversion arithmetic on it —
nearest cent, halves away from zero, over `BigInt` — the rate use cases,
`SetBaseCurrency`, and two settings rows: *Base currency* and *Exchange
rates*, the latter its own screen. [E-34](SPEC_ERRATA.md) records why the
DBD had none of this and how the rate is stored.

### Conversion, and the three E-25 deletions (FR-ACC-005) — done ([PR #107](https://github.com/SanduniLiyanage/Moneyora/pull/107))

The other half. `ConversionReader` in `core/ports/` is the seam — the
`AccountReader` shape from E-27 — through which the accounts feature reads
the base currency and rates without importing settings; the settings
feature fulfils it by joining its two repositories' streams.
`AccountTotals.from` converts at the user's rate to the base and counts
what has no such rate; the panel's note is now that fallback, and says what
would include the account. A transfer between two currencies carries the
credited figure through `TransferParams`, the header column and the credit
half, entered on the transfer screen beside the debit and pre-filled from
the stored rate when there is one — the rate suggests, the statement
decides.

**All three E-25 interim rules were deleted in a single commit**, with the
conversion that replaces them, as that entry required; its closing
addendum lists them. Editing a transfer stays out of scope: there is no
transfer-edit path today (`UpdateTransaction` refuses one half), and delete
already removes both halves by their own amounts.

FR-ACC-005 and FR-SET-003 are complete.

### The calendar: first weekday, first day of month, lookback (FR-SET-004, FR-SET-012) — done ([PR #108](https://github.com/SanduniLiyanage/Moneyora/pull/108))

Three rows under Settings › Calendar, on the #105 pattern, and the
consumers HANDOFF named: `DateRange.week` and `PlanPeriod.week` take the
first weekday, the heatmap's first column follows it, and `DateRange.monthOf`
/ `PlanPeriod.monthOf` cut a "month" from the chosen day to the day before
it next month — the 25th to the 24th, for someone paid on the 25th. A month
that does not start on day 1 is labelled as a span, not named as a month.
The Money Plan wizard reads the lookback from the stored row and says where
to change it; it does not offer to. `CalendarSettings` in `core/ports/` is
the seam, as `ConversionTable` was.

**Two behaviours changed for existing installs, on purpose.** The stored
default for the first weekday is Sunday (`first_day_week DEFAULT 0`, DBD
§3.1), while the code had hard-coded Monday "until FR-SET-004"; honouring
the row means a Sunday-first week until the user picks Monday. And the
entity's `firstDayOfWeek` now speaks Dart's weekday constants, with the
column's Sunday-at-zero mapped in the model.

### The passcode and its lockout (FR-SET-005, NFR-SEC-003) — done ([PR #109](https://github.com/SanduniLiyanage/Moneyora/pull/109))

The PIN half of FR-SET-005; biometrics (NFR-SEC-004) are the next slice, on
the `BiometricGateway` seam this one leaves for them. Three decisions worth
knowing, all recorded in the code they affect:

- **The passcode lives in the platform keychain, not the `users` row.**
  `AuthLocalDataSource` keeps a PHC-format record —
  `$pbkdf2-sha256$i=100000$<salt>$<hash>` — under `auth.passcode`, and the
  lockout state as one JSON value under `auth.lockout`, beside the database
  key `SecureStorageKeyStore` already holds there. The DBD's `passcode_hash`
  and `biometric_enabled` columns stay in the schema, unused: E-31 §1 records
  why the bare SHA-256 the DBD specified would secure nothing, and the
  keychain is readable before the database is open, which the lock screen
  — drawn during the launch — needs. No v5 migration.
- **PBKDF2-HMAC-SHA256 from `cryptography`, on a separate isolate.** The
  package was already a dependency (the receipt vault's HKDF) and ships
  Argon2id too; PBKDF2 was chosen because a pure-Dart Argon2 at a memory
  cost that means anything is seconds on an Android 8 phone, for a search
  space of at most a million values that the lockout already defends. The
  iteration count is stored in the record, so raising it later invalidates
  nothing. `Pbkdf2PinHasher` says all of this.
- **The lock screen is an app-root gate, not a route.** `AuthGate` wraps the
  Navigator through `MaterialApp.router`'s `builder`, so a deep link or a
  restored route lands behind it and the router knows nothing about auth.
  The Navigator stays in the tree offstage while locked, so every screen's
  state survives a lock; the device back button is swallowed. The app locks
  the moment it is paused and unlocks itself on return within a thirty-second
  grace — the grace is there because the receipt camera pauses the app the
  same way switching away does.

`VerifyPasscode` is the one place the lockout policy is applied: the lock
screen, the change-PIN flow and the remove-PIN flow all go through it, so a
wrong PIN costs the same wherever it is typed and no screen is a second set
of five attempts. `LockoutPolicy` is the arithmetic — thirty seconds after
the fifth failure, doubling to an hour — and its test walks the whole ladder
without a clock. Every "now" comes from `clockProvider`, added in
`injection.dart` for this, so the widget tests serve a lockout by moving it.

The Security rows are the auth feature's (`SecuritySettingsSection`) and
reach the settings screen through a widget slot the router fills, the way the
accounts panel reaches the home screen — the settings feature may not import
auth (rule 4).

### Biometric unlock (NFR-SEC-004) — done ([PR #110](https://github.com/SanduniLiyanage/Moneyora/pull/110))

The other half of FR-SET-005, and never the only way in: `EnableBiometrics`
refuses until a PIN exists and needs one successful prompt at the moment it
is turned on. A biometric unlock bypasses the PIN lockout on purpose — the
OS rate-limits the sensor, and the lockout defends the PIN.
`BiometricGateway` is its own port; `MainActivity` became a
`FlutterFragmentActivity` because the prompt is a `DialogFragment`.

### Budget alerts at 80% and 100% (FR-SET-007) — done ([PR #111](https://github.com/SanduniLiyanage/Moneyora/pull/111))

Schema v5 stores the switch and, per plan row, the level last announced
([E-35](SPEC_ERRATA.md)), so an alert fires once per crossing and again
after spend drops back and rises. The bands are FR-PLN-013's own
(`AllocationProgress.statusOf`), so a notification can never say 80% over
a row still drawn green. The level is written compare-and-set before
anything is shown, which is what makes two racing expenses announce once.
Off until turned on in Settings, which is where the permission is asked.

### Recurring entries (FR-EXP-008, FR-INC-004) — done ([PR #112](https://github.com/SanduniLiyanage/Moneyora/pull/112), [PR #113](https://github.com/SanduniLiyanage/Moneyora/pull/113))

The engine, then the screens. A rule is created with its first entry
(the DBD's template design), and every missed entry is posted on launch
and on resume, uncapped, through the same insert a typed entry takes; the
due date moves compare-and-set in the same transaction. Deleting a
series' first entry hands the template to the latest remaining one, or
stops the rule ([E-36](SPEC_ERRATA.md)). E-13's toggle sits on the entry
screen for a new entry only; the rules list at `/recurring` — home, beside
Transactions — pauses, resumes (skipping the paused stretch) and deletes
(keeping the entries).

### Recurring reminders (FR-SET-006) — done ([PR #114](https://github.com/SanduniLiyanage/Moneyora/pull/114))

Schema v6 holds the switch, days before (0–7) and a time of day as
minutes after midnight ([E-37](SPEC_ERRATA.md)). The reminders are not
stored: `SyncRecurringReminders` re-derives them from the active rules
on every change and schedules by id. Inexact on purpose — an exact alarm
needs a permission Android 14 withholds — with a boot receiver and their
own channel.

### The emulator pass's fixes — done ([PR #115](https://github.com/SanduniLiyanage/Moneyora/pull/115))

Walking #113 and #114 on the 320×640 emulator found three older faults in
the entry flow: the transaction list never named a row by its category
(every row read "Uncategorised"); an edit wrote back only the fields the
form shows, so time, split parts, receipt links and the recurring link
came back empty; and the keypad left the details list a 40dp sliver.
All three are fixed, the keypad folding away when the details are
reached for.

**Sprint 7 is complete.** Of the FR-SET requirements, three are not built:
FR-SET-002 (display languages — English only; `UserSettings.language` is
stored and read by nothing), and FR-SET-009 and FR-SET-010, which are
Sprint 8's backup and sync. FR-SET-011 is withdrawn
([E-12](SPEC_ERRATA.md)).

### The savings target (FR-SET-008) — done ([PR #117](https://github.com/SanduniLiyanage/Moneyora/pull/117))

Settings › Calendar › *Savings target*, 0–100, on the #105 pattern
(`SetSavingsTarget`). The Money Plan wizard starts its savings field from
it through `CalendarSettings`, the port that already carried the lookback,
and a figure the user types there still wins. 0 is the column's default,
which nobody chose, so it leaves the wizard's 10% suggestion in place.

## Sprint 8 — Backup, export, sync (Week 13) — done

Encrypted `.mora` backups ([E-08](SPEC_ERRATA.md) — neither `.mb` nor
`.sb`), CSV/PDF export, optional Drive/Dropbox.
**Test restore on a second physical device**, not just re-import on the same one.
That test is still owed: it is step 7 of `HANDOFF.md`'s device checklist.

### Encrypted `.mora` backup and restore (FR-BAK-001, FR-BAK-005) — done ([PR #118](https://github.com/SanduniLiyanage/Moneyora/pull/118))

FR-BAK-001's "SQLite format" and FR-BAK-005's "any device" cannot both
hold: the database is sealed under a key that never leaves this phone.
[E-38](SPEC_ERRATA.md) records the answer. A `.mora` file carries the
rows — every table read from `sqlite_master`, so a later migration's table
is included — and every kept photo decrypted, gzip'd and sealed with
AES-256-GCM under a key PBKDF2 derives from a password the user chooses.
Restore replaces rather than merges, in one transaction with foreign keys
deferred to the commit (E-36's two tables name each other), reseals the
photos under the new phone's key, refuses a newer schema, and recomputes
every balance after — E-18's second caller. The PIN stays in the keychain
and is not carried. Where the file goes is the platform's own save and
open dialogs, which already reach Google Drive's document provider.
**No migration**: the schema is still v6.

### CSV export and Clear all data (FR-SET-009, FR-RPT-007) — done ([PR #119](https://github.com/SanduniLiyanage/Moneyora/pull/119))

One row per transaction, oldest first, amount signed so a spreadsheet's
`SUM` is the net; UTF-8 with a byte-order mark so Sinhala and Tamil
notes open as text; a note that starts like a formula is led with an
apostrophe. Clear deletes every row in one transaction, writes the
first-launch seed back and discards the kept photos; the PIN stays.

### The backup reminder (FR-BAK-006) — done ([PR #120](https://github.com/SanduniLiyanage/Moneyora/pull/120))

One notification stays scheduled for seven days after the last *saved*
backup (not one abandoned in the save dialog), then each morning at 9:00
while overdue; withdrawn when there are no transactions. The date lives
in the keychain, so a restore does not tell a new phone it was backed up.

### PDF export (FR-RPT-007) — done ([PR #121](https://github.com/SanduniLiyanage/Moneyora/pull/121))

The same rows as the CSV on A4, with a total per currency and never one
across currencies. The standard PDF fonts are Latin-1 only, so a
Sinhala or Tamil note prints with "?"; the chooser says the CSV keeps
every character.

### The summary card (FR-RPT-006) — done ([PR #122](https://github.com/SanduniLiyanage/Moneyora/pull/122))

Carried since Sprint 4: average daily spend (over the days elapsed, today
included), the largest category and the change against the period before,
read from the aggregates the charts use so the card cannot disagree with
them.

**Sprint 8 is complete.** Deferred, with reasons in
[E-38](SPEC_ERRATA.md): FR-BAK-002's scheduled automatic backups (an
unattended backup needs its password on the phone) and FR-BAK-003/004's
direct Drive and Dropbox sync (each needs an OAuth client registered
outside the code). FR-SET-010's sync row waits with them.

### After the sprint: two requirements scheduled nowhere — done

FR-EXP-011's grouped list ([PR #123](https://github.com/SanduniLiyanage/Moneyora/pull/123);
see Sprint 3.5) and FR-EXP-009's photo on any expense
([PR #124](https://github.com/SanduniLiyanage/Moneyora/pull/124)). The
photo goes through the scanner's picker and vault behind
`core/ports/expense_photos.dart`, into the row's existing
`receipt_image_path`, so the backup carries it with no change. A photo
attached by hand is discarded when replaced, removed, abandoned or deleted
with its row; a scan's photo is the scan's, and view-only on the expense.

## Sprint 9 — Hardening (Week 14) — done

Coverage to >=75% domain, integration tests, perf pass against every NFR-PER
target, accessibility (4.5:1 contrast, font scaling).

### Spending patterns (FR-PLN-006) — done ([PR #126](https://github.com/SanduniLiyanage/Moneyora/pull/126))

Not hardening, but the last FR-PLN requirement. A card at the end of the
plan review compares the average spent a day on weekdays against the
weekend, and in the first ten days of a month against the last ten, over
the plan's own lookback window. A side is named at 25% more a day; under
twenty spending days it says there is too little to go on. The day cut is
the trend lines' query at day granularity, through a `DailySpendingReader`
port. Seasonal cycles are FR-PLN-004's Seasonal class; event-based spikes
are not built.

A category spent on no more than two days in each month it appears in —
a rent, a subscription, a one-off — is left out, and the card names it:
on the sample history a rent on the 1st had made the first ten days look
587% dearer. FR-PLN-004's Fixed class is not the test, because it means a
steady monthly *amount*, and steady groceries are still a daily habit.

### Font scaling — done ([PR #127](https://github.com/SanduniLiyanage/Moneyora/pull/127))

At twice the text size on a 320x640dp phone — Android's largest font on
the smallest supported screen — the transaction list, home, the four
charts and both Money Plan screens overflowed or threw. Figures now go
through `core/widgets/scale_down_text.dart`, which shrinks a figure only
when it would not fit, and fourteen widget tests pump those screens at
that size (`test/widget/large_text.dart` holds the two helpers).
Contrast was already tested for the semantic colours
(`app_theme_test.dart`).

### The Sprint 8 emulator pass — done ([PR #128](https://github.com/SanduniLiyanage/Moneyora/pull/128), [PR #129](https://github.com/SanduniLiyanage/Moneyora/pull/129))

Every Sprint 8 flow walked on the 320x640 AVD: backup, clear, restore
(a wrong password refused; the photo resealed and opening), CSV and PDF,
the summary card, the grouped list, a photo on an expense and the
patterns card. It found four faults, all fixed: the password dialog
overflowing with the keyboard up (every dialog with a text field now
scrolls), #127 splitting rows evenly with their labels, the charts
telling an emptied phone it had had a quiet month (the database summary
was read once at launch), and the PDF's headings adrift of their columns.

### Backup, clear and restore, end to end — done ([PR #131](https://github.com/SanduniLiyanage/Moneyora/pull/131))

`test/integration/backup_round_trip_test.dart` runs the flow the emulator
pass walked by hand across two "phones" — two `ProviderContainer`s, each
with its own database file, key and photo vault, through the real
providers: an expense with a photo, backed up, cleared, a wrong password
refused on the second phone, then restored with its note, its recounted
balance and its photo opening under the second phone's key.

### Contrast across the scheme's own text pairs — done ([PR #132](https://github.com/SanduniLiyanage/Moneyora/pull/132))

Ten ColorScheme text pairs measured in both themes. Two were under 4.5:1
and are fixed: the dark theme's `onError` (3.49:1, now dark text on the
red) and the list's empty-state text at 0.6 alpha (4.45:1, now 0.7 like
the rest of the app). The category hues are non-text colours named in
every legend, and stay as they are.

### Sample data, loaded once and offered where it is needed — done ([PR #133](https://github.com/SanduniLiyanage/Moneyora/pull/133), [PR #134](https://github.com/SanduniLiyanage/Moneyora/pull/134))

The debug sample-data loader wrote its two years of rows on every tap,
doubling every total, and moved neither balances nor the active plan. It
now asks first, loads once, keeps both caches right and signals the change
bus. Verifying it found a second fault: after Clear all data or a restore
every row lost its category name until a restart, because the categories
datasource had a private change bus; it now shares the app's. #134 moved
the loader from the transaction list, which is for real money, to the
Money Plan's "Nothing to plan from yet".

**Sprint 9 is complete.** The NFR-PER figures that certify are the device
checklist's ([E-28](SPEC_ERRATA.md)); the emulator's comparative
benchmark runs in every `flutter test`.

## Sprint 10 — Release (Week 15)

Beta, bug fixes, store assets, user manual, final docs.

### A plan from the user's own history, or built by hand — done ([PR #137](https://github.com/SanduniLiyanage/Moneyora/pull/137))

The product owner's review: a plan generated from sample data is
meaningless, so the debug sample-data button is gone ([E-39](SPEC_ERRATA.md)).
The wizard suggests a plan only from at least one whole month with spending
and ten expenses; below that it says which case the user is in and offers
**Build it yourself**. The new plan editor serves both that and editing a
generated plan before it is saved (FR-PLN-011): the total follows what is
typed, against the suggested total. E-39 supersedes E-21's baseline ladder.

### Budget alerts offered on save, and worded to stand alone — done ([PR #138](https://github.com/SanduniLiyanage/Moneyora/pull/138))

Alerts are off by default (E-35), so the save dialog offers them while
they are off. The notifications say which budget, which plan and what the
next purchase means ("You've gone over your Bills budget"), and expand to
the whole sentence.

### The bug-fix pass — done ([PR #136](https://github.com/SanduniLiyanage/Moneyora/pull/136), [PR #138](https://github.com/SanduniLiyanage/Moneyora/pull/138), [PR #139](https://github.com/SanduniLiyanage/Moneyora/pull/139), [PR #140](https://github.com/SanduniLiyanage/Moneyora/pull/140))

- The spending patterns left out a rent on the 1st that read as a habit
  (#136): a category spent on two days a month or fewer is a bill.
- The list's Undo bar covered the entry screen's Save (#138).
- Home opened on charts and hid every feature under a "Coming next" list
  beside a developer's database card (#139): it now opens on shortcuts,
  with an Add button, and the database figures are in Settings › About.
  The analytics period chips wrap instead of hiding half their options.
- The transaction list is grouped by day, each day with its count and
  what it cost (#140, FR-EXP-006).

### The user manual and the privacy policy — done ([PR #141](https://github.com/SanduniLiyanage/Moneyora/pull/141))

[`USER_MANUAL.md`](USER_MANUAL.md) and [`PRIVACY.md`](PRIVACY.md), both
checked against the code. Writing the policy turned Android Auto Backup off
and declared INTERNET outright. The policy's contact address is for the
owner to fill in.

### The store listing — done ([PR #143](https://github.com/SanduniLiyanage/Moneyora/pull/143))

[`store/LISTING.md`](store/LISTING.md): the Play listing's text, the
screenshot list, and the data-safety answers, each checked against the
manifest and the privacy policy.

### A balance for the chosen period and account — done ([PR #144](https://github.com/SanduniLiyanage/Moneyora/pull/144))

Income less expenses for one period and one account, green above zero and
red otherwise, with what came in and went out beneath it. It sits under
the donut on home and at the top of the transaction list, and both share
one choice of period and account, so the list shows what the balance
counts. Transfers never count (E-02).

### Beta readiness — done ([PR #146](https://github.com/SanduniLiyanage/Moneyora/pull/146))

The app's name, the launcher icon, upload-key signing from an untracked
`android/key.properties`, and the 80 MB per-ABI release gate CI had been
printing but not enforcing ([E-09](SPEC_ERRATA.md)). The notifications now
carry a monochrome status-bar icon of their own: Android draws only a small
icon's alpha channel, so the launcher icon came out a filled square.

Measured: **32.1 / 39.8 / 42.3 MB** per ABI, the largest at half the budget.

### Two fixes the screenshots found — done ([PR #147](https://github.com/SanduniLiyanage/Moneyora/pull/147))

With a real month of hand-entered spending in the app, every donut wedge
drew its percentage and its category icon within a tenth of the radius of
each other. The wedge keeps the percentage; the icon moves to the legend,
where the colour already had to be looked up.

**Transfer joined the home shortcuts.** Moving money between accounts —
cash drawn from a card at an ATM — was two screens in, behind an app-bar
icon on the transaction list, though it is as ordinary as spending. The
grid also read one past the end of an odd-length list, which the ninth
entry would have hit.

### The release checklist — done ([PR #148](https://github.com/SanduniLiyanage/Moneyora/pull/148))

[`RELEASE.md`](RELEASE.md) is the order to do the unbuildable parts in: the
upload key, the bundle, and the two items that cost calendar time rather
than effort — Google's 12-testers-for-14-days rule for a personal account,
and the macOS an iOS upload needs, which the `macos-latest` runner that
already compiles the app on every push can supply. The feature graphic is
drawn from the launcher icon's own mark so the two cannot drift apart, and
the contact address both the privacy policy and the listing were holding a
placeholder for is filled in.

### Transfers that read the way money moves — done ([PR #150](https://github.com/SanduniLiyanage/Moneyora/pull/150), [PR #151](https://github.com/SanduniLiyanage/Moneyora/pull/151))

The owner drew Rs 200 of cash from a card and looked at both accounts.
A transfer's amount is now red on the account it left and green on the
one it reached (#150); the swap icon keeps the transfer colour, so it
still reads as moving money rather than spending it. And with one account
chosen, the Balance bar and the day totals count that account's transfers
(#151): the card's balance falls by 200, the cash balance rises by 200,
and across every account the two legs cancel. Spending, income, the
charts, the plan and the budgets still never see a transfer — an
[E-02](SPEC_ERRATA.md) addendum says why this is that entry's own
account-balance rule rather than an exception to it.

## After release — 1.0.0 and 1.0.1

**1.0.0** was published on GitHub Releases on 2026-10-05, signed with the
owner's upload key, after a walk of the release APK that fixed what only a
shrunk build could show: the receipt scanner reading nothing because R8
removed ML Kit's registrar constructors (#160, an
[E-09](SPEC_ERRATA.md) addendum), Undo staying offered after the delete
was written (#158), Ask Moneyora's key screen overclaiming (#161), and an
ended plan still forecasting (#162).

**1.0.1**, published 2026-10-06, is the first round of testers' feedback
from their own phones:

- **Back never leaves the app** (#165). Confirming a receipt went to the
  list and replaced the whole stack; every screen now sits above home.
- **Arrows follow the balance** (#164): an expense points down in red,
  income up in green — the owner's call.
- **A long note stops at two lines** (#166): a scanned bus ticket had put
  its whole text in one row.
- **Plans, one door** (#167, #168; [E-40](SPEC_ERRATA.md)): a single
  Budget plans tile, Rename and Delete, and a one-category plan whose
  budget can be changed.
- **How an installed copy updates**, in [`RELEASE.md`](RELEASE.md) (#169).

**1.0.2** makes Ask Moneyora answer again. Google shut down
`gemini-2.0-flash` on 2026-06-01, so every question to 1.0.0 and 1.0.1
failed. It now asks `gemini-3.5-flash` and falls back to the newest Flash
model when that one is busy or out of quota. It replays Gemini 3's thought
signatures and answers in the base currency (#172, #174). **Change API
key** replaces a key that Google turned down.

### The reference-app layout — done (#175 to #178)

At the owner's request, after testers' feedback, home and entry were
rebuilt so the things done most often take the fewest taps, over several
PRs:

1. **The panels** — done (#175). The filter button at the top left opens
   the account and period choices, which used to be on the chart's card.
   **⇄** at the top right starts a transfer. **⋮** opens a menu of every
   screen with Settings last. **Accounts** opens in place in that menu.
   The tiles on home are gone.
2. **Home** — done (#176). The ring with each category's icon and share
   around it and income and spending in its middle, **‹ ›** and a swipe
   for the period before or after, **Balance** opening the list, and big
   **−** and **+**. The other four charts and the amounts by category
   moved to **Reports** in the menu.
3. **The list and the interval** — done (#177). A swipe on the list steps
   the period, with ‹ › above its balance. Deleting moved from a swipe on
   the row to holding it, and to a bin on the edit screen, with the same
   Undo. Interval opens a calendar that swipes between months.
4. **Entry** — done (#178). New expense and New income are laid out as
   one question at a time: Cancel, the title and a switch at the top; the
   date; the amount in a bar the colour of what it will become, with the
   account at its left and ⌫ at its right; a note, with Repeat, a photo
   and the scanner as small icons beside it; the 1-to-9 keypad with =;
   and CHOOSE CATEGORY, which opens the grid of category icons and
   records the entry on a tap.

### Still open

- **The bus ticket.** It came back as one item named with the whole
  ticket's text. Fixing the parser needs that photo as a fixture.
- **On a phone, not the emulator:** a fresh first launch and a restore
  (both replace the emulator's hand-entered data), biometric unlock (the
  emulator has no fingerprint enrolled) and a budget-alert notification.
- **The Samsung Galaxy Store** submission ([`RELEASE.md`](RELEASE.md) §3):
  free, and it updates installed copies by itself.
- **A Play Console account**, its identity verification, and the closed
  test that has to run for fourteen days before production opens. This is
  the longest item left and nothing in the repository shortens it.
- **An Apple Developer Program membership**, if iOS is wanted.

---

## Non-goals

- **No in-app purchases, paid tier, or purchase-ID handling.** FR-SET-011 was
  withdrawn as copied from the reference app's paywall — see
  [E-12](SPEC_ERRATA.md). If monetisation is ever added, this is specified
  then, against whichever billing SDK is chosen.

This list is short because it reflects decisions actually made, not
everything the app doesn't currently do. Add to it when a feature is
deliberately ruled out, not merely unscheduled.

---

## The Copilot — a workstream, not a sprint

The AI Copilot (an on-device tool-using agent — see [`COPILOT.md`](COPILOT.md))
is built in the gaps between sprints, under one rule: **it never jumps the
queue.** Two of its five specified tools wrap the Money Plan Generator and a
savings-goal feature that Sprints 5 and 6 build, so the dependency runs one
way, and an unfinished app is never the price of a finished agent ([E-24](SPEC_ERRATA.md)).

| Stage | Depends on | Status |
|---|---|---|
| Domain: entities, contracts, agent loop, first tool | nothing | **Done** |
| The category-total analytics use case | Sprint 4 | **Done** — runs against the real database |
| Gemini datasource, egress guard | the above | **Done** |
| The ask screen, with key entry | the above | **Done** |
| One real question against the live API | a Gemini API key | **Next — emulator, not device** |
| The income/compare-periods analytics use cases | Sprint 4 | **Done** — `GetIncomeForPeriod` (called by FR-RPT-004's bars since PR #60), `ComparePeriods` (tested, wired into `injection.dart`, still called by nothing — its caller is the tool below) |
| `get_income_for_period`, `compare_periods` **tools** | the use cases above | Deferred — the use case is the Sprint 4 deliverable; the tool wrapper is Copilot-workstream work, not scheduled here |
| `get_budget_plan` | Sprint 5 — **done**, so nothing blocks it now | Deferred — `WatchActivePlan` and `PlanAllocation.spentCents` are what the tool would read; the wrapper is Copilot-workstream work, as above |
| `get_savings_goal_progress`, affordability query | **Sprint 5+** | Deferred |

Test counts for each stage are in [`HANDOFF.md`](HANDOFF.md), not restated
here — that table already went stale once (PR #31) from being kept in two
places.

**The live-API proof needs no hardware.** It had been carried as "on a device",
which put the last unproven part of the Copilot behind the borrowed phone for no
reason: an emulator has network access, and the key exists. It runs in the next
emulator session and comes off the standing list. The demo recording can follow
it there too — only a *walkthrough on real hardware* belongs on the device
checklist in [`HANDOFF.md`](HANDOFF.md).

---

## Risks worth watching (beyond SRS Appendix C)

| Risk | Why it bites | Mitigation |
|---|---|---|
| No test data until Sprint 5 | Cannot develop or validate the plan engine | Seed generator in Sprint 1 |
| Receipt corpus collected late | Cannot measure the >70% M5 target | Start photographing receipts **now**, every purchase |
| `double` money columns | Cent-level drift in totals; painful late migration | Integer minor units from day one |
| iOS untested until the end | No Mac in the loop; Xcode surprises land in week 13 | Add a macOS CI job early, even if it only builds |
| Perf measured on emulator | Absolute emulator timings are not evidence about a phone | Benchmark on the emulator in Sprint 4 and label it **comparative**; confirm on the borrowed device in one batched session ([E-28](SPEC_ERRATA.md)) |
| Device access is occasional, not on demand | A sprint that blocks on a borrowed phone blocks on someone else's calendar | No sprint blocks on it. Everything needing real hardware is batched into one ordered checklist in [`HANDOFF.md`](HANDOFF.md) |
| A "temporary" structure becomes permanent | `entry_catalog.dart` was an interim home with no end date | Interim decisions get a **named sprint** that retires them ([E-27](SPEC_ERRATA.md) — Sprint 3.5) |
| The same number restated in three documents | It goes stale three times, then disagrees with itself | Exact counts live **only** in [`HANDOFF.md`](HANDOFF.md); everything else links to it |
| CI green on an artefact nobody ships | The release build was broken for 38 PRs because CI only ever built debug, which skips R8 | CI builds a **release** artefact too ([E-09](SPEC_ERRATA.md)) |
| The Copilot grows past its scope | Five tools, a chat history, a proactive agent — each plausible, and together they displace two sprints | Three tools in v1, the rest gated behind the features they wrap ([E-24](SPEC_ERRATA.md)) |
