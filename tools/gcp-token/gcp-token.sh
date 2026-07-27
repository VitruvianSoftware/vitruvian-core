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

# Homelab nodes that may hold credentials, tried IN ORDER until one mints. A list
# rather than a single host, because which node can mint changes constantly: one
# may be asleep, one may lack the SDK, one may not be logged into the account,
# and a Workspace login LAPSES per node on Google Cloud session control. Measured
# on the real fleet, james-macbook-pro had lapsed while james-mbp16 minted the
# same account fine -- so walking the list is what makes this reliable rather
# than a nice-to-have. Always-on nodes first so the fast path does not depend on
# a laptop lid, laptops after because today they are the ones actually logged in.
#
# Each node needs the Google Cloud SDK and `gcloud auth login <account>` run
# ONCE; the resulting refresh token then lives only there.
BROKER_HOSTS="${VITRUVIAN_GCP_BROKERS:-${VITRUVIAN_GCP_BROKER:-fedora,nuc9i5,nuc9i9,james-mbp16,james-macbook-pro,james-mbp,james-mbp32}}"
BROKER_USER="${VITRUVIAN_GCP_BROKER_USER:-james}"

# The node that last worked, tried FIRST next time. Without this every mint pays
# the full walk down the list (a failed SSH per node that lacks gcloud or the
# account), which is pure latency on the common path.
BROKER_CACHE="${VITRUVIAN_GCP_BROKER_CACHE:-$HOME/.config/vitruvian-core/cloud/gcp-broker}"

# Test seams; real runs get the defaults.
SSH_BIN="${SSH_BIN:-ssh}"
PULUMI_BIN="${PULUMI_BIN:-pulumi}"
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
#
# LC_ALL=C is load-bearing, not tidiness. A bracket RANGE is resolved in the
# CURRENT COLLATION, and macOS's UTF-8 collation does not order punctuation the
# way ASCII does. The first spelling of this class ended `%+-@`, which is a range
# from '+' to '@' -- on glibc under the C locale that range happens to contain
# '@', so every hermetic test and every CI run passed, while on a Mac it did not,
# and the validator rejected literally every real address:
#
#	gcp-token: invalid account 'james@vitruviansoftware.dev' (expected an email address)
#
# Two rules keep that from recurring: ranges cover only letters and digits (whose
# ASCII ordering every practical collation preserves), and every punctuation
# character is spelled as a literal member, with '-' LAST so it cannot re-form a
# range with whatever precedes it.
# The membership test itself runs in `tr`, in a CHILD PROCESS with LC_ALL=C in
# its environment, rather than as a bash pattern. The first fix for the range bug
# was a bash `case` under `local LC_ALL=C`, which assumes bash applies a function
# -local locale assignment to pattern matching -- true in bash 5, not something to
# bet on in the bash 3.2 that ships as /bin/bash on macOS, which is the exact
# platform this bug appeared on. `LC_ALL=C tr` has no such ambiguity: the child
# gets the C locale or the command fails outright.
#
# The leftover characters ARE the diagnostic, so the check and the error message
# cannot drift apart -- whatever `tr` did not delete is what is disallowed.
disallowed_chars() { # disallowed_chars <account> → the characters that are not allowed
	printf '%s' "$1" | LC_ALL=C tr -d 'a-zA-Z0-9._%@+-'
}

bad="$(disallowed_chars "$ACCOUNT")"
if [ -n "$bad" ]; then
	# Name the offending byte rather than just echoing the string. An address that
	# looks perfect in a terminal but carries a stray tab, CR or non-breaking space
	# is exactly the case where "invalid account '<looks fine>'" wastes an afternoon.
	die "invalid account '$ACCOUNT' (expected an email address)" \
		"(disallowed character(s): $(printf '%s' "$bad" | od -An -c | tr -s ' ' | sed 's/^ //;s/ $//'))"
fi
# A local part, an '@', and a dotted domain. Cheap, and all that is needed: the
# character check above already did the security-relevant work. Plain globs, no
# bracket expressions, so there is no collation involved at all.
case "$ACCOUNT" in
*?@?*.?*) ;;
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

# --- 1.5 Pulumi ESC, when configured ------------------------------------------
# Keyless and with no homelab dependency: Pulumi Cloud presents an OIDC token,
# GCP exchanges it for a short-lived access token, and nothing local need be
# awake. Requires the trust relationship built by
# //infrastructure/pulumi/foundation/gcp-bootstrap (build_pulumi_esc.go) plus an
# ESC environment using fn::open::gcp-login.
#
# Tried BEFORE the tailnet broker and AFTER local credentials: a laptop that is
# already logged in should still not touch the network, but when this machine has
# nothing, a cloud service beats a machine in someone's house.
#
# Best-effort by design -- if ESC is unreachable, misconfigured, or simply not set
# up yet, fall through to the broker rather than failing. That is what makes
# "ESC primary, homelab backup" true rather than aspirational.
if [ -n "${VITRUVIAN_ESC_ENV:-}" ] && command -v "$PULUMI_BIN" >/dev/null 2>&1; then
	_esc_err="$(mktemp)"
	# `env OPEN`, not `env get`. The distinction is the whole ballgame here and it
	# fails silently the wrong way round: `env get` reads the environment's stored
	# DEFINITION, and gcp.login.accessToken does not appear there -- it is produced
	# by `fn::open::gcp-login` performing the OIDC exchange when the environment is
	# opened. So `env get` exits 0 and prints an empty string, which looked exactly
	# like "ESC is not configured" and sent every call to the tailnet broker while
	# a working federation sat unused.
	#
	# `--format string` yields the bare token: no jq, no JSON parsing, nothing to
	# get wrong quoting back out.
	if _tok="$("$PULUMI_BIN" env open "$VITRUVIAN_ESC_ENV" "${VITRUVIAN_ESC_PATH:-gcp.login.accessToken}" \
		--format string 2>"$_esc_err" | tr -d '\r\n')" && is_token "$_tok"; then
		rm -f "$_esc_err"
		# SAY WHOSE TOKEN THIS IS. Every other path here honours the requested
		# account -- local gcloud passes --account, the broker passes --account --
		# but ESC cannot: an ESC environment is wired to exactly one service
		# account, and it hands back that identity no matter who was asked for.
		#
		# Callers rely on the answer matching the request. //tools/pulumi resolves
		# an account from infrastructure/gcp-identities.tsv, announces "pinned to
		# <account>", and then runs as whatever this returns. While the ESC identity
		# could do nothing, the mismatch announced itself as a permission error.
		# Once it can run foundation stacks, the run SUCCEEDS as the wrong principal
		# and Cloud Audit Logs record an actor the wrapper never named.
		#
		# One line on stderr is the cheap fix: stdout stays exactly the token, and
		# the substitution is visible instead of silent.
		echo "gcp-token: token minted by Pulumi ESC ($VITRUVIAN_ESC_ENV) — the identity is that" >&2
		echo "  environment's service account, NOT the requested '$ACCOUNT'." >&2
		printf '%s' "$_tok"
		exit 0
	fi
	echo "gcp-token: Pulumi ESC ($VITRUVIAN_ESC_ENV) did not yield a token; falling back to the tailnet broker" >&2
	sed 's/^/  /' "$_esc_err" >&2
	rm -f "$_esc_err"
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

# remote_cmd — the command run ON the broker.
#
# It does NOT just say `gcloud`: a non-interactive ssh session gets a bare PATH
# and does not source the user's shell profile, so a perfectly good broker looks
# like it has no SDK. Measured on james-mbp16, whose gcloud lives at
# /opt/homebrew/bin/gcloud while non-interactive ssh sees only nix paths,
# /usr/local/bin and the system dirs — the node was reported "no gcloud
# installed" while an interactive login found it immediately.
#
# So resolve in three widening steps: PATH (fast, and what Linux nodes hit),
# then the user's LOGIN shell (picks up whatever they actually configured —
# Homebrew, nix, asdf), then the known install locations. The literal
# "command not found" is preserved for the classifier when all three miss.
remote_cmd() {
	cat <<REMOTE
G="\$(command -v gcloud 2>/dev/null)"
[ -n "\$G" ] || G="\$("\${SHELL:-/bin/sh}" -lc 'command -v gcloud' 2>/dev/null)"
if [ -z "\$G" ]; then
  for p in "\$HOME/google-cloud-sdk/bin/gcloud" /opt/homebrew/bin/gcloud \
           /opt/homebrew/share/google-cloud-sdk/bin/gcloud /usr/local/bin/gcloud \
           /usr/local/share/google-cloud-sdk/bin/gcloud /snap/bin/gcloud; do
    [ -x "\$p" ] && G="\$p" && break
  done
fi
[ -n "\$G" ] || { echo "gcloud: command not found" >&2; exit 127; }
exec "\$G" auth print-access-token --account=${ACCOUNT}
REMOTE
}

# try_broker <host> — echo the token on success, or record why it failed.
#
# `--account` goes to the REMOTE gcloud so a broker cannot be asked for one
# identity and hand back another. The token is never echoed here.
try_broker() {
	local host="$1" tok
	: >"$_err"
	tok="$(timeout 45 "$SSH_BIN" "${ssh_opts[@]}" "${BROKER_USER}@${host}" \
		"$(remote_cmd)" 2>"$_err" | tr -d '\r\n')"
	if is_token "$tok"; then
		printf '%s' "$tok"
		return 0
	fi
	# Classify the failure. These want completely different fixes, so collapsing
	# them into "broker unreachable" would send someone to the wrong place —
	# REAUTH in particular is not fixed on the node at all.
	local why
	if grep -qi 'Reauthentication failed\|reauth' "$_err" 2>/dev/null; then
		why="REAUTH LAPSED — this node's login for the account has expired (another node may still mint)"
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
	echo "    · REAUTH LAPSED    → that NODE's session expired, not the account. Any node with" >&2
	echo "                         a fresh login still mints, which is why brokers are a list —" >&2
	echo "                         every one above was already tried. Re-login there with" >&2
	echo "                         'gcloud auth login $ACCOUNT', or widen Admin console →" >&2
	echo "                         Security → Google Cloud session control to make it recur less." >&2
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
