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


# Tests //tools/agent-plugins:refresh against a fake main checkout and fake
# harness installs. Never touches the real ~/.claude, ~/.gemini or OpenCode.

set -euo pipefail

REFRESH="$(cd "$(dirname "$0")" && pwd)/refresh.sh"
[[ -f "$REFRESH" ]] || REFRESH="${TEST_SRCDIR:-}/_main/tools/agent-plugins/refresh.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

P=demo
MAIN="$T/main"
for h in claude-code antigravity opencode; do
  mkdir -p "$MAIN/apps/$h/plugins/$P/lib"
  echo "v1 $h" >"$MAIN/apps/$h/plugins/$P/lib/core.mjs"
done
# OpenCode's installer writes loaders that import from its own folder.
cat >"$MAIN/apps/opencode/plugins/$P/install.sh" <<'SH'
d="$(cd "$(dirname "$0")" && pwd)"; o="$OPENCODE_CONFIG_DIR/plugins/demo"; mkdir -p "$o"
printf 'export { default } from "%s/server.mjs";\n' "$d" >"$o/server.ts"
printf 'export { default } from "%s/tui.tsx";\n' "$d" >"$o/tui.tsx"
SH

# Installed copies that match.
cp -R "$MAIN/apps/claude-code/plugins/$P" "$T/cc-copy"
cp -R "$MAIN/apps/antigravity/plugins/$P" "$T/agy-copy"
printf '{"plugins":{"demo@vitruvian-core":[{"scope":"user","installPath":"%s"}]}}' "$T/cc-copy" >"$T/installed.json"
cat >"$T/agy" <<SH
#!/usr/bin/env bash
if [[ "\$*" == "plugin list --json" ]]; then echo '[{"name":"demo","path":"$T/agy-copy"}]'; exit 0; fi
echo "\$*" >>"$T/agy.calls"
SH
cat >"$T/claude" <<SH
#!/usr/bin/env bash
echo "\$*" >>"$T/claude.calls"
SH
chmod +x "$T/agy" "$T/claude"
export OPENCODE_CONFIG_DIR="$T/opencode"
OPENCODE_CONFIG_DIR="$T/opencode" bash "$MAIN/apps/opencode/plugins/$P/install.sh"

run() {
  AGENT_PLUGINS_MAIN_CHECKOUT="$MAIN" AGENT_PLUGINS_CLAUDE="$T/claude" AGENT_PLUGINS_AGY="$T/agy" \
    AGENT_PLUGINS_CLAUDE_FILE="$T/installed.json" bash "$REFRESH" --plugin "$P" "$@" >"$T/out" 2>&1
}

if run --check; then pass "matching copies report up to date"; else fail "matching copies: $(cat "$T/out")"; fi

echo "v2" >"$MAIN/apps/claude-code/plugins/$P/lib/core.mjs"
if run --check; then fail "a changed Claude Code plugin was not reported"; else
  grep -q "Claude Code" "$T/out" && grep -q "differs" "$T/out" && pass "stale Claude Code copy fails --check" || fail "wrong message: $(cat "$T/out")"
fi
[[ ! -e "$T/claude.calls" ]] && pass "--check runs no claude command" || fail "--check ran: $(cat "$T/claude.calls")"
cp "$MAIN/apps/claude-code/plugins/$P/lib/core.mjs" "$T/cc-copy/lib/core.mjs"

echo "v2" >"$MAIN/apps/antigravity/plugins/$P/lib/core.mjs"
if run --check; then fail "a changed Antigravity plugin was not reported"; else
  grep -q "Antigravity" "$T/out" && pass "stale Antigravity copy fails --check" || fail "wrong message: $(cat "$T/out")"
fi
cp "$MAIN/apps/antigravity/plugins/$P/lib/core.mjs" "$T/agy-copy/lib/core.mjs"

: >"$T/opencode/plugins/$P/tui.tsx"
if run --check; then fail "a broken OpenCode loader was not reported"; else pass "broken OpenCode loader fails --check"; fi

# Refresh mode rewrites the OpenCode loaders itself.
if run; then pass "refresh repairs the OpenCode loaders"; else fail "refresh: $(cat "$T/out")"; fi

# --quiet (the scheduled run): silent when nothing changed, the full report when it fixed something.
if run --quiet && [[ ! -s "$T/out" ]]; then pass "--quiet prints nothing when all copies match"; else fail "--quiet with nothing to do printed: $(cat "$T/out")"; fi
: >"$T/opencode/plugins/$P/tui.tsx"
if run --quiet && grep -q "loaders rewritten" "$T/out" && grep -q "agent-plugins refresh" "$T/out"; then
  pass "--quiet prints a dated report when it repaired something"
else fail "--quiet after a repair: $(cat "$T/out")"; fi

# A Claude Code copy that stays stale after update+reinstall is a failure, not a pass.
echo "v3" >"$MAIN/apps/claude-code/plugins/$P/lib/core.mjs"
if run; then fail "refresh claimed success with a stale copy"; else
  grep -q "uninstall demo@vitruvian-core --scope user --keep-data" "$T/claude.calls" &&
    grep -q "install demo@vitruvian-core --scope user" "$T/claude.calls" &&
    pass "refresh reinstalls Claude Code and reports when the copy still differs" || fail "calls: $(cat "$T/claude.calls" 2>/dev/null)"
fi

if run --quiet; then fail "--quiet claimed success with a stale copy"; else
  grep -q "still differs" "$T/out" && pass "--quiet still reports a failure" || fail "--quiet hid a failure: $(cat "$T/out")"
fi

# --- Third-party Claude Code plugins ---
cp "$MAIN/apps/claude-code/plugins/$P/lib/core.mjs" "$T/cc-copy/lib/core.mjs"
mkdir -p "$T/mkt-remote/.claude-plugin" "$T/mkt-local/.claude-plugin"
echo '{"plugins":[{"name":"tool","source":"./","version":"2.0.0"}]}' >"$T/mkt-remote/.claude-plugin/marketplace.json"
echo '{"name":"tool","version":"2.0.0"}' >"$T/mkt-remote/.claude-plugin/plugin.json"
echo '{"plugins":[{"name":"mine","source":"./","version":"9.0.0"}]}' >"$T/mkt-local/.claude-plugin/marketplace.json"
printf '{"remote":{"source":{"source":"github","repo":"x/y"},"installLocation":"%s"},"local":{"source":{"source":"directory","path":"/x"},"installLocation":"%s"}}' \
  "$T/mkt-remote" "$T/mkt-local" >"$T/known_marketplaces.json"
write_installed() { # $1 = installed version of tool@remote
  printf '{"plugins":{"demo@vitruvian-core":[{"scope":"user","installPath":"%s"}],"tool@remote":[{"scope":"user","version":"%s"},{"scope":"project","projectPath":"/p","version":"0.1.0"}],"mine@local":[{"scope":"user","version":"1.0.0"}]}}' \
    "$T/cc-copy" "$1" >"$T/installed.json"
}
# A fake claude whose `plugin update tool@remote` installs 2.0.0, unless told to fail.
cat >"$T/claude" <<SH
#!/usr/bin/env bash
echo "\$*" >>"$T/claude.calls"
if [[ "\$1 \$2 \$3" == "plugin update tool@remote" ]]; then
  [[ -e "$T/fail-update" ]] && exit 1
  sed -i.bak 's/"version":"1.0.0"},{"scope":"project"/"version":"2.0.0"},{"scope":"project"/' "$T/installed.json"
fi
exit 0
SH
chmod +x "$T/claude"

write_installed 1.0.0
rm -f "$T/claude.calls"
if run --check; then fail "an outdated third-party plugin was not reported"; else
  grep -q "tool@remote is 1.0.0; its catalog has 2.0.0" "$T/out" && pass "--check reports an outdated third-party plugin" || fail "wrong message: $(cat "$T/out")"
fi
[[ ! -e "$T/claude.calls" ]] && pass "--check updates no third-party marketplace or plugin" || fail "--check ran: $(cat "$T/claude.calls")"
grep -q "mine@local" "$T/out" && fail "a directory marketplace plugin was checked" || pass "directory marketplace plugins are left alone"

if run --no-third-party --check; then pass "--no-third-party skips third-party plugins"; else fail "--no-third-party: $(cat "$T/out")"; fi

if run --quiet && grep -q "tool@remote updated 1.0.0 → 2.0.0" "$T/out"; then pass "refresh updates a third-party plugin and reports it"; else fail "third-party update: $(cat "$T/out")"; fi
grep -q "^plugin marketplace update remote$" "$T/claude.calls" && pass "refresh updates the plugin's marketplace first" || fail "calls: $(cat "$T/claude.calls")"
grep -q "^plugin update tool@remote --scope user$" "$T/claude.calls" && pass "update is user scope only" || fail "calls: $(cat "$T/claude.calls")"
grep -q "local\|mine@" "$T/claude.calls" && fail "refresh touched a directory marketplace: $(cat "$T/claude.calls")" || pass "refresh does not touch directory marketplaces"
grep -qE -- "(^| )(-y|--yes|--accept-command)( |$)" "$T/claude.calls" && fail "refresh auto-accepted a declared command" || pass "refresh never auto-accepts a marketplace-declared command"
grep -q '"projectPath":"/p","version":"0.1.0"' "$T/installed.json" && pass "project-scope install is left as is" || fail "project scope changed"

if run --quiet && [[ ! -s "$T/out" ]]; then pass "--quiet is silent when third-party plugins are current"; else fail "--quiet with current plugins printed: $(cat "$T/out")"; fi

write_installed 1.0.0
touch "$T/fail-update"
if run --quiet; then fail "a failed third-party update was reported as success"; else
  grep -q "tool@remote: update failed" "$T/out" && pass "a failed third-party update fails the run and is reported" || fail "failed update: $(cat "$T/out")"
fi
rm -f "$T/fail-update"

[[ "$fails" -eq 0 ]] || { echo "$fails failure(s)"; exit 1; }
echo "all passed"
