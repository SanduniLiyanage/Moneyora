# Moneyora — Session Handoff

State of the project as of **2026-09-12**, `main` at `cc96ced`, after **47
merged pull requests** (#2–#48; #1 was closed unmerged), **plus this session's
categories-presentation slice, on branch `feat/categories-presentation` as
[PR #49](https://github.com/SanduniLiyanage/Moneyora/pull/49), open and
awaiting CI/review — not yet merged.** See "This session" below.

### The numbers, measured — and the only place they live

Every figure below was produced by running the command beside it on
`feat/categories-presentation` at `b55939a` (PR #49), before it merges.
**This section is the single source of truth for counts.** `README.md` and
`ARCHITECTURE.md` link here rather than restating them: a number kept in one
place goes stale once, and a number kept in three places goes stale three
times and then disagrees with itself, which is worse than being merely out
of date.

| Figure | Value | Command |
|---|---|---|
| Tests | **648 passing** | `flutter test` |
| Analyzer | **0 issues** | `flutter analyze` |
| Layer boundaries | **clean, exit 0** | `bash scripts/check_architecture.sh` |
| Requirement citations | **clean, exit 0** | `bash scripts/check_citations.sh` |
| Domain line coverage | **not remeasured this session** — was 96.9% at `8e5085d`; `lcov` isn't on this machine, only in CI | `flutter test --coverage`, then CI's `lcov --extract coverage/lcov.info '*/domain/*'` |
| Schema | **13 tables, 11 indexes** | `grep -c 'CREATE TABLE' lib/core/database/migrations/v1_initial.dart` |
| Dart files | 91 in `lib/`, 45 in `test/` | `find lib -name '*.dart' \| wc -l` |

Tests by area: the 623 at `cc96ced` plus 25 new from this session's category
form and category list widget tests, plus one existing home-screen test
adjusted for an ambiguous finder the new "Categories" nav entry introduced —
none yet broken out by sub-area.

`bash scripts/check_citations.sh` took **under 5 seconds on CI** historically
but **nearly 5 minutes on this Windows machine** this session — `find`/`grep`
over `lib/` and `test/` through Git Bash on Windows is slow by nature of the
platform, not a regression in the script. Give it a long timeout rather than
assuming it hung.

Read this first, then [`CLAUDE.md`](../CLAUDE.md), then
[`SPEC_ERRATA.md`](SPEC_ERRATA.md). Together they are everything a new session
needs.

## This session — the categories management screen ([PR #49](https://github.com/SanduniLiyanage/Moneyora/pull/49), open)

Picking up exactly where PR #47 left off: `domain/`, `data/` and
`presentation/providers` were done, and `presentation/pages` /
`presentation/widgets` were empty. This session filled them in, following
`AccountFormPage`/`AccountDrawer`'s precedent throughout so the two feature's
screens read as one design rather than two:

- **`core/widgets/category_icons.dart`** — the icon catalogue, the same shape
  as `account_icons.dart`. Its first eighteen keys are not invented: they are
  `default_seed.dart`'s own icon strings (`basket`, `receipt`, `car`, …), so a
  seeded category and a user-created one render through the same map instead
  of two catalogues that can drift apart. `categoryIconFor` never throws, for
  the same restored-backup/older-build reasoning `accountIconFor` documents.
- **`core/theme/category_palette.dart`** — the colour picker's swatches, drawn
  from `default_seed.dart`'s own fifteen expense hues rather than a fresh set
  or an open colour wheel. That file's doc comment is explicit those hues are
  the ones that survived a categorical-distinctness and colour-vision
  check; an open-ended picker would let a user pick a colour nobody verified.
  `categoryColorFor` resolves the light/dark step from the stored light value
  at render time, the same convention `applyDefaultSeed` already uses.
- **`features/categories/presentation/pages/category_form_page.dart`** —
  create and edit, one screen for both (`CategoryFormPage`). Name, an
  expense/income `SegmentedButton`, a parent dropdown (top-level categories of
  the matching type only, excluding the category being edited), the icon grid
  and the colour grid, then Save and — once the category exists — Delete.
  Every rule shown is `AddCategory.validate`/`validateParent` or
  `DeleteCategory`, called rather than restated, the same discipline
  `AccountFormPage` holds for `AddAccount`.
- **`features/categories/presentation/pages/category_list_page.dart`** —
  management screen (`CategoryListPage`): an Expense/Income `TabBar`, each tab
  listing top-level categories with their sub-categories nested underneath,
  and a FAB whose new category takes the type of whichever tab is showing.
- **Routes and navigation**: `Routes.categories` and `Routes.categoryForm` in
  `core/router/app_router.dart` (the `extra` payload is either a `Category` to
  edit or a `CategoryType` for a new one — the same one-path-for-both shape
  `Routes.accountForm` uses), plus a "Categories" entry in the home screen's
  "Coming next" list.
- **Tests**: `test/widget/category_form_test.dart` (18 cases) and
  `test/widget/category_list_test.dart` (7 cases), the same fake-repository
  shape `account_form_test.dart`/`accounts_drawer_test.dart` use — a real
  `AddCategory`/`UpdateCategory`/`DeleteCategory` over a scripted repository,
  so the messages asserted are the use cases' own. One existing test,
  `app_shell_test.dart`'s database-summary assertion, needed scoping to the
  summary card once "Categories" started appearing twice on the home screen.

**A real bug caught by the tests, not by inspection**: `DropdownButtonFormField`
asserts if `initialValue` is not among its `items` — and editing a
sub-category hits that on the very first frame, before `categoriesProvider`'s
async stream has resolved the parent list `initialValue` needs to be
validated against. Fixed by computing a `displayedParentId` that falls back to
`null` ("None") whenever the saved parent isn't yet (or isn't ever, for a
dangling reference) among the loaded options, and rekeying the field so a
correct value seeds it once the list arrives. Covered by
`'preselects the current parent when editing a sub-category'`.

**Committed and pushed as one commit, `b55939a`** on `feat/categories-presentation`,
opened as [PR #49](https://github.com/SanduniLiyanage/Moneyora/pull/49).
`flutter analyze` (0 issues), `flutter test` (648 passing, up from 623),
`check_architecture.sh` and `check_citations.sh` are all clean.
**Not yet merged — do not merge without asking first.** Once CI is green:
`gh pr checks --watch` then `gh pr merge --squash --delete-branch` and
`git pull` on `main`, per the workflow section below.

**Still not done**: `entry_catalog.dart`'s deletion (E-27) — the entry screen
still reads categories from the catalog, not `categoriesProvider`, so deleting
it is not yet safe. E-13's inline `+` on the entry screen. FR-EXP-011's
category-grouped *transaction* list toggle — note this is **not** a
categories-screen feature; E-11's resolution raises it against FR-EXP-006 and
`SDD SCR-005`, i.e. it belongs to `transaction_list_page.dart`, not this
slice. All three were already listed separately from the categories
presentation work before this session and remain so now.

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
| E-27 | `entry_catalog.dart` sits outside a feature slice on purpose — and is **deleted in Sprint 3.5**, which is what stops "interim" becoming permanent |
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

**Sprint 3.5 — categories — is in progress.** Added 2026-09-10 and slotted
between Sprints 3 and 4: FR-EXP-004, FR-EXP-005 and FR-EXP-011 had been
scheduled in no sprint at all, while analytics, the Money Plan and the
receipt scanner all depend on categories being something the user controls.
That was a defect in the plan rather than in the SRS, so it is fixed in
[`ROADMAP.md`](ROADMAP.md) and deliberately raised no errata entry.

**`domain/`, `data/`, `presentation/providers` and now `presentation/pages`
are done and wired** (PRs #44, #46, #47, plus this session's uncommitted
category screens) — `Category`, `CategoryRepository`, the four use cases,
`CategoryLocalDataSourceImpl`, `CategoryRepositoryImpl`,
`category_providers.dart`, `injection.dart` entries for all of it (proven
reachable in `injection_test.dart` the same way the transactions slice is),
and now `CategoryListPage`/`CategoryFormPage`, reachable from the home
screen's "Coming next" list. A user can create, rename, re-icon, re-colour,
re-parent and delete a category through the app.
[E-27](SPEC_ERRATA.md)'s retirement of `entry_catalog.dart` **still hasn't
happened** — the entry screen's category chips (`add_transaction_page.dart`)
still read `EntryCatalog`, not `categoriesProvider`, so deleting the catalog
would break entry. That swap is its own piece of work, not a side effect of
adding a separate management screen.

**Sprint 4 — analytics — has domain and data only.** `GetSpendingByCategory`,
its datasource and its repository are in and tested;
`features/analytics/presentation/` is empty in all three of its
subdirectories. There is no chart. `fl_chart` is declared in `pubspec.yaml` and
imported nowhere.

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
│   │   ├── entry_catalog.dart           the entry screen's categories+accounts
│   │   │                                read. Outside a feature slice on
│   │   │                                purpose — E-27. Deleted in Sprint 3.5.
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
│   ├── analytics/       spending-by-category: domain + data. presentation/ is
│   │                    EMPTY — no charts. Sprint 4.
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

**First: watch and merge [PR #49](https://github.com/SanduniLiyanage/Moneyora/pull/49).**
Opened this session, not yet merged — deliberately left for a human decision
rather than merged automatically. Once reviewed and CI is green:

```powershell
gh pr checks 49 --watch
gh pr merge 49 --squash --delete-branch
git pull
```

Once that lands, Sprint 3.5's remaining pieces are, in the order they were
already sequenced: E-13's inline `+` on the entry screen (a category picker
that can create a category without leaving the entry flow — needs a small
inline form or a bottom sheet, not the full `CategoryFormPage`), then
retiring `entry_catalog.dart` (E-27) once the entry screen's category chips
read `categoriesProvider` instead of `EntryCatalog`. FR-EXP-011's
category-grouped list toggle is **not** part of this feature — it belongs to
`transaction_list_page.dart` (E-11 raises it against FR-EXP-006 and SDD
SCR-005), and is easy to mistake for categories-screen work because of the
name.

One thing worth deciding rather than assuming: whether a category the entry
screen's inline `+` creates should default `sortOrder` to sit after the
existing set, and whether re-ordering categories (drag-to-reorder on the list
screen) is in scope for FR-EXP-004 or a later polish pass — neither use case
nor screen makes a claim about it today, and the list currently renders in
whatever order `WatchCategories` returns them.

**The release build is fixed** (see Environment below and
[E-09](SPEC_ERRATA.md)). One thing it leaves open: a release APK has been built
but never installed or run, so put that on the next emulator session.

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

**Sprint 3.5 — categories — the full slice is built** (PRs #44, #46, #47, plus
this session's uncommitted list/form screens); see [`ROADMAP.md`](ROADMAP.md).
FR-EXP-004 (custom categories) and FR-EXP-005 (the two-level hierarchy) now
have a screen, not just use cases and a repository. What remains: E-13's
inline `+` on the entry screen, and [E-27](SPEC_ERRATA.md)'s
`entry_catalog.dart` retirement, which depends on it. FR-EXP-011 (the
category-grouped *transaction* list) is a separate requirement against
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
live-API question (the emulator has network) and the cold-start *fix* (a
main-thread block reproduces anywhere). Only the confirmed cold-start *number*
remains.

Do these in order; each later step benefits from the seed loaded in step 2.

**Before you go — prepare on the emulator, so the phone time is measurement
only:**

- [ ] Build and install a **release** APK, not debug. Debug builds carry every
      ABI and unstripped symbols, and their timings are not the ones the NFRs
      are about. **This does not currently work** — see the release-build note
      under Environment below. Fix that first or the session is wasted.
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

**A release APK has been built but never run.** R8 with
`proguard-android-optimize.txt` can break reflection-based code that compiles
cleanly, and this app leans on several JNI-backed plugins. Installing a release
build on the emulator is on the next emulator session's list. Until then,
"compiles in release" is the only claim available — E-19's distinction, applied
to a build type.

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
