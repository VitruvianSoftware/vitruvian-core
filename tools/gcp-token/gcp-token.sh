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

# The homelab node that holds the credentials. Needs the Google Cloud SDK
# installed and `gcloud auth login <account>` run ONCE; the resulting refresh
# token then lives only there. Prefer an always-on node over a laptop, or GCP
# work fails whenever the laptop sleeps. Override per invocation for a different
# broker (or to test against one).
BROKER_HOST="${VITRUVIAN_GCP_BROKER:-fedora}"
BROKER_USER="${VITRUVIAN_GCP_BROKER_USER:-james}"

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
	die "no local credentials for $ACCOUNT and ssh is not installed to reach $BROKER_HOST"

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
trap 'rm -f "$_err"' EXIT

# `--account` is passed to the REMOTE gcloud so the broker cannot hand back a
# different identity than the one asked for. The token comes back on stdout and
# is never echoed here.
_tok="$(timeout 45 "$SSH_BIN" "${ssh_opts[@]}" "${BROKER_USER}@${BROKER_HOST}" \
	"gcloud auth print-access-token --account=${ACCOUNT}" 2>"$_err" | tr -d '\r\n')"

if [ -z "$_tok" ]; then
	echo "gcp-token: could not mint a token for $ACCOUNT via ${BROKER_USER}@${BROKER_HOST}" >&2
	sed 's/^/  /' "$_err" >&2
	echo "  Checklist:" >&2
	echo "    · is the tailnet up?            tailscale status" >&2
	echo "    · does the broker have gcloud?  ssh ${BROKER_USER}@${BROKER_HOST} 'gcloud version'" >&2
	echo "    · is it logged in?              ssh ${BROKER_USER}@${BROKER_HOST} 'gcloud auth list'" >&2
	echo "    · if not:                       gcloud auth login ${ACCOUNT}   (once, on the broker)" >&2
	echo "    · different broker?             VITRUVIAN_GCP_BROKER=<host>" >&2
	exit 1
fi

if ! is_token "$_tok"; then
	die "the broker returned something too short to be an access token (${#_tok} chars)"
fi

printf '%s' "$_tok"
