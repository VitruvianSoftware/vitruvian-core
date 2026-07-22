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

# affected-targets.sh — compute the Bazel targets affected by a diff, then
# build (and test) exactly those targets against the BuildBuddy remote.
#
# SAFETY INVARIANT (issue #81): the worst case must never be less safe than a
# full `//...` sweep. Every uncertain or error path in here FALLS BACK to
# `bazel build/test //...`. Invoked on all three ci.yaml lanes:
#   pull_request  BASE_REF set        -> before-rev = merge-base vs origin/base
#   merge_group   BEFORE_REV set to github.event.merge_group.base_sha
#   push (main)   BEFORE_REV set to github.event.before (the pre-push tip);
#                 FORCED_PUSH=true -> full sweep (rewritten history has no
#                 trustworthy diff base).
#
# The cross-lane backstop for affected-selection under-attribution (e.g. an
# empty affected set for a touched-but-unreferenced data file) is the scheduled
# periodic-full-sweep.yaml workflow; //tools/conformance:check enforces that it
# exists for as long as merge_group/push run affected-scoped.
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
#   2. If global-impact files changed (MODULE.bazel, lockfile, .bazelrc,
#      .bazelversion, tools/**, root BUILD, gazelle_python.yaml, any
#      .github/workflows/ file), short-circuit to //... .
#   3. Otherwise run target-determinator to produce affected.txt.
#   4. If TD fails, or affected.txt is unreadable -> fall back to //... .
#   5. If affected.txt is empty -> nothing to do, exit 0 cleanly.
#   6. build the whole affected set, then test ONLY the testable subset
#      (--build_tests_only) so a build-only/zero-test set never errors.

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
if echo "${CHANGED_FILES}" | grep -E '^(MODULE\.bazel|MODULE\.bazel\.lock|\.bazelrc|\.bazelversion|BUILD$|gazelle_python\.yaml$)' >/dev/null 2>&1 || \
   echo "${CHANGED_FILES}" | grep -E '^tools/' | grep -E -v '^tools/(ci/|cluster/|conformance/|copybara/|doctor/|format/|gitops/|license/|lint/|rotate-buildbuddy-key/|scripts/|sync-env-secrets/|worktree/|repin$)' >/dev/null 2>&1; then
  run_full_sweep "global-impact file changed (MODULE.bazel/lockfile/.bazelrc/.bazelversion/tools/**/root BUILD/gazelle_python.yaml)" expected
fi

# --- 3. fetch + run target-determinator. -------------------------------------
# The pinned TD version/checksum + fetch logic live in tools/ci/td-lib.sh (one
# source shared with the deploy gate, tools/ci/deploy-affected.sh, so the pin
# can never drift between callers). Any fetch failure -- unsupported host,
# download error, checksum mismatch -- falls through to the full //... sweep
# (the safety invariant above).
# shellcheck source=tools/ci/td-lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/td-lib.sh"
if ! fetch_td; then
  run_full_sweep "${TD_FETCH_ERROR}" degraded
fi

# Run TD:
#   --bazel bazel                       use the repo's bazelisk-resolved bazel.
#   --targets //...                     universe to diff over.
#   --bazel-opts                        opts threaded into TD's analysis
#                                       cqueries -> remote auth, so the two
#                                       analysis passes hit the same RBE cache
#                                       the build will.
#   --before-query-error-behavior=ignore-and-build-all
#                                       if the BEFORE revision fails to analyze
#                                       (e.g. a since-deleted package), TD emits
#                                       //... rather than erroring -> stays safe.
#   --ignore-file                       this workflow + the script never trigger
#                                       a graph rebuild on their own (the global
#                                       guard above already force-fulls on real
#                                       build-config changes).
# NB: never pass --verbose; with it each line becomes "label  reason", which is
# not a valid Bazel target pattern when fed back via --target_pattern_file.
echo "affected-targets: computing affected set since ${BEFORE_REV}..."
if ! "${TD}" \
      --bazel bazel \
      --targets "//..." \
      --bazel-opts="--config=remote" \
      --bazel-opts="--remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}" \
      --before-query-error-behavior=ignore-and-build-all \
      --ignore-file .github/workflows/ci.yaml \
      --ignore-file tools/ci/affected-targets.sh \
      "${BEFORE_REV}" > affected.txt; then
  run_full_sweep "target-determinator returned non-zero" degraded
fi

# --- 4 + 5. empty-set handling. ----------------------------------------------
# [ -s file ] is true only for a non-empty regular file; this also covers the
# "TD wrote nothing" case. An empty affected set is a clean no-op, not an error.
# NB: by the time we get here the global-impact guard has already force-swept on
# any build-config change, so an empty set means a non-global diff that TD
# attributes to zero targets (e.g. a touched-but-unreferenced data file). The
# safety floor for such a change is the scheduled periodic-full-sweep.yaml
# workflow (nightly full //...), which bounds any miss to <24h.
if [ ! -s affected.txt ]; then
  echo "::notice::affected-targets: empty affected set -> nothing to build or test."
  exit 0
fi

echo "affected-targets: $(wc -l < affected.txt) affected target(s):"
sed 's/^/  /' affected.txt

# --- 6. build the full affected set, then test only its testable subset. -----
# bazel build accepts non-test targets; `bazel test` over a mixed/zero-test set
# errors (exit 4 "no test targets were found"). So: build everything, then test
# with --build_tests_only, which restricts to test targets in the pattern set
# and is a clean no-op when there are none. Both honor the default
# --test_tag_filters=-e2e from .bazelrc.
echo "affected-targets: building affected targets..."
bazel build "${REMOTE_ARGS[@]}" --target_pattern_file=affected.txt

echo "affected-targets: testing affected test targets (build_tests_only)..."
# Even with --build_tests_only, `bazel test` exits 4 ("no test targets were
# found") when the affected set contains zero test targets -- a legitimate
# non-test PR (e.g. only a genrule/docs target changed), NOT a real failure.
# So: tolerate ONLY exit 4 here; any other non-zero is a genuine test failure
# and must propagate. `set -e` is suspended for just this one command.
test_rc=0
bazel test "${REMOTE_ARGS[@]}" --build_tests_only --target_pattern_file=affected.txt || test_rc=$?
if [ "${test_rc}" -eq 0 ]; then
  echo "affected-targets: affected tests passed."
elif [ "${test_rc}" -eq 4 ]; then
  echo "::notice::affected-targets: no test targets in affected set (exit 4) -> build-only PR, OK."
else
  echo "::error::affected-targets: affected tests failed (bazel exit ${test_rc})."
  exit "${test_rc}"
fi

