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

# worktree.sh — create an isolated git worktree that also gets its OWN Bazel
# server, so multiple concurrent sessions/agents don't stomp a shared HEAD or
# contend on one output_base (issue #455). And take worktrees away again only
# when that cannot lose work.
#
# Usage (run through Bazel so $BUILD_WORKSPACE_DIRECTORY points at the checkout):
#   bazel run //tools/worktree -- <branch> [base-ref]   # create (base defaults to origin/main)
#   bazel run //tools/worktree -- --list                # list worktrees
#   bazel run //tools/worktree -- --remove <branch>     # remove the worktree for <branch>
#   bazel run //tools/worktree -- --remove <branch> --force          # ...with its uncommitted files
#   bazel run //tools/worktree -- --remove <branch> --delete-branch  # ...and its branch, if clean AND landed
#   bazel run //tools/worktree -- --prune               # DRY RUN: what would be removed, what is kept and why
#   bazel run //tools/worktree -- --prune --execute     # remove every clean, landed, unlocked worktree + branch
#
# Environment:
#   WORKTREE_ROOT    parent dir for worktrees (default: <repo-parent>/<repo>-worktrees)
#   WORKTREE_LANDED  path to tools/landed/landed.sh (default: found in runfiles)

set -euo pipefail

usage() {
  sed -n '/^# worktree.sh/,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

# ── Where are we, and where is the PRIMARY checkout? ─────────────────────────
# `bazel run` sets BUILD_WORKSPACE_DIRECTORY to the tree it was run FROM, which
# is a linked worktree whenever someone runs this from inside one. Everything
# that names the repo (the worktrees dir, the cache dir, "is this the primary
# checkout?") must come from the primary checkout, not from that tree, or a run
# from inside a worktree builds paths under the wrong directory and mistakes the
# worktree for the primary. git's common dir is the one answer every worktree
# agrees on: it is <primary>/.git.
#
# Captured before any cd: `bazel run` starts us in our runfiles tree.
START_PWD="$(pwd)"
HERE="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "${HERE}" ]; then
  echo "worktree: not inside a git repo and BUILD_WORKSPACE_DIRECTORY is unset" >&2
  exit 1
fi
HERE="$(cd "${HERE}" && pwd -P)"
common="$(git -C "${HERE}" rev-parse --path-format=absolute --git-common-dir)"
if [ "$(basename "${common}")" = ".git" ]; then
  REPO="$(cd "$(dirname "${common}")" && pwd -P)"
else
  REPO="${HERE}"   # a bare or unusual layout: fall back to where we were run
fi
cd "${REPO}"

REPO_NAME="$(basename "${REPO}")"
WT_ROOT="${WORKTREE_ROOT:-$(dirname "${REPO}")/${REPO_NAME}-worktrees}"
CACHE_ROOT="${HOME}/.cache/bazel/worktrees"
BAZEL_ROOT="${HOME}/Library/Caches/bazel/_bazel_${USER:-$(id -un)}"
[ -d "${BAZEL_ROOT}" ] || BAZEL_ROOT="${HOME}/.cache/bazel/_bazel_${USER:-$(id -un)}"
# The marker //tools/worktree writes into each per-worktree output_user_root,
# naming the worktree it belongs to. //tools/bazel-cache:gc reads it to tell an
# orphaned root (worktree gone) from a live one. Keep the name in sync there.
MARKER=".vitruvian-worktree"

if git show-ref --verify --quiet refs/remotes/origin/main; then BASE_REF="origin/main"; else BASE_REF="main"; fi

# slugify a branch name into a filesystem-safe directory component.
slug() { printf '%s' "$1" | tr '/' '-'; }
# md5 of a path = its default output base name. Portable: GNU md5sum, macOS
# md5 (in /sbin, which a Bazel test sandbox's PATH leaves out), or openssl.
md5_of() {
  printf '%s' "$1" | { md5sum 2>/dev/null || /sbin/md5 -q 2>/dev/null || md5 -q 2>/dev/null || openssl md5 -r; } | cut -d' ' -f1
}
real() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

landed_script() {
  local c
  for c in "${WORKTREE_LANDED:-}" \
           "${RUNFILES_DIR:-/nonexistent}/_main/tools/landed/landed.sh" \
           "${START_PWD}/tools/landed/landed.sh" \
           "${BASH_SOURCE[0]}.runfiles/_main/tools/landed/landed.sh" \
           "${REPO}/tools/landed/landed.sh"; do
    [ -n "${c}" ] && [ -f "${c}" ] && { printf '%s' "${c}"; return 0; }
  done
  return 1
}

# is_landed <branch> -> 0 when every commit on it is on BASE_REF. Its verdict
# line goes to LANDED_SAYS. Unknown (no landed script) counts as NOT landed.
LANDED_SAYS=""
is_landed() {
  local script rc
  script="$(landed_script)" || { LANDED_SAYS="cannot find tools/landed/landed.sh"; return 1; }
  LANDED_SAYS="$(BUILD_WORKSPACE_DIRECTORY="${REPO}" LANDED_BASE="${BASE_REF}" LANDED_NO_FETCH=1 \
    bash "${script}" --branch "$1" 2>&1)" && rc=0 || rc=$?
  LANDED_SAYS="$(printf '%s' "${LANDED_SAYS}" | sed -e $'s/\033\\[[0-9;]*m//g' -e 's/^✓ //' -e 's/^✗ //' -e 's/^→ //' | head -1)"
  return "${rc}"
}

# Every worktree as one line, fields split by \037 (NOT tab: tab is IFS
# whitespace, so `read` would merge an empty field into the next): path, branch ("" if detached),
# locked ("locked: <reason>" or ""), prunable (1/0).
worktrees() {
  git worktree list --porcelain | awk '
    function flush() { if (p != "") printf "%s\037%s\037%s\037%s\n", p, b, l, pr; p=""; b=""; l=""; pr=0 }
    /^worktree /{ flush(); p = substr($0, 10) }
    /^branch /{ b = substr($0, 8); sub(/^refs\/heads\//, "", b) }
    /^locked/{ l = (length($0) > 7) ? "locked: " substr($0, 8) : "locked" }
    /^prunable/{ pr = 1 }
    END{ flush() }'
}

# The per-worktree output_user_root a worktree pins in its user.bazelrc, but
# ONLY if it is under ~/.cache/bazel/worktrees: this path gets rm -rf'd, so a
# hand-edited user.bazelrc must not be able to point it anywhere else.
output_root_of() { # <worktree path> <branch>
  local r=""
  [ -f "$1/user.bazelrc" ] &&
    r="$(sed -n 's/^startup --output_user_root=//p' "$1/user.bazelrc" | tail -1)"
  [ -n "${r}" ] || r="${CACHE_ROOT}/${REPO_NAME}-$(slug "$2")"
  case "${r}" in
    *..*) printf '' ;;
    "${CACHE_ROOT}"/?*) printf '%s' "${r}" ;;
    *) printf '' ;;
  esac
}

# The live Bazel server pids for a worktree, from BOTH places its output base
# can be: the default output root (a plain `bazel` run there before it had a
# user.bazelrc, or with the rc ignored) and its own per-worktree root.
server_pids() { # <worktree path> <output root or "">
  local h f pid
  h="$(md5_of "$1")"
  # No md5 tool means the default output base cannot be found, so whether a
  # server runs there is unknown: report it as running (fail toward keeping).
  [ -n "${h}" ] || { printf '%s\n' "unknown(no md5 tool)"; return 0; }
  for f in "${BAZEL_ROOT}/${h}/server/server.pid.txt" ${2:+"$2/${h}/server/server.pid.txt"}; do
    [ -f "${f}" ] || continue
    pid="$(cat "${f}" 2>/dev/null || true)"
    [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null && printf '%s\n' "${pid}"
  done
  return 0
}

# Stop them. A pidfile, not `bazel shutdown`: with no server running,
# `bazel shutdown` STARTS one first (it extracts an install base and creates the
# output root), which is the opposite of cleaning up.
stop_servers() { # <worktree path> <output root or "">
  local pids pid i
  pids="$(server_pids "$1" "$2")"
  [ -n "${pids}" ] || return 0
  case "${pids}" in unknown*) echo "worktree: cannot tell whether a Bazel server runs for $1 (no md5 tool)" >&2; return 1 ;; esac
  for pid in ${pids}; do kill "${pid}" 2>/dev/null || true; done
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    pids="$(server_pids "$1" "$2")"
    [ -z "${pids}" ] && { echo "worktree: stopped the Bazel server(s) for $1"; return 0; }
    sleep 0.5
  done
  echo "worktree: Bazel server(s) for $1 did not stop (pid ${pids//$'\n'/ })" >&2
  return 1
}

# remove_one <branch> <force 0/1> <delete-branch 0/1>
# Every refusal returns 1 with a reason on stderr and touches nothing.
remove_one() {
  local br="$1" force="$2" delete_branch="$3" line dest locked unsaved output_root
  line="$(worktrees | awk -F'\037' -v b="${br}" '$2 == b {print; exit}')"
  if [ -z "${line}" ]; then
    echo "worktree: no worktree has branch ${br} checked out (see --list)" >&2
    return 1
  fi
  IFS=$'\037' read -r dest _ locked _ <<<"${line}"
  if [ "$(real "${dest}")" = "${REPO}" ]; then
    echo "worktree: ${br} is checked out in the primary checkout, which is not removed" >&2
    return 1
  fi
  if [ "$(real "${dest}")" = "${HERE}" ]; then
    echo "worktree: ${dest} is the worktree this command is running from, so it is kept." >&2
    echo "worktree: run it from the primary checkout instead: cd ${REPO} && bazel run //tools/worktree -- --remove ${br}" >&2
    return 1
  fi
  # A locked worktree is somebody's work in progress. It is kept, with or
  # without --force: unlock it first (git worktree unlock <path>).
  if [ -n "${locked}" ]; then
    echo "worktree: ${dest} is ${locked}, so it is kept. Unlock it first: git worktree unlock ${dest}" >&2
    return 1
  fi
  # Uncommitted or untracked files are work nobody has saved. They are kept
  # unless --force says otherwise. (Ignored files, such as the user.bazelrc
  # this tool writes, do not count.) --delete-branch never takes --force's
  # licence: deleting the branch is only for a worktree with nothing unsaved.
  unsaved="$(git -C "${dest}" status --porcelain 2>/dev/null || true)"
  if [ -n "${unsaved}" ] && { [ "${force}" != "1" ] || [ "${delete_branch}" = "1" ]; }; then
    {
      echo "worktree: ${dest} has uncommitted or untracked files, so it is kept:"
      printf '%s\n' "${unsaved}" | head -20 | sed 's/^/  /'
      if [ "${delete_branch}" = "1" ]; then
        echo "worktree: --delete-branch only removes a CLEAN worktree. Commit or discard them first."
      else
        echo "worktree: commit them, or remove it anyway with: --remove ${br} --force"
      fi
    } >&2
    return 1
  fi
  if [ "${delete_branch}" = "1" ] && ! is_landed "${br}"; then
    echo "worktree: ${br} is not landed on ${BASE_REF}, so it and its worktree are kept: ${LANDED_SAYS}" >&2
    return 1
  fi

  output_root="$(output_root_of "${dest}" "${br}")"
  stop_servers "${dest}" "${output_root}" || {
    echo "worktree: not removing ${dest} while its Bazel server is still running" >&2
    return 1
  }
  if [ -n "${unsaved}" ]; then
    if ! git worktree remove --force "${dest}"; then
      echo "worktree: could not remove ${dest}" >&2
      return 1
    fi
    echo "worktree: ${dest} had uncommitted or untracked files; they were removed with it" >&2
  elif ! git worktree remove "${dest}"; then
    echo "worktree: could not remove ${dest}" >&2
    return 1
  fi
  git worktree prune 2>/dev/null || true
  if [ -e "${dest}" ]; then
    echo "worktree: ${dest} is still on disk after removal" >&2
    return 1
  fi
  if [ -n "${output_root}" ] && [ -d "${output_root}" ]; then
    chmod -R u+w "${output_root}" 2>/dev/null || true
    rm -rf "${output_root}"
    echo "worktree: pruned Bazel cache ${output_root}"
  fi
  # The default-root output base for this path is left to //tools/bazel-cache:gc,
  # which now sees its workspace is gone. Its server was stopped above.
  if [ "${delete_branch}" = "1" ]; then
    git branch -D "${br}" >/dev/null
    echo "worktree: removed ${dest} and deleted branch ${br} (landed: ${LANDED_SAYS})"
  else
    echo "worktree: removed ${dest} (branch ${br} is kept; delete with 'git branch -D ${br}')"
  fi
  return 0
}

# ── --prune: which worktrees can go, and why each of the rest stays. ─────────
# A worktree is removed only if ALL hold: not the primary, not the one we run
# from, not locked, its directory exists, on a branch, nothing uncommitted or
# untracked, no Bazel server running for it (in use), the branch has commits of
# its own (a branch level with main is far more often a worktree just created
# than one abandoned), and landed --branch says every commit is on main.
# Everything else is KEPT and the reason printed. Dry run unless --execute.
cmd_prune() {
  local execute=0 path br locked prunable reason n_rm=0 n_keep=0 failed=0 candidates=()
  for a in "$@"; do
    case "${a}" in
      --execute) execute=1 ;;
      *) echo "worktree: unknown --prune flag: ${a}" >&2; exit 2 ;;
    esac
  done
  git fetch origin main -q 2>/dev/null || true
  echo "worktree: prune against ${BASE_REF}$([ "${execute}" = 1 ] || echo ' (DRY RUN)')"
  while IFS=$'\037' read -r path br locked prunable; do
    reason=""
    if [ "$(real "${path}")" = "${REPO}" ]; then reason="primary checkout"
    elif [ "$(real "${path}")" = "${HERE}" ]; then reason="this command is running from it"
    elif [ -n "${locked}" ]; then reason="${locked}"
    elif [ "${prunable}" = "1" ] || [ ! -d "${path}" ]; then reason="directory is missing (git worktree prune clears the record; branch kept)"
    elif [ -z "${br}" ]; then reason="detached HEAD, no branch to check"
    elif [ -n "$(git -C "${path}" status --porcelain 2>/dev/null)" ]; then reason="uncommitted or untracked files"
    elif [ -n "$(server_pids "${path}" "$(output_root_of "${path}" "${br}")")" ]; then reason="a Bazel server is running for it (in use)"
    elif git merge-base --is-ancestor "refs/heads/${br}" "${BASE_REF}" 2>/dev/null; then
      reason="no commits of its own yet (new or unused); remove by hand: --remove ${br} --delete-branch"
    elif ! is_landed "${br}"; then reason="not landed: ${LANDED_SAYS}"
    fi
    if [ -n "${reason}" ]; then
      printf '  KEEP    %s%s\n          %s\n' "${path}" "${br:+  (${br})}" "${reason}"
      n_keep=$((n_keep + 1))
    else
      printf '  REMOVE  %s  (%s)\n          %s\n' "${path}" "${br}" "${LANDED_SAYS}"
      candidates+=("${br}")
      n_rm=$((n_rm + 1))
    fi
  done < <(worktrees)
  echo
  if [ "${execute}" != "1" ]; then
    echo "worktree: DRY RUN: would remove ${n_rm} worktree(s) and their branches, keep ${n_keep}."
    [ "${n_rm}" -eq 0 ] || echo "worktree: re-run with --prune --execute to remove them."
    return 0
  fi
  for br in ${candidates[@]+"${candidates[@]}"}; do
    # remove_one re-checks every condition, so a worktree that changed since
    # the listing above (new file, lock, server) is kept after all.
    remove_one "${br}" 0 1 || failed=$((failed + 1))
  done
  echo "worktree: removed $((n_rm - failed)) worktree(s), kept ${n_keep}$([ "${failed}" -eq 0 ] || echo ", ${failed} refused on re-check")."
  [ "${failed}" -eq 0 ]
}

case "${1:-}" in
  ""|-h|--help)
    usage
    exit 0
    ;;
  --list)
    git worktree list
    exit 0
    ;;
  --prune)
    shift
    cmd_prune "$@"
    exit $?
    ;;
  --remove)
    br="${2:?--remove needs a <branch>}"
    force=0
    delete_branch=0
    for a in "${@:3}"; do
      case "${a}" in
        --force) force=1 ;;
        --delete-branch) delete_branch=1 ;;
        *) echo "worktree: unknown --remove flag: ${a}" >&2; exit 2 ;;
      esac
    done
    [ "${delete_branch}" = "1" ] && git fetch origin main -q 2>/dev/null || true
    remove_one "${br}" "${force}" "${delete_branch}"
    exit $?
    ;;
  -*)
    echo "worktree: unknown flag: $1 (see --help)" >&2
    exit 2
    ;;
esac

BRANCH="$1"
BASE="${2:-}"
DEST="${WT_ROOT}/$(slug "${BRANCH}")"

if [ -e "${DEST}" ]; then
  echo "worktree: destination already exists: ${DEST}" >&2
  exit 1
fi

# Default base: origin/main if present, else the current HEAD.
if [ -z "${BASE}" ]; then
  if git show-ref --verify --quiet refs/remotes/origin/main; then
    BASE="origin/main"
  else
    BASE="HEAD"
  fi
fi

mkdir -p "${WT_ROOT}"

# Create the worktree. Reuse an existing branch if it already exists; otherwise
# create it at BASE.
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
  git worktree add "${DEST}" "${BRANCH}"
else
  git worktree add -b "${BRANCH}" "${DEST}" "${BASE}"
fi

# Per-worktree Bazel server. Written to the gitignored user.bazelrc that
# .bazelrc try-imports (`try-import %workspace%/user.bazelrc`), so it applies
# ONLY to this worktree and is never committed.
OUTPUT_ROOT="${CACHE_ROOT}/${REPO_NAME}-$(slug "${BRANCH}")"
cat > "${DEST}/user.bazelrc" <<RC
# Auto-generated by //tools/worktree (issue #455). Gives this worktree its own
# Bazel server + analysis cache so it doesn't contend with the main checkout or
# sibling worktrees. Safe to edit or delete. Not committed (user.bazelrc is
# gitignored).
startup --output_user_root=${OUTPUT_ROOT}
RC

# Name the worktree inside its output root, so //tools/bazel-cache:gc can tell
# this root is orphaned once the worktree is gone (the root's own name is a
# slug of the branch, which cannot be turned back into a path).
mkdir -p "${OUTPUT_ROOT}"
printf '%s\n' "$(real "${DEST}")" > "${OUTPUT_ROOT}/${MARKER}"

# Propagate the PRIMARY checkout's build-cache setup (#506): the shared-cache
# default + auth headers live in the primary user.bazelrc (written by
# //tools/remote:setup), which git worktrees do NOT inherit — without this
# copy every worktree silently cold-builds with no remote cache. Copies the
# managed block plus the config=remote-scoped header lines; both are inert if
# the primary has no cache configured.
if [ -f "${REPO}/user.bazelrc" ]; then
  {
    awk '/^# >>> build cache \(managed by tools\/remote:setup\)/{inblk=1}
         inblk{print}
         /^# <<< build cache \(managed by tools\/remote:setup\)/{inblk=0}' "${REPO}/user.bazelrc"
    grep -E '^common:remote --(remote_header|bes_header)=' "${REPO}/user.bazelrc" || true
  } >> "${DEST}/user.bazelrc"
fi

cat <<DONE

  ✔ worktree ready
    branch:             ${BRANCH}
    path:               ${DEST}
    base:               ${BASE}
    bazel output root:  ${OUTPUT_ROOT}
                        (pinned in ${DEST}/user.bazelrc)

  next:
    cd ${DEST}
DONE
