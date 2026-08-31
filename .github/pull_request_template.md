## What & why

<!-- What changes, and what problem it solves. Not a restatement of the diff. -->

Refs: <!-- FR-PLN-007 / NFR-PER-004 / n/a for chores -->

## Checklist

- [ ] `dart format .` — clean
- [ ] `flutter analyze` — no issues
- [ ] `flutter test` — passing
- [ ] `bash scripts/check_architecture.sh` — layer boundaries intact
- [ ] Use case has a unit test before its UI exists
- [ ] Money handled as integer minor units (`amount_cents`), never `double`
- [ ] No secrets, keystores, or `.env` in the diff
- [ ] Schema change? migration script added and DB version bumped
- [ ] I read the whole diff in the Files-changed tab

## Notes for the reviewer (you, in eight weeks)

<!-- Anything non-obvious: a trade-off taken, a thing deliberately left undone. -->
