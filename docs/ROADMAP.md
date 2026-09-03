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

## Sprint 2 — Transactions (Weeks 3–4) — **in progress**

Full vertical slice, domain-first. Custom keypad with arithmetic (FR-EXP-002),
category picker, account selector, date-grouped list with daily totals.
Write the use case tests as you go — do not defer them to Sprint 9.

Done so far: the domain layer (entity, repository contract, `AddTransaction`
with its validation) and `data/models/transaction_model.dart`. Next is the
datasource, where the three-row transfer of E-15, the split writes of E-04 and
the balance cache of E-18 all land.

## Sprint 3 — Accounts & transfers (Week 5)

Account CRUD, archiving, multi-currency, atomic transfers (FR-TRF-002 —
do the debit and credit **in one sqflite transaction**, or a crash mid-write
loses money).

## Sprint 4 — Analytics (Week 6)

Donut chart, period filters, income-vs-expense bars, trend lines, heatmap.
Benchmark now: NFR-PER-006 says <100ms per query at 10k transactions. Seed 10k
and measure. Fixing indexes here is cheap; in Sprint 9 it is not.

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

## Sprint 8 — Backup, export, sync (Week 12)

Encrypted `.mb` backups, CSV/PDF export, optional Drive/Dropbox.
**Test restore on a second physical device**, not just re-import on the same one.

## Sprint 9 — Hardening (Week 13)

Coverage to >=75% domain, integration tests, perf pass against every NFR-PER
target, accessibility (4.5:1 contrast, font scaling).

## Sprint 10 — Release (Week 14)

Beta, bug fixes, store assets, user manual, final docs.

---

## Risks worth watching (beyond SRS Appendix C)

| Risk | Why it bites | Mitigation |
|---|---|---|
| No test data until Sprint 5 | Cannot develop or validate the plan engine | Seed generator in Sprint 1 |
| Receipt corpus collected late | Cannot measure the >70% M5 target | Start photographing receipts **now**, every purchase |
| `double` money columns | Cent-level drift in totals; painful late migration | Integer minor units from day one |
| iOS untested until the end | No Mac in the loop; Xcode surprises land in week 13 | Add a macOS CI job early, even if it only builds |
| Perf measured on emulator | Emulator timings do not reflect NFR-PER targets | Benchmark on a real device from Sprint 4 |
