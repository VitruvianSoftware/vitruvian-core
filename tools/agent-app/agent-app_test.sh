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
# AGENT_APP_BIN runs every behaviour check against another build of the tool
# (the Rust port, :agent-app-rs_test). The checks that read the script's
# source (the label names below) still read the script; the JWT is then taken
# from the token request the binary actually makes.
BIN="${AGENT_APP_BIN:-}"
if [ -n "$BIN" ]; then
  case "$BIN" in /*) ;; *) BIN="$PWD/$BIN" ;; esac
  RUN=("$BIN")
else
  RUN=(bash "$SCRIPT")
fi

failures=0
ok() { echo "  ok: $1"; }
bad() {
  echo "  FAIL: $1" >&2
  failures=$((failures + 1))
}

# A real jq, so the script's own --jq filters run against responses saved from
# GitHub (testdata/). Under Bazel it is the hermetic one (JQ_BIN, an exec path:
# external/<repo>/... is ../<repo>/... from the runfiles root); the remote-exec
# image has none of its own. Run by hand, the one on PATH.
if [ -n "${JQ_BIN:-}" ]; then
  case "$JQ_BIN" in external/*) JQ_BIN="../${JQ_BIN#external/}" ;; esac
  REAL_JQ="$(cd "$(dirname "$JQ_BIN")" && pwd)/$(basename "$JQ_BIN")"
else
  REAL_JQ="$(command -v jq || true)"
fi
if [ ! -x "$REAL_JQ" ]; then
  echo "agent-app_test: no jq (JQ_BIN or PATH); the filter checks cannot run" >&2
  exit 1
fi
FIXTURES="$(cd "$(dirname "$SCRIPT")/testdata" && pwd)"

# A throwaway key, generated per run: no fixture key is ever committed.
KEYDIR="$(mktemp -d)"
trap 'rm -rf "$KEYDIR"' EXIT
openssl genrsa -out "$KEYDIR/key.pem" 2048 2>/dev/null

echo "== refuses incomplete arguments rather than calling GitHub =="
for args in "convert" "convert onlycode" "installations" "installations 1" "token 1 key" "repos 1 key"; do
  # shellcheck disable=SC2086
  if out="$(GITHUB_API_URL=http://127.0.0.1:1 "${RUN[@]}" $args 2>&1)"; then
    bad "'$args' exited 0; expected a usage error"
  elif [[ "$out" != *usage* ]]; then
    bad "'$args' failed without a usage message: $out"
  else
    ok "'$args' rejected with usage"
  fi
done

echo "== never overwrites an existing key =="
touch "$KEYDIR/existing.pem"
if out="$("${RUN[@]}" convert somecode "$KEYDIR/existing.pem" 2>&1)"; then
  bad "convert overwrote an existing key file"
elif [[ "$out" != *"refusing to overwrite"* ]]; then
  bad "convert failed for the wrong reason: $out"
else
  ok "convert refuses to clobber an existing key"
fi

echo "== unknown subcommand is an error, not a no-op =="
if "${RUN[@]}" nonsense >/dev/null 2>&1; then
  bad "unknown subcommand exited 0"
else
  ok "unknown subcommand rejected"
fi

echo "== JWT is well-formed, base64url, and verifies against the key =="
# app_jwt is sourced rather than invoked so the test exercises the real function.
# shellcheck disable=SC1090
# Extract the two functions to a file and source them, so the test exercises the
# REAL implementations rather than a copy that can drift from them.
if [ -z "$BIN" ]; then
  sed -n '/^b64url()/,/^}/p;/^app_jwt()/,/^}/p' "$SCRIPT" > "$KEYDIR/funcs.sh"
  # shellcheck disable=SC1091
  source "$KEYDIR/funcs.sh"
  JWT="$(app_jwt 12345 "$KEYDIR/key.pem")"
else
  # A binary has no functions to source: take the JWT from the Authorization
  # header its token request hands curl (on a file descriptor, never argv).
  mkdir -p "$KEYDIR/jwtstub"
  cat >"$KEYDIR/jwtstub/curl" <<STUBEOF
#!/usr/bin/env bash
prev=""
for a in "\$@"; do
  if [ "\$prev" = -H ]; then case "\$a" in @*) cat "\${a#@}" >"$KEYDIR/jwt.header" ;; esac; fi
  prev="\$a"
done
printf '{"token":"t"}'
STUBEOF
  chmod +x "$KEYDIR/jwtstub/curl"
  PATH="$KEYDIR/jwtstub:$PATH" "${RUN[@]}" token 12345 "$KEYDIR/key.pem" 1 >/dev/null 2>&1
  JWT="$(sed -n 's/^Authorization: Bearer //p' "$KEYDIR/jwt.header" 2>/dev/null)"
fi

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
if out="$(AGENT_REGISTRY="$REGISTRY" "${RUN[@]}" login nosuchagent 2>&1)"; then
  bad "login accepted an unknown agent"
elif [[ "$out" != *"unknown agent"* ]]; then
  bad "login failed for the wrong reason: $out"
else
  ok "login rejects an unknown agent and lists the known ones"
fi

echo "== login refuses when the key is absent, naming the fix =="
if out="$(AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR=/nonexistent "${RUN[@]}" login beacon 2>&1)"; then
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
out="$(AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR=/nonexistent "${RUN[@]}" env beacon 2>&1 || true)"
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
ln -s "$REAL_JQ" "$STUB/jq"
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
    "${RUN[@]}" pr-create "$@" >"$KEYDIR/prc.out" 2>&1
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
if PATH="$STUB:$PATH" AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR=/nonexistent "${RUN[@]}" pr-create --title t >"$KEYDIR/prc.out" 2>&1; then
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

echo "== pr-edit, pr-comment, pr-ready, pr-close, pr-enqueue and the run commands act as the agent =="
# This fake gh logs EVERY call as one line, arguments joined by |, and answers
# the reads the way GitHub does: it takes a response saved from GitHub (in
# testdata/, see its README) and runs it through the script's OWN --jq filter
# with a real jq. So a typo in a filter fails here, not on the first real PR.
# Which saved response each read gets: FAKE_HOLD for the hold-state query,
# FAKE_ENQ for pr-enqueue's read-back, each a ;-separated list consumed one
# per read, the last one repeating.
export FAKE_LOG="$KEYDIR" FAKE_SECRET="$SECRET" FAKE_FIXTURES="$FIXTURES" FAKE_JQ="$REAL_JQ"
cat >"$STUB/curl" <<'STUBEOF'
#!/usr/bin/env bash
{ set +x; } 2>/dev/null
for a in "$@"; do case "$a" in http*) echo "$a" >>"$FAKE_LOG/curl.log" ;; esac; done
printf '{"token":"%s"}' "$FAKE_SECRET"
STUBEOF
cat >"$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
{ set +x; } 2>/dev/null
(IFS='|'; printf '%s\n' "$*") >>"$FAKE_LOG/gh.calls"
if [ "${GH_TOKEN:-}" = "$FAKE_SECRET" ] && [ -z "${GITHUB_TOKEN:-}" ]; then echo ok; else echo wrong; fi >>"$FAKE_LOG/gh.tokens"
filter="" prev=""
for a in "$@"; do [ "$prev" = --jq ] && filter="$a"; prev="$a"; done
answer() { # kind list -> the saved response for this read, through the real filter
  local n file
  n=$(($(cat "$FAKE_LOG/$1.count" 2>/dev/null || echo 0) + 1))
  echo "$n" >"$FAKE_LOG/$1.count"
  file="$(tr ';' '\n' <<<"$2" | sed -n "${n}p")"
  [ -n "$file" ] || file="$(tr ';' '\n' <<<"$2" | tail -1)"
  "$FAKE_JQ" -r "$filter" "$FAKE_FIXTURES/$file.json"
}
case "$1 $2" in
  "pr view") "$FAKE_JQ" -r "$filter" "$FAKE_FIXTURES/pr-view-id.json" ;;
  "api graphql")
    case "$*" in
      *dequeuePullRequest*) exit "${FAKE_DEQUEUE_EXIT:-0}" ;;
      *"labels(first"*) answer hold "${FAKE_HOLD:-hold-open}" ;;
      *mergeMethod*) answer enq "${FAKE_ENQ:-enqueue-armed}" ;;
      *) echo "fake gh: unexpected query" >&2; exit 1 ;;
    esac ;;
  "pr merge") exit "${FAKE_MERGE_EXIT:-0}" ;;
  "pr edit") exit "${FAKE_EDIT_EXIT:-0}" ;;
  "pr comment") exit "${FAKE_COMMENT_EXIT:-0}" ;;
  *) echo done ;;
esac
STUBEOF
chmod +x "$STUB/curl" "$STUB/gh"
PR_ID="$("$REAL_JQ" -r .id "$FIXTURES/pr-view-id.json")"
run_cmd() { # command args... -> output in $KEYDIR/cmd.out, gh calls in gh.calls
  rm -f "$KEYDIR/gh.calls" "$KEYDIR/gh.tokens" "$KEYDIR/curl.log" "$KEYDIR/hold.count" "$KEYDIR/enq.count"
  # OUTSIDE_TEST=1 runs the script as if not under bazel test; XTRACE=1 runs
  # it with tracing switched on from the environment.
  env ${OUTSIDE_TEST:+-u TEST_SRCDIR -u TEST_TMPDIR} ${XTRACE:+SHELLOPTS=xtrace} \
    PATH="$STUB:$PATH" AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR="${KEYS:-$KEYDIR/keys}" GITHUB_TOKEN=ambient \
    AGENT_APP_VERIFY_TRIES=2 AGENT_APP_VERIFY_SLEEP=0 "${RUN[@]}" "$@" >"$KEYDIR/cmd.out" 2>&1 </dev/null
}
called() { grep -qx -- "$1" "$KEYDIR/gh.calls" 2>/dev/null; }
call_line() { grep -nx -- "$1" "$KEYDIR/gh.calls" | head -1 | cut -d: -f1; }
no_gh() { [ ! -s "$KEYDIR/gh.calls" ]; }
no_token() { [ ! -s "$KEYDIR/curl.log" ]; }
leaked() { grep -q "$SECRET" "$KEYDIR/cmd.out" "$KEYDIR/gh.calls" 2>/dev/null; }
writes() { grep -cE '^pr\|(merge|edit|comment)\||dequeuePullRequest' "$KEYDIR/gh.calls" 2>/dev/null || true; }
calls() { tr '\n' ' ' <"$KEYDIR/gh.calls" 2>/dev/null; }

# command line | the gh call it must make
while IFS='	' read -r line want; do
  # shellcheck disable=SC2086
  eval "run_cmd $line"
  if ! called "$want"; then
    bad "$line: no gh call '$want'; got: $(calls); out: $(cat "$KEYDIR/cmd.out")"
  elif grep -qv '^ok$' "$KEYDIR/gh.tokens"; then
    bad "$line: gh ran without the agent token, or with an ambient GITHUB_TOKEN"
  elif ! grep -q "/app/installations/$(inst_of wren)/access_tokens" "$KEYDIR/curl.log" 2>/dev/null; then
    bad "$line: did not mint wren's token"
  elif leaked; then
    bad "$line: the token was printed or passed as an argument"
  else
    ok "$line: passed through as the wren app; token never printed"
  fi
done <<'CASES'
pr-edit 12 --title "two words" --add-label x --body-file pr.md	pr|edit|12|--title|two words|--add-label|x|--body-file|pr.md
pr-comment 12 --body-file note.md	pr|comment|12|--body-file|note.md
pr-comment 12 --body "looks good"	pr|comment|12|--body|looks good
pr-review 12 --approve	pr|review|12|--approve
pr-review 12 --approve --body "LGTM"	pr|review|12|--approve|--body|LGTM
pr-review 12 -ab "LGTM"	pr|review|12|-ab|LGTM
pr-review 12 --comment --body-file note.md	pr|review|12|--comment|--body-file|note.md
pr-review 12 --request-changes -b "needs a test"	pr|review|12|--request-changes|-b|needs a test
pr-review 12 --body "--approve" --comment	pr|review|12|--body|--approve|--comment
pr-ready 12	pr|ready|12
pr-close 12 --comment "superseded by #13" --delete-branch	pr|close|12|--comment|superseded by #13|--delete-branch
pr-enqueue 12	pr|merge|12|--auto|--squash
pr-enqueue 12 --squash --auto --match-head-commit abc	pr|merge|12|--squash|--auto|--match-head-commit|abc
pr-enqueue 12 -sd	pr|merge|12|-sd|--auto
pr-enqueue 12 --subject -m	pr|merge|12|--subject|-m|--auto|--squash
pr-enqueue 12 -t -r	pr|merge|12|-t|-r|--auto|--squash
run-rerun 18000000001 --failed	run|rerun|18000000001|--failed
run-cancel 18000000001	run|cancel|18000000001
workflow-run catalog-bump.yaml -f tool=github --ref main	workflow|run|catalog-bump.yaml|-f|tool=github|--ref|main
workflow-run catalog-bump.yaml --ref=main -Fn=1	workflow|run|catalog-bump.yaml|--ref=main|-Fn=1
issue-create --title "two words" --body-file issue.md --label ci	issue|create|--title|two words|--body-file|issue.md|--label|ci
issue-create -t t -b "a body"	issue|create|-t|t|-b|a body
issue-comment 7 --body-file note.md	issue|comment|7|--body-file|note.md
issue-close 7 --reason "not planned" --comment "superseded"	issue|close|7|--reason|not planned|--comment|superseded
CASES

run_cmd pr-edit --agent beacon --title t
no_gh && ok "pr-edit without a PR number is a usage error, not an edit of the current branch's PR" ||
  bad "pr-edit with no PR number ran gh: $(calls)"
run_cmd pr-ready --agent beacon 12
grep -q "/app/installations/$(inst_of beacon)/access_tokens" "$KEYDIR/curl.log" 2>/dev/null && called "pr|ready|12" &&
  ok "--agent picks the app and is not passed to gh" || bad "--agent beacon: gh got $(calls)"
run_cmd pr-comment 12
no_gh && grep -q "body" "$KEYDIR/cmd.out" &&
  ok "pr-comment without a body is refused (gh would wait for an editor)" || bad "pr-comment without a body: $(calls)"

echo "== pr-review and the issue commands refuse what would prompt, hang or reach another repo =="
# command line | what the refusal must say
while IFS='	' read -r line want; do
  # shellcheck disable=SC2086
  if eval "run_cmd $line"; then
    bad "$line: exited 0"
  elif ! no_gh || ! no_token; then
    bad "$line: ran gh or minted a token: $(calls)"
  elif ! grep -q -- "$want" "$KEYDIR/cmd.out"; then
    bad "$line: refused without saying '$want': $(cat "$KEYDIR/cmd.out")"
  else
    ok "$line: refused before any token is minted"
  fi
done <<'REFUSED'
pr-review --approve	missing <pr>
pr-review 12	pass one of --approve, --comment or --request-changes
pr-review 12 --approve --request-changes -b x	pass one of --approve, --comment or --request-changes
pr-review 12 -ac -b x	pass one of --approve, --comment or --request-changes
pr-review 12 --comment	give the body
pr-review 12 --request-changes	give the body
pr-review 12 -r	give the body
pr-review 12 --approve --body	usage: pr-review
pr-review 12 --approve --web	opens a browser
pr-review 12 -aw	opens a browser
issue-create --body-file issue.md	give the title
issue-create --title t	give the body
issue-create --title t --body b --repo other/repo	issues in this repository only
issue-create --title t --body b -Rother/repo	issues in this repository only
issue-create --title t --body b --web	opens a browser
issue-comment 7	give the body
issue-comment --body b	missing <issue>
issue-comment 7 --body b --repo other/repo	issues in this repository only
issue-close	missing <issue>
issue-close 7 -R other/repo	issues in this repository only
REFUSED

echo "== pr-enqueue confirms on GitHub through the real filters, and says which =="
run_cmd pr-enqueue 12
called "pr|view|12|--json|id|--jq|.id" && grep -q "^api|graphql|-f|id=$PR_ID|" "$KEYDIR/gh.calls" &&
  ok "looks the PR up by the node id the real '.id' filter reads from a saved gh pr view" ||
  bad "node id lookup: $(calls)"
FAKE_ENQ=enqueue-armed run_cmd pr-enqueue 12
grep -q "auto-merge armed by vitruvian-wren-agent (autoMergeRequest: SQUASH)" "$KEYDIR/cmd.out" &&
  ok "armed: the read-back filter names autoMergeRequest, who armed it and the method" || bad "armed: $(cat "$KEYDIR/cmd.out")"
FAKE_ENQ=enqueue-queued run_cmd pr-enqueue 12
grep -q "mergeQueueEntry: position 1, AWAITING_CHECKS" "$KEYDIR/cmd.out" &&
  ok "queued (response saved from #3425): names mergeQueueEntry, position and state" || bad "queued: $(cat "$KEYDIR/cmd.out")"
if FAKE_ENQ=enqueue-open run_cmd pr-enqueue 12; then
  bad "exited 0 although GitHub showed neither auto-merge nor a queue entry"
elif grep -q "NOT queued" "$KEYDIR/cmd.out" && [ "$(grep -c '^api|graphql' "$KEYDIR/gh.calls")" = 3 ]; then
  ok "neither set: reads again, then fails saying it is NOT queued"
else
  bad "none: $(cat "$KEYDIR/cmd.out") ; $(calls)"
fi
FAKE_HOLD=hold-merged run_cmd pr-enqueue 12
grep -q "already merged" "$KEYDIR/cmd.out" && ! grep -q '^pr|merge' "$KEYDIR/gh.calls" &&
  ok "merged (response saved from #3427): says so and arms nothing" || bad "merged: $(cat "$KEYDIR/cmd.out")"
if FAKE_MERGE_EXIT=1 run_cmd pr-enqueue 12; then
  bad "exited 0 when gh pr merge failed"
elif grep -q "NOT armed" "$KEYDIR/cmd.out"; then
  ok "gh pr merge failing is reported as NOT armed"
else
  bad "merge failure: $(cat "$KEYDIR/cmd.out")"
fi

echo "== pr-enqueue never arms over a hold =="
for held in hold-held hold-armed-labelled hold-queued-labelled; do
  if FAKE_HOLD=$held run_cmd pr-enqueue 12; then
    bad "$held: pr-enqueue exited 0 on a PR carrying do-not-automerge"
  elif grep -q '^pr|merge' "$KEYDIR/gh.calls"; then
    bad "$held: armed auto-merge over the hold"
  elif grep -q "pr-unhold 12" "$KEYDIR/cmd.out"; then
    ok "$held: refused, nothing armed, points to pr-unhold"
  else
    bad "$held: $(cat "$KEYDIR/cmd.out")"
  fi
done

# A release gate's own hold: the gate re-arms the PR itself when it clears.
while IFS='	' read -r label gate; do
  if FAKE_HOLD="hold-gate-$label" run_cmd pr-enqueue 12; then
    bad "$label: pr-enqueue exited 0 on a PR $gate is holding"
  elif grep -q '^pr|merge' "$KEYDIR/gh.calls"; then
    bad "$label: armed auto-merge over $gate's hold"
  elif grep -q "held by $gate ($label" "$KEYDIR/cmd.out" && grep -q "re-arms the PR itself" "$KEYDIR/cmd.out"; then
    ok "$label: refused, nothing armed, says $gate re-arms it itself"
  else
    bad "$label: $(cat "$KEYDIR/cmd.out")"
  fi
done <<'GATES'
dev-deploy-red	release-hold
beta-not-built	release-beta-gate
GATES
FAKE_HOLD=hold-open run_cmd pr-enqueue 12
called "pr|merge|12|--auto|--squash" && ok "no hold label of any kind: arms as usual" || bad "unheld PR not armed: $(calls)"

echo "== pr-enqueue never merges past the queue =="
for given in "--admin" "--admin=true" "--squash --admin" "--rebase" "-m" "-sm" "-dr" "-ms" "--disable-auto"; do
  # shellcheck disable=SC2086
  if run_cmd pr-enqueue 12 $given; then
    bad "pr-enqueue 12 $given exited 0"
  elif ! no_gh || ! no_token; then
    bad "pr-enqueue 12 $given still minted a token or ran gh: $(calls)"
  else
    ok "'$given' refused before any token is minted"
  fi
done
run_cmd pr-enqueue 12 --admin
grep -q "break-glass" "$KEYDIR/cmd.out" && ok "--admin refusal says why" || bad "--admin refusal: $(cat "$KEYDIR/cmd.out")"

echo "== workflow-run starts only allowlisted workflows, from main, here =="
for wf in tabula-deploy.yaml catalog-bump "catalog-bump.yaml.bak" ../catalog-bump.yaml; do
  if run_cmd workflow-run "$wf"; then
    bad "workflow-run '$wf' exited 0"
  elif ! no_gh || ! no_token; then
    bad "workflow-run '$wf' ran gh or minted a token"
  elif grep -q "not in workflow-allowlist.txt" "$KEYDIR/cmd.out"; then
    ok "'$wf' refused: not on the allowlist"
  else
    bad "'$wf' refused for the wrong reason: $(cat "$KEYDIR/cmd.out")"
  fi
done
grep -qx "catalog-bump.yaml" "$(dirname "$SCRIPT")/workflow-allowlist.txt" &&
  ok "catalog-bump.yaml is on the allowlist" || bad "catalog-bump.yaml missing from the allowlist"
for given in "--ref feature" "--ref=dev" "-r feature" "-rfeature" "--ref refs/heads/main" "-R o/r" "-Ro/r" "--repo o/r" "--repo=o/r" "--json"; do
  # shellcheck disable=SC2086
  if run_cmd workflow-run catalog-bump.yaml $given; then
    bad "workflow-run catalog-bump.yaml $given exited 0"
  elif ! no_gh || ! no_token; then
    bad "workflow-run catalog-bump.yaml $given ran gh or minted a token"
  else
    ok "workflow-run catalog-bump.yaml $given: refused, nothing run"
  fi
done

echo "== the allowlist and permissions overrides count only under bazel test =="
EVIL="$KEYDIR/evil"
mkdir -p "$EVIL"
echo "tabula-deploy.yaml" >"$EVIL/allow.txt"
printf 'beacon\tactions\twrite\n' >"$EVIL/perms.tsv"
if OUTSIDE_TEST=1 WORKFLOW_ALLOWLIST="$EVIL/allow.txt" run_cmd workflow-run tabula-deploy.yaml; then
  bad "outside bazel test, WORKFLOW_ALLOWLIST let tabula-deploy.yaml start"
elif no_gh && grep -q "not in workflow-allowlist.txt" "$KEYDIR/cmd.out"; then
  ok "outside bazel test, WORKFLOW_ALLOWLIST is ignored: the committed list applies"
else
  bad "WORKFLOW_ALLOWLIST outside test: $(cat "$KEYDIR/cmd.out")"
fi
if OUTSIDE_TEST=1 AGENT_PERMISSIONS="$EVIL/perms.tsv" run_cmd run-cancel --agent beacon 1; then
  bad "outside bazel test, AGENT_PERMISSIONS gave beacon Actions write"
elif no_gh && grep -q "no Actions write" "$KEYDIR/cmd.out"; then
  ok "outside bazel test, AGENT_PERMISSIONS is ignored: the committed file applies"
else
  bad "AGENT_PERMISSIONS outside test: $(cat "$KEYDIR/cmd.out")"
fi
# The other half, so the two above prove something: the override does work
# where it is meant to.
TEST_TMPDIR="$KEYDIR" WORKFLOW_ALLOWLIST="$EVIL/allow.txt" run_cmd workflow-run tabula-deploy.yaml
called "workflow|run|tabula-deploy.yaml" && ok "under bazel test the override is honoured (so the checks above are real)" ||
  bad "override under test: $(cat "$KEYDIR/cmd.out")"

echo "== run commands refuse an agent without Actions write =="
for line in "run-rerun --agent beacon 1" "run-cancel --agent scout 1" "workflow-run --agent forge catalog-bump.yaml"; do
  # shellcheck disable=SC2086
  if run_cmd $line; then
    bad "$line exited 0"
  elif ! no_gh || ! no_token; then
    bad "$line ran gh or minted a token"
  elif grep -q "no Actions write" "$KEYDIR/cmd.out" && grep -q "wren" "$KEYDIR/cmd.out"; then
    ok "$line: refused, naming wren as the agent that can"
  else
    bad "$line: $(cat "$KEYDIR/cmd.out")"
  fi
done
run_cmd run-rerun not-a-number
no_gh && grep -q usage "$KEYDIR/cmd.out" && ok "run-rerun needs a numeric run id" || bad "run-rerun not-a-number: $(cat "$KEYDIR/cmd.out")"

echo "== pr-hold: label first, then auto-merge off, then out of the queue, then checked =="
# FAKE_HOLD is the PR as GitHub shows it: before, after steps 1-2, at the end.
if FAKE_HOLD="hold-armed;hold-held;hold-held" run_cmd pr-hold 12 --reason "waiting on #120" &&
  called "pr|merge|12|--disable-auto" && called "pr|edit|12|--add-label|do-not-automerge" &&
  grep -q '^pr|comment|12|--body|Held by the wren agent: waiting on #120' "$KEYDIR/gh.calls" &&
  ! grep -q dequeuePullRequest "$KEYDIR/gh.calls" && grep -q "is held" "$KEYDIR/cmd.out"; then
  ok "armed PR: do-not-automerge on, auto-merge off, reason posted, confirmed"
else
  bad "armed PR: $(calls) ; out: $(cat "$KEYDIR/cmd.out")"
fi
! grep -qv '^ok$' "$KEYDIR/gh.tokens" && ! leaked &&
  ok "pr-hold runs every call as the agent; the token is never printed" || bad "pr-hold: token missing or leaked"
[ "$(call_line "pr|edit|12|--add-label|do-not-automerge")" -lt "$(call_line "pr|merge|12|--disable-auto")" ] &&
  ok "labels BEFORE turning auto-merge off: no window for a gate to re-arm it" || bad "auto-merge turned off before the label went on"

FAKE_HOLD="hold-queued;hold-queued-labelled;hold-held" run_cmd pr-hold 12
tr '\n' ' ' <"$KEYDIR/gh.calls" | grep -q "id=$PR_ID|-f|query= *mutation(\$id: ID!) { dequeuePullRequest" && ! called "pr|merge|12|--disable-auto" &&
  ok "in the queue (response saved from #3425): takes it out by node id" || bad "queued: $(calls)"

FAKE_HOLD="hold-held" run_cmd pr-hold 12
[ "$(writes)" = 0 ] && grep -q "is held" "$KEYDIR/cmd.out" &&
  ok "already held: changes nothing and says it is held" || bad "already held: $(calls)"

if FAKE_HOLD="hold-armed;hold-armed-labelled;hold-armed-labelled" run_cmd pr-hold 12 --reason r; then
  bad "exited 0 although GitHub still shows auto-merge armed"
elif grep -q "NOT held" "$KEYDIR/cmd.out" && ! grep -q '^pr|comment' "$KEYDIR/gh.calls"; then
  ok "read-back still armed: fails saying NOT held, and posts no reason"
else
  bad "still armed: $(cat "$KEYDIR/cmd.out")"
fi
if FAKE_MERGE_EXIT=1 FAKE_HOLD="hold-armed;hold-queued-labelled" run_cmd pr-hold 12 --reason r; then
  bad "exited 0 when turning auto-merge off failed"
elif grep -q dequeuePullRequest "$KEYDIR/gh.calls" && grep -q "NOT held" "$KEYDIR/cmd.out" &&
  ! grep -q '^pr|comment' "$KEYDIR/gh.calls"; then
  ok "turning auto-merge off fails and the PR has entered the queue: still takes it out, says NOT held"
else
  bad "disable failure + queued: $(calls) ; $(cat "$KEYDIR/cmd.out")"
fi
if FAKE_MERGE_EXIT=1 FAKE_HOLD="hold-armed;hold-armed-labelled" run_cmd pr-hold 12; then
  bad "exited 0 when turning auto-merge off failed"
elif grep -q "can still merge" "$KEYDIR/cmd.out" && ! grep -q dequeuePullRequest "$KEYDIR/gh.calls"; then
  ok "turning auto-merge off fails, not queued: says NOT held, it can still merge"
else
  bad "disable failure: $(cat "$KEYDIR/cmd.out")"
fi
if FAKE_EDIT_EXIT=1 FAKE_HOLD="hold-armed" run_cmd pr-hold 12; then
  bad "exited 0 when the label could not be added"
elif ! grep -q '^pr|merge' "$KEYDIR/gh.calls" && grep -q "NOT held" "$KEYDIR/cmd.out"; then
  ok "label cannot be added: stops there, says NOT held"
else
  bad "label failure: $(calls) ; $(cat "$KEYDIR/cmd.out")"
fi
if FAKE_HOLD="hold-merged" run_cmd pr-hold 12; then
  bad "held a merged PR"
elif [ "$(writes)" = 0 ]; then
  ok "a merged PR (response saved from #3427): refused, nothing changed"
else
  bad "merged PR: $(calls)"
fi
for given in "--admin" "--label x" "--reason"; do
  # shellcheck disable=SC2086
  if run_cmd pr-hold 12 $given; then
    bad "pr-hold 12 $given exited 0"
  elif ! no_gh || ! no_token; then
    bad "pr-hold 12 $given ran gh or minted a token"
  else
    ok "pr-hold 12 $given: usage error, nothing run"
  fi
done

echo "== pr-unhold removes the label and does not re-arm =="
if FAKE_HOLD="hold-open" run_cmd pr-unhold 12 &&
  called "pr|edit|12|--remove-label|do-not-automerge" && ! grep -q '^pr|merge' "$KEYDIR/gh.calls" &&
  grep -q "pr-enqueue 12" "$KEYDIR/cmd.out"; then
  ok "label removed, auto-merge left off, and it says to run pr-enqueue"
else
  bad "unhold: $(calls) ; out: $(cat "$KEYDIR/cmd.out")"
fi
if FAKE_HOLD="hold-held" run_cmd pr-unhold 12; then
  bad "unhold exited 0 although the label is still on"
elif grep -q "NOT released" "$KEYDIR/cmd.out"; then
  ok "read-back still labelled: fails saying NOT released"
else
  bad "unhold still labelled: $(cat "$KEYDIR/cmd.out")"
fi
run_cmd pr-unhold 12 --reason r
no_gh && grep -q usage "$KEYDIR/cmd.out" && ok "pr-unhold takes no --reason" || bad "unhold --reason: $(cat "$KEYDIR/cmd.out")"

echo "== xtrace cannot print the token =="
if env SHELLOPTS=xtrace bash -c 'true' 2>&1 | grep -q '^+ true'; then
  for line in "pr-edit 12 --title t" "pr-enqueue 12" "pr-hold 12" "workflow-run catalog-bump.yaml"; do
    # shellcheck disable=SC2086
    XTRACE=1 run_cmd $line
    if leaked; then
      bad "$line under SHELLOPTS=xtrace printed the token"
    elif no_gh; then
      bad "$line under SHELLOPTS=xtrace did not run: $(cat "$KEYDIR/cmd.out")"
    else
      ok "$line under SHELLOPTS=xtrace: ran, token not printed"
    fi
  done
else
  bad "SHELLOPTS=xtrace does not turn tracing on here, so this check would prove nothing"
fi

echo "== every new command fails closed with no token =="
for line in "pr-edit 12 --title t" "pr-comment 12 --body b" "pr-review 12 --approve" "pr-ready 12" "pr-close 12" "pr-enqueue 12" \
  "pr-hold 12 --reason r" "pr-unhold 12" "run-rerun 1" "run-cancel 1" "workflow-run catalog-bump.yaml"; do
  # shellcheck disable=SC2086
  if KEYS=/nonexistent run_cmd $line; then
    bad "$line exited 0 without a key"
  elif ! no_gh; then
    bad "$line ran gh anyway, as whoever it is logged in as"
  elif grep -q "NOT" "$KEYDIR/cmd.out" && grep -q "agent-keys-pull" "$KEYDIR/cmd.out"; then
    ok "$line: no key, nothing run, says so and names the fix"
  else
    bad "$line: unclear failure: $(cat "$KEYDIR/cmd.out")"
  fi
done
printf '#!/usr/bin/env bash\nexit 22\n' >"$STUB/curl"
if run_cmd pr-enqueue 12; then
  bad "pr-enqueue exited 0 when GitHub refused the token"
elif ! no_gh; then
  bad "pr-enqueue ran gh after the token request failed"
else
  ok "GitHub refusing the token: pr-enqueue runs nothing"
fi

echo "== the hold label is the one the release gates honour =="
# release-hold.sh and release-beta-gate.sh call it PERSON_LABEL: the hold they
# never remove and never re-arm over. If the names drift apart, a gate going
# green would quietly re-arm a PR an agent is holding.
hold_label="$(sed -n 's/^HOLD_LABEL="\([^"]*\)"$/\1/p' "$SCRIPT")"
for gate in tools/ci/release-hold.sh tools/ci/release-beta-gate.sh; do
  person="$(sed -n 's/^PERSON_LABEL="\([^"]*\)".*/\1/p' "$gate" 2>/dev/null)"
  if [ -n "$hold_label" ] && [ "$hold_label" = "$person" ]; then
    ok "$hold_label matches $gate's PERSON_LABEL"
  else
    bad "pr-hold uses '$hold_label' but $gate's PERSON_LABEL is '${person:-unreadable}'"
  fi
done

# pr-enqueue's copies of each gate's OWN hold label. If a gate renames its
# label and this does not follow, an agent could arm a PR that gate holds.
while IFS='	' read -r var gate; do
  ours="$(sed -n "s/^${var}=\"\([^\"]*\)\"\$/\1/p" "$SCRIPT")"
  theirs="$(sed -n 's/^HOLD_LABEL="\([^"]*\)".*/\1/p' "$gate" 2>/dev/null)"
  if [ -n "$ours" ] && [ "$ours" = "$theirs" ]; then
    ok "$var ($ours) matches $gate's HOLD_LABEL"
  else
    bad "pr-enqueue's $var is '${ours:-missing}' but $gate's HOLD_LABEL is '${theirs:-unreadable}'"
  fi
done <<'DRIFT'
RELEASE_HOLD_LABEL	tools/ci/release-hold.sh
BETA_GATE_LABEL	tools/ci/release-beta-gate.sh
DRIFT

echo "== branch-delete deletes only what the gate passes, as the agent =="
# Its own fake gh (first on PATH) and a fake gate. The gate's SHA comes from a
# scratch repo's refs/remotes/origin/<branch>, as the real gate leaves it.
BD="$KEYDIR/bd"
mkdir -p "$BD"
export FAKE_BD="$BD"
# A working token mint of its own: the shared one was left failing above.
cat >"$BD/curl" <<'STUBEOF'
#!/usr/bin/env bash
{ set +x; } 2>/dev/null
for a in "$@"; do case "$a" in http*) echo "$a" >>"$FAKE_LOG/curl.log" ;; esac; done
printf '{"token":"%s"}' "$FAKE_SECRET"
STUBEOF
cat >"$BD/gh" <<'STUBEOF'
#!/usr/bin/env bash
{ set +x; } 2>/dev/null
(IFS='|'; printf '%s\n' "$*") >>"$FAKE_BD/gh.calls"
if [ "${GH_TOKEN:-}" = "$FAKE_SECRET" ] && [ -z "${GITHUB_TOKEN:-}" ]; then echo ok; else echo wrong; fi >>"$FAKE_BD/gh.tokens"
case "$*" in
  "pr list"*) printf '%s' "${FAKE_OPEN:-}" ;;
  "pr view"*) echo "${FAKE_STATE:-MERGED}" ;;
  "api -X DELETE"*) exit "${FAKE_DELETE_EXIT:-0}" ;;
  "api repos/{owner}/{repo}/git/ref/heads/"*) echo "${FAKE_SHA_NOW:-}" ;;
  *) echo "fake gh: unexpected: $*" >&2; exit 1 ;;
esac
STUBEOF
cat >"$BD/landed.sh" <<'STUBEOF'
#!/usr/bin/env bash
echo "$*" >>"$FAKE_BD/gate.calls"
echo "gate says: ${FAKE_GATE_SAYS:-landed}"
exit "${FAKE_GATE_EXIT:-0}"
STUBEOF
chmod +x "$BD/curl" "$BD/gh" "$BD/landed.sh"
BDREPO="$KEYDIR/bdrepo"
git init -q "$BDREPO" && git -C "$BDREPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m tip
TIP="$(git -C "$BDREPO" rev-parse HEAD)"
git -C "$BDREPO" update-ref refs/remotes/origin/old/done "$TIP"
git -C "$BDREPO" update-ref refs/remotes/origin/other/done "$TIP"
bd() { # args... -> output in $BD/out; gh calls in gh.calls, gate calls in gate.calls
  rm -f "$BD/gh.calls" "$BD/gh.tokens" "$BD/gate.calls" "$KEYDIR/curl.log"
  env ${OUTSIDE_TEST:+-u TEST_SRCDIR -u TEST_TMPDIR} \
    PATH="$BD:$STUB:$PATH" AGENT_REGISTRY="$REGISTRY" AGENT_KEY_DIR="$KEYDIR/keys" GITHUB_TOKEN=ambient \
    AGENT_APP_LANDED="$BD/landed.sh" BUILD_WORKING_DIRECTORY="$BDREPO" FAKE_SHA_NOW="${FAKE_SHA_NOW-$TIP}" \
    "${RUN[@]}" branch-delete "$@" >"$BD/out" 2>&1 </dev/null
}
deleted() { grep -qx "api|-X|DELETE|repos/{owner}/{repo}/git/refs/heads/$1" "$BD/gh.calls" 2>/dev/null; }
no_delete() { ! grep -q '^api|-X|DELETE' "$BD/gh.calls" 2>/dev/null; }
gated() { grep -qx -- "--remote-branch $1" "$BD/gate.calls" 2>/dev/null; }
bdout() { tr '\n' ' ' <"$BD/out"; }

if ! bd old/done; then
  bad "a landed branch: exited non-zero: $(bdout)"
elif gated old/done && deleted old/done && grep -q "deleted old/done (${TIP:0:8})" "$BD/out" &&
  ! grep -qv '^ok$' "$BD/gh.tokens" && grep -q "/app/installations/$(inst_of wren)/access_tokens" "$KEYDIR/curl.log"; then
  ok "a branch the gate passes is deleted, as the wren app, and says which SHA"
else
  bad "a landed branch: gate $(cat "$BD/gate.calls" 2>/dev/null); gh $(tr '\n' ' ' <"$BD/gh.calls"); out $(bdout)"
fi
grep -q "$SECRET" "$BD/out" "$BD/gh.calls" && bad "branch-delete printed the token or put it in argv" ||
  ok "the token is never printed and never in argv"

if FAKE_GATE_EXIT=1 FAKE_GATE_SAYS="NOT landed: 2 commits" bd old/done; then
  bad "exited 0 although the gate failed"
elif no_delete && grep -q "kept old/done: not landed" "$BD/out" && grep -q "NOT landed: 2 commits" "$BD/out"; then
  ok "a branch the gate fails is kept, with the gate's reason, and nothing is deleted"
else
  bad "gate failed: $(bdout); gh $(tr '\n' ' ' <"$BD/gh.calls" 2>/dev/null)"
fi

if FAKE_OPEN=12 bd old/done; then
  bad "exited 0 for a branch with an open PR"
elif no_delete && [ ! -s "$BD/gate.calls" ] && grep -q "pr-close 12 --delete-branch" "$BD/out"; then
  ok "a branch with an open PR is kept, and points to pr-close --delete-branch"
else
  bad "open PR: $(bdout)"
fi

for name in main refs/heads/x "a..b" "x y"; do
  if bd "$name"; then
    bad "'$name': exited 0"
  elif no_delete && [ ! -s "$BD/gate.calls" ] && grep -q "kept $name" "$BD/out"; then
    ok "'$name' is refused before anything is asked or deleted"
  else
    bad "'$name': $(bdout)"
  fi
done

if FAKE_SHA_NOW=0000000000000000000000000000000000000000 bd old/done; then
  bad "exited 0 although the branch moved after the check"
elif no_delete && grep -q "moved since it was checked" "$BD/out"; then
  ok "a branch that moved since the gate checked it is kept"
else
  bad "moved: $(bdout)"
fi

# A failed read prints gh's error body, the same both times: that must not
# read as "unchanged" and let a delete through.
for junk in '{"message":"Not Found","status":"404"}' "" "not-a-sha"; do
  if FAKE_SHA_NOW="$junk" bd "gh-readonly-queue/main/pr-1264-ed8e62380b5893f43aa4f6696991e116f1366e42"; then
    bad "queue branch, ref read gave '$junk': exited 0"
  elif no_delete && grep -q "could not read its SHA" "$BD/out"; then
    ok "queue branch: a ref read that gives '${junk:-nothing}' keeps it, and nothing is deleted"
  else
    bad "queue branch, ref read gave '$junk': $(bdout); gh $(tr '\n' ' ' <"$BD/gh.calls" 2>/dev/null)"
  fi
done
if FAKE_SHA_NOW='{"message":"Not Found"}' bd old/done; then
  bad "landed branch, ref read failed: exited 0"
elif no_delete && grep -q "could not read its SHA" "$BD/out"; then
  ok "landed branch: a ref read that fails keeps it, and nothing is deleted"
else
  bad "landed branch, ref read failed: $(bdout)"
fi

if FAKE_DELETE_EXIT=1 bd old/done; then
  bad "exited 0 although GitHub refused the delete"
elif grep -q "GitHub refused the delete" "$BD/out"; then
  ok "GitHub refusing the delete is reported, not hidden"
else
  bad "refused delete: $(bdout)"
fi

queue="gh-readonly-queue/main/pr-1264-ed8e62380b5893f43aa4f6696991e116f1366e42"
if FAKE_STATE=MERGED bd "$queue" && deleted "$queue" && [ ! -s "$BD/gate.calls" ]; then
  ok "a merge-queue branch of a merged PR is deleted without the gate"
else
  bad "queue branch, merged PR: $(bdout)"
fi
if FAKE_STATE=OPEN bd "$queue"; then
  bad "exited 0 for the queue branch of an open PR"
elif no_delete && grep -q "merge-queue branch of PR #1264, which is OPEN" "$BD/out"; then
  ok "a merge-queue branch of an open PR is kept"
else
  bad "queue branch, open PR: $(bdout)"
fi

if bd old/done main other/done; then
  bad "exited 0 although one branch was kept"
elif deleted old/done && deleted other/done && grep -q "1 branch(es) kept" "$BD/out"; then
  ok "the others are still deleted when one is kept, and it fails naming how many"
else
  bad "mixed: $(bdout)"
fi

if OUTSIDE_TEST=1 bd old/done; then
  bad "outside bazel test, a gate named in AGENT_APP_LANDED was used to delete"
elif no_delete && [ ! -s "$BD/gate.calls" ] && grep -q "kept old/done: not landed" "$BD/out"; then
  ok "outside bazel test, AGENT_APP_LANDED is ignored and the real gate keeps the branch"
else
  bad "outside test: gate $(cat "$BD/gate.calls" 2>/dev/null); $(bdout)"
fi

echo "== a worktree finds the keys in the main checkout =="
if command -v git >/dev/null 2>&1; then
  main="$KEYDIR/main"
  git init -q "$main" && git -C "$main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init &&
    git -C "$main" worktree add -q "$KEYDIR/wt" 2>/dev/null
  mkdir -p "$main/tools/sync-env-secrets/agent-keys" "$KEYDIR/wt/tools/sync-env-secrets"
  out="$(BUILD_WORKSPACE_DIRECTORY="$KEYDIR/wt" AGENT_REGISTRY="$REGISTRY" "${RUN[@]}" login wren 2>&1 || true)"
  real_main="$(cd "$main" && pwd -P)"
  if [[ "$out" == *"no key at $real_main/tools/sync-env-secrets/agent-keys/wren.pem"* ]]; then
    ok "looks for the key in the main checkout when the worktree has none"
  else
    bad "worktree key lookup: $out"
  fi
  out="$(BUILD_WORKSPACE_DIRECTORY="$KEYDIR/wt" AGENT_KEY_DIR=/given AGENT_REGISTRY="$REGISTRY" "${RUN[@]}" login wren 2>&1 || true)"
  [[ "$out" == *"no key at /given/wren.pem"* ]] && ok "an AGENT_KEY_DIR the caller set is used as given" || bad "AGENT_KEY_DIR ignored: $out"
else
  ok "git not available here; worktree lookup not checked"
fi

if [ "$failures" -ne 0 ]; then
  echo "agent-app_test: $failures failure(s)" >&2
  exit 1
fi
echo "agent-app_test: all checks passed"
