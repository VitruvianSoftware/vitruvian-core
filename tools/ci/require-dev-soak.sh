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

# require-dev-soak.sh — refuse to PROMOTE when development is currently RED
# for the service being promoted.
#
# THE GAP THIS CLOSES. The promotion ladder's whole premise is "the release
# commit is code-identical to what soaked on dev" -- but NOTHING enforced that
# it soaked SUCCESSFULLY. release-please opens a release PR on any push to
# main (tabula-release.yml triggers on push, not on a green deploy);
# release-pr-automerge.yaml enables auto-merge the moment that PR opens; the
# checks gating that auto-merge are the PR check suite (build + test), which
# knows nothing about the DEPLOYMENT; and nonproduction carries no reviewer.
# So a commit whose development deploy FAILED could ride all the way into
# nonproduction with no human in the loop. This is the missing interlock.
#
# WHY THE GITHUB API AND NOT GCP. The obvious check -- "read development's
# live Cloud Run revision and compare digests" -- crosses a project boundary:
# development is prj-d-bu2-oss-floating-c3d1, nonproduction is
# prj-n-bu2-oss-floating-a943, and tabula/infra/identity scopes each env's
# deploy SA to its OWN project. That check would require granting the
# nonproduction SA read into development, widening the blast radius of a
# promotion credential to gain a signal GitHub already holds. It also would
# not even be reliable: a release commit bumps package.json's version, so the
# image built at the release commit is legitimately a DIFFERENT digest from
# the one that soaked pre-release. Ask GitHub "did the development deploy
# job pass?" instead -- `actions: read`, no GCP IAM change, no digest
# equality assumption.
#
# FAIL-CLOSED ON RED, FAIL-OPEN ON UNKNOWN. A definitive `failure` blocks the
# promotion (that is the entire point). An INDETERMINATE answer -- API error,
# no run found in the scan window -- warns and allows. Rationale: the harm
# from wrongly blocking every promotion on a transient API hiccup is
# continuous and self-inflicted, while the harm this guards against is a
# specific, visible, already-red deploy. A gate nobody can rely on gets
# disabled; one that only fires on real evidence gets kept. `skipped` counts
# as PASS -- the graph gate legitimately skips deploy-dev for a change that
# touches no deployable artifact (docs, CLI), and treating that as failure
# would wedge those releases permanently.
#
# Environment:
#   GH_TOKEN        token with `actions: read` on this repo
#   REPO            owner/repo (defaults to GITHUB_REPOSITORY)
#   BRANCH          branch whose deploy history is authoritative (default main)
#   WORKFLOW_FILE   workflow whose run history holds the dev deploy job.
#                   Optional: defaults to the workflow that owns the CURRENT
#                   run (see the resolution note below).
#   DEV_JOB_NAME    exact job name proving the dev deploy, e.g.
#                   "deploy-dev / deploy" (per-SERVICE: tabula-api and
#                   tabula-web have separate jobs, so one service's red
#                   development never blocks the other's promotion)
#   ALLOW_UNSOAKED  "true" bypasses the gate (break-glass; logged loudly)
#   GH_BIN, SCAN_LIMIT  test hooks

set -uo pipefail

GH_BIN="${GH_BIN:-gh}"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
BRANCH="${BRANCH:-main}"
SCAN_LIMIT="${SCAN_LIMIT:-20}"
ALLOW_UNSOAKED="${ALLOW_UNSOAKED:-false}"
DEV_JOB_NAME="${DEV_JOB_NAME:?DEV_JOB_NAME must name the development deploy job}"

pass() {
  echo "require-dev-soak[${DEV_JOB_NAME}]: PASS — $1"
  exit 0
}
block() {
  echo "::error title=development is red — promotion blocked::$1"
  echo "require-dev-soak[${DEV_JOB_NAME}]: BLOCKED — $1" >&2
  exit 1
}
unknown() {
  echo "::warning title=dev-soak indeterminate::$1 — allowing the promotion (this gate fails open on an UNKNOWN answer; it blocks only on a definitive red development deploy)"
  echo "require-dev-soak[${DEV_JOB_NAME}]: PASS (indeterminate) — $1"
  exit 0
}

if [ "${ALLOW_UNSOAKED}" = "true" ]; then
  echo "::warning title=dev-soak gate bypassed::ALLOW_UNSOAKED=true — promoting WITHOUT confirming the development deploy is green"
  pass "explicitly bypassed via ALLOW_UNSOAKED"
fi

[ -n "${REPO}" ] || unknown "REPO/GITHUB_REPOSITORY unset — cannot query run history"

# WHICH workflow's history holds the development deploy job? This script runs
# inside the REUSABLE deploy workflow, but a reusable workflow's jobs execute
# as part of the CALLER's run -- so GITHUB_RUN_ID is the caller's run, and
# asking the API which workflow owns that run is exact for every caller
# (tabula-deploy.yaml, oauth-user-inspector-deploy.yaml, ...) with no
# per-caller wiring.
#
# Deliberately NOT derived from GITHUB_WORKFLOW_REF: whether that resolves to
# the caller or the callee is a subtlety to depend on, and getting it wrong
# would query the WRONG workflow's history, find no matching job, and fail
# open -- leaving a gate that is silently a no-op, which is worse than no gate
# because it looks like protection. An explicit WORKFLOW_FILE still wins, and
# the ref-basename remains only as a last resort.
if [ -z "${WORKFLOW_FILE:-}" ] && [ -n "${GITHUB_RUN_ID:-}" ]; then
  WORKFLOW_FILE="$("${GH_BIN}" api "repos/${REPO}/actions/runs/${GITHUB_RUN_ID}" \
    --jq '.workflow_id' 2>/dev/null)"
fi
if [ -z "${WORKFLOW_FILE:-}" ]; then
  _ref="${GITHUB_WORKFLOW_REF:-}"
  _ref="${_ref%%@*}"           # strip @refs/heads/...
  WORKFLOW_FILE="${_ref##*/}"  # basename
fi
[ -n "${WORKFLOW_FILE}" ] || unknown "could not determine which workflow's history to search (no WORKFLOW_FILE, no resolvable GITHUB_RUN_ID, no GITHUB_WORKFLOW_REF)"
echo "require-dev-soak[${DEV_JOB_NAME}]: searching ${WORKFLOW_FILE} on ${BRANCH} (repo ${REPO})"

# Newest-first completed push runs. Only `push` runs deploy development (a
# release run never does), so this is the history that carries the signal.
runs="$("${GH_BIN}" run list --repo "${REPO}" -w "${WORKFLOW_FILE}" -b "${BRANCH}" \
  -e push -s completed -L "${SCAN_LIMIT}" --json databaseId --jq '.[].databaseId' 2>&1)"
rc=$?
[ "${rc}" -eq 0 ] || unknown "gh run list failed (rc=${rc}): ${runs}"
[ -n "${runs}" ] || unknown "no completed push-triggered run of ${WORKFLOW_FILE} on ${BRANCH} found"

# Walk newest -> oldest and let the FIRST run that actually reached a terminal
# state for this job decide. Runs where the job never materialised (an older
# workflow revision that predates the job, or a run cancelled before it was
# scheduled) are not evidence either way, so they are skipped rather than
# treated as a pass.
while IFS= read -r run_id; do
  [ -n "${run_id}" ] || continue

  # Emit "<name>\t<conclusion>" and match the job name in bash: gh's --jq takes
  # no --arg, so interpolating DEV_JOB_NAME into the filter would be a jq
  # injection waiting to happen.
  jobs="$("${GH_BIN}" run view "${run_id}" --repo "${REPO}" --json jobs \
    --jq '.jobs[] | "\(.name)\t\(.conclusion)"' 2>&1)"
  jrc=$?
  if [ "${jrc}" -ne 0 ]; then
    echo "require-dev-soak: could not read jobs for run ${run_id} (rc=${jrc}): ${jobs}" >&2
    continue
  fi

  conclusion="$(printf '%s\n' "${jobs}" | awk -F'\t' -v want="${DEV_JOB_NAME}" \
    '$1 == want { print $2; exit }')"
  [ -n "${conclusion}" ] || continue

  case "${conclusion}" in
    success)
      pass "development deploy '${DEV_JOB_NAME}' succeeded in run ${run_id}"
      ;;
    skipped)
      pass "development deploy '${DEV_JOB_NAME}' was skipped in run ${run_id} (the graph gate found no deployable change — nothing to soak)"
      ;;
    failure | cancelled | timed_out | action_required | startup_failure)
      block "development deploy '${DEV_JOB_NAME}' concluded '${conclusion}' in the most recent run that reached it (run ${run_id}: https://github.com/${REPO}/actions/runs/${run_id}). Promoting now would ship an artifact whose development deploy is RED. Fix development first, or set ALLOW_UNSOAKED=true to override deliberately."
      ;;
    *)
      # An unrecognised conclusion is not evidence of health; keep looking
      # rather than silently passing on it.
      echo "require-dev-soak: unrecognised conclusion '${conclusion}' for run ${run_id}; continuing" >&2
      ;;
  esac
done <<EOF
${runs}
EOF

unknown "scanned the last ${SCAN_LIMIT} completed push runs of ${WORKFLOW_FILE} without finding a terminal '${DEV_JOB_NAME}' result"
