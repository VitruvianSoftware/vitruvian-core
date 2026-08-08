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

# agent-app_test — offline tests for tools/agent-app/agent-app.sh.
#
# Everything here runs with NO network and NO real App: the parts worth pinning
# are the ones that fail silently in production. A JWT with the wrong base64
# alphabet, or an iat GitHub reads as being in the future, are both rejected with
# messages that point at the key rather than at the encoding.

set -uo pipefail

SCRIPT="${SCRIPT:-tools/agent-app/agent-app.sh}"
[ -x "$SCRIPT" ] || SCRIPT="$(dirname "$0")/agent-app.sh"
REGISTRY="${REGISTRY:-$(dirname "$SCRIPT")/agents.tsv}"

failures=0
ok() { echo "  ok: $1"; }
bad() {
  echo "  FAIL: $1" >&2
  failures=$((failures + 1))
}

# A throwaway key, generated per run: no fixture key is ever committed.
KEYDIR="$(mktemp -d)"
trap 'rm -rf "$KEYDIR"' EXIT
openssl genrsa -out "$KEYDIR/key.pem" 2048 2>/dev/null

echo "== refuses incomplete arguments rather than calling GitHub =="
for args in "convert" "convert onlycode" "installations" "installations 1" "token 1 key" "repos 1 key"; do
  # shellcheck disable=SC2086
  if out="$(GITHUB_API_URL=http://127.0.0.1:1 bash "$SCRIPT" $args 2>&1)"; then
    bad "'$args' exited 0; expected a usage error"
  elif [[ "$out" != *usage* ]]; then
    bad "'$args' failed without a usage message: $out"
  else
    ok "'$args' rejected with usage"
  fi
done

echo "== never overwrites an existing key =="
touch "$KEYDIR/existing.pem"
if out="$(bash "$SCRIPT" convert somecode "$KEYDIR/existing.pem" 2>&1)"; then
  bad "convert overwrote an existing key file"
elif [[ "$out" != *"refusing to overwrite"* ]]; then
  bad "convert failed for the wrong reason: $out"
else
  ok "convert refuses to clobber an existing key"
fi

echo "== unknown subcommand is an error, not a no-op =="
if bash "$SCRIPT" nonsense >/dev/null 2>&1; then
  bad "unknown subcommand exited 0"
else
  ok "unknown subcommand rejected"
fi

echo "== JWT is well-formed, base64url, and verifies against the key =="
# app_jwt is sourced rather than invoked so the test exercises the real function.
# shellcheck disable=SC1090
# Extract the two functions to a file and source them, so the test exercises the
# REAL implementations rather than a copy that can drift from them.
sed -n '/^b64url()/,/^}/p;/^app_jwt()/,/^}/p' "$SCRIPT" > "$KEYDIR/funcs.sh"
# shellcheck disable=SC1091
source "$KEYDIR/funcs.sh"
JWT="$(app_jwt 12345 "$KEYDIR/key.pem")"

if [ "$(awk -F. '{print NF}' <<<"$JWT")" -ne 3 ]; then
  bad "JWT does not have three dot-separated parts"
else
  ok "JWT has header.payload.signature"
fi

if [[ "$JWT" == *"+"* || "$JWT" == *"/"* || "$JWT" == *"="* ]]; then
  bad "JWT contains +, / or = -- that is standard base64, not base64url, and GitHub rejects it"
else
  ok "JWT uses the base64url alphabet with no padding"
fi

decode() { # base64url -> json
  local s="$1"
  s="${s//-/+}"
  s="${s//_//}"
  while [ $((${#s} % 4)) -ne 0 ]; do s="${s}="; done
  printf '%s' "$s" | openssl base64 -d -A
}

hdr="$(decode "$(cut -d. -f1 <<<"$JWT")")"
pay="$(decode "$(cut -d. -f2 <<<"$JWT")")"

# Deliberately NOT jq. The Bazel test sandbox has no jq -- this test passed on a
# laptop and failed in CI for exactly that reason. These are two tiny fixed-shape
# JSON objects this file generates itself, so a sed reader is sufficient and
# keeps the test dependent only on what the sandbox actually provides.
json_str() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" <<<"$1"; }
json_num() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p" <<<"$1"; }

[ "$(json_str "$hdr" alg)" = "RS256" ] && ok "alg is RS256" || bad "alg is not RS256: $hdr"
[ "$(json_str "$pay" iss)" = "12345" ] && ok "iss is the app id" || bad "iss wrong: $pay"

now="$(date +%s)"
iat="$(json_num "$pay" iat)"
exp="$(json_num "$pay" exp)"
# GitHub rejects a future iat outright; backdating is the whole reason this is
# not simply `date +%s`.
if [ "$iat" -lt "$now" ]; then
  ok "iat is backdated against clock skew"
else
  bad "iat $iat is not in the past (now=$now) -- GitHub rejects future iat"
fi
# GitHub's hard cap is 10 minutes.
if [ "$((exp - iat))" -le 600 ]; then
  ok "lifetime is within GitHub's 10-minute cap"
else
  bad "lifetime $((exp - iat))s exceeds GitHub's 600s cap"
fi

# The signature must actually verify -- a JWT that merely LOOKS right is the
# failure this whole file exists to catch.
sig_input="$(cut -d. -f1,2 <<<"$JWT")"
sig_b64="$(cut -d. -f3 <<<"$JWT")"
printf '%s' "$sig_input" > "$KEYDIR/input.bin"
decode "$sig_b64" > "$KEYDIR/sig.bin"
openssl pkey -in "$KEYDIR/key.pem" -pubout -out "$KEYDIR/pub.pem" 2>/dev/null
if openssl dgst -sha256 -verify "$KEYDIR/pub.pem" -signature "$KEYDIR/sig.bin" "$KEYDIR/input.bin" >/dev/null 2>&1; then
  ok "signature verifies against the key"
else
  bad "signature does NOT verify -- the JWT would be rejected by GitHub"
fi


echo "== login rejects an unknown agent rather than guessing =="
if out="$(AGENT_REGISTRY="$REGISTRY" bash "$SCRIPT" login nosuchagent 2>&1)"; then
  bad "login accepted an unknown agent"
elif [[ "$out" != *"unknown agent"* ]]; then
  bad "login failed for the wrong reason: $out"
else
  ok "login rejects an unknown agent and lists the known ones"
fi

echo "== login refuses when the key is absent, naming the fix =="
if out="$(AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR=/nonexistent bash "$SCRIPT" login beacon 2>&1)"; then
  bad "login proceeded without a key"
elif [[ "$out" != *"agent-keys-pull"* ]]; then
  bad "login did not point at the recovery command: $out"
else
  ok "login names agent-keys-pull when the key is missing"
fi

echo "== every registry row is well-formed =="
# A row with a missing column would resolve to an empty id and produce a 404 that
# reads like a permissions problem -- the exact confusion called out in the SOP.
bad_rows="$(awk -F'\t' '!/^#/ && NF>0 && (NF!=3 || $2=="" || $3=="")' "$REGISTRY" | wc -l | tr -d ' ')"
if [ "$bad_rows" = "0" ]; then
  ok "all registry rows have agent, app id and installation id"
else
  bad "$bad_rows malformed row(s) in agents.tsv"
fi

if [ "$failures" -ne 0 ]; then
  echo "agent-app_test: $failures failure(s)" >&2
  exit 1
fi
echo "agent-app_test: all checks passed"
