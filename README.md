<div align="center">

# Moneyora

**Personal Finance & AI Budget Planner**

*Plan. Track. Thrive.*

Offline-first Flutter app with on-device receipt scanning and statistical budget planning.

[![CI](https://github.com/SanduniLiyanage/Moneyora/actions/workflows/ci.yml/badge.svg)](https://github.com/SanduniLiyanage/Moneyora/actions/workflows/ci.yml)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-blue.svg)](LICENSE)

</div>

---

## Status

Pre-Sprint-1. Repository scaffolded; Flutter SDK installation pending.
See [`docs/SETUP.md`](docs/SETUP.md) to get running.

## What it does

| Feature | Works offline | Spec |
|---|:---:|---|
| Expense / income tracking, multi-account, transfers | yes | FR-EXP, FR-INC, FR-ACC, FR-TRF |
| **Money Plan Generator** — budgets from your own spending history | yes | FR-PLN |
| **Receipt Scanner** — ML Kit OCR + 3-layer auto-categorisation | yes | FR-RCP |
| Donut charts, trends, calendar heatmap, CSV/PDF export | yes | FR-RPT |
| Cloud backup (Drive / Dropbox), live exchange rates, AI coaching tips | no — optional | FR-BAK |

Everything in the first four rows runs with the radio off. The last row degrades
gracefully when there is no connection.

## Stack

Flutter · Dart 3 · Riverpod · SQLite + SQLCipher (AES-256) · Google ML Kit ·
fl_chart · go_router · Clean Architecture (feature-first)

## Quick start

```powershell
git clone https://github.com/SanduniLiyanage/Moneyora.git
cd Moneyora
.\scripts\bootstrap.ps1     # requires Flutter on PATH — see docs/SETUP.md
flutter run
```

## Repository layout

```
lib/
├── core/          shared: theme, errors, utils, widgets, database, router
├── features/      one self-contained module per feature
│   └── <feature>/
│       ├── domain/         pure Dart — entities, contracts, use cases
│       ├── data/           sqflite, ML Kit, http — implements the contracts
│       └── presentation/   Flutter widgets + Riverpod providers
├── main.dart
├── app.dart
└── injection.dart
docs/              guides, plus the approved SRS and SDD in docs/specs/
scripts/           bootstrap + architecture boundary checker
test/              mirrors lib/
```

## Documentation

| Document | Read it when |
|---|---|
| [SETUP.md](docs/SETUP.md) | Setting up a machine, or a build breaks |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Adding any feature — layer rules and conventions |
| [WORKFLOW.md](docs/WORKFLOW.md) | Branching, commits, releases |
| [ROADMAP.md](docs/ROADMAP.md) | Deciding what to build next |
| [CLAUDE.md](CLAUDE.md) | Working with Claude Code in this repo |
| [SPEC_ERRATA.md](docs/SPEC_ERRATA.md) | **Defects found in the baselines.** Where it and a spec disagree, it wins |
| [specs/](docs/specs/) | The approved SRS v1.0 and SDD v1.0, unmodified |

### On the errata

The SRS and SDD in [`docs/specs/`](docs/specs/) are the approved baselines and
are left exactly as approved. Reviewing them before writing the schema turned up
fourteen defects — four of which block Sprint 1, including a `transactions`
table with no way to record a transfer's destination account, and a plan
generator built on `STDDEV()`, which SQLite does not provide.

Rather than silently editing the specifications, every deviation is recorded in
[`SPEC_ERRATA.md`](docs/SPEC_ERRATA.md) with its reasoning, and folds into v1.1
at milestone M2. The baseline stays auditable; the corrections stay traceable.

## Platform status

| Platform | Status |
|---|---|
| Android 8.0+ (API 26) | Primary target. Built and tested. |
| iOS 14+ | **Compile-verified only** — CI builds it on macOS every PR, but it has never been run on a device or simulator. See [E-19](docs/SPEC_ERRATA.md). |

The distinction matters: "builds on iOS" and "works on iOS" are different
claims, and only the first is being made.

## Security

Database encrypted with AES-256 (SQLCipher); key held in the iOS Keychain /
Android Keystore. Receipt images stored in encrypted app-private storage.
No financial data leaves the device without an explicit user action. Optional
PIN (4–6 digit, 5-attempt lockout with exponential backoff) and biometrics.

## Licence

MIT — see [LICENSE](LICENSE).

Built by Sanduni.
