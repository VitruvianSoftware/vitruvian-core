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

# --- docs-only fast path. ----------------------------------------------------
# If EVERY changed file lives under docs/, gitops/, or is a standalone .md file,
# there are zero Bazel targets to build or test. Short-circuit before fetching
# target-determinator (which itself takes minutes for the download + two full
# Bazel analyses). Same ignore set as tools/ci/relevant-paths.sh.
NON_DOC="$(echo "${CHANGED_FILES}" | grep -E -v -c '^(gitops/|docs/)|\.md$' || true)"
if [ "${NON_DOC}" -eq 0 ]; then
  echo "::notice::affected-targets: all changed files are docs/gitops/markdown-only → nothing to build or test."
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

# --- 3. build + test EVERYTHING. ----------------------------------------------
# There is deliberately no affected-target selection here any more.
#
# target-determinator was measured 2026-07-27 to cost MORE than the work it
# avoids on this repo, in every observed case including its best one:
#
#   full //... sweep, no TD (global-impact runs)        393s / 399s / 407s
#   TD, empty affected set                              441s / 470s
#   TD, 8 affected targets                              506s
#   TD, 64 affected targets (178-file diff, PR #1268)   579s
#
# The reason is BuildBuddy. A full sweep is cheap because the remote cache
# absorbs it -- a representative sweep reports "Executed 5 out of 105 tests",
# i.e. 100 of 105 were cache hits. So the marginal cost of NOT knowing which
# targets changed is ~100 cache lookups, which is nearly free.
#
# TD spent ~450s of `cquery` over a 9,101-target universe to avoid that, and
# that cost is UNIVERSE-bound, not diff-bound: identical whether the diff is one
# YAML file or 178 files. Meanwhile the build work itself is the same either
# way, because the sweep cache-hits everything TD would have excluded. So
#
#   TD path  ~=  full sweep  +  ~450s analysis  -  ~0s avoided work
#
# and it cannot come out ahead while the remote cache is warm. The one case
# where a sweep genuinely IS expensive -- a cold cache after a toolchain or
# MODULE.bazel change -- is already routed past selection by the global-impact
# guard above, which sweeps unconditionally.
#
# Removing selection also deletes a whole class of defect. #1265 tried to make
# TD cheaper by persisting its results cache and instead made it OVER-select:
# restored before-rev hashes are not comparable with freshly-computed after-rev
# hashes, so a workflow-only diff "affected" 8 targets including a flaky
# Playwright suite, and main went red. With no selection there is nothing to get
# wrong. See #1262 for the full measurements and history.
#
# The cheap short-circuits ABOVE are kept and still matter: a docs/gitops/md-only
# diff exits without building anything at all.
run_full_sweep "affected-target selection removed -- a full sweep is cheaper than computing what to skip (#1262)" expected
