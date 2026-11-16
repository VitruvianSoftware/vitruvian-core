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

# Tests lock.sh's arguments against a fake pnpm that prints what it was given.
set -o nounset -o pipefail -o errexit

lock="$(dirname "$0")/lock.sh"
[[ -f "$lock" ]] || lock="$TEST_SRCDIR/_main/tools/pnpm/lock.sh"
tmp="${TEST_TMPDIR:-$(mktemp -d)}"
repo="$tmp/repo"
mkdir -p "$repo/sub/dc" "$repo/plain"
touch "$repo/package.json" "$repo/pnpm-workspace.yaml"
touch "$repo/sub/dc/package.json" "$repo/sub/dc/pnpm-workspace.yaml"
touch "$repo/plain/package.json"
fake="$tmp/pnpm"
printf '#!/bin/sh\necho "cwd=$(pwd -P) chdir=$JS_BINARY__CHDIR args=$*"\n' >"$fake"
chmod +x "$fake"
real_repo="$(cd "$repo" && pwd -P)"

run() {
  BUILD_WORKSPACE_DIRECTORY="$repo" PNPM_BIN="$fake" bash "$lock" "$@" 2>"$tmp/err"
}

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

out="$(run)" || fail "plain lock exited non-zero"
[[ "$out" == "cwd=$real_repo chdir=$repo args=--dir $repo install --lockfile-only --ignore-scripts" ]] ||
  fail "root lock: $out"

out="$(run --check)" || fail "root check exited non-zero"
[[ "$out" == *"args=--dir $repo install --frozen-lockfile --lockfile-only --ignore-scripts" ]] ||
  fail "root check: $out"

out="$(run --dir sub/dc)" || fail "--dir lock exited non-zero"
[[ "$out" == "cwd=$real_repo/sub/dc chdir=$repo/sub/dc args=--dir $repo/sub/dc install --lockfile-only --ignore-scripts" ]] ||
  fail "--dir lock: $out"

out="$(run --dir sub/dc/ --check)" || fail "--dir check exited non-zero"
[[ "$out" == *"args=--dir $repo/sub/dc install --frozen-lockfile --lockfile-only --ignore-scripts" ]] ||
  fail "--dir check: $out"

for bad in "--dir" "--dir /etc" "--dir ../x" "--dir sub/../.." "--dir sub/.." "--dir plain" "--dir missing" "--dir sub/dc --bogus" "--bogus"; do
  # shellcheck disable=SC2086
  if run $bad >/dev/null; then
    fail "accepted: $bad"
  fi
  [[ -s "$tmp/err" ]] || fail "no message for: $bad"
done

echo PASS
