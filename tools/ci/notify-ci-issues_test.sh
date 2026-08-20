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

# Hermetic guard for tools/ci/notify-ci-issues.sh. Fakes `gh api` (canned
# workflow-run JSON, real `jq` does the actual filtering/grouping) and `curl`
# (captures the ntfy POST body instead of sending it) — no network, no
# credentials. GNU `date` is required for `-d` (matches the runner; on a BSD
# `date` host — e.g. local macOS — this test shims PATH with `gdate` if
# present, exactly as production always has GNU date via ubuntu-latest).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/notify-ci-issues.sh"

fails=0
ok() { printf '  ok - %s\n' "$1"; }
bad() { printf '  NOT OK - %s\n' "$1" >&2; fails=$((fails + 1)); }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/bin"

if ! date -u -d '1 minute ago' +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
  if command -v gdate >/dev/null 2>&1; then
    ln -sf "$(command -v gdate)" "$work/bin/date"
  else
    echo "SKIP: no GNU-compatible 'date -d' available (need gdate on macOS) — cannot run this test" >&2
    exit 0
  fi
fi

recent="$(PATH="$work/bin:$PATH" date -u -d '5 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"
stale="$(PATH="$work/bin:$PATH" date -u -d '60 minutes ago' +%Y-%m-%dT%H:%M:%SZ)"

cat > "$work/bin/gh" <<'EOF'
#!/usr/bin/env bash
empty='{"workflow_runs":[]}'
if [ "$1" = "api" ]; then
  case "$2" in
    *"status=waiting"*) printf '%s' "${FAKE_WAITING_JSON:-$empty}" ;;
    *"status=action_required"*) printf '%s' "${FAKE_ACTION_REQUIRED_JSON:-$empty}" ;;
    *"status=failure"*)
      # Per-repo answers so the mirror fan-out is observable. $FAKE_UNREADABLE
      # names a repo whose API call fails, as an unreachable mirror would.
      if [ -n "${FAKE_UNREADABLE:-}" ] && case "$2" in *"${FAKE_UNREADABLE}"*) true ;; *) false ;; esac; then
        echo "HTTP 404: Not Found" >&2; exit 1
      fi
      case "$2" in
        *"owner/repo"*) printf '%s' "${FAKE_FAILURE_JSON:-$empty}" ;;
        *) printf '%s' "${FAKE_MIRROR_FAILURE_JSON:-$empty}" ;;
      esac ;;
    *) echo "unexpected gh api url: $2" >&2; exit 99 ;;
  esac
  exit 0
fi
echo "unexpected fake gh invocation: $*" >&2
exit 99
EOF
chmod +x "$work/bin/gh"

cat > "$work/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo "CALL" >> "${FAKE_CURL_LOG}"
body="" prev=""
for arg in "$@"; do
  [ "$prev" = "-d" ] && body="$arg"
  prev="$arg"
done
printf '%s\n' "$body" >> "${FAKE_CURL_BODIES}"
exit "${FAKE_CURL_RC:-0}"
EOF
chmod +x "$work/bin/curl"

run() { # <env...>
  : > "$work/curl.log"; : > "$work/curl.bodies"
  env PATH="$work/bin:$PATH" REPO="owner/repo" GH_TOKEN=x NTFY_PASSWORD=secret \
    FAKE_CURL_LOG="$work/curl.log" FAKE_CURL_BODIES="$work/curl.bodies" \
    "$@" bash "$SCRIPT" >"$work/stdout" 2>"$work/stderr"
  echo $?
}

echo "--- waiting-on-approval: recent run notifies, stale run is filtered ---"
waiting_json=$(cat <<JSON
{"workflow_runs":[
  {"name":"tabula-deploy","html_url":"https://x/runs/1","updated_at":"${recent}"},
  {"name":"stale-workflow","html_url":"https://x/runs/2","updated_at":"${stale}"}
]}
JSON
)
rc="$(run FAKE_WAITING_JSON="$waiting_json")"
if [ "$rc" = "0" ] && grep -q -- '-> waiting: tabula-deploy' "$work/stdout" \
   && ! grep -q 'stale-workflow' "$work/stdout"; then
  ok "recent waiting run is picked up, stale one is filtered by cutoff"
else
  bad "waiting-run cutoff filtering wrong (rc=$rc)"; sed 's/^/    /' "$work/stdout" >&2
fi
if grep -q '"title": "\[ci\] approval needed: tabula-deploy"' "$work/curl.bodies" \
   && grep -q '"priority": 4' "$work/curl.bodies"; then
  ok "notify() posts the expected title and priority for a waiting run"
else
  bad "notify() payload for waiting run wrong:"; cat "$work/curl.bodies" >&2
fi

echo "--- action_required: grouped by branch, one alert per branch ---"
ar_json=$(cat <<JSON
{"workflow_runs":[
  {"name":"a","head_branch":"feature-x","html_url":"https://x/runs/10","updated_at":"${recent}"},
  {"name":"b","head_branch":"feature-x","html_url":"https://x/runs/11","updated_at":"${recent}"},
  {"name":"c","head_branch":"feature-y","html_url":"https://x/runs/12","updated_at":"${stale}"}
]}
JSON
)
rc="$(run FAKE_ACTION_REQUIRED_JSON="$ar_json")"
if [ "$rc" = "0" ] && grep -q 'action_required: 2 run(s) on feature-x' "$work/stdout" \
   && ! grep -q 'feature-y' "$work/stdout"; then
  ok "two recent action_required runs on the same branch collapse into one alert; the stale branch is dropped"
else
  bad "action_required grouping wrong:"; sed 's/^/    /' "$work/stdout" >&2
fi

echo "--- main failures: recent notifies at priority 5 ---"
fail_json=$(cat <<JSON
{"workflow_runs":[
  {"name":"ci","html_url":"https://x/runs/20","updated_at":"${recent}"}
]}
JSON
)
rc="$(run FAKE_FAILURE_JSON="$fail_json")"
if [ "$rc" = "0" ] && grep -q '"title": "\[ci\] main broken: ci"' "$work/curl.bodies" \
   && grep -q '"priority": 5' "$work/curl.bodies"; then
  ok "main-branch failure notifies with priority 5"
else
  bad "main-failure payload wrong:"; cat "$work/curl.bodies" >&2
fi

echo "--- a failed ntfy push warns but never fails the run ---"
rc="$(run FAKE_FAILURE_JSON="$fail_json" FAKE_CURL_RC=22)"
if [ "$rc" = "0" ] && grep -q 'WARN: ntfy push failed for: \[ci\] main broken: ci' "$work/stderr"; then
  ok "a failed curl POST is only a WARN; the script still exits 0"
else
  bad "curl-failure handling wrong (rc=$rc):"; sed 's/^/    /' "$work/stderr" >&2
fi

echo "--- CUTOFF_MINUTES is configurable ---"
rc="$(run FAKE_WAITING_JSON="$waiting_json" CUTOFF_MINUTES=1)"
if [ "$rc" = "0" ] && grep -q "Checking for runs waiting on approval, updated since" "$work/stdout" \
   && ! grep -q 'waiting: tabula-deploy' "$work/stdout"; then
  ok "a tighter CUTOFF_MINUTES correctly excludes the 5-minutes-old run"
else
  bad "CUTOFF_MINUTES override did not take effect:"; sed 's/^/    /' "$work/stdout" >&2
fi

echo "--- exported mirrors are watched too (#1511) ---"
# Every query in this script interpolates $REPO -- the repo it runs in -- so the
# copybara mirrors were unreachable BY CONSTRUCTION. Measured 2026-08-20: four
# of eight were failing and no alert had ever fired, including nexus-agent's
# Release runs, recorded nowhere at all.
mirror_json=$(cat <<JSON
{"workflow_runs":[
  {"name":"Release","html_url":"https://x/mirror/9","updated_at":"${recent}"}
]}
JSON
)
rc="$(run MIRRORS="VitruvianSoftware/mcp-slack" FAKE_MIRROR_FAILURE_JSON="$mirror_json")"
if [ "$rc" = "0" ] && grep -q 'mcp-slack broken: Release' "$work/curl.bodies" \
   && grep -q 'exported mirror' "$work/curl.bodies"; then
  ok "a mirror failure notifies, naming the mirror and where the fix belongs"
else
  bad "mirror failure did not notify:"; sed 's/^/    /' "$work/curl.bodies" >&2
fi

echo "--- switching mirrors on does not alert their existing backlog ---"
stale_mirror=$(cat <<JSON
{"workflow_runs":[
  {"name":"Release","html_url":"https://x/mirror/8","updated_at":"${stale}"}
]}
JSON
)
rc="$(run MIRRORS="VitruvianSoftware/mcp-slack" FAKE_MIRROR_FAILURE_JSON="$stale_mirror")"
if [ ! -s "$work/curl.bodies" ]; then
  ok "a mirror's OLD failures are filtered by the cutoff (no firehose)"
else
  bad "stale mirror run alerted:"; sed 's/^/    /' "$work/curl.bodies" >&2
fi

echo "--- an unreadable mirror is loud, never silent ---"
rc="$(run MIRRORS="VitruvianSoftware/mcp-slack" FAKE_UNREADABLE="mcp-slack")"
if [ "$rc" = "0" ] && grep -q "NOT watching it" "$work/stderr"; then
  ok "an unreadable mirror warns loudly and does not abort the poll"
else
  bad "unreadable mirror was silent (the very defect being fixed):"; sed 's/^/    /' "$work/stderr" >&2
fi

echo "--- the monorepo's own failures are unchanged ---"
own_json=$(cat <<JSON
{"workflow_runs":[
  {"name":"CI","html_url":"https://x/own/7","updated_at":"${recent}"}
]}
JSON
)
rc="$(run MIRRORS="VitruvianSoftware/mcp-slack" FAKE_FAILURE_JSON="$own_json")"
if grep -q 'main broken: CI' "$work/curl.bodies" && ! grep -q 'exported mirror' "$work/curl.bodies"; then
  ok "the monorepo's own main failure still notifies, not mislabelled as a mirror"
else
  bad "own-repo failure regressed:"; sed 's/^/    /' "$work/curl.bodies" >&2
fi

if [ "$fails" -gt 0 ]; then echo "FAILED: $fails" >&2; exit 1; fi
echo "ALL PASS"
