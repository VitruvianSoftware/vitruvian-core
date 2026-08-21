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
  "whoami ") [ -n "${STUB_LOGGED_IN:-}" ] && { echo ipv1337; exit 0; }; exit 1 ;;
  "trust --help") exit 0 ;;
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

echo "--- refuses to run without a CLI login ---"
r="$(run STUB_LOGGED_IN=)"
if [ "${r%%|*}" = "2" ] && grep -q 'npm login' "$work/err"; then
    pass "no login exits 2 and names the fix, instead of failing per package"
else
    fail "expected rc=2 mentioning npm login; got rc=${r%%|*}"
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
