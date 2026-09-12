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
  subject, not the chart's.
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
- **`ComparePeriods`** (FR-COP-021, and the trend lines). No new query at
  all — it calls `spendingByCategory` for each period and diffs the results
  in the domain layer, since a delta is arithmetic on totals that already
  exist.

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

### Period filters (FR-RPT-002) — done

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

### Next — the account filter (FR-RPT-003)

Then income-vs-expense bars, trend lines and the heatmap, in that order.

## Sprint 5 — Money Plan Generator (Weeks 8–9) — the headline feature

Order: statistics -> classification -> allocation -> confidence -> wizard UI ->
live tracking. Test each stage against the seed fixtures before moving on.
Budget an extra 2–3 days for the FFT seasonal detection; it is the fiddliest
part of the spec and the easiest to get subtly wrong.

## Sprint 6 — Receipt Scanner (Weeks 10–11)

Camera -> preprocess -> ML Kit -> parse -> categorise -> review -> save -> learn.
**Collect 20–30 real receipt photos in week 1 of the sprint** (varied lighting,
crumpled, faded, handwritten) and build a fixture suite from them. Target is
>70% categorisation accuracy (M5); you cannot claim a number without a test set.

## Sprint 7 — Settings, auth, notifications (Week 12)

PIN + biometrics + lockout backoff, dark theme toggle, recurring reminders,
budget alerts at 80% / 100%.

**Plus FR-ACC-005, deferred here from Sprint 3.** Multi-currency accounts with
user-configurable exchange rates: a `exchange_rates` table behind a **v2
migration**, a base-currency setting, and conversion applied wherever balances
are summed. It lands here because the rate table is user-editable and its
screen is a settings screen, and because a migration is safer in a sprint that
is not also shipping five new pages.

Landing it removes three interim rules from Sprint 3, all named in
[E-25](SPEC_ERRATA.md): the LKR base-currency constant, the same-currency guard
in `MakeTransfer.validate`, and the Total Balance's exclusion of
foreign-currency accounts. Delete all three in the same commit that adds
conversion, or the app will refuse transfers it is now capable of making.

Also here: E-18's reconciliation behind a Settings action.
`RecomputeAccountBalance` is built, tested and wired into `injection.dart`, and
**nothing in the application calls it** — not on app start, not from any screen.
This file previously said it "has no caller outside app start", which described
a narrower gap than the real one.

It stays manual-only on purpose. Reconciliation is `O(all transactions)` per
account, and putting a full-history scan on the launch path is the opposite of
what Sprint 4 does to NFR-PER-001. Until this Settings action ships, E-18's
repair for externally-introduced drift is built and unreachable — stated plainly
in the [E-18 addendum](SPEC_ERRATA.md) rather than left to look finished.

## Sprint 8 — Backup, export, sync (Week 13)

Encrypted `.mb` backups, CSV/PDF export, optional Drive/Dropbox.
**Test restore on a second physical device**, not just re-import on the same one.

## Sprint 9 — Hardening (Week 14)

Coverage to >=75% domain, integration tests, perf pass against every NFR-PER
target, accessibility (4.5:1 contrast, font scaling).

## Sprint 10 — Release (Week 15)

Beta, bug fixes, store assets, user manual, final docs.

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
| The income/compare-periods analytics use cases | Sprint 4 | **Done** — `GetIncomeForPeriod`, `ComparePeriods`, tested and wired into `injection.dart`, called by nothing yet |
| `get_income_for_period`, `compare_periods` **tools** | the use cases above | Deferred — the use case is the Sprint 4 deliverable; the tool wrapper is Copilot-workstream work, not scheduled here |
| `get_budget_plan` | **Sprint 5** | Deferred |
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
