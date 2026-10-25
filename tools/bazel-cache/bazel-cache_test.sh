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

# Hermetic test for bazel-cache.sh gc. Builds a FAKE HOME with fake Bazel roots
# and a scratch git repo (no network, no real caches touched) and pins the
# properties that make deletion safe.

set -uo pipefail
UNDER_TEST="${1:-${UNDER_TEST:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/bazel-cache.sh}}"
case "${UNDER_TEST}" in
  /*) ;;
  *) UNDER_TEST="${PWD}/${UNDER_TEST}" ;;
esac
invoke_subject() {
  case "${UNDER_TEST}" in
    *.sh) bash "${UNDER_TEST}" "$@" ;;
    *)    "${UNDER_TEST}" "$@" ;;
  esac
}
PASS=0; FAIL=0
check() { if [ "$2" = "0" ]; then printf '  \033[32mPASS\033[0m  %s\n' "$1"; PASS=$((PASS+1));
          else printf '  \033[31mFAIL\033[0m  %s\n' "$1"; FAIL=$((FAIL+1)); fi }
yes_if() { if "$@"; then echo 0; else echo 1; fi; }
md5_of() {
  printf '%s' "$1" | { md5sum 2>/dev/null || /sbin/md5 -q 2>/dev/null || md5 -q 2>/dev/null || openssl md5 -r; } | cut -d' ' -f1
}

echo "bazel-cache_test:"
case "${UNDER_TEST}" in
  *.sh) bash -n "${UNDER_TEST}"; check "script parses" "$?" ;;
  *)    [ -x "${UNDER_TEST}" ]; check "script parses" "$?" ;;
esac

# Resolved so paths match what git records (macOS /var -> /private/var).
fake_home="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "${fake_home}"' EXIT
U="${USER:-$(id -un)}"
root="${fake_home}/.cache/bazel/_bazel_${U}"
wtroots="${fake_home}/.cache/bazel/worktrees"
mkdir -p "${root}" "${wtroots}"

# A repo with a primary checkout plus a live and a LOCKED worktree.
repo="${fake_home}/src/repo"
git init -q -b main "${repo}"
git -C "${repo}" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "${repo}" worktree add -q -b live "${fake_home}/src/repo-live" main
git -C "${repo}" worktree add -q -b held "${fake_home}/src/repo-held" main
git -C "${repo}" worktree lock --reason "in use" "${fake_home}/src/repo-held"

run() { HOME="${fake_home}" BUILD_WORKSPACE_DIRECTORY="${repo}" invoke_subject "$@" 2>&1; }
old() { touch -t 202001010000 "$@"; }
base() { mkdir -p "$1"; echo x > "$1/f"; [ -z "${2:-}" ] || printf '%s\n' "$2" > "$1/DO_NOT_BUILD_HERE"; }

# --- the bases ---------------------------------------------------------------
base "${root}/stale111";  old "${root}/stale111"                     # unknown ws, old
base "${root}/live222";   old "${root}/live222"                      # live server
mkdir -p "${root}/live222/server"; echo $$ > "${root}/live222/server/server.pid.txt"
base "${root}/fresh333"                                              # unknown ws, recent
base "${root}/orphan444" "${fake_home}/src/deleted-tree"             # ws gone, 3 days ago
three_days_ago="$(date -v-3d +%Y%m%d%H%M 2>/dev/null || date -d '3 days ago' +%Y%m%d%H%M)"
touch -t "${three_days_ago}" "${root}/orphan444"
base "${root}/recur666" "${fake_home}/src/hourly-job-tree"           # ws gone, used just now
base "${root}/primary555" "${repo}"; old "${root}/primary555"        # live ws, old
h_live="$(md5_of "${fake_home}/src/repo-live")"
base "${root}/${h_live}"; old "${root}/${h_live}"                    # md5 of live worktree, no record
# Per-worktree roots (//tools/worktree).
mkdir -p "${wtroots}/repo-gone/abc"; echo "${fake_home}/src/repo-gone" > "${wtroots}/repo-gone/.vitruvian-worktree"
old "${wtroots}/repo-gone"
mkdir -p "${wtroots}/repo-held";     echo "${fake_home}/src/repo-held" > "${wtroots}/repo-held/.vitruvian-worktree"
old "${wtroots}/repo-held"
mkdir -p "${wtroots}/repo-pinned/x"; old "${wtroots}/repo-pinned"    # no marker; pinned by user.bazelrc
printf 'startup --output_user_root=%s\n' "${wtroots}/repo-pinned" > "${fake_home}/src/repo-live/user.bazelrc"
hexbusy="0123456789abcdef0123456789abcdef"
mkdir -p "${wtroots}/repo-busy/${hexbusy}/server"; echo "${fake_home}/src/nope" > "${wtroots}/repo-busy/.vitruvian-worktree"
echo $$ > "${wtroots}/repo-busy/${hexbusy}/server/server.pid.txt"
# A stray base straight under ~/Library/Caches/bazel, and a non-base sibling.
stray="${fake_home}/Library/Caches/bazel/fedcba9876543210fedcba9876543210"
base "${stray}" "${fake_home}/src/scratch-tree"; old "${stray}"
mkdir -p "${fake_home}/.cache/bazel/repository-cache/content_addressable"
old "${fake_home}/.cache/bazel/repository-cache"

# 1. Outside a git repo it must FAIL, not protect nothing and carry on.
out="$(HOME="${fake_home}" BUILD_WORKSPACE_DIRECTORY="${fake_home}" invoke_subject gc --days 1 --execute 2>&1)"; rc=$?
check "0 worktrees found -> fails loudly" "$(yes_if [ "${rc}" != 0 ])"
case "${out}" in *"0 git worktrees"*) check "...and says why" 0 ;; *) check "...and says why: ${out}" 1 ;; esac
[ -d "${root}/stale111" ]; check "...and deletes nothing" "$?"

# 2. dry-run must delete NOTHING.
out="$(run gc --days 1)"
[ -d "${root}/stale111" ] && [ -d "${root}/orphan444" ] && [ -d "${wtroots}/repo-gone" ] && [ -d "${stray}" ]
check "dry-run keeps everything (no deletion without --execute)" "$?"
case "${out}" in *"DRY RUN"*) check "dry-run announces itself" 0 ;; *) check "dry-run announces itself" 1 ;; esac
case "${out}" in *"KEEP     ${root}/primary555"*) check "dry-run prints the KEEP reason too" 0 ;; *) check "dry-run prints the KEEP reason too: ${out}" 1 ;; esac

# 3. Orphans do not wait for --days: a 3-day-old orphan goes even at --days 9999.
out="$(run gc --days 9999 --execute)"
[ ! -d "${root}/orphan444" ];  check "a base whose workspace is gone goes after a day, despite --days 9999" "$?"
[ -d "${root}/stale111" ];     check "...while an unknown-workspace base still waits for --days" "$?"
[ -d "${root}/recur666" ];     check "a base whose workspace is gone but was used today is kept (recurring jobs)" "$?"

# 4. --execute.
out="$(run gc --days 1 --execute)"
[ ! -d "${root}/stale111" ];   check "--execute removes an old base with no workspace record" "$?"
[ -d "${root}/live222" ];      check "live server is never deleted" "$?"
[ -d "${root}/fresh333" ];     check "recently-used unknown base is never deleted" "$?"
[ -d "${root}/primary555" ];   check "an old base of a live worktree (DO_NOT_BUILD_HERE) is kept" "$?"
[ -d "${root}/${h_live}" ];    check "an old base named md5(live worktree) is kept" "$?"
[ ! -d "${wtroots}/repo-gone" ]; check "a per-worktree root whose marker names a gone worktree is removed" "$?"
[ -d "${wtroots}/repo-held" ];   check "a LOCKED worktree's root is kept" "$?"
[ -d "${wtroots}/repo-pinned" ]; check "a root pinned by a live worktree's user.bazelrc is kept (no marker)" "$?"
[ -d "${wtroots}/repo-busy" ];   check "a root with a live server is kept, even if its worktree is gone" "$?"
[ ! -d "${stray}" ];             check "a stray base under ~/Library/Caches/bazel for a gone tree is removed" "$?"
[ -d "${fake_home}/.cache/bazel/repository-cache/content_addressable" ]; check "the shared repository cache is never a candidate" "$?"

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
old "${root}/cache" "${root}/install"
run gc --days 1 --execute >/dev/null 2>&1
[ -f "${root}/cache/repos/v1/contents/entry" ]; check "repository cache SURVIVES --execute (data-loss guard)" "$?"
[ -f "${root}/install/abc/f" ];               check "install/ SURVIVES --execute" "$?"

echo
if [ "${FAIL}" -ne 0 ]; then printf '\033[31mFAIL\033[0m — %d passed, %d failed\n' "${PASS}" "${FAIL}"; exit 1; fi
printf '\033[32mPASS\033[0m — %d passed\n' "${PASS}"
