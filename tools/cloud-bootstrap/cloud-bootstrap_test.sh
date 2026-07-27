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
second     kubectl sa-second@x.iam.gserviceaccount.com  proj-b  EXTRA=extra-secret                 Second profile with its own identity.
clashing   gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=different-secret               Maps TOK to a different secret than `pinned`.
nocreds    gh      -                   -           -                                    No credentials at all.
onlytok    gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=tok-secret                     Claims TOK and nothing else.
envonly    gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=tok-secret,ENVCRED=-           Declares an environment-only credential.
cached     bazel,gh sa-pinned@x.iam.gserviceaccount.com proj-a  TOK=tok-secret,BUILDBUDDY_API_KEY=- Declares the build-cache key AND installs bazel.
nobazel    gh      sa-pinned@x.iam.gserviceaccount.com  proj-a  TOK=tok-secret,BUILDBUDDY_API_KEY=- Declares the build-cache key but installs no bazel.
TSV

SA_KEY_GOOD='{"type":"service_account","client_email":"sa-pinned@x.iam.gserviceaccount.com","private_key":"KEYBYTES"}'
SA_KEY_WRONG='{"type":"service_account","client_email":"sa-admin@x.iam.gserviceaccount.com","private_key":"KEYBYTES"}'
SA_KEY_SECOND='{"type":"service_account","client_email":"sa-second@x.iam.gserviceaccount.com","private_key":"KEYBYTES"}'

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

# Fake build-cache configurator: records argv AND the environment it was handed,
# so the test can pin that the API key arrived by env and never through argv.
make_cache_setup() { # make_cache_setup <mode: ok|fail>
	cat >"$work/cache-setup" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$work/cache-setup.argv"
printf 'KEY=%s WS=%s\n' "\${BUILDBUDDY_API_KEY:-<unset>}" \
  "\${BUILD_WORKSPACE_DIRECTORY:-<unset>}" >>"$work/cache-setup.env"
[ "$1" = fail ] && exit 3
exit 0
FAKE
	chmod +x "$work/cache-setup"
}

# run_auth <key> [extra env assignments…] — drive the real script's auth path in
# a throwaway HOME, and echo its combined output.
run_auth() {
	local key="$1"
	shift
	rm -rf "$work/home" "$work/state"
	mkdir -p "$work/home"
	: >"$work/gcloud.argv"
	: >"$work/cache-setup.argv"
	: >"$work/cache-setup.env"
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
[ ! -f "$work/state/sa-key-pinned.json" ] && pass "the rejected key is not left on disk" ||
	fail "the rejected key was left at state/sa-key-pinned.json"

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
assert_contains "…by path, never by value" "$argv" "--key-file=$work/state/sa-key-pinned.json"
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
mode="$(stat -c '%a' "$work/state/sa-key-pinned.json" 2>/dev/null || stat -f '%Lp' "$work/state/sa-key-pinned.json" 2>/dev/null)"
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
echo "cloud-bootstrap: the profile boundary actually withholds"
# ---------------------------------------------------------------------------
# The bootstrap only ever ADDS credentials, so while they come from the
# environment rather than Secret Manager a narrow profile was decorative: a
# `readonly` session -- the one whose entire purpose is to be unable to reach
# production -- still read every token straight out of the environment while
# :whoami reported "creds – none". Anything the manifest calls a credential and
# no active profile claims must be blanked.
make_gcloud ok

# effective_value <VAR> <ambient> — what a Bash tool call in the session really
# sees: the harness sets the env var, the shell sources session.env, and whatever
# survives is what the agent can use. A KEPT credential is never written to
# session.env (it was already correct in the environment), so checking that file
# alone would wrongly read as "scrubbed".
effective_value() {
	env "$1=$2" bash -c '. "$0" 2>/dev/null; printf "%s" "${!1}"' \
		"$work/state/session.env" "$1"
}

BIG_A="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
BIG_B="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
BIG_C="cccccccccccccccccccccccccccccccccccccccc"

out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=nocreds \
	TOK="$BIG_A" OTHER="$BIG_B" EXTRA="$BIG_C")"
for v in TOK OTHER EXTRA; do
	if [ -z "$(effective_value "$v" "$BIG_A")" ]; then
		pass "a no-credential profile blanks $v"
	else
		fail "$v survived into a no-credential session"
	fi
done
assert_contains "…and says so out loud" "$out" "CLEARED"

# A profile keeps what it declares and loses only the rest.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=onlytok \
	TOK="$BIG_A" OTHER="$BIG_B" EXTRA="$BIG_C")"
[ -n "$(effective_value TOK "$BIG_A")" ] && pass "a declared credential is kept" ||
	fail "the profile's own credential was scrubbed"
[ -z "$(effective_value OTHER "$BIG_B")" ] && pass "…while an undeclared one is cleared" ||
	fail "OTHER survived a profile that does not declare it"
[ -z "$(effective_value EXTRA "$BIG_C")" ] && pass "…including one only another profile declares" ||
	fail "EXTRA survived a profile that does not declare it"

# Only what the MANIFEST calls a credential is touched — guessing at other
# variables would be scope this tool has no basis for.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=nocreds SOME_UNRELATED_VAR="$BIG_C")"
assert_not_contains "a var no row names is left alone" "$out" "SOME_UNRELATED_VAR"

# ---------------------------------------------------------------------------
echo "cloud-bootstrap: environment-only credentials"
# ---------------------------------------------------------------------------
# Some credentials are not in Secret Manager and never will be --
# BUILDBUDDY_API_KEY is a GitHub Actions/Dependabot secret owned by repo_config
# and injected from the pipeline. Naming a Secret Manager entry for one would be
# a wrong address that fails the day SM is wired up; "-" declares entitlement
# WITHOUT a read, so it stays inside the boundary either way.
make_gcloud ok
BIG_D="dddddddddddddddddddddddddddddddddddddddd"

out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=envonly ENVCRED="$BIG_D")"
assert_not_contains "no Secret Manager read is attempted for it" \
	"$(grep 'secrets versions access' "$work/gcloud.argv" || true)" "--secret=-"
[ -n "$(effective_value ENVCRED "$BIG_D")" ] &&
	pass "a declaring profile keeps the environment's value" ||
	fail "an environment-only credential was scrubbed from its own profile"

# The point of declaring it: a profile that does NOT list it still scrubs it.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=onlytok ENVCRED="$BIG_D")"
[ -z "$(effective_value ENVCRED "$BIG_D")" ] &&
	pass "…and a profile that omits it still gets it scrubbed" ||
	fail "an environment-only credential escaped the boundary"

# ---------------------------------------------------------------------------
echo "cloud-bootstrap: build cache"
# ---------------------------------------------------------------------------
# The cache config lives in user.bazelrc, which is git-ignored -- so a freshly
# cloned sandbox has none, and cold-builds a large polyglot repo while holding a
# working BUILDBUDDY_API_KEY it never uses. What is pinned here is not "does the
# cache work" (that is BuildBuddy's problem) but the properties whose failure is
# a LEAKED KEY or a CREDENTIAL BAKED INTO A CACHED IMAGE.
make_gcloud ok
make_cache_setup ok
BB_KEY="bbbbbbbbkeyeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=cached \
	CLOUD_BOOTSTRAP_CACHE_SETUP="$work/cache-setup" BUILDBUDDY_API_KEY="$BB_KEY")"
cargv="$(cat "$work/cache-setup.argv")"
assert_contains "a declaring profile configures the cache" "$cargv" "--cache buildbuddy"
assert_contains "…without touching CI secrets" "$cargv" "--no-ci"

# argv is world-readable through `ps`. Same reflex as the SA key's --key-file.
assert_not_contains "the API key never reaches argv" "$cargv" "$BB_KEY"
assert_contains "…it is handed over in the environment instead" \
	"$(cat "$work/cache-setup.env")" "KEY=$BB_KEY"
# Without this the configurator falls back to `git rev-parse` and then $PWD, and
# a hook's cwd is not guaranteed to be the workspace.
assert_not_contains "…and the workspace is pinned, not guessed" \
	"$(cat "$work/cache-setup.env")" "WS=<unset>"

# The sandbox pre-sets several credential names to short dummy strings. Building
# a cache config on one yields something that looks enabled and authenticates
# against nothing -- strictly worse than no cache, because it reports success.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=cached \
	CLOUD_BOOTSTRAP_CACHE_SETUP="$work/cache-setup" BUILDBUDDY_API_KEY=dummy-key)"
[ ! -s "$work/cache-setup.argv" ] && pass "a placeholder key configures nothing" ||
	fail "the cache was configured with a placeholder key"

# Entitlement is the profile's, not the environment's: a row that does not name
# BUILDBUDDY_API_KEY has already had it scrubbed, and must not get cache WRITE
# access back through this path.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=onlytok \
	CLOUD_BOOTSTRAP_CACHE_SETUP="$work/cache-setup" BUILDBUDDY_API_KEY="$BB_KEY")"
[ ! -s "$work/cache-setup.argv" ] && pass "a profile that omits the key configures nothing" ||
	fail "an unentitled profile still configured the cache"

# No bazel in the row means nothing in the session would ever read user.bazelrc.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=nobazel \
	CLOUD_BOOTSTRAP_CACHE_SETUP="$work/cache-setup" BUILDBUDDY_API_KEY="$BB_KEY")"
[ ! -s "$work/cache-setup.argv" ] && pass "a profile without bazel configures nothing" ||
	fail "the cache was configured for a session with no bazel"

# Best-effort like every other path here: a cache is a speed-up, and failing to
# get one must never cost the session its credentials.
make_cache_setup fail
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=cached \
	CLOUD_BOOTSTRAP_CACHE_SETUP="$work/cache-setup" BUILDBUDDY_API_KEY="$BB_KEY")"
assert_contains "a failed configuration is reported, not fatal" "$out" "builds stay local"
if grep -q "^export TOK=" "$work/state/session.env"; then
	pass "…and the session still got its credentials"
else
	fail "a build-cache failure cost the session its credentials"
fi
make_cache_setup ok

# ---------------------------------------------------------------------------
echo "cloud-bootstrap: multiple profiles"
# ---------------------------------------------------------------------------
make_gcloud ok

# Combining profiles must NOT merge privileges into one identity: each keeps its
# own service account and reads only its own secrets. That is the whole reason
# combining is safe, so it is the first thing pinned.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned,second \
	VITRUVIAN_CLOUD_KEY_SECOND="$SA_KEY_SECOND")"
argv="$(cat "$work/gcloud.argv")"
assert_contains "both identities are activated" "$argv" "sa-key-pinned.json"
assert_contains "…each from its own key file" "$argv" "sa-key-second.json"

tok_line="$(grep 'secrets versions access' "$work/gcloud.argv" | grep -- '--secret=tok-secret' || true)"
extra_line="$(grep 'secrets versions access' "$work/gcloud.argv" | grep -- '--secret=extra-secret' || true)"
assert_contains "profile 1's secret is read as profile 1's SA" "$tok_line" "--account=sa-pinned@x.iam.gserviceaccount.com"
assert_contains "profile 2's secret is read as profile 2's SA" "$extra_line" "--account=sa-second@x.iam.gserviceaccount.com"
assert_contains "…and with profile 2's own project" "$extra_line" "--project=proj-b"
assert_not_contains "profile 2's SA never reads profile 1's secret" "$tok_line" "sa-second@"

for v in TOK OTHER EXTRA; do
	if grep -q "^export $v=" "$work/state/session.env"; then
		pass "the union includes $v"
	else
		fail "$v missing from the combined session env"
	fi
done

# The FIRST listed profile with an identity is the ambient one.
assert_contains "the first listed identity is the primary" "$out" "sa-pinned@x.iam.gserviceaccount.com (project proj-a) — PRIMARY"
if grep -q "^export GOOGLE_APPLICATION_CREDENTIALS=.*sa-key-pinned.json" "$work/state/session.env"; then
	pass "…and is what GOOGLE_APPLICATION_CREDENTIALS points at"
else
	fail "GOOGLE_APPLICATION_CREDENTIALS does not point at the primary key"
fi
assert_contains "…the non-primary is reported as such" "$out" "reads its own secrets only"

# Reversing the order reverses the primary — the rule is order, not luck.
out="$(run_auth "$SA_KEY_SECOND" VITRUVIAN_PROFILE=second,pinned \
	VITRUVIAN_CLOUD_KEY_PINNED="$SA_KEY_GOOD")"
assert_contains "listing order chooses the primary" "$out" "sa-second@x.iam.gserviceaccount.com (project proj-b) — PRIMARY"

# Two rows mapping the same var to DIFFERENT secrets must not resolve by row order.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned,clashing)"
assert_contains "a conflicting secret mapping is refused" "$out" "REFUSING TOK for profile 'clashing'"
assert_contains "…naming both secrets" "$out" "this one says 'different-secret'"
n="$(grep -c -- '--secret=different-secret' "$work/gcloud.argv" || true)"
[ "$n" = "0" ] && pass "…and the conflicting secret is never read" ||
	fail "the conflicting secret was read anyway"

# An identical mapping in two profiles is a harmless overlap, not a conflict.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned,pinned)"
assert_not_contains "a repeated profile is deduped, not refused" "$out" "REFUSING"
n="$(grep -c -- '--secret=tok-secret' "$work/gcloud.argv" || true)"
[ "$n" = "1" ] && pass "…and its secret is read exactly once" ||
	fail "a deduped profile read its secret $n times"

# One bad name in the list refuses the WHOLE list — no partial bootstrap.
out="$(run_auth "$SA_KEY_GOOD" VITRUVIAN_PROFILE=pinned,nope)"
assert_contains "an unknown profile in the list is refused" "$out" "is not a known profile"
[ ! -s "$work/gcloud.argv" ] && pass "…and nothing is established for the valid ones either" ||
	fail "a partial bootstrap happened despite an invalid list"

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
