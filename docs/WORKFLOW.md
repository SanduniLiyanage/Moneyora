# Moneyora — Git & Delivery Workflow

Solo project, industry conventions. The point of ceremony on a one-person
project is not coordination — it is that in Sprint 9 you will need to answer
"when did this break and why", and only a clean history can tell you.

---

## 1. Branch model — GitHub Flow

**`main` is the only permanent branch.** It is always releasable, it is
protected, and it is where the documentation lives. Everything else is a
short-lived branch that exists only until its pull request merges.

```
main  ──●──────●──────●──────●──────●──→   protected · tagged · docs live here
         \    /        \    /
          feat/transactions-add-expense
                        feat/money-plan-engine
```

Why not a `develop` branch: a permanent integration branch earns its keep when
you must patch an old release while a newer one is in progress. Moneyora ships
one version to one store listing, so `develop` would only add a second place
for `main` to fall behind — which is exactly the staleness that made this
repository's README look duplicated in the first place.

### A branch is not a place to live

`sanduni` was a person-named branch, and those are the anti-pattern this model
exists to prevent: the name says nothing about the contents, so unrelated work
accumulates on it, and it never reaches a state where merging it is a decision
rather than a gamble. A branch should describe **one change** and be deletable
within a few days.

### Branch naming

`<type>/<short-kebab-description>` where type is one of
`feat` / `fix` / `refactor` / `test` / `docs` / `chore` / `perf`.

Map branches to requirement IDs where you can — `feat/frpln-007-allocation-calc`
gives you traceability from the SRS straight to the diff, which is exactly what
an evaluation panel asks for.

### Protecting main

GitHub -> Settings -> Branches -> Add rule for `main`:

- Require a pull request before merging
- Require status checks to pass -> select **Analyze & Test**
- Require branches to be up to date before merging

Yes, this makes you open a PR against your own repository. That is the point:
the rule is what guarantees `flutter analyze` and the layer check ran before
anything reached `main`, on the day you are tired and would have pushed
directly.

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
- **Never merge broken code into `main`.** Broken commits destroy `git bisect`.
- Write the body for the version of you that comes back in 8 weeks.

## 3. The loop

```powershell
git switch main; git pull
git switch -c feat/money-plan-engine

# ... work ...
dart format .
flutter analyze
flutter test
bash scripts/check_architecture.sh

git add -p                    # stage in hunks; you WILL catch a stray debug print
git commit
git push -u origin feat/money-plan-engine
```

Then on GitHub: open the PR into `main`, wait for CI, **self-review the diff**,
and use **Squash and merge**. Delete the branch from the merge screen.

Squash-merging is what keeps `main`'s history readable: your branch's
"wip", "fix typo", "actually fix it" commits collapse into one commit whose
message you write at merge time, describing the change as a whole. The PR
keeps the detailed history if you ever want it.

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
