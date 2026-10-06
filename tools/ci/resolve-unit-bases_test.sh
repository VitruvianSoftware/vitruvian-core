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

# Tests for resolve-unit-bases.sh (#1842). Stubs only `gh`; the real script,
# the real workflow parsing and the real two-pass reduction run.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/resolve-unit-bases.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# A workflow shaped like a generated delivery-<app>.yaml: two units where one name
# is a prefix of the other, a helper job gated on NO affected_* (the changelog
# trap), and a release-gated rung that must not count as a push-lane delivery.
mkwf() {
  mkdir -p "$1/.github/workflows"
  cat > "$1/.github/workflows/wf.yaml" <<'YAML'
jobs:
  orchestrate:
    if: github.event_name == 'push'
    outputs:
      affected_app: ${{ steps.m.outputs.affected_app }}
      affected_app_identity: ${{ steps.m.outputs.affected_app_identity }}
  app-changelog:
    if: vars.X == 'true' && github.event_name == 'push'
  app-build:
    if: github.event_name == 'push' && needs.orchestrate.outputs.affected_app == 'true'
  app-development:
    if: github.event_name == 'push' && needs.orchestrate.outputs.affected_app == 'true'
  app-production:
    if: github.event_name == 'release'
  app-identity-development:
    if: github.event_name == 'push' && needs.orchestrate.outputs.affected_app_identity == 'true'
YAML
}

# gh stub. RUNS is "id sha" lines (newest first); JOBS_<id> is
# "conclusion<TAB>name" lines.
mkgh() {
  cat > "$work/gh" <<'GH'
#!/usr/bin/env bash
if [ "$1" = "run" ]; then
  wf=""; lim=1000
  while [ $# -gt 0 ]; do
    case "$1" in -w) wf="$2" ;; -L) lim="$2" ;; esac
    shift
  done
  if [ "$wf" = "legacy.yaml" ]; then
    [ "${LEGACY_RC:-0}" = "0" ] || exit 1
    printf '%s\n' "${LEGACY_RUNS:-}" | grep . | head -n "$lim"
  else
    printf '%s\n' "$RUNS" | grep . | head -n "$lim"
  fi
  exit 0
fi
if [ "$1" = "api" ]; then
  id="$(sed -n 's#.*/runs/\([0-9]*\)/jobs.*#\1#p' <<<"$2")"
  var="JOBS_${id}"; printf '%s\n' "${!var}" | awk -F'\t' '$1=="success"{print $2}'
  exit 0
fi
exit 1
GH
  chmod +x "$work/gh"
}

run_it() { # <dir> [env...] -> prints the unit_bases JSON
  local dir="$1"; shift
  ( cd "$dir" && env GH_BIN="$work/gh" REPO=o/r WORKFLOW_FILE=wf.yaml \
      WORKFLOW_PATH=.github/workflows/wf.yaml LOOKBACK=10 \
      GITHUB_OUTPUT=/dev/null "$@" bash "$SCRIPT" 2>&1 ) \
    | sed -n 's/^resolve-unit-bases: unit_bases=\(.*\) (.*/\1/p'
}

d="$work/r1"; mkwf "$d"; mkgh
# newest run: only the changelog + identity succeeded. older run: app delivered.
export RUNS='200 shaNEW
100 shaOLD'
export JOBS_200="success	app-changelog
success	app-identity-development
skipped	app-build
skipped	app-development"
export JOBS_100="success	app-build
success	app-development
success	app-identity-development"
got="$(run_it "$d")"

case "$got" in
  *'"app":"shaOLD"'*) pass "a unit's base is its laggiest rung, not the run head" ;;
  *) fail "app should pin to shaOLD, got: $got" ;;
esac
case "$got" in
  *'"app":"shaNEW"'*) fail "the changelog job advanced the unit (the trap) : $got" ;;
  *) pass "a helper job gated on no affected_* cannot advance a unit" ;;
esac
case "$got" in
  *'"app-identity":"shaNEW"'*) pass "the identity unit advances on its own delivery" ;;
  *) fail "app-identity should be shaNEW, got: $got" ;;
esac

# The prefix trap, stated as its own assertion: identity's success in the newest
# run must not have leaked into `app`.
if [ "$(printf '%s' "$got" | grep -o 'shaNEW' | wc -l | tr -d ' ')" = "1" ]; then
  pass "only the delivering unit advances (one sha appears once)"
else
  fail "prefix boundary leaked: $got"
fi

# The boundary anchor, in a shape that can actually observe it. `app`'s own
# rungs both deliver in the NEWEST run while `app-identity`'s rung last
# delivered in an OLDER one. Unanchored, `affected_app` also matches
# `affected_app_identity`, so `app` absorbs the identity rung and is dragged
# back to the older sha. The earlier scenario cannot see this: there `app` was
# already pinned old, so the leak changed nothing.
d5="$work/r5"; mkwf "$d5"
export RUNS='500 shaNEW
400 shaOLD'
export JOBS_500="success	app-build
success	app-development
skipped	app-identity-development"
export JOBS_400="success	app-identity-development"
got5="$(run_it "$d5")"
case "$got5" in
  *'"app":"shaNEW"'*) pass "affected_app does not absorb affected_app_identity (boundary observable)" ;;
  *) fail "boundary leak dragged app back: $got5" ;;
esac

# A rung with no success anywhere -> unit omitted, caller keeps today's base.
d2="$work/r2"; mkwf "$d2"
export RUNS='300 shaX'
export JOBS_300="success	app-build"
got2="$(run_it "$d2")"
case "$got2" in
  *'"app"'*) fail "app has an un-succeeded rung and must be omitted: $got2" ;;
  *) pass "a unit with an un-succeeded rung is omitted (falls back to the single base)" ;;
esac

# The per-app split: the new workflow has one run, in which `app` was skipped.
# Its last delivery happened in the legacy workflow, which must fill the window
# BEHIND the new runs so `app` keeps that older base instead of being omitted.
d6="$work/r6"; mkwf "$d6"
export RUNS='700 shaNEW'
export JOBS_700="success	app-identity-development
skipped	app-build
skipped	app-development"
export LEGACY_RUNS='600 shaLEG
550 shaOLDER'
export JOBS_600="success	app-build
success	app-development"
export JOBS_550="success	app-identity-development"
got6="$(run_it "$d6" LEGACY_WORKFLOW_FILE=legacy.yaml)"
case "$got6" in
  *'"app":"shaLEG"'*) pass "a unit last delivered by the legacy workflow keeps that base" ;;
  *) fail "app should pin to the legacy run's shaLEG, got: $got6" ;;
esac
case "$got6" in
  *'"app-identity":"shaNEW"'*) pass "the new workflow's own runs stay newest" ;;
  *) fail "app-identity should be shaNEW (new run first), got: $got6" ;;
esac
got6b="$(run_it "$d6")"
case "$got6b" in
  *'"app"'*) fail "without the legacy file, app has no success to pin to: $got6b" ;;
  *) pass "without LEGACY_WORKFLOW_FILE the legacy history is not read" ;;
esac
# The fill is capped at LOOKBACK: with LOOKBACK=1 the new run alone fills it.
got6c="$(run_it "$d6" LEGACY_WORKFLOW_FILE=legacy.yaml LOOKBACK=1)"
case "$got6c" in
  *'"app"'*) fail "the legacy fill ignored LOOKBACK: $got6c" ;;
  *) pass "the legacy fill only tops the window up to LOOKBACK" ;;
esac
# A legacy lookup failure costs only the fill.
got6d="$(run_it "$d6" LEGACY_WORKFLOW_FILE=legacy.yaml LEGACY_RC=1)"
case "$got6d" in
  *'"app-identity":"shaNEW"'*) pass "a legacy lookup failure keeps the workflow's own verdicts" ;;
  *) fail "legacy failure lost the own-run verdicts: $got6d" ;;
esac
unset LEGACY_RUNS

# Fail-open: gh unusable -> {} so the caller behaves exactly as today.
d3="$work/r3"; mkwf "$d3"
cat > "$work/gh" <<'GH'
#!/usr/bin/env bash
exit 1
GH
chmod +x "$work/gh"
got3="$(run_it "$d3")"
[ "$got3" = "{}" ] && pass "gh failure fails open to {}" || fail "expected {}, got: $got3"

# Unreadable workflow -> {} as well.
d4="$work/r4"; mkdir -p "$d4"
got4="$( ( cd "$d4" && GH_BIN="$work/gh" REPO=o/r WORKFLOW_FILE=wf.yaml \
    WORKFLOW_PATH=nope.yaml GITHUB_OUTPUT=/dev/null bash "$SCRIPT" 2>&1 ) \
  | sed -n 's/^resolve-unit-bases: unit_bases=\(.*\) (.*/\1/p')"
[ "$got4" = "{}" ] && pass "missing workflow fails open to {}" || fail "expected {}, got: $got4"

if [ "$fails" -ne 0 ]; then
  printf 'resolve-unit-bases_test: %d failure(s)\n' "$fails" >&2
  exit 1
fi
printf 'resolve-unit-bases_test: all assertions passed\n'
