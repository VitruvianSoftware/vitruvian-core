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

# sync-env-secrets_test — how ensure_bw_session picks a Bitwarden session.
# A fake `bw` on PATH says "unlocked" only for the session "good"; no vault,
# no network. The real functions are sourced from the script, not copied.

set -uo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sync-env-secrets.sh"
[ -f "$SCRIPT" ] || { echo "cannot find sync-env-secrets.sh" >&2; exit 1; }

failures=0
ok() { echo "  ok: $1"; }
bad() { echo "  FAIL: $1" >&2; failures=$((failures + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat >"$TMP/bin/bw" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = status ]; then
  if [ "${BW_SESSION:-}" = good ]; then echo '{"status":"unlocked"}'; else echo '{"status":"locked"}'; fi
fi
EOF
chmod +x "$TMP/bin/bw"
# bw_state pipes through jq. Under Bazel it is the hermetic one (JQ_BIN, an
# exec path: external/<repo>/... is ../<repo>/... from the runfiles root); CI's
# test image has none of its own. Run by hand, the one on PATH.
if [ -n "${JQ_BIN:-}" ]; then
  case "$JQ_BIN" in external/*) JQ_BIN="../${JQ_BIN#external/}" ;; esac
  ln -s "$(cd "$(dirname "$JQ_BIN")" && pwd)/$(basename "$JQ_BIN")" "$TMP/bin/jq"
fi
JQ="$(PATH="$TMP/bin:$PATH" command -v jq)" || { echo "sync-env-secrets_test: no jq (JQ_BIN or PATH)" >&2; exit 1; }
echo "using jq: $JQ"

sed -n '/^die()/,/^}/p;/^bw_state()/p;/^ensure_bw_session()/,/^}/p' "$SCRIPT" >"$TMP/funcs.sh"

# pick <exported BW_SESSION or -> <cache contents or -> -> "rc session"
pick() {
  local exported="$1" cached="$2"
  rm -f "$TMP/cache"
  [ "$cached" = - ] || printf '%s' "$cached" >"$TMP/cache"
  (
    export PATH="$TMP/bin:$PATH" SESS_CACHE="$TMP/cache"
    unset BW_SESSION BW_PASSWORD
    [ "$exported" = - ] || export BW_SESSION="$exported"
    # shellcheck disable=SC1091
    source "$TMP/funcs.sh"
    # die exits, so run it one level down and report what it left behind.
    ( ensure_bw_session </dev/null 2>/dev/null && echo "0 ${BW_SESSION:-}" ) || echo "1 -"
  )
}

echo "== ensure_bw_session =="
[ "$(pick good -)" = "0 good" ] && ok "an exported session that unlocks is used" || bad "exported good: $(pick good -)"
[ "$(pick - good)" = "0 good" ] && ok "with none exported, the cached session is used" || bad "cache only: $(pick - good)"
[ "$(pick stale good)" = "0 good" ] &&
  ok "a stale exported session falls back to the cached one" ||
  bad "stale exported + good cache: got '$(pick stale good)', want '0 good'"
[ "$(pick stale stale)" = "1 -" ] && ok "stale everywhere and no terminal: fails, unlocks nothing" || bad "stale both: $(pick stale stale)"

if [ "$failures" -ne 0 ]; then
  echo "sync-env-secrets_test: $failures failure(s)" >&2
  exit 1
fi
echo "sync-env-secrets_test: all checks passed"
