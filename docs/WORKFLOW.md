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
gives you traceability from the SRS straight to the diff. Someone reviewing this
repository can pick any requirement and find the commit that implemented it,
which is a far stronger signal than a README claiming the feature exists.

### Protecting main

`main` is guarded by a repository ruleset, **protect-main** (GitHub ->
Settings -> Rules -> Rulesets):

- a pull request is required to merge;
- the three CI checks must pass: **Analyze & Test**, **Build Android APK**
  and **Build iOS (compile only)**;
- `main` cannot be deleted or force-pushed.

It does not require a branch to be up to date with `main` first. When two
pull requests touch the same files, merge `main` into the second and let CI
run on the combination before merging it.

Yes, this makes you open a PR against your own repository. That is the point:
the rule is what guarantees `flutter analyze`, the tests and the release
build ran before anything reached `main`, on the day you are tired and would
have pushed directly. Merging past it as an admin defeats it; don't.

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
bash scripts/check_citations.sh   # every FR-/NFR-/E- ID you cited exists

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

A tag on `main` is a release: pushing `v<major>.<minor>.<patch>` runs
`.github/workflows/release.yml`, which builds, signs and publishes the APKs
on GitHub Releases. So tag only what you mean people to install.

```powershell
git switch main; git pull
git tag v1.0.1                # must match pubspec.yaml's version, or the workflow refuses
git push origin v1.0.1
```

Raise `pubspec.yaml`'s version in a pull request first — patch for fixes,
minor for new features — and the build number after the `+` every time, or
phones refuse the update. [`RELEASE.md`](RELEASE.md) has the whole
procedure, and how people who already have the app get the new one.

The sprint milestones of SRS 8.2 were never tagged; the history and
[`ROADMAP.md`](ROADMAP.md) record them instead. The first tag is `v1.0.0`.

## 5. What must never enter git

Already covered by `.gitignore`, but know *why*:

| Item | Why |
|---|---|
| `.env`, API keys | Git history is permanent. A key pushed once is a key burned — rotating is the only fix. |
| `*.jks`, `key.properties` | The upload key is the app's identity: every update must be signed with it, and whoever holds it can publish as you. It lives outside the repository and in the four release secrets ([`RELEASE.md`](RELEASE.md) §1–2). |
| `google-services.json` | Ignored in case Firebase is ever added; the app uses none today. |
| `build/`, `.dart_tool/` | Generated; bloats clones. |
| **`pubspec.lock`** | The exception: **DO commit it.** For apps it pins the exact dependency graph, so your build and CI's build are identical. (The repo's original `.gitignore` had `*.lock`, which would have silently dropped it. Fixed.) |

If you ever do commit a secret: rotate the credential first, *then* clean the
history. Deleting the file in a later commit does nothing — the blob is still
there.
