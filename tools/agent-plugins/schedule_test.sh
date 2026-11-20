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


# Tests //tools/agent-plugins:schedule with a fake launchctl and temp folders.
# Never touches the real ~/Library/LaunchAgents or launchd.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCHEDULE="$HERE/schedule.sh"
[[ -f "$SCHEDULE" ]] || SCHEDULE="${TEST_SRCDIR:-}/_main/tools/agent-plugins/schedule.sh"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }

MAIN="$T/main checkout & co"
mkdir -p "$MAIN/tools/agent-plugins"
printf '#!/usr/bin/env bash\n# --quiet\n' >"$MAIN/tools/agent-plugins/refresh.sh"
cat >"$T/launchctl" <<SH
#!/usr/bin/env bash
echo "\$*" >>"$T/calls"
if [[ "\$1" == print ]]; then [[ -f "$T/loaded" ]]; exit; fi
if [[ "\$1" == bootstrap ]]; then touch "$T/loaded"; fi
if [[ "\$1" == bootout ]]; then rm -f "$T/loaded"; fi
SH
chmod +x "$T/launchctl"
PLIST="$T/agents/dev.vitruvian.agent-plugins-refresh.plist"

run() {
  AGENT_PLUGINS_MAIN_CHECKOUT="$MAIN" AGENT_PLUGINS_LAUNCH_AGENTS="$T/agents" AGENT_PLUGINS_LOG_DIR="$T/logs" \
    AGENT_PLUGINS_LAUNCHCTL="$T/launchctl" AGENT_PLUGINS_UNAME=Darwin bash "$SCHEDULE" "$@" >"$T/out" 2>&1
}

if run status; then fail "status passed before install"; else pass "status fails when not installed"; fi

if run install; then pass "install succeeds"; else fail "install: $(cat "$T/out")"; fi
grep -q "<integer>1800</integer>" "$PLIST" && pass "default interval is 30 minutes" || fail "interval: $(grep -A1 StartInterval "$PLIST")"
grep -q "main checkout &amp; co/tools/agent-plugins/refresh.sh" "$PLIST" && pass "paths are XML-escaped" || fail "path not escaped"
grep -q -- '--quiet' "$PLIST" && pass "job runs refresh --quiet" || fail "no --quiet in job"
grep -q "^bootstrap gui/$(id -u) $PLIST" "$T/calls" && pass "install loads the job into launchd" || fail "calls: $(cat "$T/calls")"
if command -v plutil >/dev/null; then
  plutil -lint "$PLIST" >/dev/null && pass "job file is a valid plist" || fail "plutil rejected the job file"
fi

if run status && grep -q "installed and loaded" "$T/out"; then pass "status reports a loaded job"; else fail "status: $(cat "$T/out")"; fi

if run install --every 3; then fail "accepted a 3-minute interval"; else pass "rejects intervals under 5 minutes"; fi
if run install --every 60 && grep -q "<integer>3600</integer>" "$PLIST"; then pass "--every sets the interval"; else fail "--every 60: $(cat "$T/out")"; fi
[[ "$(grep -c '^bootout' "$T/calls")" -ge 1 ]] && pass "reinstall unloads the old job first" || fail "no bootout before reinstall"

if run remove && [[ ! -f "$PLIST" && ! -f "$T/loaded" ]]; then pass "remove unloads and deletes the job"; else fail "remove: $(cat "$T/out")"; fi

printf '#!/usr/bin/env bash\n' >"$MAIN/tools/agent-plugins/refresh.sh"
if run install; then fail "installed against a refresh.sh without --quiet"; else
  grep -q "update-main" "$T/out" && pass "refuses an out-of-date main checkout" || fail "message: $(cat "$T/out")"
fi

if AGENT_PLUGINS_MAIN_CHECKOUT="$MAIN" AGENT_PLUGINS_LAUNCH_AGENTS="$T/agents" AGENT_PLUGINS_LAUNCHCTL="$T/launchctl" \
  AGENT_PLUGINS_UNAME=Linux bash "$SCHEDULE" install >"$T/out" 2>&1; then fail "installed on Linux"; else pass "refuses to install off macOS"; fi

[[ "$fails" -eq 0 ]] || { echo "$fails failure(s)"; exit 1; }
echo "all passed"
