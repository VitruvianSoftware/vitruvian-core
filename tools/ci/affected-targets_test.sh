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

# Hermetic guard for tools/ci/deploy-affected.sh. Uses a REAL temp git repo
# Hermetic guard for the planning half of tools/ci/affected-targets.sh (#2841).
# Uses a REAL temp git repo (the script diffs it) and a fake `bazel` on PATH
# that replays a canned plan and records every invocation. Pins:
#   - the dependency map is handed to the planner when the workflow restored one;
#   - a map-sourced plan tests every test in the changed packages at HEAD, so a
#     test the change adds is run and one it deletes is not asked for;
#   - a live-query plan is run exactly as before;
#   - "no tests found" on a map-sourced plan full-sweeps, like an empty live plan.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/affected-targets.sh"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

repo="$work/repo"
mkdir -p "$repo/apps/a"
git -C "$repo" init -q -b main
git -C "$repo" config user.email test@example.com
git -C "$repo" config user.name test
echo one > "$repo/apps/a/a.go"
git -C "$repo" add . && git -C "$repo" commit -q -m base
base="$(git -C "$repo" rev-parse HEAD)"
echo two > "$repo/apps/a/a.go"
git -C "$repo" commit -q -am change

# Fake bazel: `run` prints $FAKE_PLAN (and $FAKE_PLAN_STDERR on stderr);
# `test` exits $FAKE_TEST_RC; everything is appended to $CALLS.
mkdir -p "$work/bin"
cat > "$work/bin/bazel" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$CALLS"
case "$1" in
  run) [ -n "${FAKE_PLAN_STDERR:-}" ] && echo "${FAKE_PLAN_STDERR}" >&2; printf '%s' "${FAKE_PLAN:-}" ;;
  test) case "$*" in *'//...'*) exit 0 ;; *) exit "${FAKE_TEST_RC:-0}" ;; esac ;;
esac
exit 0
FAKE
chmod +x "$work/bin/bazel"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s\n' "$1" >&2; fails=$((fails + 1)); }

# run_case <plan-json> [VAR=value ...] -- runs the script against the temp repo;
# leaves the recorded bazel calls in $CALLS, its output in $out, its status in $rc.
run_case() {
  local plan="$1"; shift
  export CALLS="$work/calls"; : > "$CALLS"
  out="$(cd "$repo" && env PATH="$work/bin:$PATH" BUILDBUDDY_API_KEY=k BEFORE_REV="$base" \
    FAKE_PLAN="$plan" "$@" bash "$SCRIPT" 2>&1)"
  rc=$?
}
called() { grep -qF -- "$1" "$CALLS"; }

map_plan='{"plan_source":"rdeps-map","affected_packages":["//apps/a:all"],"targets":["//apps/a:gone_test","//apps/a/sub:sub_test","//libs/b:b_test"]}'
live_plan='{"plan_source":"live-query","affected_packages":["//apps/a:all"],"targets":["//apps/a:a_test","//libs/b:b_test"]}'

echo "dependency map handed to the planner"
run_case "$map_plan" RDEPS_MAP="$work/map.json"
called "run //tools/pipeline:plan -- --base=$base --head=HEAD --format=json --rdeps-map=$work/map.json" \
  && pass "--rdeps-map passed when RDEPS_MAP is set" || fail "--rdeps-map not passed: $(cat "$CALLS")"
run_case "$live_plan"
grep -F 'run //tools/pipeline:plan' "$CALLS" | grep -qF -- '--rdeps-map' \
  && fail "--rdeps-map passed without RDEPS_MAP" || pass "no --rdeps-map when RDEPS_MAP is unset"

echo "map-sourced plan"
run_case "$map_plan" RDEPS_MAP="$work/map.json"
t="$(grep '^test ' "$CALLS")"
[ "$rc" -eq 0 ] && pass "exits 0" || fail "exit $rc: $out"
case "$t" in *' --build_tests_only '*'//apps/a:all'*) pass "changed package tested as //apps/a:all with --build_tests_only" ;; *) fail "missing package pattern: $t" ;; esac
case "$t" in *'//apps/a:gone_test'*) fail "still asks for a base-commit label in a changed package: $t" ;; *) pass "base-commit label in the changed package dropped" ;; esac
case "$t" in *'//apps/a/sub:sub_test'*'//libs/b:b_test'*) pass "labels outside the changed package kept (subpackage included)" ;; *) fail "lost an unchanged-package label: $t" ;; esac
case "$out" in *'source: rdeps-map'*) pass "logs the plan source and duration" ;; *) fail "no plan-source line: $out" ;; esac

echo "live-query plan is unchanged"
run_case "$live_plan" FAKE_PLAN_STDERR="no dependency map for this diff base; falling back to the live query"
t="$(grep '^test ' "$CALLS")"
case "$t" in *build_tests_only*|*':all'*) fail "live plan was rewritten: $t" ;; *'//apps/a:a_test //libs/b:b_test') pass "exact labels, no extra flags" ;; *) fail "unexpected: $t" ;; esac
case "$out" in *'no dependency map for this diff base'*) pass "planner's fallback reason is shown" ;; *) fail "fallback reason hidden: $out" ;; esac

echo "failures and fallbacks"
run_case "$map_plan" FAKE_TEST_RC=3
[ "$rc" -eq 3 ] && pass "a failing test still fails the job" || fail "exit $rc, want 3"
run_case "$map_plan" FAKE_TEST_RC=4
{ [ "$rc" -eq 0 ] && called 'build --config=remote' && grep -q '^test .*//\.\.\.$' "$CALLS"; } \
  && pass "no tests found on a map plan -> full //... sweep" || fail "exit $rc; calls: $(cat "$CALLS")"
run_case "$live_plan" FAKE_TEST_RC=4
[ "$rc" -eq 4 ] && pass "exit 4 on a live plan is passed through as before" || fail "exit $rc, want 4"
run_case "" FAKE_PLAN_STDERR="planner exploded"
{ grep -q '^test .*//\.\.\.$' "$CALLS" && case "$out" in *'planner exploded'*) true ;; *) false ;; esac; } \
  && pass "no plan -> full sweep, with the planner's error shown" || fail "calls: $(cat "$CALLS") out: $out"
run_case "$map_plan" PLAN_BUDGET_SEC=-1
case "$out" in *'title=affected-selection-slow'*) pass "over-budget map plan warns" ;; *) fail "no slow warning: $out" ;; esac
run_case "$map_plan"
case "$out" in *'affected-selection-slow'*) fail "warned within budget" ;; *) pass "within budget: no warning" ;; esac

echo
if [ "$fails" -gt 0 ]; then echo "$fails check(s) FAILED" >&2; exit 1; fi
echo "all affected-targets checks passed"
