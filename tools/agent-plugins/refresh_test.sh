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

# A Claude Code copy that stays stale after update+reinstall is a failure, not a pass.
echo "v3" >"$MAIN/apps/claude-code/plugins/$P/lib/core.mjs"
if run; then fail "refresh claimed success with a stale copy"; else
  grep -q "uninstall demo@vitruvian-core --scope user --keep-data" "$T/claude.calls" &&
    grep -q "install demo@vitruvian-core --scope user" "$T/claude.calls" &&
    pass "refresh reinstalls Claude Code and reports when the copy still differs" || fail "calls: $(cat "$T/claude.calls" 2>/dev/null)"
fi

[[ "$fails" -eq 0 ]] || { echo "$fails failure(s)"; exit 1; }
echo "all passed"
