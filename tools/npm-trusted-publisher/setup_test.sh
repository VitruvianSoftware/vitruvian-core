#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tests for setup.sh with a stubbed npm. This tool makes ACCOUNT-LEVEL changes,
# so the properties worth pinning are the conservative ones: it must refuse to
# run without a login rather than failing 31 times, it must not reconfigure a
# package that already has a trusted publisher (the registry errors on
# duplicates), and it must map each package to its MIRROR repo, never to
# vitruvian-core.
set -uo pipefail

SCRIPT="${1:?usage: setup_test.sh <path to setup.sh>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

mkdir -p "$work/repo/pulumi/library/ts/packages/a" "$work/repo/mcp-slack" "$work/bin"
printf '{"name":"@v/a","version":"1.0.0","private":false}\n' >"$work/repo/pulumi/library/ts/packages/a/package.json"
printf '{"name":"@v/mcp","version":"1.0.0","private":false}\n' >"$work/repo/mcp-slack/package.json"
mkdir -p "$work/repo/pulumi/library/ts/packages/priv"
printf '{"name":"@v/priv","version":"1.0.0","private":true}\n' >"$work/repo/pulumi/library/ts/packages/priv/package.json"

# npm stub. STUB_LOGGED_IN, STUB_ALREADY (space-separated names already
# configured). Records every `trust github` invocation to $CALLS.
cat >"$work/bin/npm" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "trust" ] && [ "$2" = "github" ] && [ "${3:-}" = "--help" ]; then
  # STUB_NO_ALLOW_PUBLISH models an npm like 11.11.0: it HAS `trust`, but not the
  # --allow-publish flag. That combination is what defeated the old check.
  echo "npm trust github <pkg> --repo <r> --file <f> [--yes]"
  [ -z "${STUB_NO_ALLOW_PUBLISH:-}" ] && echo "  --allow-publish"
  exit 0
fi
case "$1 ${2:-}" in
  "whoami ")
    # STUB_LOGIN_MARKER lets `login` flip this stub from logged-out to logged-in,
    # so the post-login re-verification is exercised for real.
    if [ -n "${STUB_LOGGED_IN:-}" ] || { [ -n "${STUB_LOGIN_MARKER:-}" ] && [ -f "$STUB_LOGIN_MARKER" ]; }; then
      echo ipv1337; exit 0
    fi
    exit 1 ;;
  "trust --help") exit 0 ;;
esac
if [ "$1" = "view" ]; then
  for n in ${STUB_UNPUBLISHED:-}; do [ "$n" = "$2" ] && exit 1; done
  echo "1.0.0"; exit 0
fi
case "$1 ${2:-}" in
  "login ")
    echo "login" >> "${CALLS:-/dev/null}"
    # STUB_LOGIN_USELESS: exit 0 without actually authenticating.
    [ -n "${STUB_LOGIN_USELESS:-}" ] && exit 0
    [ -n "${STUB_LOGIN_FAILS:-}" ] && exit 1
    [ -n "${STUB_LOGIN_MARKER:-}" ] && : > "$STUB_LOGIN_MARKER"
    exit 0 ;;
esac
# EVERY `npm trust` call -- `list` included -- is 2FA-protected. Model that
# faithfully: a stub that exempts `list` would let a probe gating on a read look
# like a working guard. STUB_EOTP never clears; STUB_OTP_UNTIL clears after N
# calls, standing in for the user finishing the browser flow partway through.
_otp_blocked() {
  [ -n "${STUB_EOTP:-}" ] && return 0
  [ -n "${STUB_OTP_UNTIL:-}" ] || return 1
  local n=0
  [ -f "${CALLS}.otp" ] && n="$(cat "${CALLS}.otp")"
  echo $((n + 1)) > "${CALLS}.otp"
  [ "$n" -lt "${STUB_OTP_UNTIL}" ]
}
_emit_otp() {
  echo "npm error code EOTP" >&2
  echo "npm error Open this URL in your browser to authenticate:" >&2
  echo "npm error   https://www.npmjs.com/auth/cli/STUBID" >&2
}
if [ "$1" = "trust" ] && [ "$2" = "list" ]; then
  for n in ${STUB_UNPUBLISHED:-}; do
    [ "$n" = "$3" ] && { echo "npm error code E404" >&2; exit 1; }
  done
  if _otp_blocked; then _emit_otp; exit 1; fi
  for n in ${STUB_ALREADY:-}; do [ "$n" = "$3" ] && { echo "release.yml"; exit 0; }; done
  exit 0
fi
if [ "$1" = "access" ] && [ "$2" = "set" ]; then
  echo "$*" >> "$CALLS"
  if _otp_blocked; then _emit_otp; exit 1; fi
  echo "TRUST_OK_VISIBLE"
  exit 0
fi
if [ "$1" = "trust" ] && [ "$2" = "github" ]; then
  echo "$*" >> "$CALLS"
  if _otp_blocked; then _emit_otp; exit 1; fi
  if [ -n "${STUB_GH_DUPLICATE:-}" ]; then echo "npm error already exists" >&2; exit 1; fi
  # Marker on stdout. It can only reach the SCRIPT's output if the script let
  # npm inherit stdio; if the call was captured into a variable it is swallowed.
  echo "TRUST_OK_VISIBLE"
  exit 0
fi
exit 0
EOF
chmod +x "$work/bin/npm"

# Run a command with a controlling terminal, PORTABLY.
#
# `script` takes different arguments on the two platforms this repo builds on:
# BSD/macOS is `script -q <file> <cmd> <args...>`; util-linux is
# `script -qec "<cmd string>" <file>`. Using the BSD form on Linux does
# something else entirely -- these tests passed locally on macOS and failed on
# the Linux CI runner, which is precisely the gap this removes.
run() { # <env...> ; echoes "<rc>|<stdout>"
    : >"$work/calls"
    local out rc
    out="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" \
        BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" DELAY_SECONDS=0 \
        "$@" bash "$SCRIPT" 2>"$work/err")"
    rc=$?
    printf '%s|%s' "$rc" "$out"
}

echo "--- npm selection: probe the FLAG, not the subcommand ---"
# Eight npms can sit on PATH here, 10.8.2 to 11.19.0. `npm trust` does not exist
# before 11.5.1 and --allow-publish is newer still: 11.11.0 HAS trust and rejects
# the flag. So an interactive shell and a `bazel run` resolve different npms on
# one machine. On 2026-08-21 a manual sweep configured 27 packages while the
# target reported "0 configured, 32 failed" -- same script, different npm.
mkdir -p "$work/bad" "$work/good"
cp "$work/bin/npm" "$work/good/npm"
printf '#!/usr/bin/env bash\nexport STUB_NO_ALLOW_PUBLISH=1\nexec "%s" "$@"\n' "$work/bin/npm" >"$work/bad/npm"
chmod +x "$work/bad/npm" "$work/good/npm"

: >"$work/calls"
out="$(cd "$work/repo" && env PATH="$work/bad:$work/good:/usr/bin:/bin" \
    BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" DELAY_SECONDS=0 \
    STUB_LOGGED_IN=1 bash "$SCRIPT" --dry-run 2>&1 </dev/null)"; rc=$?
if [ "$rc" = "0" ] && printf '%s' "$out" | grep -q 'lacks --allow-publish'; then
    pass "skips an npm that lacks --allow-publish and uses a capable one further down PATH"
else
    fail "did not recover from an incapable first npm: rc=$rc $(printf '%s' "$out" | head -3 | tr '\n' '|')"
fi

: >"$work/calls"
out="$(cd "$work/repo" && env PATH="$work/bad:/usr/bin:/bin" \
    BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" DELAY_SECONDS=0 \
    STUB_LOGGED_IN=1 bash "$SCRIPT" 2>&1 </dev/null)"; rc=$?
if [ "$rc" != "0" ] && ! grep -q 'trust github' "$work/calls" 2>/dev/null; then
    pass "refuses up front when NO npm supports the flag, rather than failing 32 times"
else
    fail "attempted the sweep with an incapable npm: rc=$rc $(tr '\n' ';' <"$work/calls")"
fi

out="$(cd "$work/repo" && env PATH="$work/good:/usr/bin:/bin" NPM="$work/bad/npm" \
    BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" DELAY_SECONDS=0 \
    STUB_LOGGED_IN=1 bash "$SCRIPT" 2>&1 </dev/null)"; rc=$?
if [ "$rc" != "0" ]; then
    pass "an explicitly-set NPM is refused, never silently swapped for another"
else
    fail "silently replaced the npm the caller chose"
fi

echo "--- login handling ---"
# run() gives the script no controlling terminal, so /dev/tty is unreadable in
# the sandbox -- exactly the CI/nested-shell case. It must REFUSE, not hang.
r="$(run STUB_LOGGED_IN=)"
if [ "${r%%|*}" = "2" ] && grep -q 'terminal to authenticate on' "$work/err"; then
    pass "no login and no terminal refuses UP FRONT rather than attempting an interactive prompt"
else
    fail "expected the no-terminal guard; got rc=${r%%|*}: $(head -2 "$work/err")"
fi

: >"$work/calls"
rm -f "$work/loggedin"
r="$(cd "$work/repo" && env NPM_TP_TTY_OK=1 OTP_WAIT_SECONDS=6 OTP_POLL_SECONDS=1 PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGIN_MARKER="$work/loggedin" \
    bash "$SCRIPT" --no-login >/dev/null 2>"$work/err" </dev/null; echo $?)"
if [ "$r" != "0" ] && ! grep -q '^login$' "$work/calls" 2>/dev/null; then
    pass "--no-login refuses even WITH a terminal available, never shelling out to login"
else
    fail "--no-login ignored: rc=$r calls=$(tr '\n' ';' <"$work/calls")"
fi

echo "--- a login that exits 0 without authenticating must NOT proceed ---"
: >"$work/calls"
r="$(cd "$work/repo" && env NPM_TP_TTY_OK=1 OTP_WAIT_SECONDS=6 OTP_POLL_SECONDS=1 PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGIN_USELESS=1 \
    bash "$SCRIPT" >/dev/null 2>"$work/err" </dev/null; echo $?)"
if [ "$r" != "0" ]; then
    pass "login exiting 0 without a session is re-verified and rejected (rc=$r)"
else
    fail "proceeded after a login that did not authenticate"
fi

echo "--- a successful login proceeds straight into the work ---"
: >"$work/calls"
rm -f "$work/loggedin"
r="$(cd "$work/repo" && env NPM_TP_TTY_OK=1 OTP_WAIT_SECONDS=6 OTP_POLL_SECONDS=1 PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGIN_MARKER="$work/loggedin" \
    bash "$SCRIPT" >/dev/null 2>"$work/err" </dev/null; echo $?)"
if grep -q '^login$' "$work/calls" && grep -q 'trust github' "$work/calls"; then
    pass "logs in, then configures without a second command (rc=$r)"
else
    fail "auto-login did not lead into configuration: $(tr '\n' ';' <"$work/calls")"
fi

echo "--- a PIPED caller must not defeat the auth prompt ---"
# Inheriting stdio is not enough. `bazel run ... | tee setup.log` makes the
# SCRIPT's stdout a pipe, so npm still sees no terminal and still masks the
# token -- which is exactly what happened, because the documented invocation
# used `| tee`. The fix was defeated by its own instructions. npm must be bound
# to the CONTROLLING TERMINAL, independent of how the caller redirects us.
: >"$work/calls"; rm -f "$work/calls.otp"; : >"$work/faketty"
r="$(run STUB_LOGGED_IN=1 OTP_WAIT_SECONDS=6 OTP_POLL_SECONDS=1 STUB_OTP_UNTIL=2 \
      NPM_TP_TTY_PATH="$work/faketty")"
if grep -q 'TRUST_OK_VISIBLE' "$work/faketty" 2>/dev/null; then
    pass "the auth attempt is bound to the terminal, not to our (possibly piped) stdout"
else
    fail "auth output did not reach the terminal: $(head -c 120 "$work/faketty" | tr '\n' '|')"
fi
if printf '%s' "${r#*|}" | grep -q 'TRUST_OK_VISIBLE'; then
    fail "auth output went to stdout — a piped caller would capture it and npm would mask the URL"
else
    pass "...and does NOT go to stdout, so piping this script cannot mask the URL"
fi

echo "--- configures each package against its MIRROR repo ---"
r="$(run STUB_LOGGED_IN=1)"
if grep -q -- '--repo VitruvianSoftware/pulumi-library' "$work/calls" \
   && grep -q -- '--repo VitruvianSoftware/mcp-slack' "$work/calls"; then
    pass "library -> pulumi-library, mcp-slack -> mcp-slack"
else
    fail "wrong mirror mapping: $(tr '\n' ';' <"$work/calls")"
fi
if grep -q 'vitruvian-core' "$work/calls"; then
    fail "registered vitruvian-core — the workflow runs on the MIRROR, this would never match"
else
    pass "never registers vitruvian-core"
fi
if grep -q -- '--file release.yml' "$work/calls" && grep -q -- '--allow-publish' "$work/calls"; then
    pass "passes the workflow filename and --allow-publish"
else
    fail "missing --file/--allow-publish"
fi

echo "--- --harden: require 2FA and disallow token bypass ---"
# `mfa=publish` = two-factor required AND automation tokens cannot bypass it.
# Only safe to set once CI no longer needs a token; npm's guidance is that
# disallowing tokens does not affect trusted publishers, which use OIDC.
r="$(run STUB_LOGGED_IN=1 --harden 2>/dev/null)" || true
: >"$work/calls"
out2="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" \
    BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" DELAY_SECONDS=0 \
    STUB_LOGGED_IN=1 bash "$SCRIPT" --harden 2>&1 </dev/null)"
if grep -q 'access set mfa=publish @v/a' "$work/calls" && grep -q 'access set mfa=publish @v/mcp' "$work/calls"; then
    pass "sets mfa=publish on every published, non-private package"
else
    fail "harden did not sweep: $(tr '\n' ';' <"$work/calls")"
fi
if grep -q '@v/priv' "$work/calls"; then
    fail "hardened a PRIVATE package"
else
    pass "a private package is left alone"
fi
# Mode isolation both ways: neither sweep may silently perform the other.
if grep -q 'trust github' "$work/calls"; then
    fail "--harden also reconfigured trusted publishers — one flag, one effect"
else
    pass "--harden does not touch trusted publishers"
fi
if printf '%s' "$out2" | grep -q 'set to mfa=publish'; then
    pass "the summary reports hardening, not a trust sweep"
else
    fail "wrong summary: $(printf '%s' "$out2" | tail -2 | tr '\n' '|')"
fi

: >"$work/calls"
r="$(run STUB_LOGGED_IN=1)"
if grep -q 'access set mfa' "$work/calls"; then
    fail "the DEFAULT sweep changed account security settings — that must be opt-in"
else
    pass "the default sweep never changes mfa settings"
fi

: >"$work/calls"
(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGGED_IN=1 bash "$SCRIPT" --harden --dry-run >/dev/null 2>&1)
if [ ! -s "$work/calls" ]; then
    pass "--harden --dry-run changes nothing"
else
    fail "--harden --dry-run made calls: $(tr '\n' ';' <"$work/calls")"
fi

: >"$work/calls"; rm -f "$work/calls.otp"; : >"$work/faketty3"
out2="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" \
    BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" DELAY_SECONDS=0 \
    OTP_WAIT_SECONDS=6 OTP_POLL_SECONDS=1 STUB_OTP_UNTIL=1 STUB_LOGGED_IN=1 \
    NPM_TP_TTY_PATH="$work/faketty3" bash "$SCRIPT" --harden 2>&1 </dev/null)"
if grep -q 'TRUST_OK_VISIBLE' "$work/faketty3" 2>/dev/null; then
    pass "hardening gets the same terminal-bound two-factor handling, not a masked URL"
else
    fail "harden auth was not terminal-bound: $(head -c 120 "$work/faketty3" | tr '\n' '|')"
fi

echo "--- private packages are not configured ---"
if grep -q '@v/priv' "$work/calls"; then
    fail "configured a private package"
else
    pass "a private package is skipped"
fi

echo "--- already-configured packages are not touched again ---"
r="$(run STUB_LOGGED_IN=1 STUB_ALREADY="@v/a")"
if grep -q '@v/a' "$work/calls"; then
    fail "reconfigured an already-trusted package (the registry errors on duplicates)"
else
    pass "an existing configuration is left alone, so re-running is safe"
fi

echo "--- dry run changes nothing ---"
: >"$work/calls"
(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGGED_IN=1 bash "$SCRIPT" --dry-run >/dev/null 2>&1)
if [ ! -s "$work/calls" ]; then
    pass "--dry-run issues no trust calls"
else
    fail "--dry-run made changes"
fi

echo "--- EOTP: the auth URL must reach the user, not /dev/null ---"
# Every `npm trust` call is 2FA-protected and returns EOTP with a URL to open.
# An earlier version redirected all output to /dev/null, so the user saw a
# silent failure and had no way to proceed. That is what broke the first real
# run of this tool.
: >"$work/calls"
rm -f "$work/loggedin"
: >"$work/faketty2"
out="$(cd "$work/repo" && env NPM_TP_TTY_OK=1 OTP_WAIT_SECONDS=6 OTP_POLL_SECONDS=1 PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGGED_IN=1 STUB_EOTP=1 \
    NPM_TP_TTY_PATH="$work/faketty2" \
    bash "$SCRIPT" 2>&1 </dev/null || true)"
# Still the right property -- but the user reads the URL on the TERMINAL now.
# Asserting it appears on our stdout would re-pin the bug: stdout is what npm
# masks when it is a pipe.
if grep -q 'npmjs.com/auth/cli' "$work/faketty2" 2>/dev/null; then
    pass "the authentication URL reaches the user's terminal"
else
    fail "auth URL never reached the terminal: $(head -c 120 "$work/faketty2" | tr '\n' ';')"
fi
if printf '%s' "$out" | grep -qi 'skip for the next 5 minutes'; then
    pass "...along with the instruction that makes it a one-time step"
else
    fail "no guidance about the 5-minute skip"
fi
if printf '%s' "$out" | grep -q 'gave up waiting for two-factor'; then
    pass "an authentication that never completes is reported, never silently skipped"
else
    fail "no give-up report: $(printf '%s' "$out" | tail -3 | tr '\n' ';')"
fi

echo "--- EOTP that clears mid-run: the script must WAIT, not bail ---"
# THE regression guard. The old probe polled `npm trust list` for 180s and then
# exited 2 -- while the user was still completing the browser + security-key
# flow. They finished moments later: session live, 0 of 29 packages configured,
# reported as a 2FA expiry. Here the auth completes after two rejections; the
# run must ride it out rather than give up on the user.
: >"$work/calls"; rm -f "$work/calls.otp"
out="$(cd "$work/repo" && env NPM_TP_TTY_OK=1 OTP_WAIT_SECONDS=20 OTP_POLL_SECONDS=1 \
    PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGGED_IN=1 STUB_OTP_UNTIL=2 \
    bash "$SCRIPT" 2>&1 </dev/null || true)"
if printf '%s' "$out" | grep -q '2 configured, 0 already set, 0 failed'; then
    pass "waits out the two-factor authentication and configures every package"
else
    fail "bailed instead of waiting: $(printf '%s' "$out" | tail -3 | tr '\n' ';')"
fi
if printf '%s' "$out" | grep -qi 'npm will print a URL'; then
    pass "...telling the user npm is about to prompt, instead of echoing a masked URL"
else
    fail "no handover guidance shown: $(printf '%s' "$out" | tail -3 | tr '\n' '|')"
fi

echo "--- the two-factor wait must outlast a real security-key flow ---"
# THE regression. The tool shipped with a 180s budget; that expired while the
# user was still in the browser + security-key flow. The run exited 2 having
# configured NOTHING, and their authentication landed moments later -- leaving a
# live session and an empty result that read as a 2FA expiry. The budget is the
# thing that broke, so pin the budget.
_budget="$(sed -n 's/^OTP_WAIT_SECONDS="${OTP_WAIT_SECONDS:-\([0-9]*\)}"/\1/p' "$SCRIPT" | head -1)"
if [ "${_budget:-0}" -ge 600 ]; then
    pass "default two-factor wait is ${_budget}s, enough for a browser + key round trip"
else
    fail "default two-factor wait is only ${_budget:-unset}s -- a security-key flow outlasts it"
fi

echo "--- a duplicate is reported as already-configured, not as a failure ---"
: >"$work/calls"
out="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGGED_IN=1 STUB_GH_DUPLICATE=1 \
    bash "$SCRIPT" 2>&1 || true)"
if printf '%s' "$out" | grep -qE '[0-9]+ already set, 0 failed'; then
    pass "an existing configuration counts as already-set, never as a failure"
else
    fail "duplicate mis-classified: $(printf '%s' "$out" | tail -2 | tr '\n' ';')"
fi

echo "--- an unpublished package cannot be configured, and must not derail the run ---"
# A trusted publisher attaches to a PACKAGE; for a name never published every
# trust call returns E404. Three of this repo's packages are in that state.
# Critically, the 2FA PROBE must not be one of them: an earlier version picked
# the alphabetically-first package (unpublished), so the post-auth re-check
# could never succeed and the run aborted before configuring anything.
: >"$work/calls"
out="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGGED_IN=1 STUB_UNPUBLISHED="@v/a" \
    bash "$SCRIPT" 2>&1 || true)"
if printf '%s' "$out" | grep -q 'not on the registry yet'; then
    pass "an unpublished package is reported, not attempted"
else
    fail "unpublished package not reported: $(printf '%s' "$out" | tail -2 | tr '\n' ';')"
fi
if ! grep -q '@v/a' "$work/calls" 2>/dev/null && grep -q '@v/mcp' "$work/calls" 2>/dev/null; then
    pass "...and the run continues, configuring the packages that DO exist"
else
    fail "run derailed by the unpublished package: $(tr '\n' ';' <"$work/calls")"
fi
if printf '%s' "$out" | grep -qE '1 not yet on the registry'; then
    pass "the summary counts it separately from failures"
else
    fail "unpublished not counted separately"
fi

echo
if [ "$fail_n" -gt 0 ]; then echo "FAILED: $fail_n"; exit 1; fi
echo "ALL PASS ($pass_n)"
