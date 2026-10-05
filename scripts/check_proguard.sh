#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# R8 keep-rule guard (E-09).
#
# ML Kit creates its component registrars by reflection, through their
# no-argument constructors. R8's full mode removes those constructors unless
# a rule names them, and the receipt scanner then fails on every image in a
# release build only — debug does not run R8, so no test or analyzer sees it.
#
# This asserts the rule is still in android/app/proguard-rules.pro. The
# release-APK check in CI proves the rule took effect.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail

RULES=${1:-android/app/proguard-rules.pro}

if [ ! -f "$RULES" ]; then
  echo "::error::$RULES does not exist."
  exit 1
fi

# The class line and the constructor line, in that order, with no blank
# gap: tr joins the file into one line so grep can see both at once.
if ! tr '\n' ' ' < "$RULES" | grep -qE \
  -- '-keep class \* implements com\.google\.firebase\.components\.ComponentRegistrar \{ +<init>\(\); +\}'; then
  echo "::error file=$RULES::The ComponentRegistrar constructor keep rule is missing. Without it R8 removes ML Kit's registrar constructors and the receipt scanner fails in every release build (E-09)."
  exit 1
fi

echo "R8 keeps ML Kit's registrar constructors."
