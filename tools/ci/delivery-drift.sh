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

# delivery-drift.sh — report delivery units whose last successful delivery is
# BEHIND main, i.e. work that should have shipped and did not.
#
# WHY THIS EXISTS (#1842). A skipped delivery and a correct skip look IDENTICAL
# in the runs list: both are green, both say affected=false. Nothing goes red.
# So "watch the runs" cannot detect the failure mode we actually fear, and the
# durable base makes it permanent -- once a run concludes success its head
# becomes the base, and every commit behind it leaves the diff window forever.
# We have already shipped one bug of exactly this shape (#1840: a release-bump
# HEAD dismissed a 9-commit range).
#
# THE INVARIANT, stated so it can be FALSIFIED: for every delivery unit, the
# commit last delivered to its first environment should leave that unit
# unaffected relative to main. If a unit IS affected by the diff between what it
# last shipped and main, then either a delivery is in flight or one was skipped.
#
# HOW IT STAYS HONEST: affectedness is not reimplemented here. This shells the
# SAME tools/ci/deploy-affected.sh that the orchestrator shells, with the same
# per-unit metadata, so the detector can never disagree with the decider about
# what "affected" means. The one input it derives independently is the base: a
# PER-UNIT last-delivered commit taken from run history, rather than the
# orchestrator's single global base. That difference is the entire point --
# it is what a base that advanced too far cannot hide.
#
# WHAT IT DOES NOT CHECK: live cloud state. A unit whose deploy job reported
# success but silently no-op'd looks delivered here. Verifying the deployed
# artifact against the intended one needs per-environment cloud credentials and
# is the stronger v2; this v1 needs no cloud auth at all.
#
# WHICH HISTORY: each app delivers through its own generated workflow,
# .github/workflows/delivery-<app>.yaml, named by the unit's `app`. Before the
# per-app split every unit delivered through one delivery.yaml, so a unit with
# no success in its own workflow is looked up there (LEGACY_WORKFLOW_FILE)
# rather than reported UNKNOWN for a delivery that did happen -- but only once
# its own workflow's WHOLE history has been read. Falling back earlier finds the
# pre-split delivery and blames the commit that the new workflow did deliver.
#
#
# WHICH COMMIT IS JUDGED. Every app's delivery workflow starts on every push
# to main, so on a busy day some run of it is nearly always in flight. A unit is
# therefore judged against the head commit of the newest push run of its
# workflow that has FINISHED (the "judged commit"), not against main's tip:
# that run has already decided, for every commit up to it, whether this unit
# needed delivering. Commits newer than it are still being delivered and are
# left to a later check. Nothing waits (#3280 waited up to 15 minutes for the
# workflows to go idle, and on a busy day they never did).
#   - A run the next push cancelled (its concurrency group hands the commit
#     range to the newer run) is not evidence either way: it is passed over,
#     and the newest finished run before it is used. Once the run that
#     superseded it finishes, that run is the judged commit and covers it.
#   - A run that finished with a failure IS evidence: what it did not deliver
#     is reported, never hidden behind an older success.
#   - A run parked waiting on an approval (an environment gate) leaves its
#     units not checked.
#
# THE VERDICT has three values, and the workflow publishes it as a check run
# named "delivery-drift verdict" on the commit it checked:
#   OK              conclusion success: at least one unit was judged and none
#                   is behind. Units that were skipped are named in the summary.
#   NOTHING_CHECKED conclusion neutral: every unit was skipped. Not a pass.
#   DRIFT           conclusion failure: a unit is behind its judged commit, or
#                   its state is UNKNOWN (a failed read is never a pass).
#
# Exit codes: 0 = OK or NOTHING_CHECKED, 1 = DRIFT or UNKNOWN, 2 = usage/setup
# error (no verdict written). Env: REPO (owner/name), WORKFLOW_FILE (overrides
# every unit's delivery-<app>.yaml with one workflow), LEGACY_WORKFLOW_FILE
# (default delivery.yaml; empty disables the fallback), BRANCH (default main),
# RUN_SCAN_LIMIT (default 5000 runs per workflow), DRIFT_RECENT_RUNS (default
# 50: how many of a workflow's newest push runs are searched for a finished
# one), DRIFT_RESULT_FILE (appends conclusion=/title=/checked=/skipped= lines,
# e.g. $GITHUB_OUTPUT), DRIFT_SUMMARY_FILE (writes a Markdown summary for the
# check run), DRIFT_IGNORE_IN_FLIGHT (set to any value to judge every unit
# against main's tip whatever its workflow is doing -- for an operator
# investigating, never for the scheduled job, which would then report drift on
# every normal deploy).
set -euo pipefail

REPO="${REPO:-VitruvianSoftware/vitruvian-core}"
WORKFLOW_FILE="${WORKFLOW_FILE:-}"
LEGACY_WORKFLOW_FILE="${LEGACY_WORKFLOW_FILE-delivery.yaml}"
BRANCH="${BRANCH:-main}"
# How far back to look for a unit's last delivery, in runs of one workflow.
# A FIXED WINDOW IS THE BUG THIS USED TO HAVE, twice. Every per-app workflow runs
# on every push to main (about 55 a day) and skips its delivery jobs on almost
# all of them, so a unit that rarely changes ages out of any window. At 60,
# three tabula/oauth units went UNKNOWN; at 250, charts and esp32-s3 (last
# delivered 409 runs back, at e60ed8dc) fell through to the legacy history,
# whose pre-split delivery made the checker blame e60ed8dc -- a commit that WAS
# delivered -- every hour from 2026-10-11 to 10-14, and gravastar-mouse-publish
# went UNKNOWN. So the whole history is read now, 100 runs per query; this is
# only the backstop that keeps one run's cost bounded. At ~55 runs a day, 5000
# runs is about three months: a unit with no delivery in that long reports
# UNKNOWN (and says so), never a guessed base.
RUN_SCAN_LIMIT="${RUN_SCAN_LIMIT:-5000}"
# Runs per query. 100 is the API's maximum; the test makes it small.
DRIFT_PAGE_SIZE="${DRIFT_PAGE_SIZE:-100}"
BAZEL="${BAZEL:-bazel}"
GH="${GH:-gh}"
DELIVERY_QUERY='attr(tags, "\bdelivery\b", (//... except //apps/desktop/nexus-agent/macos/...))'

# How many of a workflow's newest push runs to search for a finished one. One
# API call whatever the value; at ~55 pushes a day a run finishing every few
# minutes, 50 is more than a day's worth of runs.
DRIFT_RECENT_RUNS="${DRIFT_RECENT_RUNS:-50}"
log() { echo "delivery-drift: $*" >&2; }

command -v "$GH" >/dev/null 2>&1 || {
    log "gh not found on PATH"
    exit 2
}

# --- 1. discover the declared units -------------------------------------------
# Identical query + metadata path convention to the orchestrator, so the two
# always see the same set of units.
LABELS="$("$BAZEL" query "$DELIVERY_QUERY" --output=label 2>/dev/null || true)"
if [ -z "$LABELS" ]; then
    log "no delivery units declared (or bazel query failed) -- nothing to check"
    exit 2
fi
# shellcheck disable=SC2086
"$BAZEL" build $LABELS >/dev/null 2>&1 || {
    log "bazel build of delivery metadata failed"
    exit 2
}
BIN_DIR="$("$BAZEL" info bazel-bin 2>/dev/null)"

# --- run history, a page at a time ------------------------------------------
# One GraphQL query returns up to 100 runs of a workflow, newest first, each
# with the names of its jobs that succeeded. The REST way is one call per run
# for its jobs (plus the run list, which also stops at 1000 runs when filtered
# by branch): reading 409 runs that way took minutes and, run on a schedule,
# would grow without bound. This reads the same 409 in 5 queries.
#
# Pages are kept per workflow for the length of one check, so units that share
# a workflow (five tabula units, three oauth-user-inspector ones) share the
# reads, and the WORST CASE per check is bounded per workflow, not per unit:
# ceil(RUN_SCAN_LIMIT / 100) queries + 1 id lookup for each delivery-<app>.yaml
# and for delivery.yaml -- with today's 7 that is at most 7 x 51 = 357 calls,
# against a typical ~20. Plus one `run list` of recent runs per workflow.
PAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$PAGE_DIR"' EXIT
# shellcheck disable=SC2016 # GraphQL variables, not shell ones
RUNS_QUERY='query($id: ID!, $n: Int!, $after: String) {
  node(id: $id) { ... on Workflow { runs(first: $n, after: $after) {
    pageInfo { hasNextPage endCursor }
    nodes { databaseId checkSuite { branch { name } commit { oid }
      checkRuns(first: 100, filterBy: {conclusions: [SUCCESS]}) { nodes { name } } } } } } } }'

# fetch_page <workflow-file> <page> -> writes $PAGE_DIR/<workflow-file>.<page>:
#   run<TAB><run id><TAB><head sha><TAB><branch><TAB><job>\037<job>...
#   next<TAB><cursor of the next page, empty on the last page>
# Fails (non-zero, no file) on any API or parse error.
fetch_page() {
    local wf="$1" page="$2" f="$PAGE_DIR/$1.$2" after="" raw
    [ ! -s "$f" ] || return 0
    if [ ! -s "$PAGE_DIR/$wf.id" ]; then
        "$GH" api "repos/${REPO}/actions/workflows/${wf}" --jq .node_id >"$PAGE_DIR/$wf.id" 2>/dev/null || return 1
        [ -s "$PAGE_DIR/$wf.id" ] || return 1
    fi
    if [ "$page" -gt 1 ]; then
        after="$(awk -F'\t' '$1 == "next" { print $2 }' "$PAGE_DIR/$wf.$((page - 1))")"
    fi
    local -a args=(api graphql -f query="$RUNS_QUERY" -f id="$(cat "$PAGE_DIR/$wf.id")" -F n="$DRIFT_PAGE_SIZE")
    [ -z "$after" ] || args+=(-f after="$after")
    raw="$("$GH" "${args[@]}" 2>/dev/null)" || return 1
    printf '%s' "$raw" | python3 -c '
import json, sys
d = json.load(sys.stdin)
if d.get("errors"):
    sys.exit(1)
runs = d["data"]["node"]["runs"]
for r in runs["nodes"]:
    cs = r.get("checkSuite") or {}
    jobs = [c["name"] for c in ((cs.get("checkRuns") or {}).get("nodes") or [])]
    print("run\t%s\t%s\t%s\t%s" % (r["databaseId"], (cs.get("commit") or {}).get("oid") or "",
                                   (cs.get("branch") or {}).get("name") or "", "\037".join(jobs)))
print("next\t%s" % (runs["pageInfo"]["endCursor"] if runs["pageInfo"]["hasNextPage"] else ""))
' >"$f.part" 2>/dev/null || {
        rm -f "$f.part"
        return 1
    }
    mv "$f.part" "$f"
}

# last_delivered <workflow-file> <job-prefix> -> sets
#   LD_SHA    head sha of the newest $BRANCH run in which a job named
#             <job-prefix>* succeeded (Cloud Run units call a reusable
#             workflow, so their job shows as "<unit>-<env> / <inner job>").
#   LD_STATE  found | absent (the WHOLE history was read and has none) |
#             capped (RUN_SCAN_LIMIT runs read, history goes on) | error.
#   LD_RUNS   how many runs were read.
# Only `absent` licenses looking anywhere else.
last_delivered() {
    local wf="$1" prefix="$2" page=1 f hit
    local max_pages=$(((RUN_SCAN_LIMIT + DRIFT_PAGE_SIZE - 1) / DRIFT_PAGE_SIZE))
    LD_SHA=""
    LD_STATE=""
    LD_RUNS=0
    while :; do
        if ! fetch_page "$wf" "$page"; then
            LD_STATE=error
            return 0
        fi
        f="$PAGE_DIR/$wf.$page"
        hit="$(awk -F'\t' -v b="$BRANCH" -v p="$prefix" '
            $1 == "run" && $4 == b {
                n = split($5, jobs, "\037")
                for (i = 1; i <= n; i++) if (index(jobs[i], p) == 1) { print $3; exit }
            }' "$f")"
        LD_RUNS=$((LD_RUNS + $(awk -F'\t' '$1 == "run" { n++ } END { print n + 0 }' "$f")))
        if [ -n "$hit" ]; then
            LD_SHA="$hit"
            LD_STATE=found
            return 0
        fi
        if [ -z "$(awk -F'\t' '$1 == "next" { print $2 }' "$f")" ]; then
            LD_STATE=absent
            return 0
        fi
        if [ "$page" -ge "$max_pages" ]; then
            LD_STATE=capped
            return 0
        fi
        page=$((page + 1))
    done
}

# why_unknown <name> <env> <workflow-file> -> the log line for a non-`found` LD_STATE
why_unknown() {
    case "$LD_STATE" in
    error) log "${1}: could not read the run history of ${3} -- UNKNOWN (nothing inferred from a failed read)" ;;
    capped) log "${1}: no successful ${2} delivery in the newest ${LD_RUNS} runs of ${3}, and its history goes back further (RUN_SCAN_LIMIT=${RUN_SCAN_LIMIT}) -- UNKNOWN" ;;
    *) log "${1}: no successful ${2} delivery in the whole history of ${3} (${LD_RUNS} runs) -- UNKNOWN" ;;
    esac
}

# --- 2. resolve each unit's workflow -------------------------------------------
HEAD_SHA="$(git rev-parse HEAD)"
drift_found=0
bad=0
checked=0
skipped=0
nl=$'\n'
CHECKED_MD=""
SKIPPED_MD=""
SKIPPED_NAMES=""
# judged <unit> <verdict>: the unit was given a verdict.
judged() {
    checked=$((checked + 1))
    CHECKED_MD="${CHECKED_MD}- \`${1}\`: ${2}${nl}"
}
# failed <unit> <verdict>: judged, and the verdict is DRIFT or UNKNOWN.
failed() {
    judged "$1" "**${2}**"
    bad=$((bad + 1))
    drift_found=1
}
# skip <unit> <why>: the unit was not judged at all.
skip() {
    skipped=$((skipped + 1))
    SKIPPED_MD="${SKIPPED_MD}- \`${1}\`: ${2}${nl}"
    SKIPPED_NAMES="${SKIPPED_NAMES}${SKIPPED_NAMES:+, }${1}"
}

UNITS="$PAGE_DIR/units.tsv"
: >"$UNITS"
for label in $LABELS; do
    # //pkg/sub:x.delivery_unit -> pkg/sub/x.delivery.json
    rel="${label#@@}"
    rel="${rel#@}"
    rel="${rel#//}"
    pkg="${rel%%:*}"
    tgt="${rel#*:}"
    meta="${BIN_DIR}/${pkg}/${tgt%.delivery_unit}.delivery.json"
    [ -f "$meta" ] || {
        log "metadata missing for ${label} -- cannot check, treating as UNKNOWN"
        failed "$label" "UNKNOWN: its metadata is missing"
        continue
    }

    name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$meta")"
    first_env="$(python3 -c 'import json,sys; e=json.load(open(sys.argv[1])).get("environments") or [""]; print(e[0])' "$meta")"
    app="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("app") or "")' "$meta")"
    [ -n "$name" ] || continue

    wf="${WORKFLOW_FILE:-${app:+delivery-${app}.yaml}}"
    if [ -z "$wf" ]; then
        log "${name}: declares no app, so no workflow delivers it -- UNKNOWN"
        failed "$name" "UNKNOWN: it declares no app, so no workflow delivers it"
        continue
    fi
    printf '%s\t%s\t%s\t%s\n' "$name" "$first_env" "$wf" "$meta" >>"$UNITS"
done

# --- 3. the judged commit, per workflow -----------------------------------------
# Per workflow, not global: apps deliver independently, and one app parked on
# an approval must not blind the check to the rest. One read of each
# workflow's newest push runs on $BRANCH; nothing is polled and nothing waits.
# (Release runs carry their tag as the branch, so they are not in this list.)
#
# find_judged_commit <workflow-file> -> prints one line:
#   <judge|skip|unknown><TAB><sha, or - ><TAB><why, for the log and summary>
# shellcheck disable=SC2016 # the backticks are Markdown for the summary
find_judged_commit() {
    local wf="$1" raw id status sha conclusion in_flight=0 passed_over=0 relation
    if [ -n "${DRIFT_IGNORE_IN_FLIGHT:-}" ]; then
        printf 'judge\t%s\t%s\n' "$HEAD_SHA" "main's tip (DRIFT_IGNORE_IN_FLIGHT set)"
        return 0
    fi
    # A failed read is UNKNOWN, never "idle".
    if ! raw="$("$GH" run list --repo "$REPO" --workflow "$wf" --branch "$BRANCH" --event push \
        --limit "$DRIFT_RECENT_RUNS" --json databaseId,status,headSha,conclusion \
        --jq '.[] | "\(.databaseId) \(.status) \(.headSha) \(.conclusion)"' 2>/dev/null)"; then
        printf 'unknown\t-\tcould not read the recent runs of `%s`\n' "$wf"
        return 0
    fi
    # A run parked on an approval gate is waiting for a person, not a timer:
    # its units are not checked until it moves.
    while read -r id status sha conclusion; do
        if [ "$status" = waiting ]; then
            printf 'skip\t-\trun %s of `%s` is waiting on an approval (it will deliver once approved)\n' "$id" "$wf"
            return 0
        fi
    done <<<"$raw"
    # Newest first: the first run that finished and was not cancelled. A
    # cancelled run delivered nothing and decided nothing -- the newer run its
    # concurrency group handed the commits to does both -- so it is passed
    # over. Unfinished runs newer than the pick are what a later check judges.
    sha=""
    while read -r id status sha conclusion; do
        [ -n "$id" ] || continue
        if [ "$status" != completed ]; then
            in_flight=$((in_flight + 1))
        else
            case "$conclusion" in
            cancelled | skipped | stale) passed_over=$((passed_over + 1)) ;;
            *) break ;;
            esac
        fi
        sha=""
    done <<<"$raw"
    if [ -z "$sha" ]; then
        printf 'skip\t-\tno finished push run among the newest %s of `%s` (%s in flight, %s cancelled)\n' \
            "$DRIFT_RECENT_RUNS" "$wf" "$in_flight" "$passed_over"
        return 0
    fi
    local why="newest finished run of \`${wf}\` (${id}, ${conclusion:-no conclusion}) at \`${sha:0:8}\`"
    [ "$in_flight" -eq 0 ] || why="${why}; ${in_flight} newer still in flight"
    [ "$passed_over" -eq 0 ] || why="${why}; ${passed_over} newer cancelled"
    if ! git rev-parse --verify --quiet "${sha}^{commit}" >/dev/null; then
        # Newer than this checkout. Judging at the checkout is then a subset of
        # what that run covered -- but only if it really contains the checkout.
        relation="$("$GH" api "repos/${REPO}/compare/${HEAD_SHA}...${sha}" --jq .status 2>/dev/null || true)"
        case "$relation" in
        ahead | identical)
            printf 'judge\t%s\t%s, newer than this checkout: judged at the checkout\n' "$HEAD_SHA" "$why"
            ;;
        *) printf 'unknown\t-\t%s, which is not in this checkout (GitHub compare: %s)\n' "$why" "${relation:-no answer}" ;;
        esac
        return 0
    fi
    printf 'judge\t%s\t%s\n' "$sha" "$why"
}
# judged_commit <workflow-file> -> sets JC_STATE, JC_SHA, JC_WHY (read once
# per workflow, shared by its units)
judged_commit() {
    local f="$PAGE_DIR/$1.judged"
    [ -s "$f" ] || find_judged_commit "$1" >"$f"
    IFS=$'\t' read -r JC_STATE JC_SHA JC_WHY <"$f"
}

# --- 4. per-unit check --------------------------------------------------------
while IFS=$'\t' read -r name first_env wf meta <&3; do
    judged_commit "$wf"
    case "$JC_STATE" in
    judge) ;;
    skip)
        log "${name}: ${JC_WHY} -- not checked"
        skip "$name" "$JC_WHY"
        continue
        ;;
    *)
        log "${name}: ${JC_WHY} -- UNKNOWN"
        failed "$name" "UNKNOWN: ${JC_WHY}"
        continue
        ;;
    esac
    # Everything up to this commit has been through a finished delivery run.
    judge_sha="$JC_SHA"
    at="judged at \`${judge_sha:0:8}\`"

    # The generated job name for a unit's first rung. Cloud Run units call a
    # reusable workflow, so their job shows as "<unit>-<env> / <inner job>";
    # match on the prefix to cover both shapes.
    job_prefix="${name}-${first_env}"

    last_delivered "$wf" "$job_prefix"
    if [ "$LD_STATE" = absent ] && [ -n "$LEGACY_WORKFLOW_FILE" ] && [ "$LEGACY_WORKFLOW_FILE" != "$wf" ]; then
        last_delivered "$LEGACY_WORKFLOW_FILE" "$job_prefix"
        [ "$LD_STATE" != found ] || log "${name}: no delivery in the whole history of ${wf}; last delivered by ${LEGACY_WORKFLOW_FILE}"
        [ "$LD_STATE" = found ] || wf="${wf} or ${LEGACY_WORKFLOW_FILE}"
    fi
    if [ "$LD_STATE" != found ]; then
        why_unknown "$name" "$first_env" "$wf"
        failed "$name" "UNKNOWN: no delivery found in \`${wf}\` (${LD_STATE}, ${LD_RUNS} runs read)"
        continue
    fi
    last_sha="$LD_SHA"
    if [ "$last_sha" = "$judge_sha" ]; then
        log "${name}: up to date (delivered ${judge_sha:0:8}) -- ${JC_WHY}"
        judged "$name" "up to date (delivered \`${judge_sha:0:8}\`)"
        continue
    fi
    # "Delivered" covers the judged commit when it INCLUDES it: a newer run
    # (even one still in flight) may already have delivered past it. Asked
    # before the engine, which would read a newer delivery as a diff backwards.
    if ! git rev-parse --verify --quiet "${last_sha}^{commit}" >/dev/null; then
        # A commit that landed on main after this check started: ask GitHub
        # how it relates. Only "ahead" (it contains the judged commit) counts.
        relation="$("$GH" api "repos/${REPO}/compare/${judge_sha}...${last_sha}" --jq .status 2>/dev/null || true)"
        if [ "$relation" = ahead ]; then
            log "${name}: up to date (delivered ${last_sha:0:8}, newer than ${judge_sha:0:8})"
            judged "$name" "up to date (delivered \`${last_sha:0:8}\`, newer than the judged \`${judge_sha:0:8}\`)"
            continue
        fi
        log "${name}: last-delivered commit ${last_sha:0:8} not in this checkout, and GitHub's compare says '${relation:-no answer}' -- UNKNOWN"
        failed "$name" "UNKNOWN: delivered \`${last_sha:0:8}\`, which is not in this checkout"
        continue
    fi
    if git merge-base --is-ancestor "$judge_sha" "$last_sha" 2>/dev/null; then
        log "${name}: up to date (delivered ${last_sha:0:8}, which includes the judged ${judge_sha:0:8})"
        judged "$name" "up to date (delivered \`${last_sha:0:8}\`, which includes the judged \`${judge_sha:0:8}\`)"
        continue
    fi

    # The SAME engine the orchestrator uses, with the same per-unit inputs.
    _extra="$(python3 -c 'import json,sys; print("|".join(json.load(open(sys.argv[1])).get("extra_paths") or []))' "$meta")"
    _exclude="$(python3 -c 'import json,sys; print("|".join(json.load(open(sys.argv[1])).get("exclude_paths") or []))' "$meta")"
    _targets="$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1])).get("graph_targets") or []))' "$meta")"

    ask_engine() { # <before> <after> ; echoes the engine's stdout+stderr
        EXTRA_PATH_REGEX="$_extra" EXCLUDE_PATH_REGEX="$_exclude" DEPLOY_TARGETS="$_targets" \
            BEFORE_REV="$1" AFTER_REV="$2" GITHUB_OUTPUT=/dev/null \
            bash tools/ci/deploy-affected.sh 2>&1 </dev/null || true
    }

    # PHASE 1 -- cheap range pre-filter. Clean here means genuinely nothing to
    # deliver, and for graph-mode units it is the only target-determinator run
    # we pay for in the common case.
    # `deploy-affected.sh` fails OPEN: when target-determinator is unavailable it
    # returns affected=true so a real delivery is never missed. That is right for
    # DELIVERY and wrong here -- it turns "could not tell" into "you missed one".
    # Reproduced on Darwin/arm64, where no determinator binary is pinned: every
    # graph-mode unit reported affected=true with
    #   ::warning deploy-gate-fallback:: deploy gate degraded -- failing OPEN
    # A drift verdict built on a gate that admits it could not tell is noise.
    _phase1="$(ask_engine "$last_sha" "$judge_sha")"
    if printf '%s' "$_phase1" | grep -q 'deploy-gate-fallback\|gate degraded'; then
        log "${name}: engine could not determine affectedness (gate degraded) -- NOT CHECKED"
        skip "$name" "the affectedness engine could not tell (gate degraded)"
        continue
    fi
    if ! printf '%s' "$_phase1" | grep -q 'affected=true'; then
        log "${name}: delivered ${last_sha:0:8}; nothing since affects it ($(printf '%s' "$_phase1" | grep -o 'affected=false (.*)' | head -1))"
        judged "$name" "delivered \`${last_sha:0:8}\`; nothing since affects it (${at})"
        continue
    fi

    # PHASE 2 -- confirm per commit before crying drift.
    #
    # A RANGE verdict over-reports. The release-please guard only fires when
    # EVERY commit in the range is a version bump, so in a mixed range (the
    # normal state of main) a release commit's own artifacts -- a bumped
    # package.json, a .release-please-manifest.json -- match the unit's paths
    # and read as work that should have shipped. Nothing needs shipping: the
    # code is byte-identical to what already soaked, and the release promotes by
    # TAG, not by push. Observed on the first live run: oauth-user-inspector
    # reported drift whose only matching files were release artifacts.
    #
    # Judging each commit as its own single-commit range makes the engine's own
    # guard fire for release commits, so no rule is duplicated here. We stop at
    # the first commit that genuinely would have delivered.
    culprit=
    culprit_why=
    for c in $(git rev-list --reverse "${last_sha}..${judge_sha}"); do
        _v="$(ask_engine "${c}^" "$c")"
        printf '%s' "$_v" | grep -q 'deploy-gate-fallback\|gate degraded' && continue
        if printf '%s' "$_v" | grep -q 'affected=true'; then
            culprit="$c"
            culprit_why="$(printf '%s' "$_v" | grep -o 'affected=true (.*)' | head -1)"
            break
        fi
    done

    if [ -z "$culprit" ]; then
        log "${name}: delivered ${last_sha:0:8}; only version-bump commits since (promote by tag, nothing to deploy)"
        judged "$name" "delivered \`${last_sha:0:8}\`; only version-bump commits since (${at})"
        continue
    fi
    # Record WHY, so a drift report that disagrees with the orchestrator can be
    # adjudicated from the log instead of re-derived by hand.
    log "DRIFT ${name}: last delivered ${last_sha:0:8}, but ${culprit:0:8} ('$(git log -1 --pretty=%s "$culprit" | cut -c1-60)') should have delivered and did not -- ${culprit_why:-no reason reported} -- judged at the ${JC_WHY}"
    failed "$name" "DRIFT: last delivered \`${last_sha:0:8}\`, but \`${culprit:0:8}\` should have delivered and did not (${at})"
done 3<"$UNITS"

# --- 5. verdict -----------------------------------------------------------------
total=$((checked + skipped))
log "checked ${checked} unit(s), not checked ${skipped}"
if [ "$drift_found" -ne 0 ]; then
    verdict=DRIFT
    conclusion=failure
    title="${bad} of ${total} unit(s) behind main or unknown"
elif [ "$checked" -eq 0 ]; then
    verdict=NOTHING_CHECKED
    conclusion=neutral
    title="Nothing checked: all ${skipped} unit(s) were skipped"
else
    verdict=OK
    conclusion=success
    title="${checked} unit(s) delivered"
    [ "$skipped" -eq 0 ] || title="${title}; ${skipped} not checked"
fi
[ -z "$SKIPPED_NAMES" ] || log "NOT CHECKED: ${SKIPPED_NAMES}"
if [ -n "${DRIFT_RESULT_FILE:-}" ]; then
    printf 'conclusion=%s\ntitle=%s\nchecked=%s\nskipped=%s\n' "$conclusion" "$title" "$checked" "$skipped" >>"$DRIFT_RESULT_FILE"
fi
if [ -n "${DRIFT_SUMMARY_FILE:-}" ]; then
    {
        echo "**${title}** (commit \`${HEAD_SHA:0:8}\`)"
        echo
        if [ "$verdict" = NOTHING_CHECKED ]; then
            echo "This is not a pass: no unit was judged. Every one was skipped, for the reason given below."
            echo
        fi
        if [ -n "$CHECKED_MD" ]; then
            echo "### Checked (${checked})"
            printf '%s' "$CHECKED_MD"
            echo
        fi
        if [ -n "$SKIPPED_MD" ]; then
            echo "### Not checked (${skipped})"
            printf '%s' "$SKIPPED_MD"
            echo
        fi
        if [ "$checked" -gt 0 ]; then
            echo "Each unit is judged at the newest finished delivery run of its app, not at main's tip: newer commits are still being delivered, and a later check judges them."
        fi
    } >"$DRIFT_SUMMARY_FILE"
fi
echo "$verdict"
[ "$verdict" != DRIFT ] || exit 1
exit 0
