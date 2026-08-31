#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# Clean Architecture boundary enforcement (NFR-MNT-001).
#
# Layer rules are worthless if nothing checks them. Dart's analyzer cannot
# express "domain must not import Flutter", so we assert it here and wire this
# into CI. Runs in ~1s.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
fail=0

report() { # <message> <matches>
  if [ -n "$2" ]; then
    printf '\n\033[31mVIOLATION:\033[0m %s\n%s\n' "$1" "$2"
    fail=1
  fi
}

# RULE 1 — Domain is pure Dart. No Flutter, no DB, no network, no codegen deps.
hits=$(grep -rn --include='*.dart' \
  -E "^import 'package:(flutter|flutter_riverpod|sqflite|sqflite_sqlcipher|http|path_provider|google_mlkit|image_picker|fl_chart|go_router)" \
  lib/features/*/domain lib/core/usecases 2>/dev/null)
report "domain layer imports a framework/IO package (must be pure Dart)" "$hits"

# RULE 2 — Domain must not reach into data/ or presentation/.
hits=$(grep -rn --include='*.dart' -E "import .*/(data|presentation)/" \
  lib/features/*/domain 2>/dev/null)
report "domain layer imports data/ or presentation/ (dependencies point inward only)" "$hits"

# RULE 3 — Presentation must not import data/ directly. It talks to domain
# use cases; concrete implementations are wired only in injection.dart.
hits=$(grep -rn --include='*.dart' -E "import .*/data/" \
  lib/features/*/presentation 2>/dev/null)
report "presentation layer imports data/ directly (go through a use case)" "$hits"

# RULE 4 — No cross-feature imports. Features share code only via lib/core.
for dir in lib/features/*/; do
  feature=$(basename "$dir")
  hits=$(grep -rn --include='*.dart' -E "import 'package:moneyora/features/" "$dir" 2>/dev/null \
         | grep -v "features/$feature/")
  report "feature '$feature' imports another feature (extract to lib/core instead)" "$hits"
done

# RULE 5 — Raw SQL belongs in data/datasources only.
hits=$(grep -rln --include='*.dart' -iE "\b(SELECT .* FROM|INSERT INTO|UPDATE .* SET|DELETE FROM)\b" lib 2>/dev/null \
       | grep -v '/data/datasources/' | grep -v '/core/database/')
report "raw SQL found outside data/datasources/ or core/database/" "$hits"

if [ "$fail" -eq 0 ]; then
  printf '\033[32mArchitecture OK\033[0m — all layer boundaries respected.\n'
else
  printf '\n\033[31mArchitecture check FAILED.\033[0m See docs/ARCHITECTURE.md.\n'
fi
exit "$fail"
