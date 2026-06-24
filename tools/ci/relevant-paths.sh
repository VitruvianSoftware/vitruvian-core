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

# relevant-paths.sh — decide whether a PR's diff warrants running the heavy CI
# work, or whether it is docs/gitops-only and the heavy steps can be skipped.
#
# Emits `relevant=true|false` to $GITHUB_OUTPUT (and stdout). This is a CI
# *lead-time* optimisation ONLY; it is never the safety floor:
#
#   * It runs on pull_request ONLY. push-to-main (postsubmit) and merge_group
#     (the merge queue, #83) ALWAYS do the full work in the workflow and never
#     call this script -- so the worst case is unchanged.
#   * It FAILS SAFE. Any uncertainty -- non-PR event, missing BASE_REF, a diff
#     we cannot compute -- yields relevant=true (run the heavy work). The only
#     way to get relevant=false is a successfully-computed, non-empty diff in
#     which EVERY changed file is docs/gitops/markdown.
#
# A required status check (build-test / tidy-check) calls this from its first
# step and then gates the heavy steps on the output, so the check ALWAYS
# reports a status (it just finishes green in seconds when relevant=false) and
# never leaves a merge-queue PR stuck "pending".
#
# Optional environment (set by the workflow):
#   BASE_REF   github.base_ref, e.g. "main" (the PR target branch). Required to
#              be meaningful; if empty we fail safe to relevant=true.

set -euo pipefail

# emit KEY=VALUE to the step output (and echo it) and exit. GITHUB_OUTPUT is
# always set under Actions; when run locally (no GITHUB_OUTPUT) we just print.
emit() {
  local value="$1" reason="$2"
  echo "relevant-paths: relevant=${value} (${reason})"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "relevant=${value}" >> "${GITHUB_OUTPUT}"
  fi
  exit 0
}

# --- fail-safe guards: anything uncertain -> run the heavy work. -------------
BASE_REF="${BASE_REF:-}"
if [ -z "${BASE_REF}" ]; then
  emit true "no BASE_REF (not a pull_request, or base branch unknown) -> run"
fi

# Merge-base of the PR against its target branch. fetch-depth: 0 (ci.yaml) or an
# explicit fetch (tidy-check.yaml) guarantees origin/$BASE_REF is present. If we
# cannot compute it we cannot trust the diff -> run the heavy work.
if ! BEFORE_REV="$(git merge-base "origin/${BASE_REF}" HEAD 2>/dev/null)"; then
  emit true "could not compute merge-base against origin/${BASE_REF} -> run"
fi

# Name-only diff between the merge-base and the working tree (HEAD).
if ! CHANGED_FILES="$(git diff --name-only "${BEFORE_REV}" HEAD 2>/dev/null)"; then
  emit true "could not compute diff vs ${BEFORE_REV} -> run"
fi

# No changed files at all (e.g. an empty/no-op PR): nothing heavy to do, but be
# conservative and run -- this is not the docs-only fast path we are optimising.
if [ -z "${CHANGED_FILES}" ]; then
  emit true "no changed files detected vs ${BEFORE_REV} -> run"
fi

echo "relevant-paths: changed files vs ${BEFORE_REV}:"
echo "${CHANGED_FILES}" | sed 's/^/  /'

# --- the decision. -----------------------------------------------------------
# relevant=false ONLY when EVERY changed file is docs/gitops/markdown, i.e. it
# matches `^(gitops/|docs/)` or ends in `.md`. We invert: count any file that is
# NOT in that ignore set; if there are zero such files, the diff is docs-only.
#
# grep -E -v -c prints the count of NON-matching lines. We do NOT pipe its exit
# status (set -o pipefail + grep exit 1 on zero matches) into the script's
# control flow: the count is what we branch on.
NON_IGNORED="$(echo "${CHANGED_FILES}" | grep -E -v -c '^(gitops/|docs/)|\.md$' || true)"

if [ "${NON_IGNORED}" -eq 0 ]; then
  emit false "every changed file is gitops/ docs/ or *.md -> skip heavy work"
fi

emit true "${NON_IGNORED} changed file(s) outside gitops/docs/*.md -> run"
