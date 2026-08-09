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

# bisect-culprit.sh — mechanical culprit-finding for a red nightly sweep
# (#501, docs/engineering/flaky-tests.md).
#
# Bisects [GOOD_SHA, BAD_SHA] with `git bisect run` driving `bazel test` on
# exactly the failing targets. Affected-scoped merge lanes mean a breakage
# that slips past graph attribution could have landed with any commit since
# the last green sweep; with the remote cache, each midpoint costs roughly one
# incremental test run, so log2(range) steps are cheap.
#
# Environment:
#   GOOD_SHA   last known-green commit (required).
#   BAD_SHA    known-red commit (required).
#   TARGETS    space-separated Bazel labels to test (required).
#   BAZEL_ARGS extra args for bazel test (e.g. --config=remote + auth header).
#   TEST_CMD   override for the per-commit command (test hook; git-bisect-run
#              semantics: exit 0 good, 1-124 bad, 125 skip).
#
# Output: `culprit=<sha>` (+ `culprit_subject=...`) to $GITHUB_OUTPUT and
# stdout on success; exits non-zero if bisect could not identify a single
# first-bad commit (e.g. flaky-in-range, bad GOOD_SHA).

set -euo pipefail

GOOD_SHA="${GOOD_SHA:?GOOD_SHA must be set (last green commit)}"
BAD_SHA="${BAD_SHA:?BAD_SHA must be set (known red commit)}"
TARGETS="${TARGETS:?TARGETS must be set (space-separated Bazel labels)}"
BAZEL_ARGS="${BAZEL_ARGS:-}"

for rev in "$GOOD_SHA" "$BAD_SHA"; do
  if ! git rev-parse --verify --quiet "${rev}^{commit}" >/dev/null; then
    echo "::error::bisect-culprit: '$rev' does not resolve to a commit" >&2
    exit 2
  fi
done

# Sanity: GOOD must be an ancestor of BAD or bisect degenerates.
#
# EQUALITY FIRST, because `--is-ancestor` CANNOT catch it: a commit is its own
# ancestor, so `is-ancestor S S` exits 0 and the guard below never fires on the
# one input its own comment says degenerates bisect.
#
# Measured, not assumed (bisect-culprit_test.sh pins it): without this guard the
# run prints "bisecting 0 commit(s) in <sha>..<sha>", then `git bisect start`
# refuses with "was both 'good' and 'bad'" and `set -e` kills the script THERE —
# it never reaches the "did not converge" message below. It fails closed, so the
# answer is never wrong. What is wrong is the exit code: this script's contract
# is 2 for a caller/input error and 1 for "bisect could not identify a culprit",
# and a same-commit range reports as the second. That sends whoever is chasing a
# red sweep after flakiness in a range that never had two commits in it.
#
# Compared as resolved commit objects rather than as strings: the two may
# arrive as a tag and a sha, or abbreviated and full, and still be one commit.
if [ "$(git rev-parse "${GOOD_SHA}^{commit}")" = "$(git rev-parse "${BAD_SHA}^{commit}")" ]; then
  echo "::error::bisect-culprit: GOOD_SHA and BAD_SHA are the same commit — nothing to bisect" >&2
  exit 2
fi

if ! git merge-base --is-ancestor "$GOOD_SHA" "$BAD_SHA"; then
  echo "::error::bisect-culprit: GOOD_SHA is not an ancestor of BAD_SHA" >&2
  exit 2
fi

cleanup() { git bisect reset >/dev/null 2>&1 || true; }
trap cleanup EXIT

echo "bisect-culprit: bisecting $(git rev-list --count "${GOOD_SHA}".."${BAD_SHA}") commit(s) in ${GOOD_SHA:0:12}..${BAD_SHA:0:12}"
git bisect start "$BAD_SHA" "$GOOD_SHA"

# git bisect run interprets exit codes: 0 good, 125 skip, 1-124/126-127 bad.
# bazel's exit codes (1 build error, 3 tests failed, ...) all land in "bad",
# which is what we want -- a commit that no longer builds IS the culprit class
# this hunts. `|| true` so a run failure at the final step doesn't kill the
# script before we read the result.
BISECT_LOG="$(mktemp)"
if [ -n "${TEST_CMD:-}" ]; then
  git bisect run bash -c "${TEST_CMD}" 2>&1 | tee "$BISECT_LOG" || true
else
  # shellcheck disable=SC2086
  git bisect run bazel test ${BAZEL_ARGS} ${TARGETS} 2>&1 | tee "$BISECT_LOG" || true
fi

# git <=2.4x prints "<sha> is the first bad commit"; newer git quotes the
# term ("... the first 'bad' commit"). Accept both.
CULPRIT="$(sed -n "s/^\([0-9a-f]\{40\}\) is the first '\{0,1\}bad'\{0,1\} commit\$/\1/p" "$BISECT_LOG" | head -n1)"
if [ -z "$CULPRIT" ]; then
  echo "::error::bisect-culprit: bisect did not converge on a single first-bad commit (flaky in range, or GOOD_SHA red?)" >&2
  exit 1
fi

SUBJECT="$(git log -1 --format=%s "$CULPRIT")"
echo "bisect-culprit: culprit=${CULPRIT} (${SUBJECT})"
if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "culprit=${CULPRIT}"
    echo "culprit_subject=${SUBJECT}"
  } >> "$GITHUB_OUTPUT"
fi
