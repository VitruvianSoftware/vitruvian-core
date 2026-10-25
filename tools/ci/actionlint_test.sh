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

# actionlint_test.sh — //tools/ci:actionlint fails on what the required
# actionlint check fails on (a broken expression, a shellcheck warning in a
# `run:` block, an action not pinned to a SHA), passes a clean workflow, and runs
# the actionlint version the workflow pins. Real pinned binaries, throwaway repos.
set -uo pipefail

SCRIPT="${1:?usage: actionlint_test.sh <actionlint.sh> <actionlint.yaml> <tools.lock.json>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
WORKFLOW="$(cd "$(dirname "$2")" && pwd)/$(basename "$2")"
LOCK="$(cd "$(dirname "$3")" && pwd)/$(basename "$3")"
# ACTIONLINT_UNDER_TEST runs the same suite against another build of the tool
# (the Rust port, :actionlint-rs_test), called as the script is.
if [ -n "${ACTIONLINT_UNDER_TEST:-}" ]; then
    case "$ACTIONLINT_UNDER_TEST" in /*) ;; *) ACTIONLINT_UNDER_TEST="$PWD/$ACTIONLINT_UNDER_TEST" ;; esac
    UNDER_TEST=("$ACTIONLINT_UNDER_TEST")
else
    UNDER_TEST=(bash "$SCRIPT")
fi

work="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }
export HOME="$work/home" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"

SHA="0123456789abcdef0123456789abcdef01234567"
new_repo() { # <dir> <workflow body>: a repo holding one workflow
    mkdir -p "$1/.github/workflows"
    git init -q "$1"
    printf '%s\n' "$2" >"$1/.github/workflows/w.yaml"
}
lint() { (cd "$work" && BUILD_WORKSPACE_DIRECTORY="$1" "${UNDER_TEST[@]}"); }

GOOD="on: push
permissions: {}
jobs:
  a:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@${SHA} # v4
      - run: echo \"\$GITHUB_SHA\""

new_repo "$work/good" "$GOOD"
out="$(lint "$work/good" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ] && grep -q "pinned to a commit SHA" <<<"$out"; then
    pass "a clean, pinned workflow passes"
else
    fail "a clean workflow failed (rc=$rc): $out"
fi

new_repo "$work/expr" "${GOOD}
      - run: echo \${{ github.no_such_context.x }}"
out="$(lint "$work/expr" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "w.yaml" <<<"$out" && grep -q "no_such_context" <<<"$out"; then
    pass "a broken expression fails, naming the file"
else
    fail "a broken expression passed (rc=$rc): $out"
fi

new_repo "$work/sc" "${GOOD}
      - run: unused_var=1"
out="$(lint "$work/sc" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "SC2034" <<<"$out"; then
    pass "a shellcheck warning in a run: block fails (shellcheck is wired in)"
else
    fail "shellcheck did not run (rc=$rc): $out"
fi

new_repo "$work/info" "${GOOD}
      - run: echo \$HOME"
out="$(lint "$work/info" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
    pass "an info-level shellcheck note passes, as in CI (--severity=warning)"
else
    fail "an info-level note failed (rc=$rc): $out"
fi

new_repo "$work/tag" "${GOOD}
      - uses: actions/setup-go@v5"
out="$(lint "$work/tag" 2>&1)"; rc=$?
if [ "$rc" -eq 1 ] && grep -q "pinned to a full commit SHA" <<<"$out" && grep -q "setup-go@v5" <<<"$out"; then
    pass "an action pinned to a tag fails and is named"
else
    fail "a tag-pinned action passed (rc=$rc): $out"
fi

out="$(cd "$work" && ACTIONLINT="$work/nope" BUILD_WORKSPACE_DIRECTORY="$work/good" "${UNDER_TEST[@]}" 2>&1)"; rc=$?
if [ "$rc" -eq 2 ] && grep -q "nothing was checked" <<<"$out"; then
    pass "a missing actionlint is exit 2, not a pass"
else
    fail "a missing actionlint (rc=$rc): $out"
fi

wf_ver="$(sed -n 's/^ *ACTIONLINT_VERSION: *\([0-9.]*\).*/\1/p' "$WORKFLOW" | head -1)"
if [ -n "$wf_ver" ] && grep -q "rhysd/actionlint/releases/download/v${wf_ver}/actionlint_${wf_ver}_linux_amd64.tar.gz" "$LOCK" &&
   [ "$(grep -c "rhysd/actionlint/releases/download/v${wf_ver}/" "$LOCK")" -eq "$(grep -c "rhysd/actionlint/releases/download/" "$LOCK")" ]; then
    pass "tools.lock.json pins actionlint v$wf_ver, the version the workflow downloads"
else
    fail "actionlint pins drifted: workflow v$wf_ver, lockfile: $(grep -o 'actionlint/releases/download/v[0-9.]*' "$LOCK" | sort -u | tr '\n' ' '). Update both together."
fi

echo "actionlint_test: $pass_n passed, $fail_n failed"
[ "$fail_n" -eq 0 ]
