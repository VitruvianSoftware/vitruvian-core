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

# affected-targets.sh — build + test the repo against the BuildBuddy remote,
# skipping only the diffs that provably need no Bazel work at all.
#
# NAME KEPT DELIBERATELY: three ci.yaml lanes and the conformance guards refer
# to this path, and the file still owns the "does this diff need a build?"
# decision. It no longer performs affected-TARGET selection -- see the block at
# the bottom for the measurements that removed it (#1262).
#
# SAFETY INVARIANT (issue #81): the worst case must never be less safe than a
# full `//...` sweep. That invariant is now trivially satisfied: every path that
# builds anything builds `//...`. Invoked on all three ci.yaml lanes:
#   pull_request  BASE_REF set        -> before-rev = merge-base vs origin/base
#   merge_group   BEFORE_REV set to github.event.merge_group.base_sha
#   push (main)   BEFORE_REV set to github.event.before (the pre-push tip);
#                 FORCED_PUSH=true -> full sweep (rewritten history has no
#                 trustworthy diff base).
#
# periodic-full-sweep.yaml (nightly //...) is retained and still enforced by
# //tools/conformance:check. It was the backstop for affected-selection
# under-attribution; with selection gone there is nothing left to under-attribute,
# so it is now belt-and-braces rather than load-bearing — it still catches a
# non-determinism or a cache-poisoning that a per-diff run could mask.
#
# Environment (set by the workflow):
#   BUILDBUDDY_API_KEY  RBE/remote-cache auth header value (required).
#   BASE_REF            github.base_ref (PR lane), e.g. "main"; OR
#   BEFORE_REV          explicit before-revision (merge_group / push lanes).
#   FORCED_PUSH         "true" on a forced push -> full sweep (push lane only).
#   RDEPS_MAP           optional path to the dependency map for the diff base
#                       (#2841); a missing file just means "no map".
#   PLAN_BIN            optional path to a prebuilt //tools/pipeline/plan
#                       binary; used instead of `bazel run` when executable.
#   PLAN_BUDGET_SEC     optional; warn when a map-sourced plan takes longer
#                       (default 120).
#
# Flow:
#   1. Determine BEFORE_REV: the explicit one if provided (verified to resolve
#      to a commit), else git merge-base origin/$BASE_REF HEAD.
#   2. If the diff is docs/gitops/markdown-only, exit 0 without building
#      anything -- the one short-circuit that is still strictly cheaper than a
#      sweep, because it does no Bazel work at all.
#   3. Otherwise `bazel build //...` + `bazel test //...`.
#
# The global-impact allowlist below no longer changes WHAT runs (everything
# runs); it is retained because it classifies the sweep reason in the run UI and
# because //tools/conformance:check asserts it stays byte-identical to the one
# in deploy-affected.sh, which DOES still use it to gate live deploys.

set -euo pipefail

# --- remote auth: preserved byte-for-byte from the original full-sweep job. ---
REMOTE_ARGS=(--config=remote "--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}")

# run_full_sweep: the safe fallback. Identical semantics to the original
# unconditional full-sweep lanes (and to periodic-full-sweep.yaml).
#
# Observability (#503): $2 classifies the fallback.
#   expected  the DESIGNED full-sweep path (global-impact change, forced push,
#             ref creation) -> ::notice::, business as usual.
#   degraded  the fast path is BROKEN or unavailable (TD download/checksum
#             failure, TD error, missing base info) -> ::warning:: with a
#             stable title + a step-summary line, so a silently-broken fast
#             path (e.g. a stale TD pin after a runner image change) is
#             AUDIBLE in the run UI instead of full-sweeping every PR forever.
# Default is degraded: an unclassified new call site should be loud, not quiet.
run_full_sweep() {
  reason="$1" class="${2:-degraded}"
  if [ "${class}" = "expected" ]; then
    echo "::notice::affected-targets: full //... sweep (${reason})"
  else
    echo "::warning title=affected-selection-fallback::affected-targets fast path degraded -- full //... sweep (${reason})"
    if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
      {
        echo "### ⚠ affected-selection fallback (degraded)"
        echo ""
        echo "- reason: ${reason}"
        echo "- consequence: this run paid a full \`//...\` sweep instead of affected targets"
        echo "- if this recurs across runs, the fast path is broken (see #503): check the TD pin in \`tools/ci/td-lib.sh\` and the runner platform"
      } >> "${GITHUB_STEP_SUMMARY}"
    fi
  fi
  bazel build "${REMOTE_ARGS[@]}" //...
  bazel test "${REMOTE_ARGS[@]}" //...
  exit 0
}

BASE_REF="${BASE_REF:-}"
BEFORE_REV="${BEFORE_REV:-}"
FORCED_PUSH="${FORCED_PUSH:-false}"

# --- 1. before-revision. ------------------------------------------------------
# merge_group / push lanes pass BEFORE_REV explicitly (merge_group.base_sha /
# event.before); the PR lane passes BASE_REF and we compute the merge-base.
# fetch-depth: 0 in the workflow guarantees the revisions are present locally.
# Anything unresolvable or untrustworthy -> full sweep.
if [ "${FORCED_PUSH}" = "true" ]; then
  # A forced push rewrote history: event.before may not be an ancestor of HEAD,
  # so a diff against it can misattribute. Only the full sweep is trustworthy.
  run_full_sweep "forced push -- no trustworthy diff base" expected
fi
if [ -n "${BEFORE_REV}" ]; then
  # Verify it resolves to a commit (a just-created ref reports the zero SHA,
  # which does not resolve).
  if ! git rev-parse --verify --quiet "${BEFORE_REV}^{commit}" >/dev/null; then
    run_full_sweep "BEFORE_REV '${BEFORE_REV}' does not resolve to a commit" expected
  fi
  echo "affected-targets: before-rev (explicit) = ${BEFORE_REV}"
elif [ -n "${BASE_REF}" ]; then
  if ! BEFORE_REV="$(git merge-base "origin/${BASE_REF}" HEAD)"; then
    run_full_sweep "could not compute merge-base against origin/${BASE_REF}" degraded
  fi
  echo "affected-targets: before-rev (merge-base) = ${BEFORE_REV}"
else
  run_full_sweep "neither BEFORE_REV nor BASE_REF is set" degraded
fi

# --- 2. global-impact guard. -------------------------------------------------
# These files change build semantics for (potentially) every target, in ways a
# graph diff may under- or mis-attribute. A change to any of them is treated as
# "everything is affected" -> full sweep.
#
#   MODULE.bazel / MODULE.bazel.lock  external dep graph (every target).
#   .bazelrc / .bazelversion          flags + toolchain version (every build);
#                                     .bazelrc also defines --config=macos-app.
#   tools/                            toolchains, platforms, the imported
#                                     preset/java17/remote .bazelrc files,
#                                     formatters, lint aspects, macros, etc.
#                                     (.bazelrc `import`s tools/*.bazelrc).
#   ^BUILD$ (root)                    the root package: gazelle directives, the
#                                     Python manifest macro, multirun wiring --
#                                     it shapes the target universe itself.
#   gazelle_python.yaml (root)        Python dependency mapping that drives
#                                     BUILD generation; a graph diff may not see
#                                     a dep remap until BUILD files regenerate.
# NOTE: .github/workflows/** is deliberately NOT global-impact. A workflow-file
# edit changes zero Bazel targets, so it must not force a full //... sweep on
# every PR that touches CI. A workflow that changes how the build runs is
# validated by that workflow running on its own PR; and tools/** below still
# force-sweeps on any change to tools/ci/affected-targets.sh (this script).
#
# We diff names only (no content) between the merge-base and the working tree.
CHANGED_FILES="$(git diff --name-only "${BEFORE_REV}" -- || true)"
if [ -z "${CHANGED_FILES}" ]; then
  echo "affected-targets: no changed files detected vs ${BEFORE_REV}; nothing to do."
  exit 0
fi
echo "affected-targets: changed files:"
echo "${CHANGED_FILES}" | sed 's/^/  /'

# --- docs/metadata-only fast path. -------------------------------------------
# If EVERY changed file lives under docs/, gitops/, or is a standalone .md/metadata file,
# there are zero Bazel targets to build or test. Short-circuit before fetching
# target-determinator (which itself takes minutes for the download + two full
# Bazel analyses). Same ignore set as tools/ci/relevant-paths.sh.
NON_DOC="$(echo "${CHANGED_FILES}" | grep -E -v -c '^(gitops/|docs/|\.agents/)|\.(md|png|jpg|jpeg|svg|txt)$|(^|/)(catalog-info\.yaml|OWNERS|CODEOWNERS)$' || true)"
if [ "${NON_DOC}" -eq 0 ]; then
  echo "::notice::affected-targets: all changed files are docs/gitops/markdown/metadata-only → nothing to build or test."
  exit 0
fi

# Anchored at start-of-path. `BUILD` and `gazelle_python.yaml` are matched ONLY
# at the repo root (^BUILD$, ^gazelle_python\.yaml$); nested package BUILD files
# are intentionally left to the graph diff.
# For `tools/`, we explicitly exclude administrative subdirectories that do not
# alter the Bazel build graph (e.g. ci, copybara, scripts) to prevent unnecessary sweeps.
#
# The allowlist below MUST stay byte-identical to the one in deploy-affected.sh
# (`//tools/conformance:check` check_ci_gate_lists_match asserts it), so the
# deploy gate and the test gate can never disagree about what a change affects.
#
# `deploy/` is allowlisted even though it ships tools/deploy/defs.bzl: that .bzl
# is loaded by exactly two packages (tabula/infra/app, oauth-user-inspector/
# infra/app) and the generated sh_binary carries srcs=["//tools/deploy:
# cloud-run.sh"], so BOTH edges are target-determinator-tracked and land on the
# two dependent `:deploy` targets -- same class as the already-allowlisted
# gitops/defs.bzl and lint/linters.bzl. The DEPLOY half of this pair does not
# graph-track cloud-run.sh (its universe is DEPLOY_TARGETS, which holds the
# image/zip artifacts, not `:deploy`), so the tabula delivery() units carry
# `tools/deploy/` in EXTRA_PATH_REGEX to keep that gate firing -- narrowing the
# TEST sweep here must never silently narrow the fail-open deploy gate.
if echo "${CHANGED_FILES}" | grep -E '^(MODULE\.bazel|MODULE\.bazel\.lock|\.bazelrc|\.bazelversion|BUILD$|gazelle_python\.yaml$)' >/dev/null 2>&1 || \
   echo "${CHANGED_FILES}" | grep -E '^tools/' | grep -E -v '^tools/(ci/|cluster/|conformance/|copybara/|deploy/|doctor/|format/|gcp-secrets/|gitops/|license/|lint/|release/|rotate-buildbuddy-key/|saas-cli/|scripts/|sync-env-secrets/|worktree/|repin$)' >/dev/null 2>&1; then
  run_full_sweep "global-impact file changed (MODULE.bazel/lockfile/.bazelrc/.bazelversion/tools/**/root BUILD/gazelle_python.yaml)" expected
fi

# --- 3. Change detection plan via //tools/pipeline:plan ----------------------
# RDEPS_MAP (#2841) is the dependency map for the diff base, restored by the
# workflow from the cache Presubmit's push lane writes (#2465). With it the
# planner looks the affected tests up in milliseconds; without it (unset, file
# missing, wrong commit, unknown package) the planner runs a live `bazel query`
# over the whole repo, which takes minutes on a cold runner. The planner checks
# the map against the diff base itself, so a wrong map is never used.
RDEPS_MAP="${RDEPS_MAP:-}"
PLAN_BUDGET_SEC="${PLAN_BUDGET_SEC:-120}"
PLAN_ERR="$(mktemp)"
PLAN_ARGS=(--base="${BEFORE_REV}" --head=HEAD --format=json)
if [ -n "${RDEPS_MAP}" ]; then
  PLAN_ARGS+=(--rdeps-map="${RDEPS_MAP}")
fi
# PLAN_BIN is the planner prebuilt by the workflow with plain `go build`, the
# way Presubmit builds it. `bazel run` gives the same answer but spends about
# two minutes starting Bazel and building the planner first (134s measured on
# this job with the map already in hand), so it is only the fallback.
PLAN_BIN="${PLAN_BIN:-}"
plan_start="${SECONDS}"
if [ -n "${PLAN_BIN}" ] && [ -x "${PLAN_BIN}" ]; then
  PLAN_OUTPUT="$("${PLAN_BIN}" "${PLAN_ARGS[@]}" --repo-root="${PWD}" 2>"${PLAN_ERR}" || true)"
else
  PLAN_OUTPUT="$(bazel run //tools/pipeline:plan -- "${PLAN_ARGS[@]}" 2>"${PLAN_ERR}" || true)"
fi
plan_secs=$((SECONDS - plan_start))

if [ -z "${PLAN_OUTPUT}" ]; then
  # Fail-safe fallback to full sweep if plan binary could not execute
  echo "affected-targets: planner produced no plan after ${plan_secs}s; last lines of its output:"
  tail -n 30 "${PLAN_ERR}" || true
  run_full_sweep "change detection plan failed -- fail-closed fallback" degraded
fi

IS_DOCS_ONLY="$(echo "${PLAN_OUTPUT}" | jq -r '.is_docs_only // false' 2>/dev/null || echo "false")"
IS_FULL_SWEEP="$(echo "${PLAN_OUTPUT}" | jq -r '.is_global_impact // false' 2>/dev/null || echo "true")"
PLAN_SOURCE="$(echo "${PLAN_OUTPUT}" | jq -r '.plan_source // ""' 2>/dev/null || true)"
TARGETS=($(echo "${PLAN_OUTPUT}" | jq -r '.targets[]?' 2>/dev/null || true))

# Say where the answer came from and how long it took. A slow selection used to
# be seven silent minutes in the log (#2841); now it is one line.
echo "affected-targets: plan took ${plan_secs}s (source: ${PLAN_SOURCE:-none})"
grep -E '(no dependency map for|dependency map not used)' "${PLAN_ERR}" || true
echo "${PLAN_OUTPUT}" | jq -r '.plan_source_note // empty | "affected-targets: " + .' 2>/dev/null || true
# Regression guard: with the map in hand the plan is a lookup, so a slow one
# means something else regressed (the planner build, the Bazel startup). Warn
# only -- a required check must never fail on timing alone.
if [ "${PLAN_SOURCE}" = "rdeps-map" ] && [ "${plan_secs}" -gt "${PLAN_BUDGET_SEC}" ]; then
  echo "::warning title=affected-selection-slow::affected-targets: the plan used the dependency map but still took ${plan_secs}s (budget ${PLAN_BUDGET_SEC}s)"
fi

if [ "${IS_DOCS_ONLY}" = "true" ]; then
  echo "::notice::affected-targets: all changed files are docs/gitops/markdown-only → nothing to build or test."
  exit 0
fi

if [ "${IS_FULL_SWEEP}" = "true" ] || [ "${#TARGETS[@]}" -eq 0 ]; then
  run_full_sweep "full sweep required by change detection plan" expected
fi

# A map-sourced list describes the DIFF BASE, not this change, so inside the
# changed packages it can be wrong in both directions: it misses a test this
# change adds and still names one this change deletes or renames. (Outside the
# changed packages it is exact -- adding or removing a test means editing its
# package's BUILD file.) So for the changed packages, drop the map's labels and
# ask Bazel for every test there at HEAD instead (`//pkg:all` with
# --build_tests_only). That is the same set the live query returns: every
# non-manual test in a changed package depends on that package.
TEST_ARGS=()
if [ "${PLAN_SOURCE}" = "rdeps-map" ]; then
  PKGS=($(echo "${PLAN_OUTPUT}" | jq -r '.affected_packages[]?' 2>/dev/null || true))
  if [ "${#PKGS[@]}" -eq 0 ]; then
    run_full_sweep "dependency-map plan lists no changed packages" degraded
  fi
  PKG_LIST="$(printf '\n%s' "${PKGS[@]}")"$'\n'
  KEPT=()
  for t in "${TARGETS[@]}"; do
    case "${PKG_LIST}" in
      *$'\n'"${t%%:*}:all"$'\n'*) ;;
      *) KEPT+=("${t}") ;;
    esac
  done
  TARGETS=(${KEPT[@]+"${KEPT[@]}"} "${PKGS[@]}")
  TEST_ARGS=(--build_tests_only)
fi

echo "affected-targets: executing ${#TARGETS[@]} affected test targets:"
printf '  %s\n' "${TARGETS[@]}"
rc=0
bazel test "${REMOTE_ARGS[@]}" ${TEST_ARGS[@]+"${TEST_ARGS[@]}"} "${TARGETS[@]}" || rc=$?
if [ "${rc}" -eq 4 ] && [ "${PLAN_SOURCE}" = "rdeps-map" ]; then
  # Exit 4 = the build succeeded but no test matched: this change removed every
  # test the map knew about. The live query would have returned an empty list,
  # which full-sweeps (above); do the same.
  run_full_sweep "no tests left in the changed packages" expected
fi
exit "${rc}"
