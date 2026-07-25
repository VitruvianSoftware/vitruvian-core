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

# Hermetic test for bazel-cache.sh gc. Builds a FAKE Bazel root (no network, no
# real caches touched) and pins the properties that make deletion safe.

set -uo pipefail
UNDER_TEST="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bazel-cache.sh"
PASS=0; FAIL=0
check() { if [ "$2" = "0" ]; then printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1));
          else printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); fi }

echo "bazel-cache_test:"
bash -n "${UNDER_TEST}"; check "script parses" "$?"

# Fake Bazel root: one stale base, one live-server base, one fresh base.
root="$(mktemp -d)/_bazel_test"
mkdir -p "${root}/stale111" "${root}/live222/server" "${root}/fresh333"
echo x > "${root}/stale111/f"; echo x > "${root}/live222/f"; echo x > "${root}/fresh333/f"
echo $$ > "${root}/live222/server/server.pid.txt"     # OUR pid == definitely alive
touch -t 202001010000 "${root}/stale111" "${root}/live222"   # both old
run() { BAZEL_ROOT_OVERRIDE="${root}" bash "${UNDER_TEST}" "$@" 2>&1; }

# The script derives BAZEL_ROOT from HOME; drive it with a fake HOME instead.
fake_home="$(dirname "${root}")"
mkdir -p "${fake_home}/.cache/bazel"
mv "${root}" "${fake_home}/.cache/bazel/_bazel_${USER}"
root="${fake_home}/.cache/bazel/_bazel_${USER}"
run() { HOME="${fake_home}" bash "${UNDER_TEST}" "$@" 2>&1; }

# 1. dry-run must delete NOTHING.
out="$(run gc --days 1)"
[ -d "${root}/stale111" ]; check "dry-run keeps stale dir (no deletion without --execute)" "$?"
case "${out}" in *"DRY RUN"*) check "dry-run announces itself" 0 ;; *) check "dry-run announces itself" 1 ;; esac

# 2. --execute removes the stale one...
out="$(run gc --days 1 --execute)"
[ ! -d "${root}/stale111" ]; check "--execute removes a stale output_base" "$?"

# 3. ...but NEVER one with a live server. This is the only true hazard.
[ -d "${root}/live222" ]; check "live server is never deleted" "$?"

# 4. ...and never a recently-used one.
[ -d "${root}/fresh333" ]; check "recently-used output_base is never deleted" "$?"

# 5. install/ and cache/ are structural, never candidates.
# 5. THE data-loss invariant, asserted behaviourally rather than by grepping the
#    source. The repository cache is not a passive download cache: every
#    output_base reaches its external repos by ABSOLUTE symlink into
#    <root>/cache/repos/v1/contents/..., so deleting `cache` dangles every one of
#    them (including bases with a live server) and forces a full re-fetch.
#    `install` holds the unpacked Bazel install. Both must survive --execute even
#    when their mtimes are ancient.
mkdir -p "${root}/cache/repos/v1/contents" "${root}/install/abc"
echo x > "${root}/cache/repos/v1/contents/entry"
echo x > "${root}/install/abc/f"
touch -t 202001010000 "${root}/cache" "${root}/install"
run gc --days 1 --execute >/dev/null 2>&1
[ -f "${root}/cache/repos/v1/contents/entry" ]; check "repository cache SURVIVES --execute (data-loss guard)" "$?"
[ -f "${root}/install/abc/f" ];               check "install/ SURVIVES --execute" "$?"

rm -rf "${fake_home}"
echo
if [ "${FAIL}" -ne 0 ]; then printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1; fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
