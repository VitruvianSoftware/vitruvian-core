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
# Exit codes: 0 = no drift (or only in-flight), 1 = drift found, 2 = usage/setup
# error. Env: REPO (owner/name), WORKFLOW_FILE (default delivery.yaml),
# BRANCH (default main), RUN_SCAN_LIMIT (default 60),
# DRIFT_IGNORE_IN_FLIGHT (set to any value to print the per-unit verdicts even
# while a run is converging -- for an operator investigating, never for the
# scheduled job, which would then report drift on every normal deploy).
set -euo pipefail

REPO="${REPO:-VitruvianSoftware/vitruvian-core}"
WORKFLOW_FILE="${WORKFLOW_FILE:-delivery.yaml}"
BRANCH="${BRANCH:-main}"
RUN_SCAN_LIMIT="${RUN_SCAN_LIMIT:-60}"
BAZEL="${BAZEL:-bazel}"
GH="${GH:-gh}"
DELIVERY_QUERY='attr(tags, "\bdelivery\b", (//... except //nexus-agent/macos/...))'

log() { echo "delivery-drift: $*" >&2; }

command -v "$GH" >/dev/null 2>&1 || {
    log "gh not found on PATH"
    exit 2
}

# --- 1. in-flight guard -------------------------------------------------------
# A queued/running/waiting delivery run means the fleet is legitimately mid-
# convergence; anything "behind" is behind on purpose. Reporting drift then
# would train the reader to ignore this check, which is worse than not having
# it. Note `waiting` counts: a run parked on an approval gate WILL deliver.
IN_FLIGHT="$("$GH" run list --repo "$REPO" --workflow "$WORKFLOW_FILE" --branch "$BRANCH" \
    --limit 20 --json status --jq '[.[] | select(.status == "in_progress" or .status == "queued" or .status == "waiting")] | length' 2>/dev/null || echo 0)"
if [ "${IN_FLIGHT:-0}" -gt 0 ] && [ -z "${DRIFT_IGNORE_IN_FLIGHT:-}" ]; then
    log "${IN_FLIGHT} delivery run(s) in flight -- the fleet is mid-convergence, not drifted"
    echo "IN_FLIGHT"
    exit 0
fi

# --- 2. discover the declared units -------------------------------------------
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

# --- 3. per-unit check --------------------------------------------------------
HEAD_SHA="$(git rev-parse HEAD)"
drift_found=0
checked=0

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
        drift_found=1
        continue
    }

    name="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$meta")"
    first_env="$(python3 -c 'import json,sys; e=json.load(open(sys.argv[1])).get("environments") or [""]; print(e[0])' "$meta")"
    [ -n "$name" ] || continue

    # The generated job name for a unit's first rung. Cloud Run units call a
    # reusable workflow, so their job shows as "<unit>-<env> / <inner job>";
    # match on the prefix to cover both shapes.
    job_prefix="${name}-${first_env}"

    last_sha="$("$GH" run list --repo "$REPO" --workflow "$WORKFLOW_FILE" --branch "$BRANCH" \
        --limit "$RUN_SCAN_LIMIT" --json databaseId,headSha,createdAt \
        --jq '.[] | "\(.databaseId) \(.headSha)"' 2>/dev/null |
        while read -r rid rsha; do
            if "$GH" api "repos/${REPO}/actions/runs/${rid}/jobs?per_page=100" --paginate \
                --jq ".jobs[] | select((.name | startswith(\"${job_prefix}\")) and .conclusion == \"success\") | .name" 2>/dev/null | grep -q .; then
                echo "$rsha"
                break
            fi
        done || true)"

    checked=$((checked + 1))
    if [ -z "$last_sha" ]; then
        log "${name}: no successful ${first_env} delivery in the last ${RUN_SCAN_LIMIT} runs -- UNKNOWN"
        drift_found=1
        continue
    fi
    if [ "$last_sha" = "$HEAD_SHA" ]; then
        log "${name}: up to date (delivered ${HEAD_SHA:0:8})"
        continue
    fi
    if ! git rev-parse --verify --quiet "${last_sha}^{commit}" >/dev/null; then
        log "${name}: last-delivered commit ${last_sha:0:8} not in this checkout -- UNKNOWN (shallow clone?)"
        drift_found=1
        continue
    fi

    # The SAME engine the orchestrator uses, with the same per-unit inputs.
    verdict="$(
        EXTRA_PATH_REGEX="$(python3 -c 'import json,sys; print("|".join(json.load(open(sys.argv[1])).get("extra_paths") or []))' "$meta")" \
            EXCLUDE_PATH_REGEX="$(python3 -c 'import json,sys; print("|".join(json.load(open(sys.argv[1])).get("exclude_paths") or []))' "$meta")" \
            DEPLOY_TARGETS="$(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1])).get("graph_targets") or []))' "$meta")" \
            BEFORE_REV="$last_sha" \
            GITHUB_OUTPUT=/dev/null \
            bash tools/ci/deploy-affected.sh 2>&1 || true
    )"
    if echo "$verdict" | grep -q 'affected=true'; then
        reason="$(echo "$verdict" | grep -o 'affected=true (.*' | head -1)"
        log "DRIFT ${name}: last delivered ${last_sha:0:8}, but main ${HEAD_SHA:0:8} still affects it -- ${reason}"
        drift_found=1
    else
        log "${name}: delivered ${last_sha:0:8}; nothing since affects it"
    fi
done

log "checked ${checked} unit(s)"
if [ "$drift_found" -ne 0 ]; then
    echo "DRIFT"
    exit 1
fi
echo "OK"
exit 0
