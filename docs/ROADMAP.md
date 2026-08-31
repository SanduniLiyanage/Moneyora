# Moneyora — Build Roadmap

Follows the SRS 8.1 sprint plan, with the ordering adjustments that matter in
practice. 14 weeks, 10 sprints.

---

## The one change I'd make to the SRS plan

**Build a seed-data generator in Sprint 1, not later.**

The Money Plan Generator (Sprint 5) analyses *6 months of transaction history*.
If you have not planned for that, you arrive at Sprint 5 with a working app
containing eleven test expenses and no way to exercise the algorithm — and you
end up hand-entering hundreds of rows, or worse, shipping an untested engine.

So in Sprint 1, alongside the schema, write:

`lib/core/database/seed/dev_seed.dart` — generates ~800 synthetic transactions
across 6 months with *deliberately shaped* patterns:

- a **fixed** category (rent: same amount, monthly, CV < 0.15)
- a **variable** category (food: noisy daily spend)
- a **seasonal** category (gifts: spikes in December/April)
- a **trending** category (fuel: rising ~8%/month)
- a **sparse** category (pets: 3 transactions total -> must score LOW confidence)

That fixture set is simultaneously your dev data, your algorithm test oracle,
and your demo dataset. Gate it behind `kDebugMode` so it never ships.

---

## Sprint 1 — Foundation (Weeks 1–2)

Goal: *it compiles, the schema exists, navigation works.* No features yet.

- [ ] Install Flutter + Android SDK, pin JDK 21 (`docs/SETUP.md`)
- [ ] Run `scripts/bootstrap.ps1`
- [x] Retire branch `sanduni`; `main` is trunk (see docs/WORKFLOW.md)
- [ ] Enable branch protection on `main` (require PR + Analyze & Test)
- [ ] `core/theme/` — colour tokens, light + dark `ThemeData`
      (green = income, red = expense, teal = transfers/AI, per SRS 4.1)
- [ ] `core/errors/` — `Failure` hierarchy + `Exception` hierarchy
- [ ] `core/usecases/usecase.dart` — the `UseCase<Type, Params>` base
- [ ] `core/database/database_helper.dart` — SQLCipher open + key from
      `flutter_secure_storage`
- [ ] `core/database/migrations/v1_initial.dart` — all 9 tables + the 7 indexes
      from SDD 5.1 (**use `amount_cents INTEGER`** — see ARCHITECTURE.md 6.1)
- [ ] `core/database/seed/dev_seed.dart` — the fixture generator above
- [ ] `core/router/app_router.dart` — go_router with all 20 screens as stubs
- [ ] `injection.dart` — provider wiring
- [ ] CI green on the first PR

**Done when:** app launches to an empty home screen, you can navigate to every
stub screen, and `sqlite3` shows the seeded rows in the encrypted DB.

## Sprint 2 — Transactions (Weeks 3–4)

Full vertical slice, domain-first. Custom keypad with arithmetic (FR-EXP-002),
category picker, account selector, date-grouped list with daily totals.
Write the use case tests as you go — do not defer them to Sprint 9.

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
