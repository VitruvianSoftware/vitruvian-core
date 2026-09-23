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

# Regression guard for tools/ci/llvm-cache-stage.sh (#2456).
#
# The load-bearing case is the "toolchain moved" round trip: a cache saved
# under one hash folder, then a build that extracts under a DIFFERENT one, must
# stage the NEW folder for saving. A hand-pinned folder name got that wrong for
# ~20 runs after #2419 and paid full LLVM extraction on every Bazel lane.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${1:-${HERE}/llvm-cache-stage.sh}"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() { printf '  NOT OK - %s\n' "$1" >&2; fails=$((fails + 1)); }

tmp="$(mktemp -d)"
trap 'rm -rf "${tmp}"' EXIT

run() { bash "$SCRIPT" "$@"; }

# A fake extraction: <contents>/<hash>/<candidate>/bin/clang plus the
# second directory a real extraction materializes alongside it.
extract() {
  mkdir -p "$1/$2/cand1/bin" "$1/$2/cand1.meta"
  echo clang >"$1/$2/cand1/bin/clang"
}

# --- 1. Miss: nothing restored, nothing left behind for the post step.
S="${tmp}/1/stage" C="${tmp}/1/contents"
out="$(run restore "$S" "$C")"
[ -z "$out" ] && ok "restore with no cache entry prints nothing" || bad "restore on a miss printed '$out'"
[ ! -e "$S" ] && ok "restore on a miss leaves no stage folder" || bad "stage folder exists after a miss"

# --- 2. Stage after a build: the live folder is hard-linked, not copied.
extract "$C" aaaa
h="$(run stage "$S" "$C")"
[ "$h" = aaaa ] && ok "stage prints the live hash" || bad "stage printed '$h', want aaaa"
[ -f "$S/aaaa/cand1/bin/clang" ] && ok "stage holds the toolchain" || bad "stage is missing bin/clang"
[ -f "$C/aaaa/cand1/bin/clang" ] && ok "the live tree stays in place for later steps" || bad "stage removed the live tree"
if [ "$(stat -c %i "$S/aaaa/cand1/bin/clang" 2>/dev/null || stat -f %i "$S/aaaa/cand1/bin/clang")" = \
     "$(stat -c %i "$C/aaaa/cand1/bin/clang" 2>/dev/null || stat -f %i "$C/aaaa/cand1/bin/clang")" ]; then
  ok "staged file is a hard link (no 8GB copy)"
else
  bad "staged file is a copy, not a hard link"
fi

# --- 3. Next run restores it: moved into place under its own name.
S2="${tmp}/2/stage" C2="${tmp}/2/contents"
mkdir -p "$S2" && cp -R "$S/aaaa" "$S2/"
out="$(run restore "$S2" "$C2")"
[ "$out" = "$C2/aaaa" ] && ok "restore prints the restored folder" || bad "restore printed '$out'"
[ -f "$C2/aaaa/cand1/bin/clang" ] && ok "restore moves the toolchain into the contents cache" || bad "toolchain not in contents after restore"
[ ! -e "$S2" ] && ok "restore removes the emptied stage folder" || bad "stage folder left after restore"

# --- 4. THE CASE THAT BROKE (#2419/#2455): the toolchain moves to a new hash.
# Restored aaaa is ignored by Bazel, which extracts bbbb. Stage must pick bbbb.
rm -rf "$C2/aaaa/cand1"   # Bazel ignoring it: only bbbb holds a clang
extract "$C2" bbbb
h="$(run stage "$S2" "$C2")"
[ "$h" = bbbb ] && ok "after a toolchain move, stage saves the NEW folder" || bad "stage picked '$h' after the toolchain moved (want bbbb)"
[ ! -e "$S2/aaaa" ] && ok "the stale folder is not staged" || bad "stale folder aaaa was staged"
[ "$(run live "$C2")" = "$C2/bbbb" ] && ok "live reports the folder that holds clang" || bad "live disagrees"

# --- 5. Restore never clobbers a folder another cache layer already placed.
S3="${tmp}/3/stage" C3="${tmp}/3/contents"
extract "$C3" cccc; echo keep >"$C3/cccc/marker"
mkdir -p "$S3/cccc"; echo stale >"$S3/cccc/marker"
out="$(run restore "$S3" "$C3" 2>/dev/null)"
[ "$(cat "$C3/cccc/marker")" = keep ] && ok "restore leaves an existing folder alone" || bad "restore overwrote an existing folder"
[ "$out" = "$C3/cccc" ] && ok "and still reports it as the restored folder" || bad "restore printed '$out'"

# --- 6. A lane that never extracted LLVM stages nothing.
S4="${tmp}/4/stage" C4="${tmp}/4/contents"; mkdir -p "$C4/other/x"
h="$(run stage "$S4" "$C4" 2>/dev/null)"
[ -z "$h" ] && [ ! -e "$S4" ] && ok "no clang, no stage folder (post step saves nothing)" || bad "staged something with no LLVM present"

# --- 7. Bad usage fails, rather than silently doing nothing.
run restore "$S4" >/dev/null 2>&1 && bad "restore with a missing arg succeeded" || ok "missing arg fails"
run bogus >/dev/null 2>&1 && bad "unknown subcommand succeeded" || ok "unknown subcommand fails"

if [ "$fails" -eq 0 ]; then
  echo "llvm-cache-stage: all checks passed"
  exit 0
fi
echo "llvm-cache-stage: ${fails} check(s) failed" >&2
exit 1
