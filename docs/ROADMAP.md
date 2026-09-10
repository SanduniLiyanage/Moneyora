# Moneyora — Build Roadmap

Follows the SRS 8.1 sprint plan, with the ordering adjustments that matter in
practice. 14 weeks, 10 sprints.

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

`lib/core/database/seed/dev_seed.dart` — generates ~700 synthetic transactions
across 24 months with *deliberately shaped* patterns:

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

## Sprint 1 — Foundation (Weeks 1–2) — **complete**

Goal: *it compiles, the schema exists, navigation works.* No features yet.

- [x] Install Flutter + Android SDK, pin JDK 21 (`docs/SETUP.md`)
- [x] Run `scripts/bootstrap.ps1`
- [x] Retire branch `sanduni`; `main` is trunk (see docs/WORKFLOW.md)
- [x] Enable branch protection on `main` (require PR + Analyze & Test)
- [x] `core/theme/` — colour tokens, light + dark `ThemeData`
      (indigo brand + amber accent per E-01; green = income, red = expense,
      teal = transfers, per SRS 4.1. Verify 4.5:1 contrast, do not assume it.)
- [x] `core/errors/` — `Failure` hierarchy + `Exception` hierarchy
- [x] `core/usecases/usecase.dart` — the `UseCase<Type, Params>` base
- [x] `core/database/database_helper.dart` — SQLCipher open + key from
      `flutter_secure_storage`
- [x] `core/database/migrations/v1_initial.dart` — 13 tables + 11 indexes.
      More than the 9 and 7 of SDD 5.1: the errata added `transfers`,
      `transaction_splits` and `recurring_rules` with their indexes
      (**`amount_cents INTEGER`** throughout — see ARCHITECTURE.md 6.1)
- [x] `core/database/seed/dev_seed.dart` — the fixture generator above
- [x] `core/router/app_router.dart` — go_router, 5 top-level routes as stubs
      (the 20-screen inventory arrives feature by feature, not up front)
- [x] `injection.dart` — provider wiring
- [x] CI green on the first PR

**Done when:** app launches to an empty home screen, you can navigate to every
stub screen, and `sqlite3` shows the seeded rows in the encrypted DB.
*Met, and verified running on an Android emulator.*

## Sprint 2 — Transactions (Weeks 3–4) — **complete**

Full vertical slice, domain-first. Custom keypad with arithmetic (FR-EXP-002),
category picker, account selector, date-grouped list with daily totals.
Write the use case tests as you go — do not defer them to Sprint 9.

Delivered: the full vertical slice — entity, repository contract, five use
cases, model, datasource, repository, providers and both screens. The keypad's
arithmetic lives in `core/utils/amount_expression.dart` as pure Dart.
E-22's two empty states and E-23's undo window are implemented.

Deferred deliberately: the account selector (Sprint 3, when there is more than
one account to choose between) and E-13's inline `+` for creating a category
mid-entry, which belongs with FR-EXP-004 in the categories work.

## Sprint 3 — Accounts & transfers (Week 5) — **accounts done, transfers next**

Account CRUD, archiving, multi-currency, atomic transfers (FR-TRF-002 —
do the debit and credit **in one sqflite transaction**, or a crash mid-write
loses money).

Delivered in PR #28: the entity, the repository contract, six use cases, the
datasource and the repository impl, including `RecomputeAccountBalance` for
E-18.

Delivered since: `DatabaseChangeBus`, without which any balance on screen goes
stale the moment a transaction is written (E-18), and **FR-ACC-003's side
panel** — the accounts, their balances, a total, and a line naming what the
total left out where that applies.

Also delivered: the account form — create and edit, with the twenty-five
built-in icons E-26 substituted for FR-ACC-006's trademarked list — and
archiving, restoring and deleting (FR-ACC-004, FR-ACC-007), each showing its
use case's own refusal rather than a message the screen invented.

And the transfer screen (FR-TRF-001 to 003), on top of the `MakeTransfer` and
`createTransfer` that had been built and idle since PR #28 — including E-25's
same-currency guard, which lives in `MakeTransfer.validate` beside the rules
that were already there.

Outstanding: the entry screen's account selector, and FR-TRF-004's `From`/`To`
labels on transfer rows.

### FR-ACC-005 (multi-currency) is deferred out of this sprint

"Multi-currency" in the line above reads as one word and is a feature.
FR-ACC-005 requires *user-configurable exchange rates for balance conversion* —
a rates table, therefore a **v2 migration**, plus a conversion policy and a
change to every total in the app. That should not ride along with the account
screens, and a migration written to meet a deadline is the one you regret.

**Sprint 3 ships per-account currency display only.** Accounts already carry a
`currency` column and `currency_utils.dart` already formats any ISO code, so
displaying it costs nothing.

The deferral leaves two behaviours undefined, because FR-TRF-001 permits a
transfer between *any* two active accounts and this sprint builds transfers.
The interim rules, recorded in [E-25](SPEC_ERRATA.md) and removable in one
commit when FR-ACC-005 lands:

1. Base currency is **LKR** — the `Account.currency` default and what the seed
   creates.
2. **Cross-currency transfers are refused**, in `MakeTransfer.validate`, with a
   sentence rather than a wrong number.
3. **The Total Balance sums base-currency accounts only**, and says on screen
   which accounts it left out and why. Not the same thing as FR-ACC-002's
   Include-in-Total toggle: that is the user's choice, this is the app's limit.

FR-ACC-005 keeps its ID and is scheduled below rather than dropped, so it stays
in the traceability matrix instead of disappearing between two sprints.

### FR-ACC-007 is new — see E-25

Auditing the FR-ACC citations while planning this sprint found that no FR-ACC
authorised deleting an account, though `DeleteAccount` had shipped in PR #28.
[E-25](SPEC_ERRATA.md) raises **FR-ACC-007** for it, scoped to what the code
already enforces: permanent deletion only for an account with no transactions,
archiving (FR-ACC-004) for everything else.

## Sprint 4 — Analytics (Week 6) — **next**

Donut chart, period filters, income-vs-expense bars, trend lines, heatmap.
Benchmark now: NFR-PER-006 says <100ms per query at 10k transactions. Seed 10k
and measure. Fixing indexes here is cheap; in Sprint 9 it is not.

**The category-total use case is already built** — `GetSpendingByCategory`,
its datasource, its repository and its DI wiring, tested against the seed for
the E-02 (transfers) and E-04 (splits) traps. It is what the donut chart
renders *and* what the Copilot's spending tool reads, through
`core/ports/spending_by_category_reader.dart`: written once, consumed twice.
What remains here is the charts themselves.

## Sprint 5 — Money Plan Generator (Weeks 7–8) — the headline feature

Order: statistics -> classification -> allocation -> confidence -> wizard UI ->
live tracking. Test each stage against the seed fixtures before moving on.
Budget an extra 2–3 days for the FFT seasonal detection; it is the fiddliest
part of the spec and the easiest to get subtly wrong.

## Sprint 6 — Receipt Scanner (Weeks 9–10)

Camera -> preprocess -> ML Kit -> parse -> categorise -> review -> save -> learn.
**Collect 20–30 real receipt photos in week 1 of the sprint** (varied lighting,
crumpled, faded, handwritten) and build a fixture suite from them. Target is
>70% categorisation accuracy (M5); you cannot claim a number without a test set.

## Sprint 7 — Settings, auth, notifications (Week 11)

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

Also here: E-18's reconciliation behind a Settings action —
`RecomputeAccountBalance` is built and has no caller outside app start.

## Sprint 8 — Backup, export, sync (Week 12)

Encrypted `.mb` backups, CSV/PDF export, optional Drive/Dropbox.
**Test restore on a second physical device**, not just re-import on the same one.

## Sprint 9 — Hardening (Week 13)

Coverage to >=75% domain, integration tests, perf pass against every NFR-PER
target, accessibility (4.5:1 contrast, font scaling).

## Sprint 10 — Release (Week 14)

Beta, bug fixes, store assets, user manual, final docs.

---

## The Copilot — a workstream, not a sprint

The AI Copilot (an on-device tool-using agent — see [`COPILOT.md`](COPILOT.md))
is built in the gaps between sprints, under one rule: **it never jumps the
queue.** Two of its five specified tools wrap the Money Plan Generator and a
savings-goal feature that Sprints 5 and 6 build, so the dependency runs one
way, and an unfinished app is never the price of a finished agent ([E-24](SPEC_ERRATA.md)).

| Stage | Depends on | Status |
|---|---|---|
| Domain: entities, contracts, agent loop, first tool | nothing | **Done** — 55 tests |
| The category-total analytics use case | Sprint 4 | **Done** — runs against the real database |
| Gemini datasource, egress guard | the above | **Done** — 44 tests |
| The ask screen, with key entry | the above | **Done** — 11 widget tests |
| One real question on a device, then the demo recording | a Gemini API key | Next — manual |
| `get_income_for_period`, `compare_periods` | Sprint 4 | Planned |
| `get_budget_plan` | **Sprint 5** | Deferred |
| `get_savings_goal_progress`, affordability query | **Sprint 5+** | Deferred |

---

## Risks worth watching (beyond SRS Appendix C)

| Risk | Why it bites | Mitigation |
|---|---|---|
| No test data until Sprint 5 | Cannot develop or validate the plan engine | Seed generator in Sprint 1 |
| Receipt corpus collected late | Cannot measure the >70% M5 target | Start photographing receipts **now**, every purchase |
| `double` money columns | Cent-level drift in totals; painful late migration | Integer minor units from day one |
| iOS untested until the end | No Mac in the loop; Xcode surprises land in week 13 | Add a macOS CI job early, even if it only builds |
| Perf measured on emulator | Emulator timings do not reflect NFR-PER targets | Benchmark on a real device from Sprint 4 |
| The Copilot grows past its scope | Five tools, a chat history, a proactive agent — each plausible, and together they displace two sprints | Three tools in v1, the rest gated behind the features they wrap ([E-24](SPEC_ERRATA.md)) |
