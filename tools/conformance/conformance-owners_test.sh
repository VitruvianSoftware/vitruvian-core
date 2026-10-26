#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Test-the-guard for check.sh's `check_owners` arm.
#
# WHY IT EXISTS: the arm used to print "CODEOWNERS ... up to date" whenever the
# file existed. Two rows were hand-added to CODEOWNERS with no OWNERS file
# behind them (#2983, #3071) and the arm stayed green, so the next regeneration
# would have dropped both owners without anyone being told. The arm now runs
# the //tools/owners generator; these cases hold it to that.
#
# Each case builds a throwaway root (nothing is read from the real tree) and
# runs the REAL generator binary, handed to check.sh the same way a missing
# runfiles tree would be diagnosed: through CONFORMANCE_OWNERS_BIN.
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
CHECK_SH="$HERE/check.sh"
[ -f "$CHECK_SH" ] || { echo "FATAL: check.sh not found next to $0" >&2; exit 1; }

OWNERS_BIN="${TEST_SRCDIR:-}/${TEST_WORKSPACE:-_main}/tools/owners/owners"
[ -x "$OWNERS_BIN" ] || { echo "FATAL: owners generator not in runfiles at $OWNERS_BIN" >&2; exit 1; }

FAILURES=0
CASES=0
ROOTS=""

# The minimum check.sh needs to run at all, plus a small OWNERS tree and the
# CODEOWNERS the generator compiles from it.
new_root() {
  root="$(mktemp -d)"
  mkdir -p "$root/.github/workflows" \
           "$root/infrastructure/pulumi/platform/repo-config" \
           "$root/tools/conformance" \
           "$root/apps/web/site" "$root/apps/web/other"
  printf 'go 1.26.2\n' > "$root/go.work"
  printf '22\n' > "$root/.nvmrc"
  printf '{\n  "packageManager": "pnpm@10.20.0"\n}\n' > "$root/package.json"
  printf '# file\ttool\tpinned_value\treview_by\treason\n' > "$root/tools/conformance/version-pins.tsv"
  printf '{\n  enabledManagers: ["argocd"],\n}\n' > "$root/renovate.json5"
  for d in "" apps/ infrastructure/ tools/ apps/web/site/; do
    printf 'approvers:\n  - "@VitruvianSoftware/platform-team"\n' > "$root/${d}OWNERS"
  done
  "$OWNERS_BIN" --root "$root" --out .github/CODEOWNERS >/dev/null || {
    echo "FATAL: generator could not compile the fixture" >&2; exit 1; }
  ROOTS="$ROOTS $root"
  printf '%s' "$root"
}

# Only the OWNERS section, so no other arm can influence a verdict here.
owners_section() {
  printf '%s\n' "$1" | awk '
    /^OWNERS governance/ {in_s=1; next}
    in_s && /^[A-Za-z]/ && !/^ / {in_s=0}
    in_s {print}
  '
}

expect_has() {
  desc="$1"; text="$2"; want="$3"
  CASES=$((CASES + 1))
  case "$text" in
    *"$want"*) printf 'PASS  %s\n' "$desc" ;;
    *)
      printf 'FAIL  %s\n      want substring: %s\n      got section:\n%s\n' "$desc" "$want" "${text:-<no OWNERS section emitted>}"
      FAILURES=$((FAILURES + 1))
      ;;
  esac
}

expect_lacks() {
  desc="$1"; text="$2"; unwanted="$3"
  CASES=$((CASES + 1))
  case "$text" in
    *"$unwanted"*)
      printf 'FAIL  %s\n      unwanted substring: %s\n      got section:\n%s\n' "$desc" "$unwanted" "$text"
      FAILURES=$((FAILURES + 1))
      ;;
    *) printf 'PASS  %s\n' "$desc" ;;
  esac
}

# A throwaway root fails many unrelated arms (no workflows, no git), so the exit
# code alone proves nothing here. What gates CI is the fail COUNT in check.sh's
# summary line: each case below must add exactly one failure to the in-sync
# baseline, which is how a real run goes from green to red.
BASE_FAILS=""
fail_count() { printf '%s\n' "$1" | sed -n 's/.* \([0-9][0-9]*\) fail\..*/\1/p' | tail -1; }

expect_fails() {
  desc="$1"; got="$(fail_count "$2")"; want="$3"
  CASES=$((CASES + 1))
  if [ -n "$got" ] && [ "$got" = "$want" ]; then printf 'PASS  %s\n' "$desc"
  else
    printf 'FAIL  %s\n      want fail count: %s\n      got fail count:  %s\n' "$desc" "$want" "${got:-<no summary line>}"
    FAILURES=$((FAILURES + 1))
  fi
}

# Sets OUT. $2 is the generator path check.sh is told to use.
run_check() {
  OUT="$(BUILD_WORKSPACE_DIRECTORY="$1" CONFORMANCE_OWNERS_BIN="$2" NO_COLOR=1 bash "$CHECK_SH" 2>&1)"
}

# --- case 1: in sync -----------------------------------------------------------
# Also the baseline fail count the other cases are measured against.
case_in_sync() {
  root="$(new_root)"
  run_check "$root" "$OWNERS_BIN"
  sec="$(owners_section "$OUT")"
  expect_has "in-sync CODEOWNERS is reported up to date" "$sec" "up to date"
  expect_lacks "in-sync CODEOWNERS reports no drift" "$sec" "drifted"
  BASE_FAILS="$(fail_count "$OUT")"
  CASES=$((CASES + 1))
  case "$BASE_FAILS" in
    ''|*[!0-9]*) printf 'FAIL  no fail count in the summary line\n'; FAILURES=$((FAILURES + 1)); BASE_FAILS=0 ;;
    *) printf 'PASS  baseline fail count read (%s, none from the OWNERS section)\n' "$BASE_FAILS" ;;
  esac
  expect_lacks "the in-sync OWNERS section has no failing row" "$sec" "✗"
}

# --- case 2: a hand-added row (the 2026-10 defect) --------------------------------
# /apps/web/other/ has no OWNERS file. Regenerating would delete the row.
case_hand_added_row() {
  root="$(new_root)"
  printf '/apps/web/other/ @VitruvianSoftware/platform-team\n' >> "$root/.github/CODEOWNERS"
  run_check "$root" "$OWNERS_BIN"
  sec="$(owners_section "$OUT")"
  expect_has "a row with no OWNERS file behind it is drift" "$sec" "drifted"
  expect_has "the drift names the row a regeneration would drop" "$sec" "only in CODEOWNERS: /apps/web/other/ @VitruvianSoftware/platform-team"
  expect_lacks "a drifted CODEOWNERS is not also called up to date" "$sec" "up to date"
  expect_fails "a hand-added CODEOWNERS row fails the check" "$OUT" "$((BASE_FAILS + 1))"
}

# --- case 3: an OWNERS file CODEOWNERS never picked up ----------------------------
case_owners_not_compiled() {
  root="$(new_root)"
  printf 'approvers:\n  - "@VitruvianSoftware/platform-team"\n' > "$root/apps/web/other/OWNERS"
  run_check "$root" "$OWNERS_BIN"
  sec="$(owners_section "$OUT")"
  expect_has "an OWNERS file missing from CODEOWNERS is drift" "$sec" "only from OWNERS: /apps/web/other/ @VitruvianSoftware/platform-team"
  expect_fails "an uncompiled OWNERS file fails the check" "$OUT" "$((BASE_FAILS + 1))"
}

# --- case 4: an invalid OWNERS file ----------------------------------------------
case_invalid_owners() {
  root="$(new_root)"
  printf 'approvers:\n  - "not a handle!"\n' > "$root/apps/web/other/OWNERS"
  run_check "$root" "$OWNERS_BIN"
  sec="$(owners_section "$OUT")"
  expect_has "an invalid OWNERS file is reported" "$sec" "invalid"
  expect_lacks "an invalid OWNERS file is not called valid syntax" "$sec" "valid schema"
  expect_fails "an invalid OWNERS file fails the check" "$OUT" "$((BASE_FAILS + 1))"
}

# --- case 5: the generator cannot be found ---------------------------------------
# A check that could not run must not look like a check that passed.
case_generator_missing() {
  root="$(new_root)"
  run_check "$root" "$root/no-such-generator"
  sec="$(owners_section "$OUT")"
  expect_has "a missing generator is a failure, not a skip" "$sec" "not checked"
  expect_lacks "a missing generator never prints up to date" "$sec" "up to date"
  expect_fails "a missing generator fails the check" "$OUT" "$((BASE_FAILS + 1))"
}

case_in_sync
case_hand_added_row
case_owners_not_compiled
case_invalid_owners
case_generator_missing

for r in $ROOTS; do rm -rf "$r"; done

printf '\n%d assertion(s), %d failure(s)\n' "$CASES" "$FAILURES"
[ "$FAILURES" -eq 0 ]
