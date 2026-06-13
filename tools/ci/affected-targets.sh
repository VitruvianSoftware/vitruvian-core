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

# affected-targets.sh — compute the Bazel targets affected by a PR diff, then
# build (and test) exactly those targets against the BuildBuddy remote.
#
# SAFETY INVARIANT (issue #81): the worst case must never be less safe than a
# full `//...` sweep. Every uncertain or error path in here FALLS BACK to
# `bazel build/test //...`. This script is only ever invoked on pull_request;
# push-to-main (postsubmit) always runs the unconditional full sweep in the
# workflow and never calls this script.
#
# Required environment (set by the workflow):
#   BUILDBUDDY_API_KEY  RBE/remote-cache auth header value.
#   BASE_REF            github.base_ref, e.g. "main" (the PR target branch).
#
# Flow:
#   1. Determine BEFORE_REV = git merge-base origin/$BASE_REF HEAD.
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

# run_full_sweep: the safe fallback. Identical semantics to the postsubmit job.
run_full_sweep() {
  echo "::notice::affected-targets: falling back to full //... build+test ($1)"
  bazel build "${REMOTE_ARGS[@]}" //...
  bazel test "${REMOTE_ARGS[@]}" //...
  exit 0
}

BASE_REF="${BASE_REF:?BASE_REF must be set (github.base_ref)}"

# --- 1. before-revision = merge-base of the PR against its target branch. ----
# fetch-depth: 0 in the workflow guarantees the merge-base is present locally.
# If we cannot compute it, we cannot trust the diff -> full sweep.
if ! BEFORE_REV="$(git merge-base "origin/${BASE_REF}" HEAD)"; then
  run_full_sweep "could not compute merge-base against origin/${BASE_REF}"
fi
echo "affected-targets: before-rev (merge-base) = ${BEFORE_REV}"

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
#   .github/workflows/                any workflow file: this CI, plus the
#                                     copybara/repo-config/tabula lanes that can
#                                     reshape build inputs.
#
# We diff names only (no content) between the merge-base and the working tree.
CHANGED_FILES="$(git diff --name-only "${BEFORE_REV}" -- || true)"
if [ -z "${CHANGED_FILES}" ]; then
  echo "affected-targets: no changed files detected vs ${BEFORE_REV}; nothing to do."
  exit 0
fi
echo "affected-targets: changed files:"
echo "${CHANGED_FILES}" | sed 's/^/  /'

# Anchored at start-of-path. `BUILD` and `gazelle_python.yaml` are matched ONLY
# at the repo root (^BUILD$, ^gazelle_python\.yaml$); nested package BUILD files
# are intentionally left to the graph diff. `.github/workflows/` (no $) matches
# every workflow file under that directory.
if echo "${CHANGED_FILES}" | grep -E \
  '^(MODULE\.bazel|MODULE\.bazel\.lock|\.bazelrc|\.bazelversion|tools/|BUILD$|gazelle_python\.yaml$|\.github/workflows/)' \
  >/dev/null 2>&1; then
  run_full_sweep "global-impact file changed (MODULE.bazel/lockfile/.bazelrc/.bazelversion/tools/**/root BUILD/gazelle_python.yaml/.github/workflows/**)"
fi

# --- 3. install + run target-determinator. -----------------------------------
# go install drops the binary in GOPATH/bin, which is not on PATH on the runner
# (same pattern as addlicense). The package lives at the repo root, NOT cmd/.
echo "affected-targets: installing target-determinator..."
if ! go install github.com/bazel-contrib/target-determinator/target-determinator@v0.33.2; then
  run_full_sweep "target-determinator install failed"
fi
TD="$(go env GOPATH)/bin/target-determinator"

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
      --bazel-opts "--config=remote --remote_header=x-buildbuddy-api-key=${BUILDBUDDY_API_KEY}" \
      --before-query-error-behavior=ignore-and-build-all \
      --ignore-file .github/workflows/ci.yaml \
      --ignore-file tools/ci/affected-targets.sh \
      "${BEFORE_REV}" > affected.txt; then
  run_full_sweep "target-determinator returned non-zero"
fi

# --- 4 + 5. empty-set handling. ----------------------------------------------
# [ -s file ] is true only for a non-empty regular file; this also covers the
# "TD wrote nothing" case. An empty affected set is a clean no-op, not an error.
# NB: by the time we get here the global-impact guard has already force-swept on
# any build-config change, so an empty set means a non-global diff that TD
# attributes to zero targets (e.g. a touched-but-unreferenced data file). The
# safety floor for such a change is the postsubmit //... sweep that runs when
# the PR lands on main.
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

