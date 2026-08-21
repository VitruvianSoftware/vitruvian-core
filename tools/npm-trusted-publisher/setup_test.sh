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
if [ "$1" = "trust" ] && [ "$2" = "list" ]; then
  for n in ${STUB_UNPUBLISHED:-}; do
    [ "$n" = "$3" ] && { echo "npm error code E404" >&2; exit 1; }
  done
  if [ -n "${STUB_EOTP:-}" ]; then
    echo "npm error code EOTP" >&2
    echo "npm error Open this URL in your browser to authenticate:" >&2
    echo "npm error   https://www.npmjs.com/auth/cli/STUBID" >&2
    exit 1
  fi
  for n in ${STUB_ALREADY:-}; do [ "$n" = "$3" ] && { echo "release.yml"; exit 0; }; done
  exit 0
fi
if [ "$1" = "trust" ] && [ "$2" = "github" ]; then
  echo "$*" >> "$CALLS"
  if [ -n "${STUB_GH_DUPLICATE:-}" ]; then echo "npm error already exists" >&2; exit 1; fi
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
out="$(cd "$work/repo" && env NPM_TP_TTY_OK=1 OTP_WAIT_SECONDS=6 OTP_POLL_SECONDS=1 PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGGED_IN=1 STUB_EOTP=1 \
    bash "$SCRIPT" 2>&1 </dev/null || true)"
if printf '%s' "$out" | grep -q 'npmjs.com/auth/cli'; then
    pass "the authentication URL is shown to the user"
else
    fail "auth URL was swallowed: $(printf '%s' "$out" | tail -3 | tr '\n' ';')"
fi
if printf '%s' "$out" | grep -qi 'skip for the next 5 minutes'; then
    pass "...along with the instruction that makes it a one-time step"
else
    fail "no guidance about the 5-minute skip"
fi
if [ ! -s "$work/calls" ]; then
    pass "no trust changes attempted while unauthorised"
else
    fail "attempted changes despite EOTP: $(tr '\n' ';' <"$work/calls")"
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
