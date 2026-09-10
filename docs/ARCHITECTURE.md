# Moneyora — Architecture Guide

Implements SDD v1.0 §2–§3. This document is the rule book; `scripts/check_architecture.sh`
is the enforcement. If the two ever disagree, fix the script.

Where this guide or the baselines conflict with [`SPEC_ERRATA.md`](SPEC_ERRATA.md),
the errata wins. It records every deviation from the approved baselines, with
its reasoning; **see that file for the current entry count and status** rather
than a figure restated here, which is how the previous version of this sentence
came to claim twenty-three defects and two withdrawals when the register held
twenty-six entries and one withdrawal (E-12).

Exact counts live in one place per subject: [`SPEC_ERRATA.md`](SPEC_ERRATA.md)
for errata, [`HANDOFF.md`](HANDOFF.md) for tests and coverage.

Note that the DBD came to light after the first audit and **it, not SRS §6.2, is
the authoritative schema** (Amendment A). Several entries are superseded further
down that file than their own Resolution section, so read an entry to its end.

---

## 1. The one rule

**Dependencies point inward. Always.**

```
  presentation ──────► domain ◄────── data
   (Flutter)         (pure Dart)     (sqflite, ML Kit, http)
```

`domain/` imports nothing but `dart:*` and tiny pure-Dart helpers. That is what
makes the Money Plan Generator (SDD §7.1) testable without a device, an
emulator, or a database — which is what lets you hit NFR-MNT-002's 75% coverage
floor without fighting for it.

### What each layer may import

| Layer | May import | Must never import |
|---|---|---|
| `domain/` | `dart:*`, `fpdart`, `equatable` | Flutter, sqflite, http, ML Kit, `data/`, `presentation/` |
| `data/` | `domain/`, any package | `presentation/` |
| `presentation/` | `domain/`, Flutter, Riverpod | `data/` (except `injection.dart`) |
| any `features/x/` | `core/`, own feature | another feature |

## 2. Anatomy of one vertical slice

Every feature is built in this order. Do not start a screen before the use case
below it exists and has a test.

```
features/transactions/
├── domain/                              ← 1. START HERE. Pure Dart.
│   ├── entities/transaction.dart            immutable business object
│   ├── repositories/transaction_repository.dart   abstract; the CONTRACT
│   └── usecases/add_transaction.dart        one class, one operation, validates
├── data/                                ← 2. Fulfil the contract.
│   ├── models/transaction_model.dart        extends entity; toMap/fromMap
│   ├── datasources/transaction_local_datasource.dart   the ONLY place SQL lives
│   └── repositories/transaction_repository_impl.dart   implements the interface
└── presentation/                        ← 3. Last.
    ├── providers/transaction_provider.dart  Riverpod notifier
    ├── pages/transaction_list_page.dart
    └── widgets/transaction_tile.dart
```

Why this order matters: writing `domain/` first forces you to decide what the
feature *does* before you get distracted by how it looks. It is also the only
order in which you can write the test before the implementation.

## 3. Error handling — one convention, no exceptions

Exceptions are thrown **only** in `data/`, and are caught at the repository
boundary and converted to a `Failure`. Everything above `data/` returns
`Either<Failure, T>`. No `try/catch` in a use case; no `try/catch` in a widget.

```
datasource   throws CacheException
    ↓
repository   catches it → returns Left(CacheFailure('...'))
    ↓
use case     passes the Either through (adds validation Lefts of its own)
    ↓
notifier     result.fold(onError, onSuccess) → AsyncValue.error / .data
    ↓
widget       switch on AsyncValue — loading / error / data, all three handled
```

The payoff: a widget can never forget to handle an error, because `AsyncValue`
has no "success only" shape.

## 4. Naming conventions

| Thing | Convention | Example |
|---|---|---|
| Files, folders | `snake_case` | `add_transaction.dart` |
| Classes | `PascalCase` | `AddTransaction` |
| Use case class | verb + noun, no `Service`/`Manager` | `GenerateMoneyPlan` |
| Abstract repo | `<Entity>Repository` | `TransactionRepository` |
| Impl | `<Entity>RepositoryImpl` | `TransactionRepositoryImpl` |
| Provider | `<thing>Provider` | `transactionRepositoryProvider` |
| Test file | mirrors source + `_test` | `add_transaction_test.dart` |

Money is stored as **integer minor units** (cents), never `double`. See §6.

## 5. Where things go when you are unsure

- Used by two features → `lib/core/`
- A *signal* two features share, rather than a contract →
  `lib/core/database/database_change_bus.dart`. One feature's write can move
  another's rows: every transaction write adjusts
  `accounts.current_balance_cents` inside the same database transaction
  (E-18), so an accounts watcher hearing only accounts writes shows a stale
  balance. Both datasources publish to one bus, `injection.dart` owns and
  closes it, and neither feature imports the other — which rule 4 forbids and
  which would be the wrong shape anyway.
- A contract two features share, so neither imports the other →
  `lib/core/ports/`. The owning feature implements it; the other depends on the
  contract. `SpendingByCategoryReader` is the worked example: analytics owns
  the query, the Copilot reads through the port, and rule 4 stays intact.
- Used by one feature, more than one layer → that feature's `domain/`
- Formats or parses a value → `lib/core/utils/`
- Reusable widget with no business logic → `lib/core/widgets/`
- Widget that knows about one entity → that feature's `presentation/widgets/`
- SQL → `data/datasources/` or `core/database/`. Nowhere else. Enforced.
- **A read whose feature slice does not exist yet** → `core/database/`, as
  `entry_catalog.dart` does for the entry screen's category and account lists.
  This is the one place the build order in §2 is not followed, it was done
  deliberately, and it is recorded as [E-27](SPEC_ERRATA.md).

  Categories are shared by analytics, the Money Plan and the receipt scanner, so
  a `features/categories/` slice imported by `features/transactions/` would
  break rule 4 the moment it was written — and a full slice was not justified by
  reading a seeded list nothing could yet edit.

  **This exception has an end date.** `entry_catalog.dart` is deleted in Sprint
  3.5, when the categories slice lands and its reads move behind that slice's
  repository. Do not treat it as a pattern to copy: if you are tempted, the
  answer is almost always that the feature slice should exist.

## 6. Two deviations from SDD v1.0, both now settled

This section was written while both were open questions. **Both have since been
decided and implemented**, and are recorded as deviations in
[`SPEC_ERRATA.md`](SPEC_ERRATA.md) — E-06 and E-14 — rather than applied
silently. They are kept here because the reasoning is worth reading before you
are tempted to undo either one.

### 6.1 Store money as integers, not `REAL`

SDD §5 / SRS §6.2 declare `amount REAL NOT NULL`. IEEE-754 doubles cannot
represent most decimal amounts exactly:

```dart
0.1 + 0.2 == 0.30000000000000004   // true
```

Accumulate a few thousand of those across the Money Plan Generator's
`SUM(amount)` queries and your "Plan vs Actual" totals drift by visible cents.
Users notice; graders notice faster.

**Fix:** store `amount_cents INTEGER NOT NULL` (LKR has 2 decimals, so
`Rs 1,250.75` → `125075`), and convert only at the display edge in
`core/utils/currency_utils.dart`. This is what every production finance app does.

**Done in Sprint 1.** Every monetary column in `v1_initial.dart` is
`*_cents INTEGER`, and `currency_utils.dart` is the only file permitted to turn
cents into text or text into cents. All three baseline documents specify `REAL`;
the override is E-06.

### 6.2 `StateNotifier` and `dartz` are both legacy

- SDD §6.3 uses `StateNotifier`. Riverpod has since moved to `Notifier` /
  `AsyncNotifier`, and `StateNotifier` is retained only for backward
  compatibility. New code should use `AsyncNotifier`.
- `dartz` (SDD §10.1) is a broad, thinly-maintained Haskell port. `fpdart` is
  the actively-maintained alternative with a near-identical `Either` API.

Neither changes the architecture — only import lines and a base class name.

**Decision (2026-09-01): take the modern option for both.** `AsyncNotifier`
over `StateNotifier`, `fpdart` over `dartz`. This project's audience is a
reviewer reading the repository, and a 2026 Flutter codebase built on a
deprecated notifier and a thinly-maintained functional library reads as one
assembled from an old tutorial. Recorded as a deviation from SDD §10.1 in
[`SPEC_ERRATA.md`](SPEC_ERRATA.md) E-14 rather than applied silently.

## 7. Testing strategy

| Layer | Test type | Target | Mock |
|---|---|---|---|
| `domain/usecases` | Pure unit | **≥75%** (NFR-MNT-002), aim 90% | the repository |
| `domain` plan engine | Pure unit, table-driven | ~100% | nothing — feed it fixtures |
| `data/repositories` | Unit | ~70% | the datasource |
| `data/datasources` | Integration, in-memory sqflite | happy path + migrations | nothing |
| `presentation` | Widget test | key screens | override providers |
| Critical flows | `integration_test/` | add-expense, scan-receipt, plan | nothing |

The Money Plan Generator is the feature to over-test. It is pure arithmetic over
fixtures, it is your headline feature, and a wrong allocation is invisible until
a user complains. Write the fixture set (6 months of synthetic transactions with
a known-correct expected plan) *before* the algorithm.
