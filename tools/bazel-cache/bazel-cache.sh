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

BAZEL_ROOT="${HOME}/Library/Caches/bazel/_bazel_${USER}"
[ -d "${BAZEL_ROOT}" ] || BAZEL_ROOT="${HOME}/.cache/bazel/_bazel_${USER}"

info() { printf '\033[36m→\033[0m %s\n' "$*"; }
ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

human() { # bytes -> human
  awk -v b="${1:-0}" 'BEGIN{s="B KB MB GB TB";split(s,a," ");i=1;
    while(b>=1024&&i<5){b/=1024;i++} printf "%.1f%s", b, a[i]}'
}

# --- gc ----------------------------------------------------------------------
# An output_base directory is named md5(workspace-path) (verified). We cannot
# invert that hash, so staleness is decided CONSERVATIVELY on two independent
# signals, and never on the hash alone:
#   1. no live Bazel server (server/server.pid.txt absent, or its pid is dead)
#   2. untouched for >= --days (default 30)
# Deleting an output_base is RECOVERABLE -- Bazel simply re-analyses on the next
# build -- so the real hazard is only ever deleting one that is IN USE, which
# (1) is there to prevent. Dry-run is the default; --execute is required to
# delete, and the live-server check re-runs immediately before each removal.
cmd_gc() {
  local days=30 execute=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --days) days="${2:?--days needs a value}"; shift 2 ;;
      --execute) execute=1; shift ;;
      *) die "unknown flag: $1" ;;
    esac
  done
  [ -d "${BAZEL_ROOT}" ] || die "no Bazel root at ${BAZEL_ROOT}"

  local live_ws=() d name pidf pid total=0 n=0
  # Every workspace this machine currently has checked out is OFF LIMITS.
  while IFS= read -r w; do
    [ -n "${w}" ] && live_ws+=("$(printf '%s' "${w}" | md5 -q 2>/dev/null || printf '%s' "${w}" | md5sum | cut -d' ' -f1)")
  done < <(git worktree list --porcelain 2>/dev/null | awk '/^worktree /{print $2}')

  info "Bazel root: ${BAZEL_ROOT}"
  info "protecting ${#live_ws[@]} live workspace(s); stale threshold ${days}d"
  echo

  for d in "${BAZEL_ROOT}"/*/; do
    name="$(basename "${d}")"
    case "${name}" in install|cache) continue ;; esac
    [ -d "${d}" ] || continue

    # (1) never touch a live server.
    pidf="${d}server/server.pid.txt"
    if [ -f "${pidf}" ]; then
      pid="$(cat "${pidf}" 2>/dev/null || true)"
      if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then continue; fi
    fi
    # (2) never touch a current workspace's output_base.
    for h in ${live_ws[@]+"${live_ws[@]}"}; do [ "${name}" = "${h}" ] && continue 2; done
    # (3) never touch something recently used.
    [ -n "$(find "${d}" -maxdepth 0 -mtime "-${days}" 2>/dev/null)" ] && continue

    sz=$(du -sk "${d}" 2>/dev/null | cut -f1); sz=$(( ${sz:-0} * 1024 ))
    total=$((total+sz)); n=$((n+1))
    printf '  %-34s %8s  last used %s\n' "${name}" "$(human "${sz}")" \
      "$(find "${d}" -maxdepth 0 -exec stat -f '%Sm' -t '%Y-%m-%d' {} \; 2>/dev/null)"

    if [ "${execute}" = "1" ]; then
      # Re-check liveness immediately before deleting. A build may have started
      # since classification, and the pidfile alone is not enough: there is a
      # window during server startup where the process exists but
      # server/server.pid.txt has not been written yet. (Note the lock file next
      # to it is NOT an advisory lock in Bazel 9 -- it can be flock'd freely
      # during an active build -- so it must not be used as a liveness signal.)
      # Re-stat'ing the mtime closes most of that window: anything that has
      # touched the base since we classified it makes us skip.
      if [ -f "${pidf}" ] && kill -0 "$(cat "${pidf}" 2>/dev/null || echo 0)" 2>/dev/null; then
        warn "  ${name} became live — skipping"; continue
      fi
      if [ -z "$(find "${d}" -maxdepth 0 -mtime "+${days}" 2>/dev/null)" ]; then
        warn "  ${name} was touched since classification — skipping"; continue
      fi
      chmod -R u+w "${d}" 2>/dev/null || true
      rm -rf "${d}" 2>/dev/null || warn "  could not fully remove ${name}"
    fi
  done

  echo
  if [ "${n}" -eq 0 ]; then ok "nothing reclaimable (threshold ${days}d)"; return 0; fi
  if [ "${execute}" = "1" ]; then
    ok "reclaimed $(human "${total}") across ${n} output_base(s)"
  else
    ok "DRY RUN — $(human "${total}") reclaimable across ${n} output_base(s)"
    info "re-run with --execute to delete. Deleting only discards build state; Bazel re-analyses on the next build."
  fi
}

case "${1:-}" in
  gc)   shift; cmd_gc "$@" ;;
  *) die "usage: bazel-cache.sh gc [--days N] [--execute]" ;;
esac
