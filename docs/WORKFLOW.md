# Moneyora — Git & Delivery Workflow

Solo project, industry conventions. The point of ceremony on a one-person
project is not coordination — it is that in Sprint 9 you will need to answer
"when did this break and why", and only a clean history can tell you.

---

## 1. Branch model

You are currently on a branch named **`sanduni`**. Rename it. Person-named
branches carry no information about *what* is on them, and they never end —
so they accumulate unrelated work and can never be safely merged or deleted.

```
main       <- always releasable. Tagged. Protected. Never commit directly.
└── develop  <- integration branch. CI must be green.
    ├── feat/transactions-add-expense
    ├── feat/money-plan-engine
    ├── fix/donut-chart-overflow
    └── chore/ci-coverage-gate
```

One-time migration:

```powershell
git branch -m sanduni develop        # rename local
git push origin -u develop           # publish
git push origin --delete sanduni     # remove the old remote branch
```

Then set `develop` as the default branch in GitHub -> Settings -> Branches, and
add a protection rule on `main`: require CI to pass, require a PR.

### Branch naming

`<type>/<short-kebab-description>` where type is one of
`feat` / `fix` / `refactor` / `test` / `docs` / `chore` / `perf`.

Map branches to requirement IDs where you can — `feat/frpln-007-allocation-calc`
gives you traceability from the SRS straight to the diff, which is exactly what
an evaluation panel asks for.

## 2. Commit messages — Conventional Commits

```
<type>(<scope>): <imperative summary, <=72 chars>

<why this change exists — not what the diff shows>

Refs: FR-PLN-007
```

Real examples:

```
feat(money-plan): add weighted moving average allocator

Implements the 60/40 recent-vs-older weighting from SRS 7.1 Phase 2.
Fixed categories bypass the weighting and use a 3-occurrence mean, since
their CV < 0.15 makes smoothing pointless.

Refs: FR-PLN-007
```

```
fix(transactions): stop balance drifting on repeated edits

current_balance was recomputed from the edited row instead of re-summing
the account, so an edit-then-undo left the balance off by the delta.

Refs: FR-EXP-007
```

Rules that matter more than the format:
- **One logical change per commit.** If the body needs "and", split it.
- **Never commit broken code to `develop`.** Broken commits destroy `git bisect`.
- Write the body for the version of you that comes back in 8 weeks.

## 3. The loop

```powershell
git switch develop; git pull
git switch -c feat/money-plan-engine

# ... work ...
dart format .
flutter analyze
flutter test
bash scripts/check_architecture.sh

git add -p                    # stage in hunks; you WILL catch a stray debug print
git commit
git push -u origin feat/money-plan-engine
# open a PR into develop, let CI run, self-review the diff, merge
```

**Self-review the PR diff in GitHub's UI before merging, every time.** Reading
your own code in a different medium catches a startling amount — leftover
`print`s, commented-out blocks, a TODO you meant to resolve.

## 4. Tags and releases

Tag every sprint milestone (SRS 8.2) on `main`:

```powershell
git tag -a v0.1.0-M1 -m "M1 Foundation: schema + navigation"
git push origin v0.1.0-M1
```

`v<major>.<minor>.<patch>` — bump minor per completed milestone, patch for
fixes. This gives you a demoable build for every checkpoint.

## 5. What must never enter git

Already covered by `.gitignore`, but know *why*:

| Item | Why |
|---|---|
| `.env`, API keys | Git history is permanent. A key pushed once is a key burned — rotating is the only fix. |
| `*.jks`, `key.properties` | Whoever holds your upload keystore controls your Play Store listing. |
| `google-services.json` | Ties to a live Firebase project. |
| `build/`, `.dart_tool/` | Generated; bloats clones. |
| **`pubspec.lock`** | The exception: **DO commit it.** For apps it pins the exact dependency graph, so your build and CI's build are identical. (The repo's original `.gitignore` had `*.lock`, which would have silently dropped it. Fixed.) |

If you ever do commit a secret: rotate the credential first, *then* clean the
history. Deleting the file in a later commit does nothing — the blob is still
there.
