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
#
# It also updates every other Claude Code plugin installed from a remote
# marketplace (GitHub, git, URL), which Claude Code does not auto-update.

set -euo pipefail

PLUGIN="vitruvian-orchestrator"
MODE="refresh"
PULL=1
QUIET=0
THIRD_PARTY=1

usage() {
  sed -n '/^# Refresh this repo/,/^# marketplace (GitHub, git, URL)/p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'USAGE'

Options:
  --check          Report only. Changes nothing; exits 1 if any copy is stale.
  --no-pull        Do not fast-forward the main checkout to origin/main first.
  --quiet          Print nothing unless something was updated, is stale or failed
                   (for the scheduled run; see schedule.sh).
  --no-third-party Skip updating Claude Code plugins installed from remote
                   (GitHub, git, URL) marketplaces.
  --plugin <name>  Plugin folder name (default: vitruvian-orchestrator).
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) MODE="check" ;;
    --no-pull) PULL=0 ;;
    --quiet) QUIET=1 ;;
    --no-third-party) THIRD_PARTY=0 ;;
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
changed=0

# --quiet: hold the report back and print it at the end only if anything changed,
# is stale or failed, so a scheduled run that finds nothing to do logs nothing.
# An unexpected error (set -e) also prints it, from the EXIT trap.
REPORT=""
flush_report() {
  local rc="${1:-0}"
  [[ -n "$REPORT" ]] || return 0
  exec 1>&3
  if [[ "$rc" -ne 0 || "$changed" -ne 0 || "$stale" -ne 0 || "$failed" -ne 0 ]]; then cat "$REPORT"; fi
  rm -f "$REPORT"
  REPORT=""
}
if [[ "$QUIET" -eq 1 ]]; then
  REPORT="$(mktemp)"
  trap 'flush_report $?' EXIT
  exec 3>&1 >"$REPORT"
  echo "$(date '+%Y-%m-%d %H:%M:%S %Z') agent-plugins refresh"
fi
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; }
note() { printf '  · %s\n' "$*"; }

# Same files, ignoring caches the harness or the OS adds.
same_tree() {
  [[ -d "$1" && -d "$2" ]] && diff -rq -x node_modules -x .DS_Store "$1" "$2" >/dev/null 2>&1
}

json_field() { # file-or-dash, python expression over `d`, then values the expression reads as a[0], a[1], ...
  # Pass any data (plugin names, keys) as trailing arguments, never inside the expression.
  python3 -I -c 'import json,sys
src=sys.argv[1]
d=json.load(sys.stdin if src=="-" else open(src))
try:
    v=eval(sys.argv[2],{"d":d,"a":sys.argv[3:]})
except Exception:
    v=None
print(v or "")' "$@"
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
      changed=1
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
    "next((e['installPath'] for e in d.get('plugins',d).get(a[0],[]) if e.get('scope')=='user'), '')" "$PLUGIN@$MARKETPLACE"
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
    "$CLAUDE" plugin marketplace update "$MARKETPLACE" </dev/null >/dev/null
    if [[ -n "$dest" ]]; then "$CLAUDE" plugin update "$PLUGIN@$MARKETPLACE" </dev/null >/dev/null || true; fi
    dest="$(claude_path)"
    if ! same_tree "$src" "$dest"; then
      if [[ -n "$dest" ]]; then
        "$CLAUDE" plugin uninstall "$PLUGIN@$MARKETPLACE" --scope user --keep-data >/dev/null
      fi
      "$CLAUDE" plugin install "$PLUGIN@$MARKETPLACE" --scope user >/dev/null
      dest="$(claude_path)"
    fi
    changed=1
    if same_tree "$src" "$dest"; then ok "reinstalled; copy matches ($dest)"; else bad "still differs after reinstall ($dest)"; failed=1; fi
  fi
fi

# 3. Antigravity: a copy under ~/.gemini/config/plugins.
agy_path() {
  "$AGY" plugin list --json 2>/dev/null | json_field - \
    "next((p['path'] for p in (d if isinstance(d,list) else d.get('plugins',[])) if p.get('name')==a[0]), '')" "$PLUGIN"
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
    changed=1
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
    changed=1
    if opencode_ok "$src"; then ok "loaders rewritten"; else bad "loaders still wrong after install.sh"; failed=1; fi
  fi
fi

# 5. Third-party Claude Code plugins. Claude Code does not auto-update plugins from
# marketplaces other than its official one, so a plugin installed from GitHub stays
# on whatever version it was installed at (antigravity sat on 0.22.0 for months
# while its `pro` tier pointed at a model Antigravity no longer offers). Update
# every user-scope plugin whose marketplace is fetched from a remote (github, git,
# url); directory marketplaces are local checkouts and are left alone. Never
# accepts a marketplace-declared command: an update that needs one fails here and
# is reported, to be run by hand.
KNOWN_MARKETPLACES_FILE="${AGENT_PLUGINS_KNOWN_MARKETPLACES_FILE:-$(dirname "$CLAUDE_PLUGINS_FILE")/known_marketplaces.json}"
remote_plugins() { # prints "plugin@marketplace<TAB>version<TAB>marketplace-dir" for each remote user-scope plugin
  [[ -f "$CLAUDE_PLUGINS_FILE" && -f "$KNOWN_MARKETPLACES_FILE" ]] || return 0
  python3 -I - "$CLAUDE_PLUGINS_FILE" "$KNOWN_MARKETPLACES_FILE" "$MARKETPLACE" <<'PY'
import json, re, sys
SAFE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9._-]*")
installed = json.load(open(sys.argv[1]))
known = json.load(open(sys.argv[2]))
own = sys.argv[3]
plugins = installed.get("plugins", installed)
for key in sorted(plugins):
    name, _, mkt = key.rpartition("@")
    if not SAFE.fullmatch(key) or mkt == own:  # odd names (quotes, tabs, newlines) are skipped
        continue
    src = (known.get(mkt) or {}).get("source") or {}
    if src.get("source") not in ("github", "git", "url"):
        continue
    for e in plugins[key]:
        if e.get("scope") == "user":
            ver = str(e.get("version") or "")
            loc = str((known.get(mkt) or {}).get("installLocation") or "")
            if any(c in ver + loc for c in "\t\n\r"):
                continue
            print(f"{key}\t{ver}\t{loc}")
PY
}
marketplace_version() { # $1=plugin name $2=marketplace dir; prints the catalog's version, or nothing
  [[ -n "$2" && -f "$2/.claude-plugin/marketplace.json" ]] || return 0
  python3 -I - "$1" "$2" <<'PY'
import json, os, sys
name, root = sys.argv[1], sys.argv[2]
m = json.load(open(os.path.join(root, ".claude-plugin", "marketplace.json")))
for p in m.get("plugins", []):
    if p.get("name") != name:
        continue
    v = p.get("version")
    src = p.get("source")
    if not v and isinstance(src, str):
        base = os.path.realpath(root)
        f = os.path.realpath(os.path.join(root, src, ".claude-plugin", "plugin.json"))
        if f.startswith(base + os.sep) and os.path.isfile(f):
            v = json.load(open(f)).get("version")
    print(v or "")
    break
PY
}
installed_version() { # $1=plugin@marketplace
  json_field "$CLAUDE_PLUGINS_FILE" \
    "next((e.get('version') for e in d.get('plugins',d).get(a[0],[]) if e.get('scope')=='user'), '')" "$1"
}
if [[ "$THIRD_PARTY" -eq 1 ]]; then
  rows="$(remote_plugins)"
  if [[ -n "$rows" ]]; then
    echo "Third-party Claude Code plugins"
    if [[ "$MODE" == "refresh" ]]; then
      while IFS= read -r mkt; do
        "$CLAUDE" plugin marketplace update "$mkt" </dev/null >/dev/null 2>&1 || { bad "could not update marketplace $mkt"; failed=1; }
      done < <(printf '%s\n' "$rows" | cut -f1 | sed 's/.*@//' | sort -u)
    fi
    while IFS=$'\t' read -r key before dir; do
      name="${key%@*}"
      if [[ "$MODE" == "check" ]]; then
        latest="$(marketplace_version "$name" "$dir")"
        if [[ -z "$latest" || -z "$before" ]]; then
          note "$key $before (no catalog version to compare)"
        elif [[ "$latest" == "$before" ]]; then
          ok "$key $before is the catalog's version"
        else
          bad "$key is $before; its catalog has $latest"
          stale=1
        fi
        continue
      fi
      if ! "$CLAUDE" plugin update "$key" --scope user </dev/null >/dev/null 2>&1; then
        bad "$key: update failed (it may need a command confirmed by hand: claude plugin update $key)"
        failed=1
        continue
      fi
      after="$(installed_version "$key")"
      if [[ "$after" != "$before" ]]; then
        changed=1
        ok "$key updated ${before:-?} → ${after:-?}"
      else
        ok "$key ${before:-?} is current"
      fi
    done <<<"$rows"
  fi
fi

flush_report
if [[ "$failed" -ne 0 ]]; then
  echo "Refresh failed for at least one harness (see ✗ above)." >&2
  exit 1
fi
if [[ "$stale" -ne 0 ]]; then
  echo "Stale. Run: bazel run //tools/agent-plugins:refresh" >&2
  exit 1
fi
if [[ "$MODE" == "refresh" && ( "$QUIET" -eq 0 || "$changed" -ne 0 ) ]]; then
  echo "Done. Running sessions keep the old code: run /reload-plugins in Claude Code, and restart Antigravity and OpenCode."
fi
