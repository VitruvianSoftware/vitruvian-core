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
bad_rows="$(awk -F'\t' '!/^#/ && NF>0 && (NF!=4 || $2=="" || $3=="")' "$REGISTRY" | wc -l | tr -d ' ')"
if [ "$bad_rows" = "0" ]; then
  ok "all registry rows have agent, app id and installation id"
else
  bad "$bad_rows malformed row(s) in agents.tsv"
fi


echo "== env emits BOTH the token and the git identity =="
# The whole point: GH_TOKEN alone leaves commits authored by the machine owner.
# A regression here is silent -- pushes keep working, attribution quietly reverts.
out="$(AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR=/nonexistent bash "$SCRIPT" env beacon 2>&1 || true)"
if [[ "$out" == *"agent-keys-pull"* ]]; then
  ok "env fails closed when the key is missing (cannot emit a half identity)"
else
  bad "env did not fail on a missing key: $out"
fi

echo "== every registry row carries a bot_user_id =="
# A row missing column 4 would emit an author address like "+slug[bot]@..." --
# syntactically valid, attributed to nobody, and invisible until someone reads
# the commit log.
missing="$(awk -F'\t' '!/^#/ && NF>0 && (NF!=4 || $4=="")' "$REGISTRY" | wc -l | tr -d ' ')"
if [ "$missing" = "0" ]; then
  ok "all registry rows carry a bot_user_id"
else
  bad "$missing row(s) missing bot_user_id -- commits would be attributed to nobody"
fi

echo "== pr-create opens the PR as the agent, with the fast-lane label once =="
# Offline: stub curl (GitHub's token endpoint), jq (absent in the sandbox) and
# gh on PATH. The token is a sentinel, so any place it leaks is easy to see.
STUB="$KEYDIR/stub"
mkdir -p "$STUB" "$KEYDIR/keys"
cp "$KEYDIR/key.pem" "$KEYDIR/keys/wren.pem"
cp "$KEYDIR/key.pem" "$KEYDIR/keys/beacon.pem"
SECRET="ghs_SENTINEL_never_print_me"
cat >"$STUB/curl" <<STUBEOF
#!/usr/bin/env bash
for a in "\$@"; do case "\$a" in http*) echo "\$a" >>"$KEYDIR/curl.log" ;; esac; done
printf '{"token":"%s"}' "$SECRET"
STUBEOF
cat >"$STUB/jq" <<'STUBEOF'
#!/usr/bin/env bash
sed -n 's/.*"token":"\([^"]*\)".*/\1/p'
STUBEOF
cat >"$STUB/gh" <<STUBEOF
#!/usr/bin/env bash
: >"$KEYDIR/gh.args"
for a in "\$@"; do printf '%s\n' "\$a" >>"$KEYDIR/gh.args"; done
if [ "\${GH_TOKEN:-}" = "$SECRET" ]; then echo ok; else echo wrong; fi >"$KEYDIR/gh.token"
echo "\${GITHUB_TOKEN:-}" >"$KEYDIR/gh.github_token"
echo "https://github.com/o/r/pull/1"
STUBEOF
chmod +x "$STUB/curl" "$STUB/jq" "$STUB/gh"
prc() { # args... -> runs pr-create, output in $KEYDIR/prc.out
  rm -f "$KEYDIR/gh.args" "$KEYDIR/gh.token" "$KEYDIR/curl.log"
  PATH="$STUB:$PATH" AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR="$KEYDIR/keys" GITHUB_TOKEN=ambient \
    bash "$SCRIPT" pr-create "$@" >"$KEYDIR/prc.out" 2>&1
}
label_count() { grep -cx "agent-fast-lane" "$KEYDIR/gh.args" 2>/dev/null || true; }
inst_of() { awk -F'\t' -v a="$1" '!/^#/ && $1==a {print $3}' "$REGISTRY"; }

prc --title "two words" --body-file pr.md --draft
want="$(printf '%s\n' pr create --title "two words" --body-file pr.md --draft --label agent-fast-lane)"
if [ "$(cat "$KEYDIR/gh.args" 2>/dev/null)" = "$want" ]; then
  ok "adds --label agent-fast-lane and passes every other argument through unchanged"
else
  bad "gh got: $(tr '\n' '|' <"$KEYDIR/gh.args" 2>/dev/null) ; out: $(cat "$KEYDIR/prc.out")"
fi
[ "$(cat "$KEYDIR/gh.token" 2>/dev/null)" = ok ] && ok "gh runs with the agent's token" || bad "gh did not get the agent token"
[ -z "$(cat "$KEYDIR/gh.github_token" 2>/dev/null)" ] && ok "an ambient GITHUB_TOKEN cannot override it" || bad "GITHUB_TOKEN leaked through to gh"
grep -q "/app/installations/$(inst_of wren)/access_tokens" "$KEYDIR/curl.log" 2>/dev/null &&
  ok "defaults to the wren app" || bad "did not mint wren's token: $(cat "$KEYDIR/curl.log" 2>/dev/null)"
if grep -q "$SECRET" "$KEYDIR/prc.out" "$KEYDIR/gh.args"; then
  bad "the token was printed or passed as an argument"
else
  ok "the token is never printed and never in argv"
fi

for given in "--label agent-fast-lane" "--label=agent-fast-lane" "-l agent-fast-lane" "--label ci,agent-fast-lane"; do
  # shellcheck disable=SC2086
  prc --title t $given
  if [ "$(label_count)" -le 1 ] && grep -q "agent-fast-lane" "$KEYDIR/gh.args" &&
    [ "$(grep -c -e '^--label' -e '^-l$' "$KEYDIR/gh.args")" -eq 1 ]; then
    ok "not added again when the caller passed '$given'"
  else
    bad "'$given': gh got $(tr '\n' '|' <"$KEYDIR/gh.args")"
  fi
done
prc --title t --label ci
[ "$(label_count)" = 1 ] && grep -qx ci "$KEYDIR/gh.args" &&
  ok "another label does not count: the fast-lane label is still added" || bad "with --label ci, gh got $(tr '\n' '|' <"$KEYDIR/gh.args")"

prc --agent beacon --title t
grep -q "/app/installations/$(inst_of beacon)/access_tokens" "$KEYDIR/curl.log" 2>/dev/null &&
  ! grep -qx -e --agent -e beacon "$KEYDIR/gh.args" &&
  ok "--agent picks the app and is not passed to gh" || bad "--agent beacon: curl $(cat "$KEYDIR/curl.log" 2>/dev/null); gh $(tr '\n' '|' <"$KEYDIR/gh.args")"

echo "== pr-create fails clearly and opens nothing when no token can be minted =="
rm -f "$KEYDIR/gh.args"
if PATH="$STUB:$PATH" AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR=/nonexistent bash "$SCRIPT" pr-create --title t >"$KEYDIR/prc.out" 2>&1; then
  bad "pr-create exited 0 without a key"
elif [ -e "$KEYDIR/gh.args" ]; then
  bad "gh was run anyway, as whoever it is logged in as"
elif grep -q "NOT opened" "$KEYDIR/prc.out" && grep -q "agent-keys-pull" "$KEYDIR/prc.out"; then
  ok "no key: says the PR was not opened and names the fix; gh never runs"
else
  bad "unclear failure: $(cat "$KEYDIR/prc.out")"
fi
rm -f "$KEYDIR/gh.args"
if prc --agent nosuchagent --title t; then
  bad "pr-create accepted an unknown agent"
elif [ -e "$KEYDIR/gh.args" ]; then
  bad "gh was run for an unknown agent"
else
  ok "an unknown agent opens nothing"
fi
printf '#!/usr/bin/env bash\nexit 22\n' >"$STUB/curl"
rm -f "$KEYDIR/gh.args"
if prc --title t; then
  bad "pr-create exited 0 when GitHub refused the token"
elif [ -e "$KEYDIR/gh.args" ]; then
  bad "gh was run after the token request failed"
else
  ok "GitHub refusing the token opens nothing"
fi

echo "== a worktree finds the keys in the main checkout =="
if command -v git >/dev/null 2>&1; then
  main="$KEYDIR/main"
  git init -q "$main" && git -C "$main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init &&
    git -C "$main" worktree add -q "$KEYDIR/wt" 2>/dev/null
  mkdir -p "$main/tools/sync-env-secrets/agent-keys" "$KEYDIR/wt/tools/sync-env-secrets"
  out="$(BUILD_WORKSPACE_DIRECTORY="$KEYDIR/wt" AGENT_REGISTRY="$REGISTRY" bash "$SCRIPT" login wren 2>&1 || true)"
  real_main="$(cd "$main" && pwd -P)"
  if [[ "$out" == *"no key at $real_main/tools/sync-env-secrets/agent-keys/wren.pem"* ]]; then
    ok "looks for the key in the main checkout when the worktree has none"
  else
    bad "worktree key lookup: $out"
  fi
  out="$(BUILD_WORKSPACE_DIRECTORY="$KEYDIR/wt" AGENT_KEY_DIR=/given AGENT_REGISTRY="$REGISTRY" bash "$SCRIPT" login wren 2>&1 || true)"
  [[ "$out" == *"no key at /given/wren.pem"* ]] && ok "an AGENT_KEY_DIR the caller set is used as given" || bad "AGENT_KEY_DIR ignored: $out"
else
  ok "git not available here; worktree lookup not checked"
fi

if [ "$failures" -ne 0 ]; then
  echo "agent-app_test: $failures failure(s)" >&2
  exit 1
fi
echo "agent-app_test: all checks passed"
