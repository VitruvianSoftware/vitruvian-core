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


# Refresh this repo's agent plugins in every harness on this machine, from the
# main checkout, and check that each installed copy matches it.
#
#   bazel run //tools/agent-plugins:refresh             # update main, reinstall, verify
#   bazel run //tools/agent-plugins:refresh -- --check  # only report; exit 1 if stale
#
# Claude Code and Antigravity run their own COPY of a plugin, made at install
# time, so a merged change does not reach them until the copy is redone. Claude
# Code keys its copy by version, and our plugins rarely bump it, so a plain
# `claude plugin update` can leave the old files in place; this reinstalls when
# the copy still differs. OpenCode loads the plugin straight from the main
# checkout through two small loader files, so it only needs those to exist.

set -euo pipefail

PLUGIN="vitruvian-orchestrator"
MODE="refresh"
PULL=1

usage() {
  sed -n '/^# Refresh this repo/,/^# checkout through/p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'USAGE'

Options:
  --check          Report only. Changes nothing; exits 1 if any copy is stale.
  --no-pull        Do not fast-forward the main checkout to origin/main first.
  --plugin <name>  Plugin folder name (default: vitruvian-orchestrator).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --no-pull) PULL=0 ;;
    --plugin)
      [[ $# -ge 2 ]] || { echo "--plugin needs a name" >&2; exit 2; }
      PLUGIN="$2"
      shift
      ;;
    -h | --help) usage; exit 0 ;;
    *) echo "unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

CLAUDE="${AGENT_PLUGINS_CLAUDE:-claude}"
AGY="${AGENT_PLUGINS_AGY:-agy}"
CLAUDE_PLUGINS_FILE="${AGENT_PLUGINS_CLAUDE_FILE:-$HOME/.claude/plugins/installed_plugins.json}"
OPENCODE_DIR="${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
MARKETPLACE="vitruvian-core"

# The main checkout, wherever this runs from: the parent of the shared .git dir.
if [[ -n "${AGENT_PLUGINS_MAIN_CHECKOUT:-}" ]]; then
  MAIN="$AGENT_PLUGINS_MAIN_CHECKOUT"
else
  ws="${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
  MAIN="$(dirname "$(git -C "$ws" rev-parse --path-format=absolute --git-common-dir)")"
fi

stale=0
failed=0
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; }
note() { printf '  · %s\n' "$*"; }

# Same files, ignoring caches the harness or the OS adds.
same_tree() {
  [[ -d "$1" && -d "$2" ]] && diff -rq -x node_modules -x .DS_Store "$1" "$2" >/dev/null 2>&1
}

json_field() { # file-or-dash, python expression over `d`
  python3 -I -c 'import json,sys
src=sys.argv[1]
d=json.load(sys.stdin if src=="-" else open(src))
try:
    v=eval(sys.argv[2],{"d":d})
except Exception:
    v=None
print(v or "")' "$1" "$2"
}

echo "Main checkout: $MAIN"

# 1. Bring the main checkout up to main, since every harness installs from it.
if git -C "$MAIN" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$MAIN" fetch -q origin main || note "could not fetch origin/main; using what is local"
  branch="$(git -C "$MAIN" symbolic-ref --quiet --short HEAD || echo '(detached)')"
  behind="$(git -C "$MAIN" rev-list --count HEAD..origin/main 2>/dev/null || echo 0)"
  if [[ "$branch" != "main" ]]; then
    bad "main checkout is on '$branch', not main; plugins would install from that branch"
    stale=1
  elif [[ "$behind" -gt 0 ]]; then
    if [[ "$MODE" == "check" || "$PULL" -eq 0 ]]; then
      bad "main checkout is $behind commit(s) behind origin/main"
      stale=1
    elif [[ -n "$(git -C "$MAIN" status --porcelain --untracked-files=no)" ]]; then
      bad "main checkout is $behind commit(s) behind and has local changes; not updating it"
      failed=1
    else
      git -C "$MAIN" merge --ff-only -q origin/main
      ok "main checkout fast-forwarded $behind commit(s) to $(git -C "$MAIN" rev-parse --short HEAD)"
    fi
  else
    ok "main checkout is up to date with origin/main"
  fi
fi

# 2. Claude Code: a versioned copy under ~/.claude/plugins/cache.
claude_path() {
  [[ -f "$CLAUDE_PLUGINS_FILE" ]] || return 0
  json_field "$CLAUDE_PLUGINS_FILE" \
    "next((e['installPath'] for e in d.get('plugins',d).get('$PLUGIN@$MARKETPLACE',[]) if e.get('scope')=='user'), '')"
}
src="$MAIN/apps/claude-code/plugins/$PLUGIN"
if [[ -d "$src" ]]; then
  echo "Claude Code ($PLUGIN@$MARKETPLACE)"
  dest="$(claude_path)"
  if same_tree "$src" "$dest"; then
    ok "installed copy matches the main checkout"
  elif [[ "$MODE" == "check" ]]; then
    bad "installed copy ${dest:-(not installed)} differs from the main checkout"
    stale=1
  else
    "$CLAUDE" plugin marketplace update "$MARKETPLACE" >/dev/null
    if [[ -n "$dest" ]]; then "$CLAUDE" plugin update "$PLUGIN@$MARKETPLACE" >/dev/null || true; fi
    dest="$(claude_path)"
    if ! same_tree "$src" "$dest"; then
      if [[ -n "$dest" ]]; then
        "$CLAUDE" plugin uninstall "$PLUGIN@$MARKETPLACE" --scope user --keep-data >/dev/null
      fi
      "$CLAUDE" plugin install "$PLUGIN@$MARKETPLACE" --scope user >/dev/null
      dest="$(claude_path)"
    fi
    if same_tree "$src" "$dest"; then ok "reinstalled; copy matches ($dest)"; else bad "still differs after reinstall ($dest)"; failed=1; fi
  fi
fi

# 3. Antigravity: a copy under ~/.gemini/config/plugins.
agy_path() {
  "$AGY" plugin list --json 2>/dev/null | json_field - \
    "next((p['path'] for p in (d if isinstance(d,list) else d.get('plugins',[])) if p.get('name')=='$PLUGIN'), '')"
}
src="$MAIN/apps/antigravity/plugins/$PLUGIN"
if [[ -d "$src" ]]; then
  echo "Antigravity ($PLUGIN)"
  dest="$(agy_path)"
  if same_tree "$src" "$dest"; then
    ok "installed copy matches the main checkout"
  elif [[ "$MODE" == "check" ]]; then
    bad "installed copy ${dest:-(not installed)} differs from the main checkout"
    stale=1
  else
    if [[ -n "$dest" ]]; then "$AGY" plugin uninstall "$PLUGIN" >/dev/null; fi
    "$AGY" plugin install "$src" >/dev/null
    dest="$(agy_path)"
    if same_tree "$src" "$dest"; then ok "reinstalled; copy matches ($dest)"; else bad "still differs after reinstall (${dest:-not installed})"; failed=1; fi
  fi
fi

# 4. OpenCode: loader files that import the plugin from the main checkout.
opencode_ok() {
  local d="$OPENCODE_DIR/plugins/$PLUGIN"
  grep -qF "\"$1/server.mjs\"" "$d/server.ts" 2>/dev/null &&
    grep -qF "\"$1/tui.tsx\"" "$d/tui.tsx" 2>/dev/null
}
src="$MAIN/apps/opencode/plugins/$PLUGIN"
if [[ -d "$src" ]]; then
  echo "OpenCode ($PLUGIN)"
  if opencode_ok "$src"; then
    ok "loaders point at the main checkout (nothing is copied)"
  elif [[ "$MODE" == "check" ]]; then
    bad "loaders in $OPENCODE_DIR/plugins/$PLUGIN are missing or point elsewhere"
    stale=1
  else
    OPENCODE_CONFIG_DIR="$OPENCODE_DIR" bash "$src/install.sh" >/dev/null
    if opencode_ok "$src"; then ok "loaders rewritten"; else bad "loaders still wrong after install.sh"; failed=1; fi
  fi
fi

if [[ "$failed" -ne 0 ]]; then
  echo "Refresh failed for at least one harness (see ✗ above)." >&2
  exit 1
fi
if [[ "$stale" -ne 0 ]]; then
  echo "Stale. Run: bazel run //tools/agent-plugins:refresh" >&2
  exit 1
fi
if [[ "$MODE" == "refresh" ]]; then
  echo "Done. Running sessions keep the old code: run /reload-plugins in Claude Code, and restart Antigravity and OpenCode."
fi
