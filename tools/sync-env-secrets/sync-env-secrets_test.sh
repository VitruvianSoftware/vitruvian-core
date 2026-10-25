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
# SYNC_ENV_SECRETS_BIN runs the same checks against another build of the tool
# (the Rust port, :sync-env-secrets-rs_test). A binary has no functions to
# source, so there each check drives a whole subcommand instead: the session
# ensure_bw_session picked is the one `unlock` caches, and the mode check is
# `agent-keys-push` on a real store.
BIN="${SYNC_ENV_SECRETS_BIN:-}"
if [ -n "$BIN" ]; then
  case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
fi

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
# Enough of the rest for a whole bw-push (the binary checks only).
case "$1 ${2:-}" in
  "list items") echo '[]' ;;
  "encode "*) base64 ;;
  "create item") echo '{"id":"item-1"}' ;;
esac
exit 0
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
pick_bin() { # the binary: `unlock` caches whatever session it settled on
  local exported="$1" cached="$2"
  rm -rf "$TMP/xdg"; mkdir -p "$TMP/xdg/vitruvian-core"
  [ "$cached" = - ] || printf '%s' "$cached" >"$TMP/xdg/vitruvian-core/bw-session"
  (
    export PATH="$TMP/bin:$PATH" XDG_CACHE_HOME="$TMP/xdg"
    unset BW_SESSION BW_PASSWORD
    [ "$exported" = - ] || export BW_SESSION="$exported"
    "$BIN" unlock </dev/null >/dev/null 2>&1 && echo "0 $(cat "$TMP/xdg/vitruvian-core/bw-session")"
  ) || echo "1 -"
}
pick() {
  [ -z "$BIN" ] || { pick_bin "$@"; return; }
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

echo "== agent-keys-push checks the key's mode =="
# A fake stat that behaves like GNU's: -f is filesystem status (it succeeds, with
# text that is no mode); -c %a is the mode. Trying the BSD form first reads the
# filesystem text as the mode and refuses every key on Linux.
cat >"$TMP/bin/stat" <<'EOF2'
#!/usr/bin/env bash
if [ "$1" = -f ]; then echo "  File: \"$3\"  ID: 0 Namelen: 255 Type: ext2/ext3"; exit 0; fi
if [ "$1" = -c ]; then case "$3" in *loose*) echo 644 ;; *) echo 600 ;; esac; exit 0; fi
exit 1
EOF2
chmod +x "$TMP/bin/stat"
sed -n '/^die()/,/^}/p;/^cmd_agent_keys_push()/,/^}/p' "$SCRIPT" >"$TMP/keys.sh"
push_bin() { # the binary: a real agent-keys-push, the file's mode set for real
  local ws="$TMP/ws" out
  rm -rf "$ws"; mkdir -p "$ws/tools/sync-env-secrets/agent-keys"
  : >"$ws/tools/sync-env-secrets/agent-keys/$1"
  local mode=600
  case "$1" in *loose*) mode=644 ;; esac
  chmod "$mode" "$ws/tools/sync-env-secrets/agent-keys/$1"
  out="$(
    export PATH="$TMP/bin:$PATH" BUILD_WORKSPACE_DIRECTORY="$ws" BW_SESSION=good TMPDIR="$TMP"
    "$BIN" agent-keys-push </dev/null 2>&1
  )" && case "$out" in *"pushed agent-app-keys.tar.gz"*) out=pushed ;; esac
  printf '%s\n' "$out"
}
push() { # key file name -> output of the push precheck, `pushed` if it got past it
  [ -z "$BIN" ] || { push_bin "$@"; return; }
  rm -rf "$TMP/store"; mkdir -p "$TMP/store"; : >"$TMP/store/$1"
  (
    export PATH="$TMP/bin:$PATH"
    AGENT_KEY_STORE="$TMP/store"; AGENT_KEY_ITEM=x; AGENT_KEY_ARCHIVE=x
    cmd_bw_push() { echo pushed; }
    # shellcheck disable=SC1091
    source "$TMP/keys.sh"
    ( cmd_agent_keys_push ) 2>&1
  )
}
[ "$(push good.pem)" = pushed ] && ok "a mode-600 key goes through where stat -f is filesystem status" ||
  bad "mode-600 key: got '$(push good.pem)'"
loose="$(push loose.pem)"
case "$loose" in *"mode 644; expected 600"*) ok "a mode-644 key is refused" ;; *) bad "mode-644 key: got '$loose'" ;; esac

if [ "$failures" -ne 0 ]; then
  echo "sync-env-secrets_test: $failures failure(s)" >&2
  exit 1
fi
echo "sync-env-secrets_test: all checks passed"
