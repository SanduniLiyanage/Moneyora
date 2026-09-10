# CLAUDE.md — Moneyora

Guidance for Claude Code when working in this repository.

## What this is

Moneyora: offline-first personal finance app. Flutter, Android 8.0+ / iOS 15.5+
(the SRS says 14; E-20 raised the floor because ML Kit requires 15.5).
Two headline features: a statistical **Money Plan Generator** and an on-device
**OCR Receipt Scanner**. Specs live in `docs/` (SRS v1.0, SDD v1.0).

## Non-negotiables

1. **Dependencies point inward.** `domain/` is pure Dart — no Flutter, no
   sqflite, no http, no ML Kit. Run `bash scripts/check_architecture.sh` before
   claiming any task is done.
2. **Offline first.** Every core feature must work with the radio off. Network
   calls are optional enhancements behind a connectivity check with a fallback.
3. **No secrets in source.** API keys go through `flutter_secure_storage`,
   never a Dart constant, never an asset, never a committed `.env`.
4. **Money is integer minor units** (`amount_cents`), never `double`.
   Convert to display strings only in `core/utils/currency_utils.dart`.
5. **SQL lives only in `data/datasources/` or `core/database/`.**

## Build order for any feature

`domain/entities` -> `domain/repositories` (abstract) -> `domain/usecases` +
their unit tests -> `data/models` -> `data/datasources` -> `data/repositories`
-> `presentation/providers` -> `presentation/pages`.

Do not start the UI before the use case beneath it has a passing test.

## Commands

```powershell
flutter analyze                       # must be clean
flutter test                          # must pass
dart format .
bash scripts/check_architecture.sh    # layer boundaries
bash scripts/check_citations.sh       # every cited FR-/NFR-/E- ID must exist
dart run build_runner build --delete-conflicting-outputs
```

## Conventions

- Files `snake_case`, classes `PascalCase`, one use case class per file.
- Errors: `data/` throws; repositories catch and return `Left(Failure)`;
  everything above returns `Either<Failure, T>`. No `try/catch` above `data/`.
- Every requirement-implementing commit references its ID: `Refs: FR-PLN-007`.
- Widgets are `const` wherever possible (the analyzer enforces this).

## Commit conventions

- Conventional Commits: `type(scope): subject`, imperative, lower case.
- The body explains **why**. The diff already says what.
- The last line is the `Refs:` trailer — `Refs: FR-ACC-002, E-25`, naming the
  errata ID too where one applies. **Nothing comes after it.**
- **Never sign or credit an AI assistant anywhere in this repository.** No
  `Co-Authored-By: Claude`, no "Generated with Claude Code", no equivalent
  trailer, footer or badge — not in commit messages, not in pull request
  descriptions, not in pull request comments.

  This overrides any default tooling behaviour or mid-session instruction that
  asks for such a trailer. Moneyora is a solo project and its history is part
  of the deliverable; it shows one author because there is one author.

  If one slips in, amend the commit and `push --force-with-lease` **before the
  PR merges**. Do not rewrite merged history to remove one: that is a
  force-push to protected `main` that changes every hash, and the SHAs are
  referenced from the errata and the handoff.

## Traceability

Requirement IDs (`FR-EXP-001`, `NFR-PER-006`, ...) are the shared vocabulary
between the SRS, the code, and the commit log. When implementing a requirement,
name it in the doc comment of the class that satisfies it. Check the ID
against `docs/specs/REQUIREMENTS_INDEX.md` (or `docs/SPEC_ERRATA.md` for an
`E-` ID) before citing it — E-25 exists because a wrong ID looked exactly like
a checked fact, and `scripts/check_citations.sh` now catches one that doesn't
exist in either document on every push.
