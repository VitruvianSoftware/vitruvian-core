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
  "login ")
    echo "login" >> "${CALLS:-/dev/null}"
    # STUB_LOGIN_USELESS: exit 0 without actually authenticating.
    [ -n "${STUB_LOGIN_USELESS:-}" ] && exit 0
    [ -n "${STUB_LOGIN_FAILS:-}" ] && exit 1
    [ -n "${STUB_LOGIN_MARKER:-}" ] && : > "$STUB_LOGIN_MARKER"
    exit 0 ;;
esac
if [ "$1" = "trust" ] && [ "$2" = "list" ]; then
  for n in ${STUB_ALREADY:-}; do [ "$n" = "$3" ] && { echo "release.yml"; exit 0; }; done
  exit 0
fi
if [ "$1" = "trust" ] && [ "$2" = "github" ]; then
  echo "$*" >> "$CALLS"; exit 0
fi
exit 0
EOF
chmod +x "$work/bin/npm"

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
r="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGIN_MARKER="$work/loggedin" \
    script -q /dev/null bash "$SCRIPT" --no-login >/dev/null 2>"$work/err" </dev/null; echo $?)"
if [ "$r" != "0" ] && ! grep -q '^login$' "$work/calls" 2>/dev/null; then
    pass "--no-login refuses even WITH a terminal available, never shelling out to login"
else
    fail "--no-login ignored: rc=$r calls=$(tr '\n' ';' <"$work/calls")"
fi

echo "--- a login that exits 0 without authenticating must NOT proceed ---"
: >"$work/calls"
r="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGIN_USELESS=1 \
    script -q /dev/null bash "$SCRIPT" >/dev/null 2>"$work/err" </dev/null; echo $?)"
if [ "$r" != "0" ]; then
    pass "login exiting 0 without a session is re-verified and rejected (rc=$r)"
else
    fail "proceeded after a login that did not authenticate"
fi

echo "--- a successful login proceeds straight into the work ---"
: >"$work/calls"
rm -f "$work/loggedin"
r="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" BUILD_WORKSPACE_DIRECTORY="$work/repo" \
    CALLS="$work/calls" DELAY_SECONDS=0 STUB_LOGIN_MARKER="$work/loggedin" \
    script -q /dev/null bash "$SCRIPT" >/dev/null 2>"$work/err" </dev/null; echo $?)"
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

echo
if [ "$fail_n" -gt 0 ]; then echo "FAILED: $fail_n"; exit 1; fi
echo "ALL PASS ($pass_n)"
