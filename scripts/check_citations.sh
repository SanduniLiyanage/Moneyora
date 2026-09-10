#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Citation integrity check.
#
# E-25 found four FR-ACC citations naming the wrong requirement, and one use
# case shipped citing nothing that existed at all. That was caught by a human
# rereading the SRS against the code. This script is the version of that
# rereading that runs every time: every FR-, NFR- or E- ID cited in a Dart
# comment must exist in one of the documents that defines IDs. An invented ID
# looks exactly like a checked fact until someone opens the source it claims
# to cite — this makes opening the source automatic.
#
# Valid IDs come from three places, because two specifications are live here:
#   - docs/specs/REQUIREMENTS_INDEX.md   the parent SRS's FR-*/NFR-* (82+28)
#   - docs/specs/SRS_Copilot.md,
#     docs/specs/SDD_Copilot.md          the Copilot draft's FR-COP-*/NFR-*
#   - docs/SPEC_ERRATA.md                every E-* entry raised so far
#
# Scope is Dart **comments** (`//` and `///`), not string literals — an
# exception message or a SQL string embedded in a migration may mention an ID
# for a human reading a stack trace, and that is not a traceability record.
# Scope is comment-only lines (the trimmed line starts with `//`); nothing in
# this codebase cites an ID as a trailing comment after code, and restricting
# to whole-line comments is what keeps a string literal like
# '...(E-15).' from being misread as a citation.
#
# A range citation such as `FR-ACC-001..006` is expanded to every ID in the
# range and each one is checked individually — a range citing five IDs that
# exist and one that does not is exactly the failure mode E-25 was raised for,
# one level up.
#
# Commit-trailer checking is left to the human/PR-review step for now: this
# script only sees the checked-out tree, and a merged commit's trailer cannot
# be fixed after the fact without rewriting protected history, which
# CLAUDE.md forbids. Catching a bad ID before it is committed is what the
# doc-comment check buys; catching one already in `git log` is a job for a
# reviewer, same as always.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
fail=0

INDEX="docs/specs/REQUIREMENTS_INDEX.md"
ERRATA="docs/SPEC_ERRATA.md"
COP_SRS="docs/specs/SRS_Copilot.md"
COP_SDD="docs/specs/SDD_Copilot.md"

for f in "$INDEX" "$ERRATA"; do
  if [ ! -f "$f" ]; then
    printf '\033[31mCannot find %s.\033[0m Run this from the repository root.\n' "$f"
    exit 1
  fi
done

VALID="$(mktemp)"
trap 'rm -f "$VALID"' EXIT

{
  grep -ohE '\b(FR|NFR)-[A-Z]+-[0-9]+\b' "$INDEX"
  [ -f "$COP_SRS" ] && grep -ohE '\b(FR|NFR)-[A-Z]+-[0-9]+\b' "$COP_SRS"
  [ -f "$COP_SDD" ] && grep -ohE '\b(FR|NFR)-[A-Z]+-[0-9]+\b' "$COP_SDD"
  grep -ohE '\bE-[0-9]+\b' "$ERRATA"
} | sort -u > "$VALID"

is_valid() {
  grep -qxF "$1" "$VALID"
}

# Expands "FR-ACC-001..006" to FR-ACC-001 FR-ACC-002 ... FR-ACC-006, padded to
# the width of the lower bound. Anything else passes through unchanged.
expand_ids() {
  local raw="$1"
  if [[ "$raw" =~ ^((FR|NFR)-[A-Z]+)-([0-9]+)\.\.([0-9]+)$ ]]; then
    local prefix="${BASH_REMATCH[1]}" lo="${BASH_REMATCH[3]}" hi="${BASH_REMATCH[4]}"
    local width=${#lo} n
    for ((n = 10#$lo; n <= 10#$hi; n++)); do
      printf '%s-%0*d\n' "$prefix" "$width" "$n"
    done
  else
    printf '%s\n' "$raw"
  fi
}

# <file> <line> <raw citation as written> — reports every ID the raw citation
# expands to that is not in $VALID.
check_citation() {
  local file="$1" line="$2" raw="$3" id unknown=()
  while IFS= read -r id; do
    is_valid "$id" || unknown+=("$id")
  done < <(expand_ids "$raw")

  if [ "${#unknown[@]}" -gt 0 ]; then
    if [ "${#unknown[@]}" -eq 1 ] && [ "${unknown[0]}" = "$raw" ]; then
      printf '\033[31mUNKNOWN CITATION:\033[0m %s:%s cites %s, which is not in %s or %s\n' \
        "$file" "$line" "$raw" "$INDEX" "$ERRATA"
    else
      printf '\033[31mUNKNOWN CITATION:\033[0m %s:%s cites %s, which expands to %s — not in %s or %s\n' \
        "$file" "$line" "$raw" "${unknown[*]}" "$INDEX" "$ERRATA"
    fi
    fail=1
  fi
}

# Scan every comment-only line (after trimming leading whitespace, the line
# starts with `//`) in lib/ and test/ for FR-/NFR-/E- style citations,
# including the `..` range form.
id_pattern='\b(FR|NFR)-[A-Z]+-[0-9]+(\.\.[0-9]+)?\b|\bE-[0-9]+\b'

while IFS=: read -r file line rest; do
  trimmed="${rest#"${rest%%[! $'\t']*}"}"
  case "$trimmed" in
  //*)
    while IFS= read -r raw; do
      [ -n "$raw" ] && check_citation "$file" "$line" "$raw"
    done < <(grep -oE "$id_pattern" <<<"$trimmed")
    ;;
  esac
done < <(grep -rn --include='*.dart' -E '^[[:space:]]*//' lib test 2>/dev/null)

if [ "$fail" -eq 0 ]; then
  printf '\033[32mCitations OK\033[0m — every cited FR-/NFR-/E- ID exists.\n'
else
  printf '\n\033[31mCitation check FAILED.\033[0m Check the ID against %s and %s before citing it —\n' \
    "$INDEX" "$ERRATA"
  printf 'E-25 exists because a wrong ID looked exactly like a checked fact.\n'
fi
exit "$fail"
