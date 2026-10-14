#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tests for delivery-drift.sh. Stubs `gh` and `bazel` (there is no GitHub or
# Bazel in a hermetic test) but drives the REAL tools/ci/deploy-affected.sh, so
# the property under test -- "the detector and the decider agree about what
# affected means" -- is actually exercised rather than mocked away.
set -uo pipefail

SCRIPT="${1:?usage: delivery-drift_test.sh <path to delivery-drift.sh> <path to deploy-affected.sh>}"
ENGINE="${2:?missing deploy-affected.sh}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
ENGINE="$(cd "$(dirname "$ENGINE")" && pwd)/$(basename "$ENGINE")"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() {
    echo "  ✓ $1"
    pass_n=$((pass_n + 1))
}
fail() {
    echo "  ✗ $1" >&2
    fail_n=$((fail_n + 1))
}

# --- a real git repo with a real history --------------------------------------
repo="$work/repo"
mkdir -p "$repo/tools/ci" "$repo/oauth-user-inspector/app" "$repo/bazel-bin/oauth-user-inspector/infra/app"
cp "$ENGINE" "$repo/tools/ci/deploy-affected.sh"
cd "$repo" || exit 1
git init -q .
git config user.email t@t
git config user.name t
git add -A
git commit -qm "base"
BASE_SHA="$(git rev-parse HEAD)"
echo "changed" >"$repo/oauth-user-inspector/app/index.ts"
git add -A
git commit -qm "feat(oauth): a change that must deploy"
REAL_SHA="$(git rev-parse HEAD)"
# A release-please version bump on top: its artifacts match the unit's paths but
# require no deploy (the code already soaked; releases promote by TAG).
printf '{"version":"1.2.3"}\n' >"$repo/oauth-user-inspector/package.json"
printf '{".":"1.2.3"}\n' >"$repo/oauth-user-inspector/.release-please-manifest.json"
git add -A
git commit -qm "chore(main): release oauth-user-inspector 1.2.3"
RELEASE_SHA="$(git rev-parse HEAD)"
# A real commit that does NOT touch this unit's paths. Now the range
# REAL_SHA..HEAD is MIXED (a release commit + a real one), so the engine's
# guard -- which needs EVERY commit to be a bump -- correctly does not fire,
# and only a per-commit walk can tell that nothing here needed delivering.
# This is the exact shape of the first live false positive.
mkdir -p "$repo/tools/pulumi"
echo "unrelated" >"$repo/tools/pulumi/wrapper.sh"
git add -A
git commit -qm "fix(pulumi): something unrelated to this unit"
HEAD_SHA="$(git rev-parse HEAD)"

# Unit metadata, exactly the shape delivery() emits.
cat >"$repo/bazel-bin/oauth-user-inspector/infra/app/oauth-user-inspector.delivery.json" <<EOF
{"schema":1,"name":"oauth-user-inspector","app":"oauth-user-inspector","kind":"cloud-run",
 "environments":["development","nonproduction","production"],
 "extra_paths":["oauth-user-inspector/"],"exclude_paths":[],"graph_targets":[]}
EOF
# A second unit, on its own workflow, used only where STUB_LABELS names it: it
# lets one run hold a unit that is judged and one that is still delivering.
mkdir -p "$repo/bazel-bin/other/infra"
cat >"$repo/bazel-bin/other/infra/other-unit.delivery.json" <<EOF
{"schema":1,"name":"other-unit","app":"other","kind":"cloud-run",
 "environments":["development"],"extra_paths":["other/"],"exclude_paths":[],"graph_targets":[]}
EOF
OAUTH_LABEL="//oauth-user-inspector/infra/app:oauth-user-inspector.delivery_unit"
OTHER_LABEL="//other/infra:other-unit.delivery_unit"

# --- stubs --------------------------------------------------------------------
stubs="$work/stubs"
mkdir -p "$stubs"
cat >"$stubs/bazel" <<EOF
#!/usr/bin/env bash
case "\$1" in
  query) printf '%s\n' \${STUB_LABELS:-$OAUTH_LABEL} ;;
  build) exit 0 ;;
  info)  echo "$repo/bazel-bin" ;;
esac
EOF
# gh stub. It answers BOTH ways a run history can be read -- `run list` +
# one `api .../runs/<id>/jobs` per run, and `api graphql` pages of runs with
# their successful jobs -- so the same cases can be pointed at an older
# delivery-drift.sh and show it failing.
#
#   STUB_INFLIGHT        the in-flight count.
#   STUB_INFLIGHT_SEQ    one in-flight count per poll of a workflow ("1 1 0":
#                        busy for two polls, then settled; the last repeats).
#   STUB_INFLIGHT_WF     when set, the ONLY workflow with runs in flight.
#   STUB_INFLIGHT_STATUS the status of those runs (default in_progress).
#   STUB_POLL_LOG        one line per in-flight poll: "<workflow>".
#   STUB_COMPARE         the answer of the compare API (empty => it fails).
#   STUB_DELIVERED_SHA   one-run history "111 <sha>" whose dev job succeeded
#                        (empty => no successful delivery).
#   STUB_DELIVERED_WF    when set, the ONLY workflow whose history holds it.
#   STUB_RUNS            replaces that history for every workflow except
#                        delivery.yaml: "<run id> <sha>" lines, newest first.
#   STUB_LEGACY_RUNS     the history of delivery.yaml, same shape.
#   STUB_HIT_RUNS        run ids whose dev job succeeded.
#   STUB_GQL_FAIL        make every graphql call fail.
#   STUB_LOG             every workflow queried is appended here.
#   STUB_GQL_LOG         one line per graphql call: "<workflow> <after>".
cat >"$stubs/gh" <<'EOF'
#!/usr/bin/env bash
history() { # <workflow> -> "<id> <sha>" lines, newest first
  if [ "$1" = "delivery.yaml" ] && [ -n "${STUB_LEGACY_RUNS:-}" ]; then printf '%s\n' "$STUB_LEGACY_RUNS"; return; fi
  if [ -n "${STUB_RUNS:-}" ] && [ "$1" != "delivery.yaml" ]; then printf '%s\n' "$STUB_RUNS"; return; fi
  if [ -n "${STUB_RUNS:-}${STUB_LEGACY_RUNS:-}" ]; then return; fi
  if [ -n "${STUB_DELIVERED_WF:-}" ] && [ "$1" != "$STUB_DELIVERED_WF" ]; then return; fi
  [ -z "${STUB_DELIVERED_SHA:-}" ] || echo "111 ${STUB_DELIVERED_SHA}"
}
inflight_n() { # <workflow> -> the in-flight count of this poll
  if [ -n "${STUB_INFLIGHT_WF:-}" ] && [ "$1" != "$STUB_INFLIGHT_WF" ]; then echo 0; return; fi
  if [ -z "${STUB_INFLIGHT_SEQ:-}" ]; then echo "${STUB_INFLIGHT:-0}"; return; fi
  local seq i
  seq=($STUB_INFLIGHT_SEQ)
  i="$(grep -cx "$1" "${STUB_POLL_LOG:-/dev/null}" 2>/dev/null || true)"
  [ "${i:-0}" -lt "${#seq[@]}" ] || i=$((${#seq[@]} - 1))
  echo "${seq[${i:-0}]}"
}
hits=" ${STUB_HIT_RUNS:-} "
[ -z "${STUB_DELIVERED_SHA:-}" ] || hits="${hits}111 "
if [ "$1" = "run" ] && [ "$2" = "list" ]; then
  wf=""; limit=20; prev=""
  for a in "$@"; do
    [ "$prev" = "--workflow" ] && wf="$a"
    [ "$prev" = "--limit" ] && limit="$a"
    prev="$a"
  done
  echo "$wf" >> "${STUB_LOG:-/dev/null}"
  case "$*" in
    *"length"*) inflight_n "$wf"; exit 0 ;;
    *"join"*)
      n="$(inflight_n "$wf")"
      [ -z "${STUB_POLL_LOG:-}" ] || echo "$wf" >>"$STUB_POLL_LOG"
      out=""; i=0
      while [ "$i" -lt "$n" ]; do out="${out}${out:+ }${STUB_INFLIGHT_STATUS:-in_progress}"; i=$((i + 1)); done
      echo "$out"; exit 0 ;;
    *) history "$wf" | head -n "$limit"; exit 0 ;;
  esac
fi
if [ "$1" = "api" ] && [ "$2" = "graphql" ]; then
  [ -z "${STUB_GQL_FAIL:-}" ] || { echo "gh: HTTP 502" >&2; exit 1; }
  id=""; n=100; after=""
  for a in "$@"; do
    case "$a" in id=*) id="${a#id=}" ;; n=*) n="${a#n=}" ;; after=*) after="${a#after=}" ;; esac
  done
  wf="${id#WF:}"
  echo "$wf" >> "${STUB_LOG:-/dev/null}"
  echo "$wf ${after:-start}" >> "${STUB_GQL_LOG:-/dev/null}"
  history "$wf" | python3 -c '
import json, sys
n, after, hits = int(sys.argv[1]), sys.argv[2], sys.argv[3].split()
rows = [l.split() for l in sys.stdin if l.strip()]
off = int(after[1:]) if after else 0
page = rows[off:off + n]
nodes = [{"databaseId": int(rid), "checkSuite": {"branch": {"name": "main"}, "commit": {"oid": sha},
          "checkRuns": {"nodes": ([{"name": "oauth-user-inspector-development / deploy"}] if rid in hits else [])
                        + [{"name": "orchestrate"}]}}} for rid, sha in page]
more = off + n < len(rows)
print(json.dumps({"data": {"node": {"runs": {"pageInfo": {"hasNextPage": more, "endCursor": "o%d" % (off + n) if more else None}, "nodes": nodes}}}}))
' "$n" "$after" "$hits"
  exit 0
fi
if [ "$1" = "api" ]; then
  case "$2" in
    repos/*/actions/workflows/*) echo "WF:${2##*/}"; exit 0 ;;
    repos/*/compare/*) [ -n "${STUB_COMPARE:-}" ] || exit 1; echo "$STUB_COMPARE"; exit 0 ;;
  esac
  # jobs listing for one run
  for r in $hits; do
    case "$*" in *"/runs/$r/jobs"*) echo "oauth-user-inspector-development / deploy"; exit 0 ;; esac
  done
  exit 0
fi
exit 0
EOF
chmod +x "$stubs/bazel" "$stubs/gh"

# Each run also leaves its verdict for the check run in $work/result
# (conclusion=, title=) and the reader's summary in $work/summary, and one line
# per in-flight poll in $work/polls. Waits are polls with no sleep in between.
run_drift() { # <inflight> <delivered_sha> ; echoes "<rc> <stdout>"
    local out rc
    rm -f "$work/result" "$work/summary"
    : >"$work/polls"
    out="$(cd "$repo" && env PATH="$stubs:/usr/bin:/bin" \
        STUB_INFLIGHT="$1" STUB_DELIVERED_SHA="$2" STUB_POLL_LOG="$work/polls" \
        DRIFT_SETTLE_INTERVAL=0 DRIFT_RESULT_FILE="$work/result" DRIFT_SUMMARY_FILE="$work/summary" \
        REPO="o/r" bash "$SCRIPT" 2>"$work/err")"
    rc=$?
    echo "$rc ${out}"
}

# conclusion_is <want> -> true when the run left that check-run conclusion
conclusion_is() { [ -f "$work/result" ] && grep -qx "conclusion=$1" "$work/result"; }
show() { # dump what a failing case saw
    sed 's/^/      err: /' "$work/err" >&2
    [ ! -f "$work/result" ] || sed 's/^/      result: /' "$work/result" >&2
}

echo "--- drift is detected when a unit is behind main ---"
read -r rc out <<<"$(run_drift 0 "$BASE_SHA")"
if [ "$rc" -eq 1 ] && [ "$out" = "DRIFT" ] && conclusion_is failure; then
    pass "a unit whose last delivery predates an affecting commit reports DRIFT (check run failure)"
else
    fail "expected rc=1/DRIFT, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi
if grep -q 'DRIFT oauth-user-inspector' "$work/err"; then
    pass "the drift line names the unit"
else
    fail "drift report does not name the unit"
fi

echo "--- no drift when the unit already has main ---"
read -r rc out <<<"$(run_drift 0 "$HEAD_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && conclusion_is success; then
    pass "a unit delivered at main HEAD reports OK (check run success)"
else
    fail "expected rc=0/OK, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi

echo "--- release-please noise is NOT drift ---"
# Delivered the real change; only a version bump has landed since. A RANGE
# verdict says affected (the bumped package.json matches the unit's paths), but
# nothing needs deploying. This is the false positive the first live run hit.
read -r rc out <<<"$(run_drift 0 "$REAL_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ]; then
    pass "a MIXED range whose only matching files are release artifacts reports OK"
else
    fail "release noise must not be drift — got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi
if grep -q 'only version-bump commits since' "$work/err"; then
    pass "the report says WHY it is not drift (phase 2 ran and cleared it)"
else
    fail "expected the phase-2 explanation; the mixed range must reach phase 2"
    sed 's/^/      /' "$work/err" >&2
fi
# Single-commit release range: phase 1's guard clears it without a walk.
read -r rc out <<<"$(run_drift 0 "$RELEASE_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ]; then
    pass "an unrelated real commit alone is not drift for this unit"
else
    fail "unrelated commit must not be drift — got rc=$rc out='$out'"
fi

echo "--- a real commit behind a release commit is STILL drift ---"
# The dangerous inverse: do not let the version-bump exemption swallow a
# genuine miss that happens to sit behind a release commit in the range.
read -r rc out <<<"$(run_drift 0 "$BASE_SHA")"
if [ "$rc" -eq 1 ] && [ "$out" = "DRIFT" ]; then
    pass "a genuine miss is still caught in a mixed range"
else
    fail "mixed range must still report the real miss — got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi
if grep -q 'should have delivered and did not' "$work/err"; then
    pass "the drift line names the culprit commit"
else
    fail "drift line does not name the culprit commit"
fi

echo "--- a run that checked nothing is NEUTRAL, not a pass ---"
# Every unit's workflow stays busy through the whole wait. Nothing was judged,
# so the verdict must not look like "everything delivered".
read -r rc out <<<"$(DRIFT_SETTLE_POLLS=3 run_drift 2 "$BASE_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "NOTHING_CHECKED" ] && conclusion_is neutral; then
    pass "all units in flight => NOTHING_CHECKED, check run neutral (rc=$rc)"
else
    fail "expected rc=0/NOTHING_CHECKED/neutral, got rc=$rc out='$out'"
    show
fi
if grep -q 'Nothing checked' "$work/result" 2>/dev/null && grep -q 'oauth-user-inspector' "$work/summary" 2>/dev/null &&
    grep -q 'still in flight after waiting' "$work/summary"; then
    pass "the title says nothing was checked, and the summary names the skipped unit and why"
else
    fail "expected a 'Nothing checked' title and the skipped unit named in the summary"
    show
fi
if [ "$(grep -c . "$work/polls")" -eq 4 ]; then
    pass "it polled once, then waited the full 3 extra polls before giving up"
else
    fail "expected 4 in-flight polls (1 + DRIFT_SETTLE_POLLS=3), got $(grep -c . "$work/polls")"
fi
if ! grep -q 'should have delivered and did not' "$work/err"; then
    pass "mid-convergence is not reported as drift"
else
    fail "an in-flight unit was judged"
fi

echo "--- a run that settles within the wait is judged normally ---"
read -r rc out <<<"$(STUB_INFLIGHT_SEQ="1 1 0" run_drift 0 "$BASE_SHA")"
if [ "$rc" -eq 1 ] && [ "$out" = "DRIFT" ] && conclusion_is failure && [ "$(grep -c . "$work/polls")" -eq 3 ]; then
    pass "busy for two polls, then settled: the unit is judged (DRIFT), after exactly 3 polls"
else
    fail "expected DRIFT after 3 polls, got rc=$rc out='$out' polls=$(grep -c . "$work/polls")"
    show
fi
read -r rc out <<<"$(STUB_INFLIGHT_SEQ="1 0" run_drift 0 "$HEAD_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && conclusion_is success; then
    pass "settled and delivered => OK, check run success"
else
    fail "expected OK/success after settling, got rc=$rc out='$out'"
    show
fi

echo "--- a run parked on an approval is not waited for ---"
# A human gate can hold a run for days; polling it for 15 minutes every hour
# only burns a runner. It still counts as in flight.
read -r rc out <<<"$(STUB_INFLIGHT_STATUS=waiting run_drift 1 "$BASE_SHA")"
if [ "$out" = "NOTHING_CHECKED" ] && conclusion_is neutral && [ "$(grep -c . "$work/polls")" -eq 1 ] &&
    grep -q 'waiting on an approval' "$work/summary" 2>/dev/null; then
    pass "a waiting run is polled once, skipped with its reason, verdict neutral"
else
    fail "expected one poll and a neutral verdict for a waiting run, got out='$out' polls=$(grep -c . "$work/polls")"
    show
fi

echo "--- some checked, some still in flight: success, naming the skipped ---"
read -r rc out <<<"$(STUB_LABELS="$OAUTH_LABEL $OTHER_LABEL" STUB_INFLIGHT_WF=delivery-other.yaml DRIFT_SETTLE_POLLS=2 run_drift 1 "$HEAD_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && conclusion_is success; then
    pass "one unit judged and delivered, one still delivering => OK, check run success"
else
    fail "expected OK/success with one unit skipped, got rc=$rc out='$out'"
    show
fi
if grep -q 'other-unit' "$work/summary" 2>/dev/null && grep -q '1 not checked' "$work/result" 2>/dev/null &&
    ! grep -q 'other-unit: up to date' "$work/err"; then
    pass "the skipped unit is named in the summary and counted in the title"
else
    fail "expected other-unit named as skipped"
    show
fi
if grep -qx 'delivery-other.yaml' "$work/polls" && [ "$(grep -cx 'delivery-oauth-user-inspector.yaml' "$work/polls")" -eq 1 ]; then
    pass "only the busy workflow is polled again; the settled one is polled once"
else
    fail "expected the settled workflow polled once, got: $(tr '\n' ' ' <"$work/polls")"
fi

echo "--- a delivery newer than this check's checkout is current, not UNKNOWN ---"
# While the check waits, main moves on and a newer run delivers a commit this
# checkout does not have. GitHub's compare says it contains HEAD.
NEWER_SHA=1234567890abcdef1234567890abcdef12345678
read -r rc out <<<"$(STUB_RUNS="700 ${NEWER_SHA}" STUB_HIT_RUNS="700" STUB_COMPARE=ahead run_drift 0 "")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && grep -q 'up to date (delivered 12345678, newer than' "$work/err"; then
    pass "a delivery of a newer commit that contains HEAD is up to date"
else
    fail "expected OK for a newer delivered commit, got rc=$rc out='$out'"
    show
fi
read -r rc out <<<"$(STUB_RUNS="700 ${NEWER_SHA}" STUB_HIT_RUNS="700" STUB_COMPARE="" run_drift 0 "")"
if [ "$rc" -eq 1 ] && conclusion_is failure && grep -q 'UNKNOWN' "$work/err"; then
    pass "if GitHub cannot say how it relates to HEAD, it stays UNKNOWN (red)"
else
    fail "expected UNKNOWN when the compare read fails, got rc=$rc out='$out'"
    show
fi

echo "--- each unit is read from its own app's workflow ---"
log="$work/gh.log"; : >"$log"
read -r rc out <<<"$(STUB_LOG="$log" run_drift 0 "$HEAD_SHA")"
if grep -qx 'delivery-oauth-user-inspector.yaml' "$log" && ! grep -qx 'delivery.yaml' "$log"; then
    pass "the unit's history is read from delivery-<app>.yaml, and the legacy one is not needed"
else
    fail "expected only delivery-oauth-user-inspector.yaml queried, got: $(tr '\n' ' ' <"$log")"
fi

echo "--- a unit last delivered before the per-app split ---"
read -r rc out <<<"$(STUB_DELIVERED_WF=delivery.yaml run_drift 0 "$HEAD_SHA")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && grep -q 'last delivered by delivery.yaml' "$work/err"; then
    pass "a delivery found only in the legacy delivery.yaml counts (not UNKNOWN)"
else
    fail "expected OK from the legacy history, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi
read -r rc out <<<"$(STUB_DELIVERED_WF=delivery.yaml LEGACY_WORKFLOW_FILE='' run_drift 0 "$HEAD_SHA")"
if [ "$rc" -eq 1 ]; then
    pass "with the legacy fallback disabled, that unit is UNKNOWN"
else
    fail "expected rc=1 with LEGACY_WORKFLOW_FILE empty, got rc=$rc out='$out'"
fi

echo "--- the newest delivery wins ---"
# 20 runs, newest first, all in one page. Runs 1010 and 1013 both delivered;
# 1010 is newer, so its sha must be the answer.
runs=""
for n in $(seq 1001 1020); do
    sha="$BASE_SHA"
    [ "$n" -eq 1010 ] && sha="$HEAD_SHA"
    runs="${runs}${runs:+
}${n} ${sha}"
done
read -r rc out <<<"$(STUB_RUNS="$runs" STUB_HIT_RUNS="1013 1010" run_drift 0 "")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && grep -q "up to date (delivered ${HEAD_SHA:0:8})" "$work/err"; then
    pass "the newest successful run is used, not an older one from the same page"
else
    fail "expected the run-1010 delivery (HEAD) to win, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi

echo "--- a long history costs one query per page of runs, not one per run ---"
# The scheduled job once hit its 20-minute limit asking for each run's jobs
# one API call at a time. 20 runs fit in one page: one query, whatever the
# history holds.
gql="$work/gql.log"; : >"$gql"
read -r rc out <<<"$(STUB_GQL_LOG="$gql" STUB_RUNS="$runs" STUB_HIT_RUNS="1020" run_drift 0 "")"
if [ "$(grep -c . "$gql")" -eq 1 ]; then
    pass "20 runs were read with 1 query"
else
    fail "expected 1 graphql query for 20 runs, got $(grep -c . "$gql"): $(tr '\n' ' ' <"$gql")"
fi

# A history longer than any fixed window: 300 runs of the unit's own workflow,
# and the unit's only delivery there is run 1020, the 281st newest -- past the
# 250 runs the checker used to read. The legacy delivery.yaml holds an OLDER
# delivery at BASE_SHA. Reading only a window misses run 1020, falls back to
# the legacy history and blames a commit that WAS delivered: the shape of the
# charts and esp32-s3 false alarms of 2026-10-11..14.
long_runs=""
for n in $(seq 1001 1300); do
    sha="$BASE_SHA"
    [ "$n" -ge 1020 ] && sha="$HEAD_SHA"
    long_runs="${long_runs}${long_runs:+
}${n} ${sha}"
done
long_runs="$(printf '%s\n' "$long_runs" | sort -rn)" # newest first
legacy_runs="900 ${BASE_SHA}"

echo "--- a delivery older than any fixed window is still found ---"
read -r rc out <<<"$(STUB_RUNS="$long_runs" STUB_LEGACY_RUNS="$legacy_runs" STUB_HIT_RUNS="1020 900" run_drift 0 "")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && grep -q "up to date (delivered ${HEAD_SHA:0:8})" "$work/err"; then
    pass "the delivery 281 runs back is found and the unit is up to date"
else
    fail "expected OK from run 1020 (HEAD), got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi
if grep -q 'should have delivered and did not' "$work/err" || grep -q 'last delivered by delivery.yaml' "$work/err"; then
    fail "a delivered commit was blamed, or the legacy history was consulted while the unit's own history held a delivery"
else
    pass "no commit is blamed and the legacy history is not consulted"
fi
# Same history, but the delivery is of REAL_SHA: the release commit after it
# is not drift, and the real commit before it is not blamed.
long_real="$(printf '%s\n' "$long_runs" | sed "s/${HEAD_SHA}/${REAL_SHA}/")"
read -r rc out <<<"$(STUB_RUNS="$long_real" STUB_LEGACY_RUNS="$legacy_runs" STUB_HIT_RUNS="1020 900" run_drift 0 "")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && grep -q "delivered ${REAL_SHA:0:8}" "$work/err"; then
    pass "an old delivery followed only by a release bump reports OK"
else
    fail "expected OK from run 1020 (REAL_SHA), got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi

echo "--- the legacy history is used only once the unit's own is exhausted ---"
# 300 runs of the unit's own workflow, none delivered it; the legacy history
# delivered HEAD. Every page of the unit's own workflow must be read first.
gql="$work/gql.log"; : >"$gql"
read -r rc out <<<"$(STUB_GQL_LOG="$gql" STUB_RUNS="$long_runs" STUB_LEGACY_RUNS="900 ${HEAD_SHA}" STUB_HIT_RUNS="900" run_drift 0 "")"
if [ "$rc" -eq 0 ] && [ "$out" = "OK" ] && grep -q 'last delivered by delivery.yaml' "$work/err"; then
    pass "a unit never delivered by its own workflow falls back to delivery.yaml"
else
    fail "expected OK from the legacy history, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi
if [ "$(grep -c '^delivery-oauth-user-inspector.yaml ' "$gql")" -eq 3 ]; then
    pass "all 3 pages of the unit's own workflow were read before falling back"
else
    fail "expected 3 pages of delivery-oauth-user-inspector.yaml, got: $(tr '\n' ' ' <"$gql")"
fi

echo "--- a commit that really was not delivered is still DRIFT ---"
# The long history again, but its delivery (run 1020) is of BASE_SHA. REAL_SHA
# came after and touches the unit: a genuine miss, however old the delivery.
long_base="$(printf '%s\n' "$long_runs" | sed "s/${HEAD_SHA}/${BASE_SHA}/")"
read -r rc out <<<"$(STUB_RUNS="$long_base" STUB_LEGACY_RUNS="900 ${HEAD_SHA}" STUB_HIT_RUNS="1020 900" run_drift 0 "")"
if [ "$rc" -eq 1 ] && [ "$out" = "DRIFT" ] && grep -q "DRIFT oauth-user-inspector: last delivered ${BASE_SHA:0:8}, but ${REAL_SHA:0:8}" "$work/err"; then
    pass "the undelivered commit is named, with the old delivery as its base"
else
    fail "expected DRIFT blaming ${REAL_SHA:0:8}, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi

echo "--- a history longer than the scan limit is UNKNOWN, not a fallback ---"
read -r rc out <<<"$(RUN_SCAN_LIMIT=200 STUB_RUNS="$long_runs" STUB_LEGACY_RUNS="900 ${HEAD_SHA}" STUB_HIT_RUNS="1020 900" run_drift 0 "")"
if [ "$rc" -eq 1 ] && grep -q 'UNKNOWN' "$work/err" && ! grep -q 'last delivered by delivery.yaml' "$work/err"; then
    pass "an unfinished search reports UNKNOWN and does not consult the legacy history"
else
    fail "expected rc=1/UNKNOWN without the legacy fallback, got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi

echo "--- an API failure is UNKNOWN, not a fallback and not green ---"
read -r rc out <<<"$(STUB_GQL_FAIL=1 STUB_DELIVERED_WF=delivery.yaml run_drift 0 "$HEAD_SHA")"
if [ "$rc" -eq 1 ] && conclusion_is failure && grep -q 'could not read' "$work/err" && ! grep -q 'last delivered by delivery.yaml' "$work/err"; then
    pass "a failed history read is reported, and nothing is inferred from it"
else
    fail "expected rc=1 'could not read', got rc=$rc out='$out'"
    sed 's/^/      /' "$work/err" >&2
fi

echo "--- an unknown delivery state is NOT treated as healthy ---"
read -r rc out <<<"$(run_drift 0 "")"
if [ "$rc" -eq 1 ] && conclusion_is failure; then
    pass "no successful delivery found => reported, not silently OK (rc=$rc, check run failure)"
else
    fail "expected rc=1 for unknown state, got rc=$rc out='$out'"
fi

echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n"
    exit 1
fi
echo "ALL PASS ($pass_n)"
