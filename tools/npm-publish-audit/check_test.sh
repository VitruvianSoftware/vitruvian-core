#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tests for check.sh with a stubbed `npm view`. The property that matters is
# that a BEHIND package fails: an audit that cannot fail is the same defect it
# was written to detect.
set -uo pipefail

SCRIPT="${1:?usage: check_test.sh <path to check.sh>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0
fail_n=0
pass() {
    echo "  ✓ $1"
    pass_n=$((pass_n + 1))
}
fail() {
    echo "  ✗ $1" >&2
    fail_n=$((fail_n + 1))
}

mk() { # <dir> <name> <version> <private> [repo-url] [directory]
    mkdir -p "$work/repo/$1"
    _url="${5-https://github.com/o/r.git}"
    _dir="${6-}"
    if [ -n "$_dir" ]; then
        printf '{"name":"%s","version":"%s","private":%s,"repository":{"url":"%s","directory":"%s"}}\n' \
            "$2" "$3" "$4" "$_url" "$_dir" >"$work/repo/$1/package.json"
    elif [ -n "$_url" ]; then
        printf '{"name":"%s","version":"%s","private":%s,"repository":{"url":"%s"}}\n' \
            "$2" "$3" "$4" "$_url" >"$work/repo/$1/package.json"
    else
        printf '{"name":"%s","version":"%s","private":%s}\n' "$2" "$3" "$4" >"$work/repo/$1/package.json"
    fi
}
mkdir -p "$work/repo/pulumi/library/ts/packages" "$work/repo/mcp-slack" "$work/bin"

# npm stub: STUB_VERSIONS is "name=version,name=version"; absent => not published.
cat >"$work/bin/npm" <<'EOF'
#!/usr/bin/env bash
if [ "$1" = "view" ]; then
  for pair in ${STUB_VERSIONS//,/ }; do
    case "$pair" in "$2"=*) echo "${pair#*=}"; exit 0 ;; esac
  done
  exit 1
fi
exit 0
EOF
chmod +x "$work/bin/npm"

run() { # <stub versions> ; echoes "<rc>|<stdout>"
    local out rc
    out="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" \
        BUILD_WORKSPACE_DIRECTORY="$work/repo" STUB_VERSIONS="$1" \
        bash "$SCRIPT" 2>"$work/err")"
    rc=$?
    printf '%s|%s' "$rc" "$out"
}

mk "pulumi/library/ts/packages/a" "@v/a" "1.2.0" false "https://github.com/o/r.git" "ts/packages/a"
mk "pulumi/library/ts/packages/b" "@v/b" "0.3.0" false "https://github.com/o/r.git" "ts/packages/b"
mk "pulumi/library/ts/packages/priv" "@v/priv" "9.9.9" true "https://github.com/o/r.git" "ts/packages/priv"
mk "mcp-slack" "@v/mcp" "1.9.0" false

echo "--- everything current ---"
r="$(run '@v/a=1.2.0,@v/b=0.3.0,@v/mcp=1.9.0')"
[ "${r%%|*}" = "0" ] && printf '%s' "${r#*|}" | grep -q 'all 3 published'
check=$?
if [ "$check" = "0" ]; then pass "exits 0 and counts only the 3 public packages"; else fail "got rc=${r%%|*} out=${r#*|}"; fi

echo "--- a BEHIND package must fail ---"
r="$(run '@v/a=1.2.0,@v/b=0.2.0,@v/mcp=1.9.0')"
if [ "${r%%|*}" = "1" ]; then pass "a package behind the registry exits 1"; else fail "expected rc=1, got ${r%%|*}"; fi
if grep -q 'BEHIND' "$work/err" || printf '%s' "${r#*|}" | grep -q 'BEHIND'; then
    pass "...and names it as BEHIND"
else fail "no BEHIND marker in output"; fi

echo "--- a NEVER PUBLISHED package must fail ---"
r="$(run '@v/a=1.2.0,@v/mcp=1.9.0')"
if [ "${r%%|*}" = "1" ]; then pass "an unpublished package exits 1"; else fail "expected rc=1, got ${r%%|*}"; fi

echo "--- private packages are not audited ---"
r="$(run '@v/a=1.2.0,@v/b=0.3.0,@v/mcp=1.9.0')"
if [ "${r%%|*}" = "0" ]; then pass "a private package with no registry entry does not fail the audit"; else fail "private package leaked into the audit"; fi

echo "--- provenance preflight: a publish-blocking repository field must fail ---"
# Trusted publishing signs each publish; npm rejects with E422 when package.json
# does not declare a repository matching the provenance. That is discoverable
# WITHOUT publishing, and mcp-slack 1.10.0 found it the expensive way.
mk "mcp-slack" "@v/mcp" "1.9.0" false ""      # no repository at all
r="$(run '@v/a=1.2.0,@v/b=0.3.0,@v/mcp=1.9.0')"
if [ "${r%%|*}" = "1" ] && printf '%s' "${r#*|}" | grep -q 'NO repository.url'; then
    pass "a package with no repository.url fails before it can be published"
else
    fail "expected rc=1 and a NO repository.url line; got rc=${r%%|*}"
    sed 's/^/      /' "$work/err" >&2
fi
mk "mcp-slack" "@v/mcp" "1.9.0" false "https://github.com/o/r.git"   # restore

mk "pulumi/library/ts/packages/b" "@v/b" "0.3.0" false "https://github.com/o/r.git" "ts/packages/WRONG"
r="$(run '@v/a=1.2.0,@v/b=0.3.0,@v/mcp=1.9.0')"
if [ "${r%%|*}" = "1" ] && printf '%s' "${r#*|}" | grep -q 'repository.directory'; then
    pass "a repository.directory pointing at a sibling is caught"
else
    fail "expected rc=1 and a directory mismatch; got rc=${r%%|*}"
    sed 's/^/      /' "$work/err" >&2
fi
mk "pulumi/library/ts/packages/b" "@v/b" "0.3.0" false "https://github.com/o/r.git" "ts/packages/b"

echo
if [ "$fail_n" -gt 0 ]; then
    echo "FAILED: $fail_n"
    exit 1
fi
echo "ALL PASS ($pass_n)"
