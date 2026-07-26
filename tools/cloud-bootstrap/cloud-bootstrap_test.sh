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

# Hermetic regression guard for cloud-bootstrap.sh. Drives the REAL script's
# `auth` path against a fake `gcloud` that records every invocation (argv) and
# serves secret values, so the assertions are about what the tool actually does.
# Only `auth` is exercised: the installers are network downloads, and what is
# worth pinning here is not "can it curl" but the properties whose failure is a
# PRIVILEGE ESCALATION or a SECRET LEAK:
#
#   1. an unset or unknown VITRUVIAN_PROFILE bootstraps NOTHING — there is no
#      implicit fall-back to a privileged profile;
#   2. a key whose client_email is not the profile's declared sa_account is
#      REFUSED — the wrong key never silently widens a session's identity;
#   3. the matching key IS activated, and via --key-file (a path), so the key
#      bytes are never an argv element (argv is world-readable through `ps`);
#   4. every secret read carries the pinned --account AND --project — never
#      ambient gcloud;
#   5. secret values never appear in stdout/stderr, and land only in a 0600 file
#      outside the workspace;
#   6. gcloud's exit-0-with-"ERROR:"-on-stderr is treated as FAILURE, not as an
#      empty-but-fine credential;
#   7. an env var already set on the environment WINS and is never overwritten;
#   8. a profile declaring no identity ('-') reads no secrets at all;
#   9. a placeholder CLOUDSDK_AUTH_ACCESS_TOKEN is cleared, so the pulumi wrapper
#      does not mistake it for real ambient credentials and skip its identity pin.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="${HERE}/cloud-bootstrap.sh"

fails=0
pass() { printf '  ✓ %s\n' "$1"; }
fail() {
	printf '  ✗ %s\n' "$1" >&2
	fails=$((fails + 1))
}
assert_contains() {
	case "$2" in
	*"$3"*) pass "$1" ;;
	*) fail "$1 — %s not found in output"$'\n'"$3" ;;
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

# --- fixtures ----------------------------------------------------------------

PROFILES="$work/profiles.tsv"
cat >"$PROFILES" <<'TSV'
# profile  tools   sa_account          sa_project  secrets                              purpose
pinned     gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=tok-secret,OTHER=other-secret  Pinned test profile.
nocreds    gh      -                   -           -                                    No credentials at all.
TSV

SA_KEY_GOOD='{"type":"service_account","client_email":"sa-pinned@x.iam.gserviceaccount.com","private_key":"KEYBYTES"}'
SA_KEY_WRONG='{"type":"service_account","client_email":"sa-admin@x.iam.gserviceaccount.com","private_key":"KEYBYTES"}'

SECRET_VALUE="s3cr3t-value-do-not-print-0123456789"

# Fake gcloud: records argv per call, serves secrets, and can be told to emulate
# the exit-0-but-ERROR-on-stderr failure that a real expired credential produces.
make_gcloud() { # make_gcloud <mode: ok|autherr>
	cat >"$work/gcloud" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/gcloud.argv"
mode="$1"
for a in "\$@"; do
  case "\$a" in
    "secrets") is_secret=1 ;;
  esac
done
if [ "\${is_secret:-0}" = 1 ]; then
  if [ "\$mode" = autherr ]; then
    echo "ERROR: (gcloud.secrets) Reauthentication failed" >&2
    exit 0
  fi
  echo "$SECRET_VALUE"
  exit 0
fi
exit 0
FAKE
	chmod +x "$work/gcloud"
}

# run_auth <key> [extra env assignments…] — drive the real script's auth path in
# a throwaway HOME, and echo its combined output.
run_auth() {
	local key="$1"
	shift
	rm -rf "$work/home" "$work/state"
	mkdir -p "$work/home"
	: >"$work/gcloud.argv"
	env -i \
		PATH="$PATH" \
		HOME="$work/home" \
		CLAUDE_CODE_REMOTE=true \
		CLOUD_BOOTSTRAP_PROFILES="$PROFILES" \
		CLOUD_BOOTSTRAP_STATE_DIR="$work/state" \
		CLOUD_BOOTSTRAP_BASHRC="$work/home/.bashrc" \
		GCLOUD_BIN="$work/gcloud" \
		VITRUVIAN_CLOUD_KEY="$key" \
		"$@" \
		bash "$SCRIPT" auth 2>&1
}

# ---------------------------------------------------------------------------
echo "cloud-bootstrap: profile resolution"
# ---------------------------------------------------------------------------
make_gcloud ok

out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=)"
assert_contains "unset profile bootstraps nothing" "$out" "VITRUVIAN_PROFILE is not set"
assert_contains "unset profile lists the valid names" "$out" "pinned"
[ ! -s "$work/gcloud.argv" ] && pass "unset profile makes no gcloud call" ||
	fail "unset profile still called gcloud"

out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=admin-everything)"
assert_contains "unknown profile is refused" "$out" "is not a known profile"
[ ! -s "$work/gcloud.argv" ] && pass "unknown profile makes no gcloud call" ||
	fail "unknown profile still called gcloud"

# The profile name is used to build variable names, so it is constrained at the
# door rather than trusted because "the manifest is the only source of truth".
out="$(run_auth "$SA_KEY_GOOD" 'VITRUVIAN_PROFILE=pinned;touch '"$work/pwned")"
assert_contains "a shell-metacharacter profile name is rejected" "$out" "invalid profile name"
[ ! -e "$work/pwned" ] && pass "…and nothing from it is executed" ||
	fail "a profile name was executed as shell"

# ---------------------------------------------------------------------------
echo "cloud-bootstrap: identity pinning"
# ---------------------------------------------------------------------------
out="$(run_auth "$SA_KEY_WRONG" VITRUVIAN_PROFILE=pinned)"
assert_contains "a key for another account is refused" "$out" "REFUSING to authenticate"
assert_contains "…and both identities are named" "$out" "sa-admin@x.iam.gserviceaccount.com"
assert_not_contains "…and no secret is read with it" "$(cat "$work/gcloud.argv")" "secrets versions access"
[ ! -f "$work/state/sa-key.json" ] && pass "the rejected key is not left on disk" ||
	fail "the rejected key was left at state/sa-key.json"

out="$(run_auth "base64:$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned)"
assert_contains "a malformed key is refused, not guessed at" "$out" "not a valid service-account key"

# Base64 is accepted the same as raw JSON (kube-setup.sh's CLAUDE_SSH_KEY habit).
b64="$(printf '%s' "$SA_KEY_GOOD" | base64 | tr -d '\n')"
out="$(run_auth "$b64" VITRUVIAN_PROFILE=pinned)"
assert_contains "a base64-encoded key is accepted" "$(cat "$work/gcloud.argv")" "activate-service-account"

# ---------------------------------------------------------------------------
echo "cloud-bootstrap: credential handling"
# ---------------------------------------------------------------------------
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned)"
argv="$(cat "$work/gcloud.argv")"

assert_contains "the matching key IS activated" "$argv" "activate-service-account"
assert_contains "…by path, never by value" "$argv" "--key-file=$work/state/sa-key.json"
assert_not_contains "…so the key bytes never reach argv" "$argv" "KEYBYTES"

assert_contains "secrets are read with the pinned account" "$argv" "--account=sa-pinned@x.iam.gserviceaccount.com"
assert_contains "…and the pinned project" "$argv" "--project=proj-a"
n_reads="$(grep -c 'secrets versions access' "$work/gcloud.argv")"
n_pinned="$(grep 'secrets versions access' "$work/gcloud.argv" | grep -c -- '--account=sa-pinned@x.iam.gserviceaccount.com')"
if [ "$n_reads" -gt 0 ] && [ "$n_reads" = "$n_pinned" ]; then
	pass "EVERY secret read is identity-pinned ($n_reads/$n_reads)"
else
	fail "only $n_pinned of $n_reads secret reads were identity-pinned"
fi

assert_not_contains "the secret value never reaches the output" "$out" "$SECRET_VALUE"
assert_contains "…but the operator is told where it came from" "$out" "TOK: from tok-secret"

envfile="$work/state/session.env"
if [ -f "$envfile" ] && grep -q "^export TOK=" "$envfile"; then
	pass "the value lands in the session env file"
else
	fail "the value did not reach $envfile"
fi
mode="$(stat -c '%a' "$envfile" 2>/dev/null || stat -f '%Lp' "$envfile" 2>/dev/null)"
[ "$mode" = "600" ] && pass "the session env file is 0600" || fail "session env file is mode $mode, want 600"
mode="$(stat -c '%a' "$work/state/sa-key.json" 2>/dev/null || stat -f '%Lp' "$work/state/sa-key.json" 2>/dev/null)"
[ "$mode" = "600" ] && pass "the SA key file is 0600" || fail "SA key file is mode $mode, want 600"

case "$envfile" in
"$HERE"/* | */vitruvian-core/tools/*) fail "the session env file is inside the workspace" ;;
*) pass "the session env file is outside the workspace (never git-addable)" ;;
esac

if grep -q "session.env" "$work/home/.bashrc" 2>/dev/null; then
	pass "the session env is wired into ~/.bashrc for every later shell"
else
	fail "~/.bashrc does not source the session env"
fi

# ---------------------------------------------------------------------------
echo "cloud-bootstrap: failure modes"
# ---------------------------------------------------------------------------
make_gcloud autherr
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned)"
assert_contains "gcloud's exit-0 auth failure is still a failure" "$out" "could not read tok-secret"
if [ -f "$work/state/session.env" ] && grep -q "^export TOK=''" "$work/state/session.env"; then
	fail "an empty credential was written as if it were real"
else
	pass "no empty credential is written when the read fails"
fi

make_gcloud ok
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned TOK=already-set-on-the-environment)"
assert_contains "an env var already set WINS" "$out" "TOK: already set on the environment"
assert_not_contains "…and is not re-read from Secret Manager" \
	"$(grep 'secrets versions access' "$work/gcloud.argv" || true)" "tok-secret"

# The sandbox pre-sets GH_TOKEN and friends to short dummy strings. Honoring one
# as if it were real is the worst outcome available: the genuine token is never
# fetched, and every later call fails 401 against a credential the report called
# fine. A placeholder must LOSE to the profile's secret.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned TOK=dummy-token)"
assert_contains "a placeholder env var does NOT win" "$out" "ignoring a placeholder value"
assert_contains "…the real secret is fetched over it" "$out" "TOK: from tok-secret"
if grep -q "^export TOK=" "$work/state/session.env" &&
	! grep -q "^export TOK=dummy-token" "$work/state/session.env"; then
	pass "…and the placeholder never reaches the session env"
else
	fail "the placeholder value survived into the session env"
fi

out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=nocreds)"
assert_contains "a no-identity profile establishes nothing" "$out" "declares no GCP identity"
[ ! -s "$work/gcloud.argv" ] && pass "…and reads no secrets at all" ||
	fail "a no-identity profile still called gcloud"

out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned CLOUDSDK_AUTH_ACCESS_TOKEN=dummy-token)"
assert_contains "a placeholder ambient GCP token is cleared" "$out" "cleared a placeholder"
if grep -q "^export CLOUDSDK_AUTH_ACCESS_TOKEN=''" "$work/state/session.env"; then
	pass "…so the pulumi wrapper still applies its identity pin"
else
	fail "the placeholder token was not cleared in the session env"
fi

# A real (long) token must NOT be clobbered — that is a deliberate break-glass.
real_token="ya29.$(printf 'a%.0s' $(seq 1 80))"
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned "CLOUDSDK_AUTH_ACCESS_TOKEN=$real_token")"
assert_not_contains "a real ambient token is left alone" "$out" "cleared a placeholder"

# ---------------------------------------------------------------------------
echo "cloud-bootstrap: shipped manifest"
# ---------------------------------------------------------------------------
# The committed profiles.tsv must stay parseable by the same resolver, and must
# never carry a value that looks like a credential.
SHIPPED="${HERE}/profiles.tsv"
if [ -f "$SHIPPED" ]; then
	rows="$(awk '$1 !~ /^#/ && NF > 0 { print $1 }' "$SHIPPED" | wc -l | tr -d ' ')"
	[ "$rows" -ge 1 ] && pass "the shipped manifest declares $rows profile(s)" ||
		fail "the shipped manifest declares no profiles"
	bad="$(awk '$1 !~ /^#/ && NF > 0 && NF < 6 { print $1 }' "$SHIPPED")"
	[ -z "$bad" ] && pass "every shipped row has all six columns" ||
		fail "under-specified rows in profiles.tsv: $bad"
	if grep -qiE 'BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|ya29\.|ghp_|pul-[0-9a-f]{40}' "$SHIPPED"; then
		fail "profiles.tsv contains something that looks like a credential"
	else
		pass "profiles.tsv contains no credential-shaped values"
	fi
else
	fail "profiles.tsv is missing"
fi

echo
if [ "$fails" -eq 0 ]; then
	echo "cloud-bootstrap: all checks passed"
	exit 0
fi
echo "cloud-bootstrap: $fails check(s) failed" >&2
exit 1
