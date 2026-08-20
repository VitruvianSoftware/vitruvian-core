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

# resolve-unit-bases.sh — per-unit durable diff bases for the delivery lane (#1842).
#
# THE PROBLEM resolve-deploy-base.sh cannot solve on its own. That script picks
# ONE base: the head of the last push run that concluded `success`. Run-level
# success is a proxy for "everything this range required was delivered", and it
# is not a faithful one. A run in which every delivery job was SKIPPED — because
# the engine judged every unit unaffected — still concludes `success` and still
# becomes the base. Observed 2026-08-20 on run 32424592611: 27 of 29 jobs
# skipped, conclusion `success`, and it became the base for all ten units.
#
# Once that happens every commit in the range is permanently outside any future
# diff. If the engine's "unaffected" verdict was WRONG for one unit — the #1840
# class of bug — that unit's delivery is not deferred, it is lost, with no red
# check and no alert.
#
# THE FIX: judge currency per unit, from the unit's OWN last successful delivery
# job rather than from the run's conclusion. A unit that actually delivered
# advances; a unit that was skipped keeps its older base, so the commits it
# missed stay inside its next diff and the miss SELF-HEALS on the next push.
#
# SAFETY PROPERTY (asserted by the tests): a unit's last successful JOB always
# lives in some run at or before the last successful RUN, so a per-unit base is
# always older than or equal to the single base it replaces. This can therefore
# only ever WIDEN a diff, never narrow one — the failure mode it introduces is a
# redundant deploy, never a lost one. That is the same direction
# resolve-deploy-base.sh and deploy-affected.sh already fail in.
#
# UNIT LIST comes from the workflow file itself: the generator emits one
# `affected_<unit>:` output per unit, so parsing those names keeps this in sync
# with the declarations automatically and needs no second source of truth.
#
# JOB→UNIT comes from each job's own `if:`, not from its name. A job belongs to
# unit U's push lane exactly when its condition references `affected_<U>` — which
# is what actually gates it. Name matching was tried first and is wrong twice
# over: `tabula-api-changelog` shares the `tabula-api` prefix but is not a
# delivery (it references no `affected_*` at all, and crediting it advanced that
# unit's base past two undelivered runs on real history), and
# `oauth-user-inspector` is a prefix of `oauth-user-inspector-identity`, so the
# app would absorb the identity unit's deliveries. The `affected_` match is
# boundary-anchored for that second reason. Release-gated rungs
# (`*-nonproduction`, `*-production`, `*-require-dev-soak`) reference no
# `affected_*` either and are correctly excluded from the push lane.
# Reusable-workflow jobs render as "<job> / <inner>", so the suffix is stripped.
#
# FAIL-OPEN: any problem (gh error, unparseable workflow, no history) yields an
# EMPTY object. The caller then uses the single base for every unit — exactly
# today's behaviour — so this is strictly additive.
#
# Environment:
#   GH_TOKEN       token with `actions: read`.
#   REPO           owner/repo (defaults to GITHUB_REPOSITORY).
#   WORKFLOW_FILE  the workflow whose history to read, e.g. delivery.yaml.
#   WORKFLOW_PATH  the workflow file to parse for unit names
#                  (default .github/workflows/$WORKFLOW_FILE).
#   BRANCH         defaults to main.
#   LOOKBACK       how many push runs to scan (default 30).
#   GH_BIN         test hook (default: gh).
#
# Output: `unit_bases=<compact JSON object>` to $GITHUB_OUTPUT.
set -uo pipefail

GH_BIN="${GH_BIN:-gh}"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
BRANCH="${BRANCH:-main}"
LOOKBACK="${LOOKBACK:-30}"
WORKFLOW_FILE="${WORKFLOW_FILE:?WORKFLOW_FILE must be set}"
WORKFLOW_PATH="${WORKFLOW_PATH:-.github/workflows/${WORKFLOW_FILE}}"

emit() { # <json> <reason>
  echo "resolve-unit-bases: unit_bases=${1} (${2})"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "unit_bases=${1}" >> "${GITHUB_OUTPUT}"
  fi
  exit 0
}

[ -n "${REPO}" ] || emit "{}" "REPO/GITHUB_REPOSITORY unset"
[ -r "${WORKFLOW_PATH}" ] || emit "{}" "workflow ${WORKFLOW_PATH} not readable"

# Unit names from the generated `affected_<unit>:` outputs. Underscores in the
# output name map back to dashes in the unit name.
units="$(sed -n 's/^[[:space:]]*affected_\([a-z0-9_]*\):.*/\1/p' "${WORKFLOW_PATH}" \
  | sort -u)"
[ -n "${units}" ] || emit "{}" "no affected_* outputs found in ${WORKFLOW_PATH}"

# job id -> its `if:` condition, for every job under `jobs:`.
conds="$(awk '
  /^jobs:/ { injobs = 1; next }
  !injobs { next }
  /^  [a-z0-9][a-z0-9-]*:[[:space:]]*$/ { j = $1; sub(/:$/, "", j); next }
  /^    if: / { if (j != "") { line = $0; sub(/^    if: /, "", line); print j "\t" line } }
' "${WORKFLOW_PATH}")"
[ -n "${conds}" ] || emit "{}" "no job conditions parsed from ${WORKFLOW_PATH}"

runs="$("${GH_BIN}" run list --repo "${REPO}" -w "${WORKFLOW_FILE}" -b "${BRANCH}" \
  -e push -L "${LOOKBACK}" --json databaseId,headSha --jq '.[] | "\(.databaseId) \(.headSha)"' 2>&1)"
if [ $? -ne 0 ] || [ -z "${runs}" ]; then
  emit "{}" "could not list runs for ${WORKFLOW_FILE}: ${runs}"
fi

# TWO PASSES, and the order matters. First: per JOB, its NEWEST success (runs
# arrive newest-first, so first-writer-wins). Second: per UNIT, the OLDEST of
# its rungs' newest successes — a unit is only as current as its laggiest rung.
#
# Collapsing these into one pass ("oldest run in which any rung of this unit
# succeeded") is a different and much weaker quantity: it pins every unit to the
# oldest scanned run, which is exactly what a first attempt here did.
#
# Plain "key value" accumulators rather than associative arrays: bash 3.2 (the
# macOS system bash these tests also run under) has no `declare -A`, and no
# other script in this tree relies on one.
idx=0
jobsucc=""      # "<job> <run-index> <sha>", newest success per job
while read -r run_id head_sha; do
  [ -n "${run_id}" ] || continue
  jobs="$("${GH_BIN}" api "/repos/${REPO}/actions/runs/${run_id}/jobs" --paginate \
    --jq '.jobs[] | select(.conclusion=="success") | .name' 2>/dev/null)" || { idx=$((idx + 1)); continue; }
  while IFS= read -r job; do
    [ -n "${job}" ] || continue
    job="${job%% / *}"                      # reusable-workflow "<job> / <inner>"
    printf '%s\n' "${jobsucc}" | awk -v j="${job}" '$1==j{f=1} END{exit !f}' && continue
    jobsucc="${jobsucc}
${job} ${idx} ${head_sha}"
  done <<< "${jobs}"
  idx=$((idx + 1))
done <<< "${runs}"

# Per unit: the largest run-index (= oldest run) among its rungs' newest
# successes. A rung that never succeeded in the window leaves the unit unknown,
# and an unknown unit is simply omitted so the caller keeps today's single base
# -- this stays strictly additive.
found=""
for uu in ${units}; do
  u="$(printf '%s' "${uu}" | tr '_' '-')"
  worst_idx=-1; worst_sha=""; missing=0; any=0
  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    jid="${line%%$'\t'*}"; cond="${line#*$'\t'}"
    # Boundary-anchored: affected_oauth_user_inspector must NOT match
    # affected_oauth_user_inspector_identity.
    printf '%s\n' "${cond}" | grep -qE "affected_${uu}([^a-z0-9_]|\$)" || continue
    any=1
    rec="$(printf '%s\n' "${jobsucc}" | awk -v j="${jid}" '$1==j{print $2" "$3; exit}')"
    if [ -z "${rec}" ]; then missing=1; break; fi
    ri="${rec%% *}"; rs="${rec#* }"
    if [ "${ri}" -gt "${worst_idx}" ]; then worst_idx="${ri}"; worst_sha="${rs}"; fi
  done <<< "${conds}"
  [ "${any}" -eq 1 ] && [ "${missing}" -eq 0 ] && [ -n "${worst_sha}" ] || continue
  found="${found}${u} ${worst_sha}
"
done

json="{"
sep=""
for uu in ${units}; do
  u="$(printf '%s' "${uu}" | tr '_' '-')"
  v="$(printf '%s\n' "${found}" | awk -v u="${u}" '$1==u{print $2; exit}')"
  [ -n "${v}" ] || continue                 # unknown unit -> caller keeps the single base
  json="${json}${sep}\"${u}\":\"${v}\""
  sep=","
done
json="${json}}"

emit "${json}" "per-unit bases from the last ${LOOKBACK} push runs of ${WORKFLOW_FILE}"
