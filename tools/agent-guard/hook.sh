#!/bin/sh
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

# agent-guard's launcher: the PreToolUse hook command for Claude Code
# (.claude/settings.json) and Antigravity (.agents/hooks.json). It reads the
# tool call on stdin and prints the guard's answer.
#
# 1. It finds the checkout from its OWN path, never from the working folder:
#    agy runs it from .agents/, Claude Code from wherever the agent is.
# 2. It runs the guard and policy as they are on origin/main, not this
#    checkout's copy, so an agent's local edit to tools/agent-guard governs
#    nothing until it has been reviewed and merged. The guard is Rust: the
#    first call after main changes compiles origin/main's src/ with plain
#    `rustc -O` (standard library only, ~2-3 s); later calls reuse the binary.
#    Binary and policy are cached by git object id in
#    ~/.local/state/agent-guard/cache, which agents may not write to. Not
#    $TMPDIR: agents can write there, and the next id is predictable, so an
#    agent could plant a binary that allows everything.
# 3. Fallbacks, each logged in "source": origin/main's copy; else this
#    checkout's copy (built on demand, cached by checksum); else the newest
#    copy of main built here before. It exits 1 only if none builds and runs;
#    Claude Code's command-tool entry (onFailure: block) and agy then refuse
#    the call (fail closed), as when no python3 worked before.
# 4. It tries each rustc it can find (rustup's toolchains, Homebrew, Bazel's
#    rules_rust toolchains, then PATH), so losing one does not wedge agents.
#
# Agents may not edit this file (category guard-config): unlike the guard
# itself, it takes effect the moment it changes.

umask 077
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_CEILING_DIRECTORIES

case $0 in
*/*) here=${0%/*} ;;
*) here=. ;;
esac
case $here in
/*) ;; # Claude Code passes an absolute path: no subshell needed
*)
  here=$(cd "$here" 2>/dev/null && pwd -P) || {
    echo "agent-guard: cannot find the folder holding $0" >&2
    exit 1
  }
  ;;
esac
root=${here%/tools/agent-guard}

# --- rustcs: begin (tests replace this block) ---
# Every rustc worth trying, listed only when a binary has to be built. The
# toolchains' own binaries, not rustup's proxy (~/.cargo/bin/rustc), which
# can stop to download a toolchain. PATH comes last.
rustcs() {
  h=${HOME:-/nonexistent}
  for p in "$h"/.rustup/toolchains/*/bin/rustc \
    /opt/homebrew/bin/rustc /usr/local/bin/rustc \
    "$h"/Library/Caches/bazel/_bazel_*/*/external/rules_rust++rust+rust_*__stable_tools/bin/rustc \
    "$h"/.cache/bazel/_bazel_*/*/external/rules_rust++rust+rust_*__stable_tools/bin/rustc \
    "$h"/.cache/bazel/worktrees/*/*/external/rules_rust++rust+rust_*__stable_tools/bin/rustc; do
    [ -x "$p" ] && echo "$p"
  done
  command -v rustc 2>/dev/null
}
# --- rustcs: end ---

cache=${HOME:-/nonexistent}/.local/state/agent-guard/cache
rel=tools/agent-guard
why=

# build SRC OUT: compile SRC/lib.rs and SRC/main.rs into the executable OUT.
# It builds in a fresh folder beside OUT and renames the result into place,
# so a concurrent call sees no binary or a whole one. A source no rustc here
# builds is remembered (OUT.failed holds the rustcs tried), so later calls do
# not pay for it again until the set of rustcs changes.
build() {
  found=$(rustcs | tr '\n' ' ')
  if [ -z "$found" ]; then
    why="no rustc found"
    return 1
  fi
  if [ -f "$2.failed" ] && [ "$(cat "$2.failed" 2>/dev/null)" = "$found" ]; then
    why="it did not build with $found"
    return 1
  fi
  mkdir -p "${2%/*}" 2>/dev/null || {
    why="cannot write ${2%/*}"
    return 1
  }
  why="it does not build with $found"
  for rc in $found; do
    t=$(mktemp -d "$2.build.XXXXXX" 2>/dev/null) || {
      why="cannot write ${2%/*}"
      return 1
    }
    # rustc links with cc: make sure the system's is reachable.
    if PATH="$PATH:/usr/bin:/bin" "$rc" --edition 2021 -O --crate-type rlib \
      --crate-name agent_guard -o "$t/libagent_guard.rlib" "$1/lib.rs" 2>"$t/err" &&
      PATH="$PATH:/usr/bin:/bin" "$rc" --edition 2021 -O --crate-name agent_guard_hook \
        --extern agent_guard="$t/libagent_guard.rlib" -o "$t/agent-guard" "$1/main.rs" 2>>"$t/err" &&
      mv -f "$t/agent-guard" "$2"; then
      rm -rf "$t" "$2.failed"
      return 0
    fi
    rm -rf "$t"
  done
  printf '%s' "$found" >"$2.failed" 2>/dev/null
  return 1
}

# Which copy of the guard to run.
bin=
policy=$here/policy.json
source="working-copy"
if ! command -v git >/dev/null 2>&1; then
  source="working-copy (git not found)"
elif ! ids=$(git -C "$root" rev-parse "origin/main:$rel/src" "origin/main:$rel/policy.json" 2>/dev/null); then
  source="working-copy (no origin/main:$rel in $root)"
else
  set -- $ids
  gbin=$cache/guard-$1
  pfile=$cache/policy-$2.json
  if [ ! -s "$pfile" ] && mkdir -p "$cache" 2>/dev/null &&
    git -C "$root" cat-file blob "$2" >"$pfile.new.$$" 2>/dev/null; then
    mv -f "$pfile.new.$$" "$pfile"
  fi
  rm -f "$pfile.new.$$" 2>/dev/null
  if [ ! -x "$gbin" ] && [ -s "$pfile" ]; then
    # First call since main changed: build main's copy, then drop entries
    # nobody has written for a week (another checkout re-creates its own).
    s=$(mktemp -d "$cache/src.XXXXXX" 2>/dev/null) &&
      git -C "$root" archive --format=tar "$1" 2>/dev/null | tar -xf - -C "$s" 2>/dev/null &&
      build "$s" "$gbin" &&
      find "$cache" -mindepth 1 -maxdepth 1 -mtime +7 \
        ! -name "guard-$1" ! -name "policy-$2.json" -exec rm -rf {} + 2>/dev/null
    [ -n "$s" ] && rm -rf "$s"
  fi
  if [ -x "$gbin" ] && [ -s "$pfile" ]; then
    bin=$gbin
    policy=$pfile
    source="origin/main:$1"
  elif [ ! -s "$pfile" ]; then
    source="working-copy (could not cache origin/main's copy in $cache)"
  else
    source="working-copy (origin/main's copy did not build: $why)"
  fi
fi

# This checkout's copy, built on demand and cached by a checksum of its source.
local_bin() {
  sum=$(cat "$here"/src/*.rs 2>/dev/null | cksum | tr ' ' '-') &&
    lbin=$cache/working-copy-$sum &&
    { [ -x "$lbin" ] || build "$here/src" "$lbin"; }
}

in=$(cat)
if [ -n "$bin" ]; then
  [ -n "${AGENT_GUARD_ANNOUNCE:-}" ] && echo "agent-guard: running $source" >&2
  out=$(printf '%s' "$in" | AGENT_GUARD_SOURCE=$source AGENT_GUARD_POLICY=$policy "$bin")
  rc=$?
  if [ "$rc" -eq 0 ]; then
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
  fi
  source="working-copy (origin/main's copy failed with exit $rc)"
fi
echo "agent-guard: running $here, not origin/main's copy: $source" >&2
if local_bin && out=$(printf '%s' "$in" |
  AGENT_GUARD_SOURCE=$source AGENT_GUARD_POLICY=$here/policy.json "$lbin"); then
  [ -n "$out" ] && printf '%s\n' "$out"
  exit 0
fi
# Last resort before refusing: the newest copy of main built here before.
# Only main's: a working copy may hold an agent's unreviewed edit.
old=$(ls -t "$cache"/guard-* 2>/dev/null | grep -v '\.failed$' | grep -v '\.build\.' | head -n 1)
if [ -n "$old" ] && [ -x "$old" ] && [ "$old" != "$bin" ]; then
  echo "agent-guard: this checkout's copy did not build or run ($why); running an older origin/main build, $old" >&2
  if out=$(printf '%s' "$in" |
    AGENT_GUARD_SOURCE="origin/main:${old##*/guard-} (stale: $source)" \
      AGENT_GUARD_POLICY=$here/policy.json "$old"); then
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
  fi
fi
echo "agent-guard: no copy of the guard would build or run (${why:-it failed})" >&2
exit 1
