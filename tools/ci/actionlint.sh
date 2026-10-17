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

# actionlint.sh — the required `actionlint` check, run locally.
#
# Usage:
#   bazel run //tools/ci:actionlint                  # every workflow, as CI checks them
#   bazel run //tools/ci:actionlint -- <file>...     # just these workflow files
#
# The same two steps as .github/workflows/actionlint.yaml: actionlint (pinned in
# tools/tools.lock.json at the workflow's ACTIONLINT_VERSION) with shellcheck at
# warning level over the `run:` blocks, then the check that every outside
# action is pinned to a commit SHA (tools/ci/require-pinned-actions.sh).
#
# One difference: CI uses the shellcheck preinstalled on its runner; this uses
# the pinned one from aspect_rules_lint, so a finding new to one shellcheck
# release can show up on one side only.
#
# Exit codes: 0 clean, 1 something to fix, 2 the check could not run.

set -euo pipefail

# --- begin runfiles.bash initialization v3 ---
set -uo pipefail; set +e; f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null || \
  source "$0.runfiles/$f" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null || \
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null
f=; set -euo pipefail
# --- end runfiles.bash initialization v3 ---
from_runfiles() { declare -F rlocation >/dev/null && rlocation "$1" 2>/dev/null || true; }
ACTIONLINT="${ACTIONLINT:-$(from_runfiles multitool/tools/actionlint/actionlint)}"
SHELLCHECK="${SHELLCHECK:-$(from_runfiles multitool/tools/shellcheck/shellcheck)}"
PIN_CHECK="${PIN_CHECK:-$(from_runfiles _main/tools/ci/require-pinned-actions.sh)}"

case "${1:-}" in
  -h | --help)
    sed -n '/^# actionlint.sh/,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
    exit 0
    ;;
esac

for t in "${ACTIONLINT}" "${SHELLCHECK}" "${PIN_CHECK}"; do
  if [ -z "${t}" ] || [ ! -f "${t}" ]; then
    echo "actionlint: cannot find the pinned tools; nothing was checked. Run it as: bazel run //tools/ci:actionlint" >&2
    exit 2
  fi
done

HERE="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
cd "${HERE}"
# File arguments are relative to where `bazel run` was started.
args=()
for a in "$@"; do
  case "${a}" in
    -*) args+=("${a}") ;;
    /*) args+=("${a}") ;;
    *) args+=("${BUILD_WORKING_DIRECTORY:-${HERE}}/${a}") ;;
  esac
done

color=()
[ -t 1 ] && color=(-color)
rc=0
# CI: SHELLCHECK_OPTS=--severity=warning (info-level notes are accepted noise).
SHELLCHECK_OPTS="${SHELLCHECK_OPTS:---severity=warning}" \
  "${ACTIONLINT}" -shellcheck "${SHELLCHECK}" ${color[@]+"${color[@]}"} ${args[@]+"${args[@]}"} || rc=$?
case "${rc}" in
  0) ;;
  1) echo "actionlint: the findings above fail the required actionlint check. Fix them, then run this again." >&2 ;;
  *) echo "actionlint: actionlint could not run (exit ${rc}); nothing was checked." >&2; exit 2 ;;
esac
pin_rc=0
bash "${PIN_CHECK}" || pin_rc=$?
[ "${pin_rc}" -eq 0 ] || rc=1
[ "${rc}" -eq 0 ] && echo "actionlint: workflows pass actionlint and every outside action is pinned to a commit SHA."
exit "${rc}"
