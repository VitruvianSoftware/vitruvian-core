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

# bazel-cache.sh — local Bazel cache upkeep.
#
#   bazel run //tools/bazel-cache:gc            # DRY-RUN: list reclaimable output_bases
#   bazel run //tools/bazel-cache:gc -- --execute
#   bazel run //tools/bazel-cache:gc -- --days 60 --execute
#
# WHY:
#   .bazelrc pins `common --repository_cache=~/.cache/bazel/repository-cache` so
#   the repository cache is shared across every output_base. Without it,
#   //tools/worktree's per-worktree `--output_user_root` (issue #455) silently
#   relocates that cache too, and every worktree re-fetches everything.
#   Measured: fresh output_user_root, `bazel build //devx:devx` -- 193s and 9.7GB
#   fetched with its own cache, versus 65s and 0 fetched when shared.
#
#   `gc` reclaims output_bases left behind by deleted worktrees.
#
# WHAT THIS DELIBERATELY DOES NOT DO -- read before adding a subcommand:
#   The Bazel 8/9 repository cache is NOT a passive archive of downloads. It is
#   the repo CONTENTS cache, and every output_base reaches its external repos by
#   ABSOLUTE symlink into it, e.g.
#     <output_base>/external/+http_archive+net_sourceforge_pmd
#       -> <repo-cache>/contents/<hash>/<uuid>
#   Two consequences, both load-bearing:
#     1. The legacy cache under <bazel-root>/cache/repos/v1 is NOT a stale
#        duplicate of the shared one. It is the live backing store for every
#        output_base created before the .bazelrc pin. Deleting or "merging" it
#        dangles every external/* symlink in those bases -- including any with a
#        running server -- and forces exactly the full re-fetch the pin exists to
#        avoid. NEVER delete a repository cache. `gc` skips `cache`/`install`.
#     2. Back-filling the shared cache by copying entries out of the legacy one
#        is NOT proven safe: entries are materialized repo directories with their
#        own metadata, not flat files, and Bazel runs its own age-based GC over
#        them (see the gc_lock in that directory), so naively copied entries can
#        be unrecognized or promptly evicted. A `seed` subcommand was written and
#        REMOVED for exactly this reason. Do not reintroduce one without first
#        proving Bazel accepts the copied entries.
#   Migration therefore needs no action: existing bases keep using the legacy
#   cache, new ones populate the shared cache lazily, and the two coexist.

set -euo pipefail

info() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# `bazel run` starts a binary in its RUNFILES tree, not in the checkout. From
# there `git worktree list` finds no repository, so gc used to protect ZERO
# worktrees and judged every output base on age alone. Run from the checkout.
cd "${BUILD_WORKSPACE_DIRECTORY:-.}" || die "cannot cd to ${BUILD_WORKSPACE_DIRECTORY:-.}"

BAZEL_USER="${USER:-$(id -un)}"
BAZEL_ROOT="${HOME}/Library/Caches/bazel/_bazel_${BAZEL_USER}"
[ -d "${BAZEL_ROOT}" ] || BAZEL_ROOT="${HOME}/.cache/bazel/_bazel_${BAZEL_USER}"
# //tools/worktree gives each worktree its own --output_user_root here.
WT_CACHE_ROOT="${HOME}/.cache/bazel/worktrees"
# Output bases can also sit directly in these, when someone ran Bazel with
# --output_user_root pointed at the parent (seen: a 3.2 GB base for a deleted
# worktree straight under ~/Library/Caches/bazel). Only 32-hex children count.
STRAY_PARENTS=("${HOME}/Library/Caches/bazel" "${HOME}/.cache/bazel")
# Written by //tools/worktree into each per-worktree root: the worktree's path.
MARKER=".vitruvian-worktree"
# A base whose workspace is gone is reclaimed once untouched this long,
# regardless of --days.
ORPHAN_GRACE_DAYS=1

human() { # bytes -> human
  awk -v b="${1:-0}" 'BEGIN{s="B KB MB GB TB";split(s,a," ");i=1;
    while(b>=1024&&i<5){b/=1024;i++} printf "%.1f%s", b, a[i]}'
}
# md5 of a path = its default output base name. Portable: GNU md5sum, macOS
# md5 (in /sbin, which a Bazel test sandbox's PATH leaves out), or openssl.
md5_of() {
  printf '%s' "$1" | { md5sum 2>/dev/null || /sbin/md5 -q 2>/dev/null || md5 -q 2>/dev/null || openssl md5 -r; } | cut -d' ' -f1
}
is_hex32() { [[ "$1" =~ ^[0-9a-f]{32}$ ]]; }
last_used() { date -r "$1" +%Y-%m-%d 2>/dev/null || echo '?'; }
used_within() { [ -n "$(find "$1" -maxdepth 0 -mtime "-$2" 2>/dev/null)" ]; } # <dir> <days>
size_of() { local k; k="$(du -sk "$1" 2>/dev/null | cut -f1)"; echo $(( ${k:-0} * 1024 )); }

# The pid of a live server in this output base, or nothing.
live_pid() {
  local f="$1/server/server.pid.txt" pid
  [ -f "${f}" ] || return 0
  pid="$(cat "${f}" 2>/dev/null || true)"
  [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null && printf '%s' "${pid}"
  return 0
}

# Which workspace an output base belongs to. Bazel writes the path into
# DO_NOT_BUILD_HERE (top level; older layouts under execroot/), and the server
# records it as --workspace_directory in server/cmdline (NUL-separated).
workspace_of() {
  local b="$1" w=""
  for f in "${b}/DO_NOT_BUILD_HERE" "${b}/execroot/DO_NOT_BUILD_HERE"; do
    [ -f "${f}" ] && w="$(head -1 "${f}" 2>/dev/null || true)" && [ -n "${w}" ] && break
  done
  if [ -z "${w}" ] && [ -f "${b}/server/cmdline" ]; then
    w="$(tr '\0' '\n' < "${b}/server/cmdline" | sed -n 's/^--workspace_directory=//p' | head -1)"
  fi
  printf '%s' "${w}"
}

LIVE_WS=()     # every worktree of this repo
LIVE_HASH=()   # md5 of each: its default output base name
LIVE_ROOTS=()  # per-worktree output roots that live worktrees pin in user.bazelrc
is_live_ws()   { local w; for w in ${LIVE_WS[@]+"${LIVE_WS[@]}"}; do [ "$1" = "${w}" ] && return 0; done; return 1; }
is_live_hash() { local h; for h in ${LIVE_HASH[@]+"${LIVE_HASH[@]}"}; do [ "$1" = "${h}" ] && return 0; done; return 1; }
is_live_root() { local r; for r in ${LIVE_ROOTS[@]+"${LIVE_ROOTS[@]}"}; do [ "$1" = "${r}" ] && return 0; done; return 1; }

# classify_base <output base> <days> -> VERDICT (keep|reclaim) + WHY.
classify_base() {
  local b="${1%/}" days="$2" pid ws
  pid="$(live_pid "${b}")"
  if [ -n "${pid}" ]; then VERDICT=keep; WHY="live Bazel server (pid ${pid})"; return; fi
  ws="$(workspace_of "${b}")"
  if [ -n "${ws}" ]; then
    if is_live_ws "${ws}"; then VERDICT=keep; WHY="worktree ${ws}"
    elif [ ! -e "${ws}" ]; then
      # Gone, but give it a day: recurring jobs (e.g. the hourly pipeline watch)
      # tear their tree down after each run and recreate the same path, so a
      # base used within a day is a warm cache between runs, not an orphan.
      if used_within "${b}" "${ORPHAN_GRACE_DAYS}"; then VERDICT=keep; WHY="workspace gone, but used within ${ORPHAN_GRACE_DAYS}d (may be recreated): ${ws}"
      else VERDICT=reclaim; WHY="its workspace is gone: ${ws}"
      fi
    elif used_within "${b}" "${days}"; then VERDICT=keep; WHY="workspace ${ws}, used within ${days}d"
    else VERDICT=reclaim; WHY="workspace ${ws} exists, but this base is untouched for ${days}d+"
    fi
    return
  fi
  if is_live_hash "$(basename "${b}")"; then VERDICT=keep; WHY="output base of a live worktree"
  elif used_within "${b}" "${days}"; then VERDICT=keep; WHY="unknown workspace, used within ${days}d"
  else VERDICT=reclaim; WHY="unknown workspace, untouched for ${days}d+"
  fi
}

# classify_root <per-worktree output_user_root> <days>: the whole root goes or stays.
classify_root() {
  local r="${1%/}" days="$2" b pid ws=""
  if is_live_root "${r}"; then VERDICT=keep; WHY="pinned by a live worktree's user.bazelrc"; return; fi
  for b in "${r}"/*/; do
    is_hex32 "$(basename "${b}")" || continue
    pid="$(live_pid "${b%/}")"
    [ -n "${pid}" ] && { VERDICT=keep; WHY="live Bazel server (pid ${pid})"; return; }
    [ -n "${ws}" ] || ws="$(workspace_of "${b%/}")"
  done
  [ -f "${r}/${MARKER}" ] && ws="$(head -1 "${r}/${MARKER}")"
  if [ -n "${ws}" ]; then
    if is_live_ws "${ws}"; then VERDICT=keep; WHY="worktree ${ws}"
    elif [ -e "${ws}" ]; then VERDICT=keep; WHY="workspace ${ws} still exists"
    elif used_within "${r}" "${ORPHAN_GRACE_DAYS}"; then VERDICT=keep; WHY="worktree gone, but used within ${ORPHAN_GRACE_DAYS}d: ${ws}"
    else VERDICT=reclaim; WHY="its worktree is gone: ${ws}"
    fi
    return
  fi
  if used_within "${r}" "${days}"; then VERDICT=keep; WHY="no marker or workspace record, used within ${days}d"
  else VERDICT=reclaim; WHY="no marker or workspace record, untouched for ${days}d+"
  fi
}

# --- gc ----------------------------------------------------------------------
# An output_base directory is named md5(workspace-path) (verified). Every base is
# classified on these signals, and the reason is printed for each:
#   1. a live Bazel server (server/server.pid.txt, pid alive)  -> KEEP, always
#   2. its workspace (DO_NOT_BUILD_HERE, server/cmdline, or the //tools/worktree
#      marker in a per-worktree root) is a live worktree       -> KEEP
#   3. that workspace no longer exists, untouched for a day    -> RECLAIM (orphan)
#   4. otherwise, untouched for >= --days (default 30)          -> RECLAIM, else KEEP
# Deleting an output_base is RECOVERABLE -- Bazel simply re-analyses on the next
# build -- so the real hazard is only ever deleting one that is IN USE, which
# (1) is there to prevent. Dry-run is the default; --execute is required to
# delete, and classification re-runs immediately before each removal.
cmd_gc() {
  local days=30 execute=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --days) days="${2:?--days needs a value}"; shift 2 ;;
      --execute) execute=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  local w r
  [ -n "$(md5_of /)" ] || die "no md5 tool (md5sum, md5 or openssl), so output bases cannot be matched to worktrees."
  while IFS= read -r w; do
    [ -n "${w}" ] || continue
    LIVE_WS+=("${w}")
    LIVE_HASH+=("$(md5_of "${w}")")
    if [ -f "${w}/user.bazelrc" ]; then
      r="$(sed -n 's/^startup --output_user_root=//p' "${w}/user.bazelrc" | tail -1)"
      [ -n "${r}" ] && LIVE_ROOTS+=("${r%/}")
    fi
  done < <(git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
  # Every checkout has at least itself as a worktree. Zero means we are not in
  # the repo, and then nothing would be protected but age: refuse.
  [ "${#LIVE_WS[@]}" -gt 0 ] || die "found 0 git worktrees from $(pwd), so nothing can be protected.
   Run it from the repo: bazel run //tools/bazel-cache:gc"

  info "protecting ${#LIVE_WS[@]} worktree(s) of $(git rev-parse --show-toplevel 2>/dev/null); age threshold ${days}d"
  info "scanning ${BAZEL_ROOT}, ${WT_CACHE_ROOT}/*, and stray bases in ${STRAY_PARENTS[*]}"
  echo

  local total=0 n=0 kept=0 items=() kinds=() d name sz
  # (kind, path) pairs to consider, in display order.
  if [ -d "${BAZEL_ROOT}" ]; then
    for d in "${BAZEL_ROOT}"/*/; do
      name="$(basename "${d}")"
      # NEVER the repository cache or the install base. See the header.
      case "${name}" in install|cache) continue ;; esac
      items+=("${d%/}"); kinds+=(base)
    done
  fi
  if [ -d "${WT_CACHE_ROOT}" ]; then
    for d in "${WT_CACHE_ROOT}"/*/; do [ -d "${d}" ] && { items+=("${d%/}"); kinds+=(root); }; done
  fi
  for r in "${STRAY_PARENTS[@]}"; do
    [ -d "${r}" ] || continue
    for d in "${r}"/*/; do
      is_hex32 "$(basename "${d}")" && { items+=("${d%/}"); kinds+=(base); }
    done
  done

  local i
  for i in ${items[@]+"${!items[@]}"}; do
    d="${items[$i]}"
    [ -d "${d}" ] || continue
    if [ "${kinds[$i]}" = root ]; then classify_root "${d}" "${days}"; else classify_base "${d}" "${days}"; fi
    if [ "${VERDICT}" = keep ]; then
      printf '  KEEP     %s\n           %s\n' "${d}" "${WHY}"
      kept=$((kept+1))
      continue
    fi
    sz="$(size_of "${d}")"
    printf '  RECLAIM  %s  %s, last used %s\n           %s\n' "${d}" "$(human "${sz}")" "$(last_used "${d}")" "${WHY}"

    if [ "${execute}" = "1" ]; then
      # Re-classify immediately before deleting: a build may have started, or a
      # worktree reappeared, since the first pass. (The lock file next to the
      # pidfile is NOT an advisory lock in Bazel 9 -- it can be flock'd freely
      # during an active build -- so it is not used as a liveness signal.)
      if [ "${kinds[$i]}" = root ]; then classify_root "${d}" "${days}"; else classify_base "${d}" "${days}"; fi
      if [ "${VERDICT}" != reclaim ]; then warn "  changed since classification (${WHY}) — skipping"; continue; fi
      chmod -R u+w "${d}" 2>/dev/null || true
      rm -rf "${d}" 2>/dev/null || warn "  could not fully remove ${d}"
    fi
    total=$((total+sz)); n=$((n+1))
  done

  echo
  if [ "${n}" -eq 0 ]; then ok "nothing reclaimable (kept ${kept}; threshold ${days}d)"; return 0; fi
  if [ "${execute}" = "1" ]; then
    ok "reclaimed $(human "${total}") across ${n} output base(s)/root(s); kept ${kept}"
  else
    ok "DRY RUN — $(human "${total}") reclaimable across ${n} output base(s)/root(s); kept ${kept}"
    info "re-run with --execute to delete. Deleting only discards build state; Bazel re-analyses on the next build."
  fi
}

case "${1:-}" in
  gc)   shift; cmd_gc "$@" ;;
  *) die "usage: bazel-cache.sh gc [--days N] [--execute]" ;;
esac
