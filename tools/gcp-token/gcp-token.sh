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

# gcp-token — print a short-lived GCP access token for a declared account,
# minting it over the tailnet when this machine has no credentials of its own.
#
#   bazel run //tools/gcp-token -- james@vitruviansoftware.dev
#   export GOOGLE_OAUTH_ACCESS_TOKEN="$(tools/gcp-token/gcp-token.sh <account>)"
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS
# ---------------------------------------------------------------------------
# A Claude Code *cloud* session has no GCP credentials and no human at a browser
# to run `gcloud auth login`. The obvious fix — put a service-account key on the
# cloud environment — is refused by this org's own policy:
# `iam.disableServiceAccountKeyCreation` is enforced org-wide
# (infrastructure/pulumi/foundation/gcp-org/envs/shared/org_policy.go), and its
# comment says why: "prevent SA key sprawl". Working around a control we
# deliberately set is the wrong move.
#
# But a cloud session already has something better: it is ON THE TAILNET, with
# passwordless SSH to the homelab as `james` (docs/admin/claude-code-cloud-sessions.md).
# A homelab node that is already `gcloud auth login`-ed can therefore mint a
# token on demand. The properties that fall out of that:
#
#   * NO long-lived credential in the cloud environment at all — not a key, not
#     a refresh token. The session only ever holds a ~1h access token.
#   * The refresh token never leaves the homelab box.
#   * Nothing to rotate on the cloud environment, and no org-policy exception.
#   * Tailnet membership IS the authentication factor. Revoke the node from the
#     tailnet (or the agent's SSH key) and cloud sessions lose GCP instantly.
#
# MINT ON DEMAND, NEVER AT SESSION START. An access token lives about an hour
# and a Claude session outlives that comfortably, so a token fetched by the
# SessionStart hook would be stale by the time it mattered. Callers ask for one
# when they need one; //tools/pulumi does exactly that.
#
# LOCAL FIRST. On a laptop that is already logged in, this is just
# `gcloud auth print-access-token` and never touches the network — so the same
# command works everywhere and CI/laptop/cloud share one code path.
set -uo pipefail

# Homelab nodes that may hold credentials, tried IN ORDER until one mints. A
# list rather than a single host because any given node may be asleep, may not
# have the SDK, or may not be logged into the account being asked for -- and
# which node that is changes over time. Always-on nodes first, laptops last, so
# the fast path does not depend on someone's lid being open.
#
# Each node needs the Google Cloud SDK and `gcloud auth login <account>` run
# ONCE; the resulting refresh token then lives only there.
BROKER_HOSTS="${VITRUVIAN_GCP_BROKERS:-${VITRUVIAN_GCP_BROKER:-fedora,nuc9i5,nuc9i9,james-macbook-pro}}"
BROKER_USER="${VITRUVIAN_GCP_BROKER_USER:-james}"

# The node that last worked, tried FIRST next time. Without this every mint pays
# the full walk down the list (a failed SSH per node that lacks gcloud or the
# account), which is pure latency on the common path.
BROKER_CACHE="${VITRUVIAN_GCP_BROKER_CACHE:-$HOME/.config/vitruvian-core/cloud/gcp-broker}"

# Test seams; real runs get the defaults.
SSH_BIN="${SSH_BIN:-ssh}"
GCLOUD_BIN="${GCLOUD_BIN:-gcloud}"
SOCKS_PORT="${VITRUVIAN_SOCKS_PORT:-1055}"

die() {
	echo "gcp-token: $*" >&2
	exit 1
}

# is_token — long enough to be a real Google access token (they run 200+ chars).
# Applied to EVERY source, not just the remote one: the sandbox pre-sets
# CLOUDSDK_AUTH_ACCESS_TOKEN to a short placeholder and `gcloud auth
# print-access-token` faithfully echoes it back, so the local path can hand back a
# non-credential just as easily as a broken broker can. Exporting either as
# GOOGLE_OAUTH_ACCESS_TOKEN produces a confusing 401 far from the cause.
is_token() { [ -n "${1:-}" ] && [ "${#1}" -ge "${MIN_TOKEN_LEN:-40}" ]; }

ACCOUNT="${1:-}"
[ -n "$ACCOUNT" ] || die "usage: gcp-token.sh <account-email>"

# The account is interpolated into a REMOTE command line, so constrain it to
# what a Google account can actually be before it ever reaches ssh. This is the
# only caller-controlled value in that string.
case "$ACCOUNT" in
*[!a-zA-Z0-9._%+-@]* | *' '* | "")
	die "invalid account '$ACCOUNT' (expected an email address)"
	;;
esac
case "$ACCOUNT" in
*@*.*) ;;
*) die "invalid account '$ACCOUNT' (expected an email address)" ;;
esac

# --- 1. local credentials, if this machine has them --------------------------
# Silent on success: stdout is the token and nothing else, so the usual
# `$(...)` capture stays clean.
if command -v "$GCLOUD_BIN" >/dev/null 2>&1; then
	# Drop an implausible ambient token FIRST. gcloud treats
	# CLOUDSDK_AUTH_ACCESS_TOKEN as the answer and returns it verbatim, so leaving
	# the sandbox's placeholder in place would make every local probe "succeed"
	# with a dud and never reach the broker.
	if ! is_token "${CLOUDSDK_AUTH_ACCESS_TOKEN:-}"; then
		unset CLOUDSDK_AUTH_ACCESS_TOKEN
	fi
	if _tok="$("$GCLOUD_BIN" auth print-access-token --account="$ACCOUNT" 2>/dev/null)"; then
		if is_token "$_tok"; then
			printf '%s' "$_tok"
			exit 0
		fi
	fi
fi

# --- 2. mint over the tailnet -------------------------------------------------
command -v "$SSH_BIN" >/dev/null 2>&1 ||
	die "no local credentials for $ACCOUNT and ssh is not installed to reach a broker"

# Userspace networking (what tailscale-up.sh configures in a cloud sandbox) has
# no kernel route to 100.x, so ssh must dial through the SOCKS5 proxy. A machine
# with a real tailnet route needs no proxy — detect rather than assume, so this
# works unchanged on a laptop.
ssh_opts=(
	-o StrictHostKeyChecking=accept-new
	-o GSSAPIAuthentication=no
	-o PreferredAuthentications=publickey
	-o BatchMode=yes
	-o ConnectTimeout=10
)
if command -v nc >/dev/null 2>&1 && nc -z localhost "$SOCKS_PORT" >/dev/null 2>&1; then
	ssh_opts+=(-o "ProxyCommand=nc -X 5 -x localhost:${SOCKS_PORT} %h %p")
fi

_err="$(mktemp)"
_report="$(mktemp)"
trap 'rm -f "$_err" "$_report"' EXIT

# try_broker <host> — echo the token on success, or record why it failed.
#
# `--account` goes to the REMOTE gcloud so a broker cannot be asked for one
# identity and hand back another. The token is never echoed here.
try_broker() {
	local host="$1" tok
	: >"$_err"
	tok="$(timeout 45 "$SSH_BIN" "${ssh_opts[@]}" "${BROKER_USER}@${host}" \
		"gcloud auth print-access-token --account=${ACCOUNT}" 2>"$_err" | tr -d '\r\n')"
	if is_token "$tok"; then
		printf '%s' "$tok"
		return 0
	fi
	# Classify the failure. These want completely different fixes, so collapsing
	# them into "broker unreachable" would send someone to the wrong place —
	# REAUTH in particular is not fixed on the node at all.
	local why
	if grep -qi 'Reauthentication failed\|reauth' "$_err" 2>/dev/null; then
		why="REAUTH REQUIRED — this account needs an interactive re-login that ssh cannot give it"
	elif grep -qi 'command not found\|No such file' "$_err" 2>/dev/null; then
		why="no gcloud installed"
	elif grep -qi 'not have any valid credentials\|no credentialed account\|is not a valid account\|Could not find\|not a valid account' "$_err" 2>/dev/null; then
		why="gcloud present but not logged in as $ACCOUNT"
	elif grep -qi 'Connection refused\|timed out\|unreachable\|Host key\|Permission denied' "$_err" 2>/dev/null; then
		why="unreachable over the tailnet"
	elif [ -n "$tok" ]; then
		why="returned something too short to be a token (${#tok} chars)"
	else
		why="$(head -1 "$_err" 2>/dev/null || echo 'no output')"
	fi
	printf '  %-22s %s\n' "$host" "$why" >>"$_report"
	return 1
}

# Cached winner first, then the declared order (skipping the cached one).
_ordered=""
if [ -r "$BROKER_CACHE" ]; then
	_cached="$(tr -d '[:space:]' <"$BROKER_CACHE" 2>/dev/null)"
	case ",$BROKER_HOSTS," in
	*",$_cached,"*) _ordered="$_cached" ;;
	esac
fi
for _h in $(printf '%s' "$BROKER_HOSTS" | tr ',' ' '); do
	[ "$_h" = "${_cached:-}" ] && continue
	_ordered="${_ordered:+$_ordered }$_h"
done

_tok=""
for _h in $_ordered; do
	if _tok="$(try_broker "$_h")"; then
		# Remember the winner. Best-effort: a read-only HOME must not turn a
		# successful mint into a failure.
		(umask 077; mkdir -p "$(dirname "$BROKER_CACHE")" 2>/dev/null &&
			printf '%s\n' "$_h" >"$BROKER_CACHE" 2>/dev/null) || true
		break
	fi
	_tok=""
done

if [ -z "$_tok" ]; then
	echo "gcp-token: no broker could mint a token for $ACCOUNT" >&2
	cat "$_report" >&2
	echo "  Fixes, by cause:" >&2
	echo "    · REAUTH REQUIRED  → Workspace forces periodic interactive re-login for this" >&2
	echo "                         account. Either run 'gcloud auth login $ACCOUNT' on that" >&2
	echo "                         node again, or lengthen Admin console → Security → Google" >&2
	echo "                         Cloud session control. No node-side change fixes it." >&2
	echo "    · no gcloud        → install the SDK on that node" >&2
	echo "    · not logged in    → gcloud auth login $ACCOUNT   (once, on that node)" >&2
	echo "    · unreachable      → tailscale status" >&2
	echo "    · other brokers    → VITRUVIAN_GCP_BROKERS=host1,host2" >&2
	exit 1
fi

if ! is_token "$_tok"; then
	die "the broker returned something too short to be an access token (${#_tok} chars)"
fi

printf '%s' "$_tok"
