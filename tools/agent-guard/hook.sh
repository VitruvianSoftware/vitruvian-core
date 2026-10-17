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
#    nothing until it has been reviewed and merged. The two files are read with
#    git once per change on main and cached by blob id in
#    ~/.local/state/agent-guard/cache, which agents may not write to.
# 3. If origin/main, its copy of the guard, or git is not there, it runs this
#    checkout's copy instead and says so: every log line carries "source".
# 4. It tries each python3 in turn, so losing one (a Homebrew cleanup, an Xcode
#    switch) does not wedge every agent. It exits 1 only if none works; Claude
#    Code's command-tool entry (onFailure: block) and agy then refuse the call.
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

# --- pythons: begin (tests replace this block) ---
# Homebrew's versioned links first, newest first: independent of Xcode and
# stable across patch upgrades. This includes every python@3.N installed on
# request, which Homebrew's cleanup never removes. Then the Command Line Tools'
# own python3, then Apple's /usr/bin/python3 shim (it fails while Xcode is
# being replaced). The same order the per-user installer used.
pythons=
for prefix in /opt/homebrew/opt /usr/local/opt; do
  n=40
  while [ "$n" -ge 9 ]; do
    p=$prefix/python@3.$n/bin/python3.$n
    [ -x "$p" ] && pythons="$pythons $p"
    n=$((n - 1))
  done
done
pythons="$pythons /Library/Developer/CommandLineTools/usr/bin/python3 /usr/bin/python3"
# --- pythons: end ---

# Which copy of the guard to run.
cache=${HOME:-/nonexistent}/.local/state/agent-guard/cache
rel=tools/agent-guard
src=$here
policy=$here/policy.json
source="working-copy"
if ! command -v git >/dev/null 2>&1; then
  source="working-copy (git not found)"
elif ! blobs=$(git -C "$root" rev-parse "origin/main:$rel/agent_guard.py" "origin/main:$rel/policy.json" 2>/dev/null); then
  source="working-copy (no origin/main:$rel in $root)"
else
  set -- $blobs
  gdir=$cache/guard-$1
  pfile=$cache/policy-$2.json
  if [ ! -s "$gdir/agent_guard.py" ] || [ ! -s "$pfile" ]; then
    # First call since main changed: write both atomically, then drop entries
    # nobody has written for a week (another checkout re-creates its own).
    if mkdir -p "$gdir" 2>/dev/null &&
      git -C "$root" cat-file blob "$1" >"$gdir/.new.$$" &&
      mv -f "$gdir/.new.$$" "$gdir/agent_guard.py" &&
      git -C "$root" cat-file blob "$2" >"$pfile.new.$$" &&
      mv -f "$pfile.new.$$" "$pfile"; then
      find "$cache" -mindepth 1 -maxdepth 1 -mtime +7 \
        ! -name "guard-$1" ! -name "policy-$2.json" -exec rm -rf {} + 2>/dev/null
    fi
    rm -f "$gdir/.new.$$" "$pfile.new.$$" 2>/dev/null
  fi
  if [ -s "$gdir/agent_guard.py" ] && [ -s "$pfile" ]; then
    src=$gdir
    policy=$pfile
    source="origin/main:$1"
  else
    source="working-copy (could not cache origin/main's copy in $cache)"
  fi
fi
case $source in
working-copy*) echo "agent-guard: running $here, not origin/main's copy: $source" >&2 ;;
*) [ -n "${AGENT_GUARD_ANNOUNCE:-}" ] && echo "agent-guard: running $source" >&2 ;;
esac

# -I ignores PYTHON* variables and the user's site folder, -S skips site
# entirely (the guard needs only the standard library; it saves 5-10 ms).
# Loads agent_guard.py from the folder given, by path (so nothing else in that
# folder can shadow a standard module), and caches its bytecode: Apple's
# python3 reads a cache but never writes one itself.
boot='import os, sys
from importlib import util
path = os.path.join(sys.argv[1], "agent_guard.py")
try:
    cached = util.cache_from_source(path)
    if not os.path.exists(cached):
        import py_compile
        py_compile.compile(path, cfile=cached, doraise=True)
except Exception:
    pass
spec = util.spec_from_file_location("agent_guard", path)
guard = util.module_from_spec(spec)
sys.modules["agent_guard"] = guard
spec.loader.exec_module(guard)
sys.exit(guard.main([]))'

in=$(cat)
tried=
for py in $pythons; do
  [ -x "$py" ] || continue
  tried="$tried $py"
  if out=$(printf '%s' "$in" |
    AGENT_GUARD_SOURCE=$source AGENT_GUARD_POLICY=$policy "$py" -I -S -c "$boot" "$src"); then
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
  fi
  # origin/main's copy would not run on this python: try this checkout's.
  if [ "$src" != "$here" ] && out=$(printf '%s' "$in" |
    AGENT_GUARD_SOURCE="working-copy (origin/main's copy failed on $py)" \
      AGENT_GUARD_POLICY=$here/policy.json "$py" -I -S -c "$boot" "$here"); then
    [ -n "$out" ] && printf '%s\n' "$out"
    exit 0
  fi
done
echo "agent-guard: no working python3 (tried:${tried:- none})" >&2
exit 1
