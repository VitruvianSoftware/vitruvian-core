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

# Re-lock pnpm-lock.yaml with the pinned pnpm. See BUILD for usage.
set -o nounset -o pipefail

# --- begin runfiles.bash initialization v3 ---
set +e
f=bazel_tools/tools/bash/runfiles/runfiles.bash
# shellcheck disable=SC1090
source "${RUNFILES_DIR:-/dev/null}/$f" 2>/dev/null ||
  source "$(grep -sm1 "^$f " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
  source "$0.runfiles/$f" 2>/dev/null ||
  source "$(grep -sm1 "^$f " "$0.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
  source "$(grep -sm1 "^$f " "$0.exe.runfiles_manifest" | cut -f2- -d' ')" 2>/dev/null ||
  {
    echo >&2 "ERROR: cannot find $f"
    exit 1
  }
f=
set -e
# --- end runfiles.bash initialization v3 ---

usage() {
  cat <<'USAGE'
bazel run //tools/pnpm:lock              # after editing any package.json in the workspace
bazel run //tools/pnpm:lock -- --check   # is pnpm-lock.yaml in step? changes nothing, exits 1 if not
USAGE
}

root="${BUILD_WORKSPACE_DIRECTORY:-}"
if [[ -z "$root" ]]; then
  echo "lock: run this with bazel run //tools/pnpm:lock" >&2
  exit 2
fi

pnpm="$(rlocation "$PNPM_BIN")"
if [[ ! -x "$pnpm" ]]; then
  echo "lock: cannot find the pinned pnpm ($PNPM_BIN)" >&2
  exit 1
fi
# The pnpm launcher is a js_binary; it finds node and its own files through
# these, and must not try to cd into the Bazel output tree.
export RUNFILES_DIR="${RUNFILES_DIR:-$0.runfiles}"
export JS_BINARY__NO_CD_BINDIR=1
export JS_BINARY__CHDIR="$root"

safe=(--lockfile-only --ignore-scripts)

case "${1:-}" in
"")
  args=(install "${safe[@]}")
  ;;
--check)
  args=(install --frozen-lockfile "${safe[@]}")
  ;;
-h | --help | help)
  usage
  exit 0
  ;;
*)
  echo "lock: unknown argument '$1'. Edit the package.json by hand, then re-lock." >&2
  usage >&2
  exit 2
  ;;
esac
if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

cd "$root"
echo "+ pnpm ${args[*]}" >&2
exec "$pnpm" --dir "$root" "${args[@]}"
