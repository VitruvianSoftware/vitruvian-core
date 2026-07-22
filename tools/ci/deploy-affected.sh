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

# deploy-affected.sh — decide whether a push to main affects an app's
# DEPLOYABLE artifacts, using the Bazel graph (target-determinator) instead of
# directory path globs (#498).
#
# WHY: path globs are strictly coarser than the graph in both directions.
# They UNDER-trigger — a change to a shared library outside the app's dir
# (e.g. a root runtime dep) never redeploys the app, so the running service
# silently keeps the stale dependency. And they OVER-trigger — docs/cli-only
# changes under the app dir rebuild + redeploy the image needlessly.
#
# FAIL-OPEN INVARIANT (the mirror image of affected-targets.sh's fail-closed
# full sweep): every uncertain or error path yields affected=true. A redundant
# deploy is an idempotent blue-green no-op; a silently SKIPPED deploy is the
# #498 bug this script exists to fix. The only way to get affected=false is a
# successfully-computed diff whose graph attribution says none of the deploy
# targets changed AND no declared non-graph input changed.
#
# Environment (set by the workflow):
#   BUILDBUDDY_API_KEY  remote-cache auth for TD's analysis cqueries (required).
#   BEFORE_REV          the pre-push tip (github.event.before).
#   FORCED_PUSH         "true" on a forced push -> affected=true.
#   DEPLOY_TARGETS      space-separated Bazel labels of the deployable
#                       artifacts (e.g. "//tabula/api:image_push
#                       //tabula/extension:chrome_zip").
#   EXTRA_PATH_REGEX    ERE (anchored at path start) of NON-GRAPH inputs that
#                       must also deploy: the app's Pulumi program (a
#                       standalone Go module, invisible to the Bazel graph)
#                       and the deploy workflow files themselves.
#   TD_BIN              optional test hook (see tools/ci/td-lib.sh).
#
# Output: `affected=true|false` to $GITHUB_OUTPUT (echoed either way).

set -euo pipefail

emit() {
  local value="$1" reason="$2" class="${3:-expected}"
  echo "deploy-affected: affected=${value} (${reason})"
  # Observability (#503): "degraded" marks a fail-open caused by the fast path
  # being BROKEN (TD unavailable / TD error), not by a designed deploy trigger.
  # Surfaced as a titled warning + step-summary line so a persistently broken
  # gate (deploying on every push) is audible instead of silently tolerated.
  if [ "${class}" = "degraded" ]; then
    echo "::warning title=deploy-gate-fallback::deploy gate degraded -- failing OPEN to deploy (${reason})"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      {
        echo "### ⚠ deploy-gate fallback (degraded)"
        echo ""
        echo "- reason: ${reason}"
        echo "- consequence: deployed without graph attribution (fail-open, idempotent blue-green)"
        echo "- if this recurs, the gate fast path is broken (see #503): check tools/ci/td-lib.sh"
      } >> "${GITHUB_STEP_SUMMARY}"
    fi
  fi
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "affected=${value}" >> "${GITHUB_OUTPUT}"
  fi
  exit 0
}

DEPLOY_TARGETS="${DEPLOY_TARGETS:?DEPLOY_TARGETS must be set (space-separated Bazel labels)}"
EXTRA_PATH_REGEX="${EXTRA_PATH_REGEX:-}"
BEFORE_REV="${BEFORE_REV:-}"
FORCED_PUSH="${FORCED_PUSH:-false}"

# --- 1. diff base. Anything untrustworthy -> deploy. --------------------------
if [ "${FORCED_PUSH}" = "true" ]; then
  emit true "forced push -- no trustworthy diff base"
fi
if [ -z "${BEFORE_REV}" ] || ! git rev-parse --verify --quiet "${BEFORE_REV}^{commit}" >/dev/null; then
  emit true "BEFORE_REV '${BEFORE_REV}' unset or does not resolve to a commit"
fi

CHANGED_FILES="$(git diff --name-only "${BEFORE_REV}" HEAD -- || true)"
if [ -z "${CHANGED_FILES}" ]; then
  emit false "no changed files vs ${BEFORE_REV}"
fi
echo "deploy-affected: changed files:"
echo "${CHANGED_FILES}" | sed 's/^/  /'

# --- 2. non-graph inputs (Pulumi program, workflow files). --------------------
if [ -n "${EXTRA_PATH_REGEX}" ] \
   && echo "${CHANGED_FILES}" | grep -E "^(${EXTRA_PATH_REGEX})" >/dev/null 2>&1; then
  emit true "non-graph deploy input changed (matched ${EXTRA_PATH_REGEX})"
fi

# --- 3. global-impact guard (same set as affected-targets.sh). ----------------
# A build-config change can affect any target in ways a graph diff may
# misattribute; fail open.
if echo "${CHANGED_FILES}" | grep -E '^(MODULE\.bazel|MODULE\.bazel\.lock|\.bazelrc|\.bazelversion|BUILD$|gazelle_python\.yaml$)' >/dev/null 2>&1 || \
   echo "${CHANGED_FILES}" | grep -E '^tools/' | grep -E -v '^tools/(ci/|cluster/|conformance/|copybara/|doctor/|format/|gitops/|license/|lint/|rotate-buildbuddy-key/|scripts/|sync-env-secrets/|worktree/|repin$)' >/dev/null 2>&1; then
  emit true "global-impact file changed"
fi

# --- 4. graph attribution over ONLY the deploy targets. -----------------------
# shellcheck source=tools/ci/td-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/td-lib.sh"
if ! fetch_td; then
  emit true "target-determinator unavailable (${TD_FETCH_ERROR})" degraded
fi

# The universe is the UNION of the deploy targets (a bazel query expression):
# TD reports which of exactly these targets the diff affects. Dependencies
# outside the universe still attribute correctly -- that is the whole point
# (a shared-lib change lands in the deploy target's affected verdict).
TD_UNIVERSE=""
for t in ${DEPLOY_TARGETS}; do
  if [ -z "${TD_UNIVERSE}" ]; then TD_UNIVERSE="${t}"; else TD_UNIVERSE="${TD_UNIVERSE} + ${t}"; fi
done

echo "deploy-affected: computing affected deploy targets since ${BEFORE_REV} (universe: ${TD_UNIVERSE})..."
if ! "${TD}" \
      --bazel bazel \
      --targets "${TD_UNIVERSE}" \
      --bazel-opts="--config=remotecache" \
      --bazel-opts="--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}" \
      --before-query-error-behavior=ignore-and-build-all \
      "${BEFORE_REV}" > deploy-affected.txt; then
  emit true "target-determinator returned non-zero" degraded
fi

if [ -s deploy-affected.txt ]; then
  echo "deploy-affected: affected deploy target(s):"
  sed 's/^/  /' deploy-affected.txt
  emit true "deploy target(s) affected by the diff"
fi
emit false "no deploy target affected by the diff"
