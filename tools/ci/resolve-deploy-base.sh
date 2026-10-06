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

# resolve-deploy-base.sh — find the durable diff base for a push-triggered
# deploy lane whose concurrency group intentionally COALESCES queued pushes
# (each app's generated .github/workflows/delivery-<app>.yaml; see #1351).
#
# WHY NOT github.event.before: it is the tip of the PREVIOUS push, regardless
# of whether that push's own run ever completed. GitHub evicts an
# already-PENDING run in a constant concurrency group when a newer one queues
# behind it (the same mechanism #1311/#1335 fixed for the merge_group gating
# lanes) — so a dropped run's commit range is never diffed by anyone again,
# and its deploy is skipped PERMANENTLY, not deferred. Keying the group on
# github.sha (the #1335 fix) is NOT an option here: these lanes serialize on
# purpose (a shared live env + a shared build Artifact Registry), so two
# commits must never race the same deploy — see
# tools/conformance/check.sh's check_deploy_durable_base, which asserts this
# stays a coalescing group rather than a sha-keyed one.
#
# THE FIX: derive the diff base from the last PUSH-triggered run of THIS
# workflow that actually completed with conclusion=success on the target
# branch. Every job in the push-triggered chain (gate -> build -> deploy) is a
# plain job with no continue-on-error, so a run only concludes success when
# either (a) the gate correctly found nothing to deploy, or (b) the deploy
# itself genuinely succeeded — never merely "the run finished". A dropped
# run's conclusion is `cancelled`, not `success`, so this lookup transparently
# skips it and walks back to the last commit that is verifiably live — the
# skipped commit's changes then fall inside the NEXT run's diff range and
# self-heal, instead of vanishing.
#
# `-e push` deliberately excludes workflow_dispatch runs: a single-env
# break-glass dispatch (e.g. production only) can succeed without ever
# exercising the push-triggered gate->build->deploy-dev chain this base is
# meant to track, so treating its sha as "development is now current" would
# be wrong. Missing a dispatch-driven update only makes the NEXT push's diff
# wider than strictly necessary (an extra, harmless redundant deploy) — the
# safe direction, matching deploy-affected.sh's own fail-open invariant.
#
# This trades the Cloud-Run-revision-label and moving-git-tag alternatives
# (also raised in #1351) for one that needs NO new IAM grant and NO new
# labeling mechanism in the shared _deploy-cloud-run.yaml: it reads the
# calling workflow's own run history via the GitHub Actions API, which the
# default GITHUB_TOKEN already reaches (needs `actions: read`, scoped to the
# gate job only — see the calling workflow's job-level `permissions:`).
#
# FAIL-OPEN: any lookup problem (gh error, no prior successful run — e.g. the
# very first push) yields an EMPTY base_sha. The caller MUST fall back to
# github.event.before (today's behavior) when base_sha is empty —
# deploy-affected.sh's own BEFORE_REV guard then fails open to affected=true
# if THAT is also unusable. This script never itself decides affected=true;
# it only ever supplies (or withholds) a diff base.
#
# Environment:
#   GH_TOKEN        a token with `actions: read` on this repo (the job's
#                   GITHUB_TOKEN is sufficient).
#   REPO            owner/repo (defaults to GITHUB_REPOSITORY).
#   WORKFLOW_FILE   the calling workflow's own filename, e.g.
#                   delivery-tabula.yaml (required).
#   LEGACY_WORKFLOW_FILE
#                   optional: the workflow that delivered these units BEFORE
#                   WORKFLOW_FILE existed (delivery.yaml, before the per-app
#                   split). Consulted only when WORKFLOW_FILE has no successful
#                   push run yet, so a new workflow's first run re-diffs what
#                   the old one never delivered instead of falling back to
#                   github.event.before. Retires itself once WORKFLOW_FILE has
#                   a success.
#   BRANCH          defaults to main.
#   GH_BIN          test hook (default: gh).
#
# Output: `base_sha=<sha or empty>` to $GITHUB_OUTPUT (always written, echoed
# either way).

set -uo pipefail

GH_BIN="${GH_BIN:-gh}"
REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
BRANCH="${BRANCH:-main}"
WORKFLOW_FILE="${WORKFLOW_FILE:?WORKFLOW_FILE must be set to the calling workflow filename}"

emit() { # <sha-or-empty> <reason>
  echo "resolve-deploy-base: base_sha='${1}' (${2})"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "base_sha=${1}" >> "${GITHUB_OUTPUT}"
  fi
  exit 0
}

if [ -z "${REPO}" ]; then
  emit "" "REPO/GITHUB_REPOSITORY unset -- cannot query run history"
fi

# Last push-triggered, fully-successful run of THIS workflow on the target
# branch. `-s success` filters on conclusion (gh's --status flag accepts
# conclusion values too); `-L 1` + `--json headSha` keeps the response to
# exactly the field this script needs.
last_success() { # <workflow-file>
  "${GH_BIN}" run list --repo "${REPO}" -w "${1}" -b "${BRANCH}" \
    -e push -s success -L 1 --json headSha --jq '.[0].headSha // empty' 2>&1
}

result="$(last_success "${WORKFLOW_FILE}")"
rc=$?

if [ "${rc}" -ne 0 ]; then
  echo "::warning title=deploy-gate-durable-base-fallback::could not resolve the durable deploy base for ${WORKFLOW_FILE} (${result}); falling back to github.event.before"
  emit "" "gh run list failed (rc=${rc}): ${result}"
fi

if [ -n "${result}" ]; then
  emit "${result}" "last successful push-triggered run of ${WORKFLOW_FILE}"
fi

# No success of its own yet: a workflow that took these units over from
# LEGACY_WORKFLOW_FILE resumes from where that one last delivered.
if [ -n "${LEGACY_WORKFLOW_FILE:-}" ] && [ "${LEGACY_WORKFLOW_FILE}" != "${WORKFLOW_FILE}" ]; then
  legacy="$(last_success "${LEGACY_WORKFLOW_FILE}")"
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    echo "::warning title=deploy-gate-durable-base-fallback::no successful run of ${WORKFLOW_FILE} yet, and could not read ${LEGACY_WORKFLOW_FILE} (${legacy}); falling back to github.event.before"
    emit "" "gh run list for ${LEGACY_WORKFLOW_FILE} failed (rc=${rc}): ${legacy}"
  fi
  if [ -n "${legacy}" ]; then
    emit "${legacy}" "no successful push-triggered run of ${WORKFLOW_FILE} yet; last successful push-triggered run of ${LEGACY_WORKFLOW_FILE}, which delivered these units before it"
  fi
fi

emit "" "no prior successful push-triggered run of ${WORKFLOW_FILE} found (first run, or every prior run failed/was evicted)"
