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

# Anchored at start-of-path. `BUILD` and `gazelle_python.yaml` are matched ONLY
# at the repo root (^BUILD$, ^gazelle_python\.yaml$); nested package BUILD files
# are intentionally left to the graph diff.
if echo "${CHANGED_FILES}" | grep -E \
  '^(MODULE\.bazel|MODULE\.bazel\.lock|\.bazelrc|\.bazelversion|tools/|BUILD$|gazelle_python\.yaml$)' \
  >/dev/null 2>&1; then
  run_full_sweep "global-impact file changed (MODULE.bazel/lockfile/.bazelrc/.bazelversion/tools/**/root BUILD/gazelle_python.yaml)"
fi

# --- 3. download + run target-determinator. ----------------------------------
# WHY a prebuilt binary and NOT `go install`: target-determinator's Bazel proto
# bindings (third_party/protobuf/bazel/{analysis,build}) are generated by protoc
# *via Bazel* at build time and are .gitignore'd upstream, so the published Go
# module ships only an empty `package analysis` / `package build` stub. A pure
# `go install` therefore compiles those packages empty and ALWAYS fails with
# "undefined: analysis.ConfiguredTarget" -- for every released version, not just
# one (this is NOT a clash with our Bazel/rules_go version). Upstream's
# documented install path (README, "How to get Target Determinator") is the
# prebuilt GitHub release binary, which we fetch and checksum-pin here -- the
# same digest-pinning this repo already applies to its third-party GitHub
# Actions. The binary just shells out to `--bazel bazel` (our bazelisk-resolved
# 9.1.1), so the Bazel it was built against is irrelevant at runtime.
#
# This job runs on linux/amd64 only; any other host, a download error, or a
# checksum mismatch falls through to the full //... sweep (the safety invariant
# above). Bump TD_VERSION and TD_SHA256 together; TD_SHA256 is the sha256 of the
# `target-determinator.linux.amd64` release asset for TD_VERSION.
TD_VERSION="v0.34.0"
TD_SHA256="115e1c63d39e2cd0d0b011c9fadc80f059f021176a4ae0de2232cdd83b1f8011"

case "$(uname -s)/$(uname -m)" in
  Linux/x86_64) TD_ASSET="target-determinator.linux.amd64" ;;
  *) run_full_sweep "no pinned target-determinator binary for $(uname -s)/$(uname -m)" ;;
esac

TD="$(mktemp -d)/target-determinator"
TD_URL="https://github.com/bazel-contrib/target-determinator/releases/download/${TD_VERSION}/${TD_ASSET}"
echo "affected-targets: downloading target-determinator ${TD_VERSION} (${TD_ASSET})..."
if ! curl -fsSL --retry 4 --retry-delay 2 --retry-all-errors -o "${TD}" "${TD_URL}"; then
  run_full_sweep "target-determinator download failed (${TD_URL})"
fi
echo "${TD_SHA256}  ${TD}" > "${TD}.sha256"
if ! sha256sum --check --status "${TD}.sha256"; then
  run_full_sweep "target-determinator checksum mismatch (expected ${TD_SHA256} for ${TD_ASSET})"
fi
chmod +x "${TD}"

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

