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

# git.sh — the git writes agents make, with the safety checks built in.
#
# Run from inside your worktree (made with //tools/worktree), never the main checkout.
#
# Save work:
#   bazel run //tools/git:commit -- -m "fix(scope): what changed" <paths>...
#   bazel run //tools/git:commit -- -m "feat(x): y" -m "Co-Authored-By: ..." --all
#   bazel run //tools/git:commit -- -F msg.txt <paths>...
#   bazel run //tools/git:commit -- --fixup <sha> <paths>...  # fold into <sha> later with sync --autosquash
#   bazel run //tools/git:commit -- --agent <name> -m "..." <paths>  # commit as that agent's bot
#   bazel run //tools/git:commit                              # during a merge: finish it
#
#   It stages the paths you name (or everything with --all), scans what is staged
#   for secrets, and commits. It refuses on main, in the main checkout, when
#   nothing is staged, when the scan finds something, and when a merge still has
#   conflict markers. With --agent <name> the author and committer are that
#   agent's GitHub App bot, from //tools/agent-app; without it, whoever
#   GIT_AUTHOR_*/GIT_COMMITTER_* or git config say.
#
# Publish work:
#   bazel run //tools/git:push                         # push this branch, set its upstream
#   bazel run //tools/git:push -- --agent <name>       # push as that agent's GitHub App
#   bazel run //tools/git:push -- --force-with-lease   # after a rebase (sync); never plain --force
#   bazel run //tools/git:push -- --dry-run            # say what would be pushed
#
#   It never pushes main, and scans the commits it is about to publish first.
#
# Catch up with main:
#   bazel run //tools/git:sync                    # fetch, then rebase this branch onto origin/main
#   bazel run //tools/git:sync -- --autosquash    # ...and fold in --fixup commits
#   bazel run //tools/git:sync -- --autosquash --keep-base  # fold them in where the branch is; main stays out
#   bazel run //tools/git:sync -- --merge         # merge origin/main in instead (no force-push needed)
#   bazel run //tools/git:sync -- --abort         # give up an unfinished merge or rebase
#
#   It refuses when you have uncommitted changes (it never stashes: the stash is
#   shared by every worktree). A rebase that hits a conflict is undone and the
#   files listed. A merge that hits one is left for you to finish. A branch
#   that already has merge commits is never rebased (that would drop them):
#   keep using --merge.
#
# Exit codes: 0 done, 1 refused or failed (the reason and what to run instead
# are printed), 2 bad arguments.

set -euo pipefail

usage() {
  sed -n '/^# git.sh/,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

# --- tools this calls, found before any cd. ---------------------------------
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
# Overridable for tests. AGENT_APP is //tools/agent-app's own script: --agent
# runs its public `env` command rather than copying how it finds keys.
SECRET_SCAN="${SECRET_SCAN:-$(from_runfiles _main/tools/secret-scan/secret-scan.sh)}"
GITLEAKS="${GITLEAKS:-$(from_runfiles multitool/tools/gitleaks/gitleaks)}"
GITLEAKS_CONFIG="${GITLEAKS_CONFIG:-$(from_runfiles _main/.gitleaks.toml)}"
AGENT_APP="${AGENT_APP:-$(from_runfiles _main/tools/agent-app/agent-app.sh)}"
export GITLEAKS GITLEAKS_CONFIG

CMD="${1:-}"
[ $# -gt 0 ] && shift
NAME="//tools/git:${CMD:-?}"

# refuse <reason> <command to run instead>...: print, change nothing more, exit 1.
refuse() {
  local reason="$1"
  shift
  echo "${NAME}: refused: ${reason}" >&2
  if [ $# -gt 0 ]; then
    echo "  instead:" >&2
    printf '    %s\n' "$@" >&2
  fi
  exit 1
}
bad_args() {
  echo "${NAME}: $* (see: bazel run ${NAME} -- --help)" >&2
  exit 2
}

# --- where are we? ----------------------------------------------------------
# `bazel run` starts us in our runfiles tree and says where it was run from:
# BUILD_WORKSPACE_DIRECTORY is the worktree, BUILD_WORKING_DIRECTORY the
# directory inside it. Paths and message files are relative to the latter.
case "${CMD}" in "" | -h | --help | help) usage; exit 0 ;; esac
HERE="${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || true)}"
if [ -z "${HERE}" ] || ! git -C "${HERE}" rev-parse --git-dir >/dev/null 2>&1; then
  refuse "this is not inside a git repository" "cd into your worktree, then: bazel run ${NAME}"
fi
HERE="$(cd "${HERE}" && pwd -P)"
WD="${BUILD_WORKING_DIRECTORY:-$(pwd)}"
WD="$(cd "${WD}" 2>/dev/null && pwd -P || printf '%s' "${HERE}")"
case "${WD}/" in "${HERE}"/*) ;; *) WD="${HERE}" ;; esac
cd "${HERE}"

git_dir="$(git rev-parse --path-format=absolute --git-dir)"
common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
BRANCH="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
is_primary() { [ "${git_dir}" = "${common_dir}" ]; }
in_merge() { [ -f "$(git rev-parse --git-path MERGE_HEAD)" ]; }
in_rebase() { [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; }
base_ref() { if git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; then echo origin/main; else echo main; fi; }

# A branch you may write to: a real branch, not main.
need_work_branch() {
  if [ -z "${BRANCH}" ]; then
    refuse "HEAD is detached, so there is no branch to put this on" \
      "make a branch worktree: bazel run //tools/worktree -- <branch>"
  fi
  if [ "${BRANCH}" = "main" ]; then
    refuse "this is main. Work happens on a branch in its own worktree" \
      "bazel run //tools/worktree -- <branch>, then run this from inside it"
  fi
}
no_op_in_progress() {
  if in_rebase; then
    refuse "a rebase is in progress here" "finish or drop it: bazel run //tools/git:sync -- --abort"
  fi
}
conflicted_files() { git diff --name-only --diff-filter=U; }

# scan <secret-scan args...>: 0 clean; otherwise refuse (the scan printed why).
scan() {
  [ -n "${SECRET_SCAN}" ] && [ -f "${SECRET_SCAN}" ] ||
    refuse "cannot find //tools/secret-scan, so nothing could be scanned" "run this through Bazel: bazel run ${NAME}"
  local rc=0
  BUILD_WORKSPACE_DIRECTORY="${HERE}" bash "${SECRET_SCAN}" "$@" || rc=$?
  return "${rc}"
}

# agent_exports <name>: what //tools/agent-app's public `env` command prints for
# that agent, run against this worktree so agent-app's own key lookup applies.
# Call as: exports="$(agent_exports <name>)" || exit 1
agent_exports() {
  local agent="$1" out
  if [ -z "${AGENT_APP}" ] || [ ! -f "${AGENT_APP}" ]; then
    refuse "cannot find //tools/agent-app" "run this through Bazel: bazel run ${NAME} -- --agent ${agent}"
  fi
  out="$(BUILD_WORKSPACE_DIRECTORY="${HERE}" bash "${AGENT_APP}" env "${agent}")" ||
    refuse "could not get ${agent}'s GitHub identity (agent-app's reason is above); nothing was done" \
      "check the name and the key: bazel run //tools/agent-app -- env ${agent}"
  printf '%s\n' "${out}"
}

# ============================================================================
# commit
# ============================================================================
# Conventional Commits, as CONTRIBUTING.md asks (release-please reads them).
CONVENTIONAL='^(feat|fix|docs|chore|ci|build|refactor|perf|test|style|revert)(\([^)]+\))?!?: .+'
# What `git revert` and GitHub's Revert button write: Revert "<original title>".
REVERT_TITLE='^Revert ".+"'

cmd_commit() {
  local msgs=() msg_file="" fixup="" all=0 paths=() subject agent=""
  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help) usage; exit 0 ;;
      -m | --message) [ $# -ge 2 ] || bad_args "-m needs a message"; msgs+=("$2"); shift ;;
      -F | --file) [ $# -ge 2 ] || bad_args "-F needs a file"; msg_file="$2"; shift ;;
      --fixup) [ $# -ge 2 ] || bad_args "--fixup needs a commit"; fixup="$2"; shift ;;
      --agent) [ $# -ge 2 ] || bad_args "--agent needs a name"; agent="$2"; shift ;;
      -a | --all) all=1 ;;
      --amend | --no-verify | -n)
        refuse "$1 is not offered: amending rewrites a commit, and hooks are part of the checks" \
          "add a commit that fixes it: bazel run //tools/git:commit -- --fixup <sha> <paths>" ;;
      --) shift; paths+=("$@"); break ;;
      -*) bad_args "unknown flag: $1" ;;
      *) paths+=("$1") ;;
    esac
    shift
  done

  if is_primary; then
    refuse "this is the main checkout, which stays on main and is shared" \
      "make a worktree: bazel run //tools/worktree -- <branch>, then commit from inside it" \
      "to carry edits you already made here: git diff HEAD --binary > /tmp/wip.patch (here)," \
      "  then git apply /tmp/wip.patch in the new worktree; copy any new (untracked) files across too"
  fi
  no_op_in_progress
  need_work_branch

  local merging=0
  in_merge && merging=1
  [ "${all}" = 1 ] && [ ${#paths[@]} -gt 0 ] && bad_args "give paths or --all, not both"
  [ -n "${msg_file}" ] && [ ${#msgs[@]} -gt 0 ] && bad_args "give -m or -F, not both"
  if [ -n "${fixup}" ] && { [ -n "${msg_file}" ] || [ ${#msgs[@]} -gt 0 ]; }; then
    bad_args "--fixup writes its own message; drop -m/-F"
  fi
  if [ -n "${fixup}" ] && [ "${merging}" = 1 ]; then
    refuse "a merge is in progress; a fixup cannot conclude it" \
      "finish the merge first: bazel run //tools/git:commit" \
      "or drop it: bazel run //tools/git:sync -- --abort"
  fi
  if [ -z "${fixup}" ] && [ -z "${msg_file}" ] && [ ${#msgs[@]} -eq 0 ] && [ "${merging}" = 0 ]; then
    refuse "a commit message is required" \
      "bazel run //tools/git:commit -- -m \"fix(scope): what changed\" <paths>..."
  fi

  # The message: a file is read relative to where you ran the command.
  if [ -n "${msg_file}" ]; then
    case "${msg_file}" in /*) ;; *) msg_file="${WD}/${msg_file}" ;; esac
    [ -f "${msg_file}" ] || bad_args "no such message file: ${msg_file}"
  fi
  if [ -z "${fixup}" ] && [ "${merging}" = 0 ]; then
    if [ -n "${msg_file}" ]; then
      subject="$(grep -v '^#' "${msg_file}" | grep -m1 . || true)"
    else
      subject="$(printf '%s\n' "${msgs[0]}" | head -1)"
    fi
    if ! grep -Eq "${CONVENTIONAL}" <<<"${subject}" && ! grep -Eq "${REVERT_TITLE}" <<<"${subject}"; then
      refuse "the first line is not a Conventional Commit: \"${subject}\"" \
        "start it with a type and optional scope, e.g. -m \"fix(worktree): keep locked trees\"" \
        "types: feat fix docs chore ci build refactor perf test style revert; or a revert's own Revert \"<title>\""
    fi
  fi

  if [ -n "${fixup}" ]; then
    local target
    target="$(git rev-parse --verify --quiet "${fixup}^{commit}" || true)"
    [ -n "${target}" ] || bad_args "--fixup: no such commit: ${fixup}"
    git merge-base --is-ancestor "${target}" HEAD ||
      refuse "${fixup} is not on this branch, so there is nothing for the fixup to fold into" \
        "name a commit from: git log --oneline $(base_ref)..HEAD"
    if git merge-base --is-ancestor "${target}" "$(base_ref)" 2>/dev/null; then
      refuse "${fixup} is already on $(base_ref); it cannot be rewritten" \
        "commit the fix normally: bazel run //tools/git:commit -- -m \"fix(scope): ...\" <paths>"
    fi
  fi

  # Whose commit this is. Only the identity is taken: the token agent-app also
  # prints is not needed to commit and is not kept.
  if [ -n "${agent}" ]; then
    local exports ident
    exports="$(agent_exports "${agent}")" || exit 1
    ident="$(printf '%s\n' "${exports}" | grep -E '^export GIT_(AUTHOR|COMMITTER)_(NAME|EMAIL)=' || true)"
    [ "$(grep -c . <<<"${ident}")" -eq 4 ] ||
      refuse "agent-app printed no complete git identity for ${agent}; nothing was committed" \
        "check it: bazel run //tools/agent-app -- env ${agent}"
    eval "${ident}"
  fi

  # Stage. Paths are relative to where you ran the command.
  if [ "${all}" = 1 ]; then
    git add -A
  elif [ ${#paths[@]} -gt 0 ]; then
    # A file git already tracks is staged with -f: git otherwise stages it but
    # exits 1 when it sits in an ignored folder (.claude/settings.json under
    # .claude/). Only exact tracked files, matched literally (no globs): a
    # folder or a new file still goes through the ignore rules, so nothing
    # ignored is added by accident.
    local tracked=() rest=() p
    for p in "${paths[@]}"; do
      if [ ! -d "${WD}/${p}" ] &&
        git --literal-pathspecs -C "${WD}" ls-files --error-unmatch -- "${p}" >/dev/null 2>&1; then
        tracked+=("${p}")
      else
        rest+=("${p}")
      fi
    done
    if [ ${#tracked[@]} -gt 0 ]; then
      git --literal-pathspecs -C "${WD}" add -f -- "${tracked[@]}" ||
        refuse "could not stage ${tracked[*]} (see git's message above)" \
          "check the paths, relative to ${WD}: git status --short"
    fi
    if [ ${#rest[@]} -gt 0 ]; then
      git -C "${WD}" add -- "${rest[@]}" ||
        refuse "could not stage ${rest[*]} (see git's message above)" \
          "check the paths, relative to ${WD}: git status --short"
    fi
  fi

  if [ "${merging}" = 1 ]; then
    local unmerged
    unmerged="$(conflicted_files)"
    if [ -n "${unmerged}" ]; then
      {
        echo "${NAME}: refused: these files still have merge conflicts:"
        printf '%s\n' "${unmerged}" | sed 's/^/    /'
        echo "  instead: fix them, then stage and conclude in one step:"
        echo "    bazel run //tools/git:commit -- $(printf '%s' "${unmerged}" | tr '\n' ' ')"
        echo "  or drop the merge: bazel run //tools/git:sync -- --abort"
      } >&2
      exit 1
    fi
    # Files both sides changed are where conflicts were. A marker left in one
    # means a conflict was "resolved" by staging it as-is.
    local both markers=""
    both="$(comm -12 <(git diff --cached --name-only HEAD | sort) <(git diff --cached --name-only MERGE_HEAD | sort))"
    while IFS= read -r f; do
      [ -n "${f}" ] || continue
      markers+="$(git show ":${f}" 2>/dev/null | grep -nE '^(<{7}|>{7}|\|{7})( |$)' | cut -d: -f1 | sed "s|^|${f}:|" || true)"$'\n'
    done <<<"${both}"
    markers="$(printf '%s' "${markers}" | grep . || true)"
    if [ -n "${markers}" ]; then
      {
        echo "${NAME}: refused: conflict markers are still in the staged files:"
        printf '%s\n' "${markers}" | sed 's/^/    /'
        echo "  instead: remove the <<<<<<< / >>>>>>> sections, then:"
        echo "    bazel run //tools/git:commit -- $(printf '%s\n' "${markers}" | cut -d: -f1 | sort -u | tr '\n' ' ')"
        echo "  or drop the merge: bazel run //tools/git:sync -- --abort"
      } >&2
      exit 1
    fi
  elif git diff --cached --quiet; then
    refuse "nothing is staged, so there is nothing to commit" \
      "name what to commit: bazel run //tools/git:commit -- -m \"...\" <paths>" \
      "or everything changed: bazel run //tools/git:commit -- -m \"...\" --all"
  fi

  # Scan exactly what the commit will record.
  if ! scan --staged; then
    refuse "the secret scan did not pass, so nothing was committed (your changes are still staged)" \
      "fix what it names above, then run the same commit again"
  fi

  local args=()
  if [ -n "${fixup}" ]; then
    args=(--fixup="$(git rev-parse --verify "${fixup}^{commit}")")
  elif [ -n "${msg_file}" ]; then
    args=(-F "${msg_file}" --cleanup=strip)
  elif [ ${#msgs[@]} -gt 0 ]; then
    for m in "${msgs[@]}"; do args+=(-m "${m}"); done
  else
    # Concluding a merge with git's own message, minus its "# Conflicts:" notes.
    args=(--no-edit --cleanup=strip)
  fi
  GIT_EDITOR=: git commit -q "${args[@]}" ||
    refuse "git commit failed (see above); nothing was committed" "fix what git reports, then run the same commit again"

  echo "${NAME}: committed $(git rev-parse --short HEAD) on ${BRANCH}: $(git log -1 --format=%s)"
  echo "  author: $(git log -1 --format='%an <%ae>')"
  case "$(git log -1 --format=%an)" in
    vitruvian-*-agent\[bot\]) ;;
    *) echo "  note: that is not an agent's bot. Agents commit with --agent <name>." ;;
  esac
  if [ -n "${fixup}" ]; then
    echo "  next: fold it in with: bazel run //tools/git:sync -- --autosquash"
  else
    echo "  next: bazel run //tools/git:push"
  fi
}

# ============================================================================
# push
# ============================================================================
cmd_push() {
  local agent="" lease=0 dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help) usage; exit 0 ;;
      --agent) [ $# -ge 2 ] || bad_args "--agent needs a name"; agent="$2"; shift ;;
      --force-with-lease) lease=1 ;;
      --dry-run | -n) dry=1 ;;
      -f | --force | --force=* | --force-with-lease=*)
        refuse "$1 is not offered. A plain force push can throw away commits someone else pushed" \
          "bazel run //tools/git:push -- --force-with-lease   (only overwrites what you last fetched)" ;;
      -*) bad_args "unknown flag: $1" ;;
      *) bad_args "push takes no branch or remote: it always pushes the current branch to origin under the same name" ;;
    esac
    shift
  done

  no_op_in_progress
  need_work_branch
  if in_merge; then
    refuse "a merge is in progress and not concluded" \
      "finish it: bazel run //tools/git:commit" "or drop it: bazel run //tools/git:sync -- --abort"
  fi
  git remote get-url origin >/dev/null 2>&1 ||
    refuse "this repository has no remote called origin" "add it, then retry"

  # Scan what this push publishes: the commits origin does not have yet.
  if ! scan --unpushed; then
    refuse "the secret scan did not pass, so nothing was pushed" \
      "fix it in a new commit and fold it in:" \
      "  bazel run //tools/git:commit -- --fixup <sha> <file>" \
      "  bazel run //tools/git:sync -- --autosquash" \
      "then: bazel run //tools/git:push -- --force-with-lease"
  fi

  if [ -n "${agent}" ]; then
    local exports
    # agent-app's own lookup decides where the key is: same registry, same key
    # dir (AGENT_KEY_DIR), resolved from this worktree.
    exports="$(agent_exports "${agent}")" || exit 1
    eval "${exports}"
    echo "${NAME}: pushing as ${GIT_COMMITTER_NAME:-${agent}}"
  fi

  # --no-follow-tags: push.followTags=true would otherwise send tags along.
  local args=(push -u --no-follow-tags)
  [ "${dry}" = 1 ] && args+=(--dry-run)
  [ "${lease}" = 1 ] && args+=(--force-with-lease --force-if-includes)
  # An explicit refspec to the same name: whatever push.default or the
  # branch's tracking config say, this can only ever write refs/heads/<branch>.
  args+=(origin "refs/heads/${BRANCH}:refs/heads/${BRANCH}")
  if ! git "${args[@]}"; then
    if [ "${lease}" = 0 ]; then
      refuse "the push was rejected (git's reason is above). If origin has commits you do not, catch up first" \
        "bazel run //tools/git:sync, then push again" \
        "if you rewrote this branch (sync, --autosquash): bazel run //tools/git:push -- --force-with-lease"
    fi
    refuse "the push was rejected (git's reason is above). --force-with-lease refuses when origin has commits you have not fetched" \
      "bazel run //tools/git:sync, check the result, then push again"
  fi
  [ "${dry}" = 1 ] && { echo "${NAME}: dry run: nothing was pushed"; return 0; }
  echo "${NAME}: pushed ${BRANCH} ($(git rev-parse --short HEAD)) to origin; it now tracks origin/${BRANCH}"
}

# ============================================================================
# sync
# ============================================================================
cmd_sync() {
  local mode="rebase" autosquash=0 abort=0 keep_base=0
  while [ $# -gt 0 ]; do
    case "$1" in
      -h | --help) usage; exit 0 ;;
      --autosquash) autosquash=1 ;;
      --keep-base) keep_base=1 ;;
      --merge) mode="merge" ;;
      --abort) abort=1 ;;
      -*) bad_args "unknown flag: $1" ;;
      *) bad_args "sync takes no branch: it always brings origin/main into the current branch" ;;
    esac
    shift
  done
  [ "${mode}" = merge ] && [ "${autosquash}" = 1 ] && bad_args "--autosquash rewrites commits; it goes with a rebase, not --merge"
  [ "${mode}" = merge ] && [ "${keep_base}" = 1 ] && bad_args "--keep-base goes with a rebase, not --merge"

  if [ "${abort}" = 1 ]; then
    if in_merge; then
      git merge --abort && echo "${NAME}: dropped the unfinished merge; ${BRANCH:-HEAD} is back where it was"
    elif in_rebase; then
      git rebase --abort && echo "${NAME}: dropped the unfinished rebase; ${BRANCH:-HEAD} is back where it was"
    else
      echo "${NAME}: no merge or rebase is in progress; nothing to abort"
    fi
    return 0
  fi

  if [ "${BRANCH}" = "main" ]; then
    refuse "this is main, which only ever fast-forwards" "git pull --ff-only"
  fi
  no_op_in_progress
  need_work_branch
  if in_merge; then
    refuse "a merge is already in progress" \
      "finish it: bazel run //tools/git:commit" "or drop it: bazel run //tools/git:sync -- --abort"
  fi
  # Untracked files do not count: git itself stops if one would be overwritten.
  local dirty
  dirty="$(git status --porcelain --untracked-files=no)"
  if [ -n "${dirty}" ]; then
    {
      echo "${NAME}: refused: you have uncommitted changes, and sync never stashes them"
      echo "  (the stash is shared by every worktree, so another session could take yours):"
      printf '%s\n' "${dirty}" | head -20 | sed 's/^/    /'
      echo "  instead: commit them first: bazel run //tools/git:commit -- -m \"...\" <paths>"
    } >&2
    exit 1
  fi

  git fetch -q origin main ||
    refuse "could not fetch origin/main (git's reason is above); nothing changed" "check the network, then retry"
  local before onto
  before="$(git rev-parse HEAD)"
  onto="$(git rev-parse --short origin/main)"

  if [ "${mode}" = merge ]; then
    if GIT_EDITOR=: git -c merge.autoStash=false merge -q --no-edit origin/main; then
      echo "${NAME}: merged origin/main (${onto}) into ${BRANCH}"
      echo "  next: bazel run //tools/git:push"
      return 0
    fi
    local files
    files="$(conflicted_files)"
    if [ -z "${files}" ] || ! in_merge; then
      in_merge && git merge --abort
      refuse "the merge stopped (git's reason is above); ${BRANCH} is unchanged" "fix what git reports, then retry"
    fi
    {
      echo "${NAME}: merging origin/main (${onto}) into ${BRANCH} hit conflicts in:"
      printf '%s\n' "${files}" | sed 's/^/    /'
      echo "  The merge is left in progress so you can resolve them."
      echo "  To finish: fix each file, then stage them and conclude the merge in one step:"
      echo "    bazel run //tools/git:commit -- $(printf '%s' "${files}" | tr '\n' ' ' | sed 's/ $//')"
      echo "  To give up: bazel run //tools/git:sync -- --abort"
    } >&2
    exit 1
  fi

  # A rebase drops merge commits (it replays only the commits under them), so
  # a branch kept up to date with --merge stays on --merge.
  local merges
  merges="$(git rev-list --merges origin/main..HEAD)"
  if [ -n "${merges}" ]; then
    refuse "${BRANCH} has $(grep -c . <<<"${merges}") merge commit(s) since origin/main; a rebase would drop them" \
      "keep merging: bazel run //tools/git:sync -- --merge"
  fi

  local args=(-c rebase.autoStash=false rebase -q)
  [ "${autosquash}" = 1 ] && args+=(-i --autosquash)
  # --keep-base: rewrite the branch where it stands (fold fixups in) without
  # bringing in newer main, e.g. when main now conflicts with the original commit.
  [ "${keep_base}" = 1 ] && args+=(--keep-base)
  if GIT_SEQUENCE_EDITOR=: GIT_EDITOR=: git "${args[@]}" origin/main; then
    if [ "$(git rev-parse HEAD)" = "${before}" ]; then
      echo "${NAME}: ${BRANCH} is already up to date with origin/main (${onto})"
      return 0
    fi
    if [ "${keep_base}" = 1 ]; then
      echo "${NAME}: rewrote ${BRANCH} in place$([ "${autosquash}" = 1 ] && echo ', fixups folded in'); origin/main was not brought in"
      echo "  bring it in later with: bazel run //tools/git:sync"
      git rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null &&
        echo "  origin/${BRANCH} has the old commits; publish with: bazel run //tools/git:push -- --force-with-lease"
      return 0
    fi
    echo "${NAME}: rebased ${BRANCH} onto origin/main (${onto})$([ "${autosquash}" = 1 ] && echo ', fixups folded in')"
    if git rev-parse --verify --quiet "refs/remotes/origin/${BRANCH}" >/dev/null; then
      echo "  origin/${BRANCH} still has the old commits. Publish the new ones with:"
      echo "    bazel run //tools/git:push -- --force-with-lease"
    else
      echo "  next: bazel run //tools/git:push"
    fi
    return 0
  fi
  local files
  files="$(conflicted_files)"
  in_rebase && git rebase --abort
  if [ -n "${files}" ]; then
    {
      echo "${NAME}: rebasing ${BRANCH} onto origin/main (${onto}) hit conflicts in:"
      printf '%s\n' "${files}" | sed 's/^/    /'
      echo "  The rebase was undone; ${BRANCH} is exactly as it was."
      echo "  instead: merge main in and resolve the conflicts once:"
      echo "    bazel run //tools/git:sync -- --merge"
    } >&2
    exit 1
  fi
  refuse "the rebase stopped (git's reason is above) and was undone; ${BRANCH} is unchanged" \
    "fix what git reports, then retry, or merge instead: bazel run //tools/git:sync -- --merge"
}

case "${CMD}" in
  commit) cmd_commit "$@" ;;
  push) cmd_push "$@" ;;
  sync) cmd_sync "$@" ;;
  *) NAME="//tools/git"; bad_args "unknown command: ${CMD} (one of: commit, push, sync)" ;;
esac
