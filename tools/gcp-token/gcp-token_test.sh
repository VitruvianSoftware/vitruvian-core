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

# Hermetic guard for gcp-token.sh. Drives the REAL script against a fake gcloud
# and a fake ssh that record argv, so the assertions are about what the tool
# does. The properties pinned are the ones whose failure would be a CREDENTIAL
# LEAK, a WRONG IDENTITY, or a silent non-credential exported as one:
#
#   1. local credentials are preferred and the network is never touched;
#   2. the tailnet broker is used ONLY as a fallback;
#   3. the remote command carries the REQUESTED account — a broker cannot be
#      asked for one identity and hand back another by omission;
#   4. stdout is the bare token and nothing else, so `$(...)` capture is clean;
#   5. the token never appears on stderr;
#   6. an account containing shell metacharacters is refused before it can reach
#      the remote command line;
#   7. a short/garbage broker reply is refused rather than exported as a
#      credential that 401s later;
#   8. a broker failure is fatal AND actionable (names the fix).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/gcp-token.sh"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() {
	printf '  ✗ %s\n' "$1" >&2
	fails=$((fails + 1))
}
assert_contains() {
	case "$2" in
	*"$3"*) pass "$1" ;;
	*) fail "$1 — did not find: $3" ;;
	esac
}
assert_not_contains() {
	case "$2" in
	*"$3"*) fail "$1 — unexpectedly found: $3" ;;
	*) pass "$1" ;;
	esac
}

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

LOCAL_TOKEN="ya29.local-$(printf 'L%.0s' $(seq 1 60))"
BROKER_TOKEN="ya29.broker-$(printf 'B%.0s' $(seq 1 60))"
ACCOUNT="james@vitruviansoftware.dev"

# fake gcloud: `have` = local credentials work, `none` = it has none.
make_gcloud() {
	cat >"$work/gcloud" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/gcloud.argv"
[ "$1" = have ] && { echo "$LOCAL_TOKEN"; exit 0; }
echo "ERROR: (gcloud.auth.print-access-token) no credentials" >&2
exit 1
FAKE
	chmod +x "$work/gcloud"
}

# fake ssh: `ok` = returns a token, `down` = unreachable, `junk` = short reply.
make_ssh() {
	cat >"$work/ssh" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/ssh.argv"
case "$1" in
  ok)   echo "$BROKER_TOKEN"; exit 0 ;;
  junk) echo "not-a-token"; exit 0 ;;
  *)    echo "ssh: connect to host: Network is unreachable" >&2; exit 255 ;;
esac
FAKE
	chmod +x "$work/ssh"
}

# Host-aware fake ssh, for failover: each node fails in a DIFFERENT real way and
# only `good` mints. The failure strings are copied verbatim from what the real
# homelab nodes returned, so the classifier is tested against reality.
make_ssh_fleet() {
	cat >"$work/ssh" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/ssh.argv"
target=""
for a in "\$@"; do case "\$a" in james@*) target="\${a#james@}" ;; esac; done
case "\$target" in
  nogcloud) echo "gcloud: command not found" >&2; exit 127 ;;
  nologin)  echo "ERROR: (gcloud.auth.print-access-token) Your current active account [x] does not have any valid credentials" >&2; exit 1 ;;
  reauth)   echo "ERROR: (gcloud.auth.print-access-token) There was a problem refreshing your current auth tokens: Reauthentication failed. cannot prompt during non-interactive execution." >&2; exit 1 ;;
  down)     echo "ssh: connect to host: Connection timed out" >&2; exit 255 ;;
  good)     echo "$BROKER_TOKEN"; exit 0 ;;
  *)        echo "ssh: unknown host" >&2; exit 255 ;;
esac
FAKE
	chmod +x "$work/ssh"
}

run() { # run <account> [extra env…]  → stdout; stderr captured to a file
	local acct="$1"
	shift
	: >"$work/gcloud.argv"
	: >"$work/ssh.argv"
	# Neutralise every variable the script reads BEFORE "$@", so a caller can still
	# override any of them and the ambient environment can override none.
	#
	# This suite calls itself hermetic; it was not. A cloud session with
	# VITRUVIAN_ESC_ENV set on the environment -- which is the documented way to
	# turn ESC on -- leaked it into the cases that assert ESC is NOT used, and the
	# leak cascaded: once ESC answered, every broker-failure case got a token and
	# "the mint fails" assertions passed a token instead. Six failures, one cause,
	# none of them reproducible on a laptop without that variable set.
	env GCLOUD_BIN="$work/gcloud" SSH_BIN="$work/ssh" VITRUVIAN_GCP_BROKER=testbroker \
		PULUMI_BIN="$work/pulumi" VITRUVIAN_GCP_BROKER_CACHE="$work/broker-cache" \
		VITRUVIAN_ESC_ENV= VITRUVIAN_ESC_PATH= VITRUVIAN_GCP_BROKERS= \
		CLOUDSDK_AUTH_ACCESS_TOKEN= GOOGLE_OAUTH_ACCESS_TOKEN= \
		"$@" bash "$SCRIPT" "$acct" 2>"$work/stderr"
}

# ---------------------------------------------------------------------------
echo "gcp-token: local credentials win"
# ---------------------------------------------------------------------------
make_gcloud have
make_ssh ok
out="$(run "$ACCOUNT")"
[ "$out" = "$LOCAL_TOKEN" ] && pass "the local token is returned verbatim" ||
	fail "expected the local token, got ${#out} bytes"
[ ! -s "$work/ssh.argv" ] && pass "…and the tailnet is never touched" ||
	fail "ssh was invoked despite working local credentials"
assert_contains "the local call is account-pinned" "$(cat "$work/gcloud.argv")" "--account=$ACCOUNT"
[ ! -s "$work/stderr" ] && pass "nothing is written to stderr on success" ||
	fail "stderr was not empty: $(cat "$work/stderr")"

# ---------------------------------------------------------------------------
echo "gcp-token: tailnet fallback"
# ---------------------------------------------------------------------------
make_gcloud none
make_ssh ok
out="$(run "$ACCOUNT")"
[ "$out" = "$BROKER_TOKEN" ] && pass "the broker token is returned when local has none" ||
	fail "expected the broker token, got ${#out} bytes"

ssh_argv="$(cat "$work/ssh.argv")"
assert_contains "the broker is asked for the REQUESTED account" "$ssh_argv" "--account=$ACCOUNT"
assert_contains "…as the configured broker user@host" "$ssh_argv" "james@testbroker"
assert_contains "…non-interactively (no password/agent prompt can hang a session)" "$ssh_argv" "BatchMode=yes"

# stdout must be the bare token: a trailing newline or a banner breaks `$(...)`
# consumers like `export GOOGLE_OAUTH_ACCESS_TOKEN=$(...)`.
[ "$out" = "$BROKER_TOKEN" ] && pass "stdout is the bare token, no banner" ||
	fail "stdout carried more than the token"
assert_not_contains "the token never reaches stderr" "$(cat "$work/stderr")" "$BROKER_TOKEN"

# ---------------------------------------------------------------------------
echo "gcp-token: placeholders are not tokens"
# ---------------------------------------------------------------------------
# The sandbox pre-sets CLOUDSDK_AUTH_ACCESS_TOKEN to a short dummy, and `gcloud
# auth print-access-token` returns it VERBATIM. Honoring that is the worst
# outcome available: the local probe "succeeds" with a dud, the broker is never
# consulted, and the dud gets exported as GOOGLE_OAUTH_ACCESS_TOKEN to 401 later,
# far from the cause. Found in a live session, where it printed "proxy-injected".
cat >"$work/gcloud" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/gcloud.argv"
# Mirror real gcloud: if an ambient access token is set, hand it straight back.
[ -n "\${CLOUDSDK_AUTH_ACCESS_TOKEN:-}" ] && { printf '%s' "\$CLOUDSDK_AUTH_ACCESS_TOKEN"; exit 0; }
echo "ERROR: no credentials" >&2
exit 1
FAKE
chmod +x "$work/gcloud"
make_ssh ok

out="$(run "$ACCOUNT" CLOUDSDK_AUTH_ACCESS_TOKEN=proxy-injected)"
assert_not_contains "a placeholder ambient token is never returned" "$out" "proxy-injected"
[ "$out" = "$BROKER_TOKEN" ] && pass "…and the broker is consulted instead" ||
	fail "the placeholder suppressed the broker fallback"

# A REAL ambient token must still short-circuit — this is the documented
# break-glass path, not something to override.
real="ya29.$(printf 'R%.0s' $(seq 1 80))"
out="$(run "$ACCOUNT" "CLOUDSDK_AUTH_ACCESS_TOKEN=$real")"
[ "$out" = "$real" ] && pass "a real ambient token still wins locally" ||
	fail "a valid ambient token was discarded"
[ ! -s "$work/ssh.argv" ] && pass "…without touching the tailnet" ||
	fail "the broker was consulted despite valid local credentials"

# ---------------------------------------------------------------------------
echo "gcp-token: broker failover"
# ---------------------------------------------------------------------------
# One node is never enough: any given box may be asleep, lack the SDK, or not be
# logged into the account asked for — which is exactly what the real homelab
# returned when this was first tried. Walk the list until one mints.
make_gcloud none
make_ssh_fleet
rm -f "$work/broker-cache"
out="$(run "$ACCOUNT" VITRUVIAN_GCP_BROKERS=nogcloud,nologin,reauth,good)"
[ "$out" = "$BROKER_TOKEN" ] && pass "walks past every broken node and mints from the good one" ||
	fail "failover did not reach the working broker"

ssh_argv="$(cat "$work/ssh.argv")"
for h in nogcloud nologin reauth good; do
	assert_contains "…$h was tried" "$ssh_argv" "james@$h"
done

# Each failure mode wants a DIFFERENT fix, so collapsing them into "unreachable"
# would send someone to the wrong place. REAUTH especially: no node-side change
# fixes it.
rm -f "$work/broker-cache"
out="$(run "$ACCOUNT" VITRUVIAN_GCP_BROKERS=nogcloud,nologin,reauth,down)" || true
err="$(cat "$work/stderr")"
assert_contains "a node without the SDK is named as such" "$err" "no gcloud installed"
assert_contains "a node not logged in is named as such" "$err" "not logged in"
assert_contains "a lapsed-login node is called out specifically" "$err" "REAUTH LAPSED"
assert_contains "an unreachable node is named as such" "$err" "unreachable over the tailnet"
assert_contains "…said to be the NODE's session, not the account" "$err" "another node may still mint"
assert_contains "…with the Workspace setting offered to make it recur less" "$err" "session control"

# The winning broker is remembered, so the common path stops paying for the walk.
rm -f "$work/broker-cache"
out="$(run "$ACCOUNT" VITRUVIAN_GCP_BROKERS=nogcloud,good)"
[ "$(tr -d '[:space:]' <"$work/broker-cache" 2>/dev/null)" = "good" ] &&
	pass "the winning broker is cached" || fail "no broker was cached after a successful mint"

out="$(run "$ACCOUNT" VITRUVIAN_GCP_BROKERS=nogcloud,good)"
first="$(head -1 "$work/ssh.argv" | tr ' ' '\n' | grep '^james@' | head -1)"
[ "$first" = "james@good" ] && pass "…and tried FIRST on the next call" ||
	fail "the cached broker was not tried first (got ${first:-none})"

# A cached host that is no longer in the list must not resurrect it.
printf 'ghost\n' >"$work/broker-cache"
out="$(run "$ACCOUNT" VITRUVIAN_GCP_BROKERS=nogcloud,good)"
assert_not_contains "a stale cached broker outside the list is ignored" "$(cat "$work/ssh.argv")" "james@ghost"
[ "$out" = "$BROKER_TOKEN" ] && pass "…and the list still mints" || fail "a stale cache broke the mint"

# The remote command must not assume gcloud is on the non-interactive PATH.
# Measured on james-mbp16: gcloud lives at /opt/homebrew/bin/gcloud while a
# non-interactive ssh sees only nix paths + the system dirs, so the node was
# reported "no gcloud installed" while an interactive login found it at once.
rm -f "$work/broker-cache"
out="$(run "$ACCOUNT" VITRUVIAN_GCP_BROKERS=good)"
remote="$(cat "$work/ssh.argv")"
assert_contains "the remote lookup falls back to a LOGIN shell" "$remote" "-lc"
assert_contains "…and to known install locations" "$remote" "/opt/homebrew/bin/gcloud"
assert_contains "…including a self-installed SDK under \$HOME" "$remote" "google-cloud-sdk/bin/gcloud"

# ---------------------------------------------------------------------------
echo "gcp-token: Pulumi ESC source"
# ---------------------------------------------------------------------------
# ESC is keyless AND has no homelab dependency, so it goes ahead of the broker --
# but it must stay BEHIND local credentials (a logged-in laptop should not phone
# a cloud service), and it must FALL THROUGH rather than fail, which is what
# makes "ESC primary, homelab backup" real instead of aspirational.
ESC_TOKEN="ya29.esc-$(printf 'E%.0s' $(seq 1 60))"
make_pulumi() { # make_pulumi <ok|broken>
	cat >"$work/pulumi" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/pulumi.argv"
[ "$1" = ok ] && { echo "$ESC_TOKEN"; exit 0; }
echo "error: could not open environment" >&2
exit 1
FAKE
	chmod +x "$work/pulumi"
}

make_gcloud none
make_ssh ok
make_pulumi ok
: >"$work/pulumi.argv"
out="$(run "$ACCOUNT" VITRUVIAN_ESC_ENV=proj/env)"
[ "$out" = "$ESC_TOKEN" ] && pass "ESC mints when configured" || fail "ESC did not provide the token"
[ ! -s "$work/ssh.argv" ] && pass "…and the tailnet is not touched" ||
	fail "the broker ran despite ESC succeeding"
assert_contains "…asked for the configured environment" "$(cat "$work/pulumi.argv")" "proj/env"
assert_contains "…as a bare string, so no JSON parsing is needed" "$(cat "$work/pulumi.argv")" "--value string"

# Local credentials still win over ESC.
make_gcloud have
: >"$work/pulumi.argv"
out="$(run "$ACCOUNT" VITRUVIAN_ESC_ENV=proj/env)"
[ "$out" = "$LOCAL_TOKEN" ] && pass "local credentials still beat ESC" ||
	fail "ESC overrode working local credentials"
[ ! -s "$work/pulumi.argv" ] && pass "…without invoking pulumi at all" ||
	fail "pulumi ran despite working local credentials"

# A broken ESC must degrade to the broker, not fail the whole mint.
make_gcloud none
make_pulumi broken
out="$(run "$ACCOUNT" VITRUVIAN_ESC_ENV=proj/env)"
[ "$out" = "$BROKER_TOKEN" ] && pass "a broken ESC falls through to the broker" ||
	fail "a broken ESC was fatal instead of falling back"
assert_contains "…and says why" "$(cat "$work/stderr")" "falling back to the tailnet broker"

# Unconfigured ESC is simply skipped.
make_pulumi ok
: >"$work/pulumi.argv"
out="$(run "$ACCOUNT")"
[ ! -s "$work/pulumi.argv" ] && pass "ESC is skipped when VITRUVIAN_ESC_ENV is unset" ||
	fail "pulumi ran without ESC being configured"

# ---------------------------------------------------------------------------
echo "gcp-token: refusals"
# ---------------------------------------------------------------------------
make_gcloud none
make_ssh ok
out="$(run 'james@x.dev; touch '"$work/pwned")" || true
assert_contains "a metacharacter account is refused" "$(cat "$work/stderr")" "invalid account"
[ ! -e "$work/pwned" ] && pass "…and nothing from it is executed" ||
	fail "an account value was executed as shell"
[ ! -s "$work/ssh.argv" ] && pass "…and it never reaches the remote command line" ||
	fail "the bad account was passed to ssh"

out="$(run 'not-an-email')" || true
assert_contains "a non-email account is refused" "$(cat "$work/stderr")" "invalid account"

# REGRESSION: the validator's character class must ACCEPT ordinary addresses.
# It once did not. The class ended `%+-@`, a collation RANGE from '+' to '@'
# rather than three literals; under the C locale that range contains '@' so
# Linux CI passed, while macOS's UTF-8 collation orders punctuation differently
# and '@' fell outside it -- rejecting every real address on a Mac with
# "invalid account 'james@vitruviansoftware.dev'". Green tests are the reason it
# shipped, so these assert the ACCEPT side, which nothing did before.
make_gcloud ok
for good in \
	'james@vitruviansoftware.dev' \
	'james.nguyen@gmail.com' \
	'sa-claude-cloud@prj-c-bu2-infra-pipeline-3d09.iam.gserviceaccount.com' \
	'user+tag@example.co.uk'; do
	out="$(run "$good" 2>/dev/null)" || true
	assert_not_contains "a valid address is accepted: $good" "$(cat "$work/stderr")" "invalid account"
done

# The same bug in its general form. Scoped to NEGATED classes ([!…]/[^…]), which
# is where this script does its validation -- a broad sweep matches `${1:-}` and
# every `[ -n … ]` test and is pure noise. A '-' between two non-alphanumerics is
# a punctuation range; a trailing '-' is the literal, which is what we want.
if LC_ALL=C grep -nE '\[[!^][^]]*[^]a-zA-Z0-9-]-[^]a-zA-Z0-9]' "$SCRIPT" >"$work/badranges" 2>/dev/null &&
	[ -s "$work/badranges" ]; then
	fail "a collation-dependent punctuation range remains: $(cat "$work/badranges")"
else
	pass "no negated class relies on a punctuation range"
fi

# The diagnostic must name the offending byte -- an address that looks perfect
# in a terminal but carries a stray tab is the case that wastes an afternoon.
out="$(run "$(printf 'james@x.dev\t')")" || true
assert_contains "an invisible bad byte is named, not just quoted" \
	"$(cat "$work/stderr")" "disallowed character"

make_ssh junk
out="$(run "$ACCOUNT")"
rc=$?
[ "$rc" -ne 0 ] && pass "a too-short broker reply is fatal" ||
	fail "a garbage reply was accepted (rc=$rc)"
assert_not_contains "…and is not printed as a credential" "$out" "not-a-token"

make_ssh down
out="$(run "$ACCOUNT")"
rc=$?
[ "$rc" -ne 0 ] && pass "an unreachable broker is fatal" || fail "unreachable broker exited 0"
err="$(cat "$work/stderr")"
assert_contains "…and the error is actionable" "$err" "gcloud auth login"
assert_contains "…naming the tailnet as a thing to check" "$err" "tailscale status"
assert_contains "…and how to point at another broker" "$err" "VITRUVIAN_GCP_BROKER"

echo
if [ "$fails" -eq 0 ]; then
	echo "gcp-token: all checks passed"
	exit 0
fi
echo "gcp-token: $fails check(s) failed" >&2
exit 1
