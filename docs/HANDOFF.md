# Moneyora — Session Handoff

State of the project as of **2026-09-12**, `main` at `40c61cd`, after **57
merged pull requests** (#2–#58; #1 was closed unmerged) — the donut chart
([PR #55](https://github.com/SanduniLiyanage/Moneyora/pull/55)), FR-RPT-002's
period filters ([PR #56](https://github.com/SanduniLiyanage/Moneyora/pull/56))
and FR-RPT-003's account filter
([PR #58](https://github.com/SanduniLiyanage/Moneyora/pull/58)) all merged
during this window. See "This session" below.

### The numbers, measured — and the only place they live

Every figure below was produced by running the command beside it on `main`
at `40c61cd`, with PR #58 merged.
**This section is the single source of truth for counts.** `README.md` and
`ARCHITECTURE.md` link here rather than restating them: a number kept in one
place goes stale once, and a number kept in three places goes stale three
times and then disagrees with itself, which is worse than being merely out
of date.

| Figure | Value | Command |
|---|---|---|
| Tests | **752 passing** | `flutter test` |
| Analyzer | **0 issues** | `flutter analyze` |
| Layer boundaries | **clean, exit 0** | `bash scripts/check_architecture.sh` |
| Requirement citations | **clean, exit 0** | `bash scripts/check_citations.sh` |
| Domain line coverage | **not remeasured this session** — was 96.9% at `8e5085d`; `lcov` isn't on this machine, only in CI | `flutter test --coverage`, then CI's `lcov --extract coverage/lcov.info '*/domain/*'` |
| Schema | **13 tables, 11 indexes** | `grep -c 'CREATE TABLE' lib/core/database/migrations/v1_initial.dart` |
| Dart files | 103 in `lib/`, 53 in `test/` | `find lib -name '*.dart' \| wc -l` |

Tests by area: 728 at `cdc1ae3` (PR #56, merged) plus 24 net new from
FR-RPT-003 — 10 in `test/unit/features/analytics/domain/entities/spending_query_test.dart`
(All Accounts against one account, narrowing and widening, and the value
identity the provider family is keyed on), 5 added to
`analytics_local_datasource_test.dart` against real in-memory SQLite (the
filter itself, All Accounts, an account with nothing in the period, the
split-follows-its-parent rule, and transfers staying out from both sides), and
10 in `test/widget/account_filter_test.dart` (which query is actually asked
for after each change, the period and account surviving each other, and the
three awkward account lists). Existing tests were updated for the new
parameter type only — fake signatures and call sites — with **no assertion
changed or removed**.
`main.dart` is composition-root wiring (a real `ProviderContainer` against
real platform channels), not something `flutter test`'s VM can exercise the
way the rest of the app is; it was verified on the emulator instead, the same
way `HomePage`'s own doc comment says Sprint 1's proof always has been.

`bash scripts/check_citations.sh` took **under 5 seconds on CI** historically
but **nearly 5 minutes on this Windows machine** in an earlier session —
`find`/`grep` over `lib/` and `test/` through Git Bash on Windows is slow by
nature of the platform, not a regression in the script. Give it a long
timeout rather than assuming it hung.

Read this first, then [`CLAUDE.md`](../CLAUDE.md), then
[`SPEC_ERRATA.md`](SPEC_ERRATA.md). Together they are everything a new session
needs.

## This session — the account filter ([PR #58](https://github.com/SanduniLiyanage/Moneyora/pull/58), merged as `40c61cd`)

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

**Sprint 4 — analytics — has domain, data and the first chart.** The
cold-start splash (PR #52), the query benchmark (PR #53) and all three
aggregates (PR #54) — `GetSpendingByCategory`, `GetIncomeForPeriod`,
`ComparePeriods`, with `AnalyticsRepository`/`AnalyticsLocalDataSourceImpl`
underneath — are in and tested; a benchmark proves the category-total query
stays fast at 10,000 rows on this host's VM (see "Session before that"
above). This session's `SpendingDonutChart` (PR #55, open) is the first
thing in `features/analytics/presentation/`, and `fl_chart` has its first
import. Four charts remain — period filters, income-vs-expense bars, trend
lines, heatmap, per `ROADMAP.md`'s order. NFR-PER-001's item is done — it
lived in `main.dart`, not the feature, so it did not need the feature's own
layers to exist first.

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

Sprint 4's cold-start item (PR #52), its query benchmark (PR #53), all three
aggregates (PR #54), the donut chart (PR #55), the period filters (PR #56) and
the account filter (PR #58) are closed, and `main` is clean at `40c61cd`. Both
of Sprint 4's filters are done; what remains is the other three charts, in the
order `ROADMAP.md` sets:

- **Income-vs-expense bars (FR-RPT-004)**, with net savings highlighted.
  **This is the next unfinished Sprint 4 item.** `GetIncomeForPeriod` is built
  and wired (`getIncomeForPeriodProvider`) and called by nothing yet; it takes
  the same `DateRange` `analyticsRangeProvider` already holds, so the period
  filter needs no change to serve it. Two things it does need deciding:
  whether the account filter applies (income is not in `SpendingQuery`, and
  `incomeForPeriod` takes no account id), and
  [SPEC_ERRATA.md](SPEC_ERRATA.md)'s colour-collision check, which the donut
  chart could skip because it shows expenses only — a chart with both on it is
  the second surface that entry names, and the Bills/Deposits,
  Entertainment/Salary and Gifts/Savings pairs can render together there.
- Then trend lines (FR-RPT-005) over `ComparePeriods` — also built, wired as
  `comparePeriodsProvider`, and called by nothing — and the calendar heatmap
  (FR-RPT-009).

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
