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

# Tests for bootstrap.sh with a stubbed npm. This publishes to a PUBLIC registry
# and npm restricts unpublish to a 72h window, so the properties worth pinning
# are the ones that prevent an unwanted publish: never touch a package that is
# already there, never touch a private one, and never publish before the build
# (main is dist/index.js -- publishing first ships a broken entry point that npm
# accepts without complaint).
set -uo pipefail

SCRIPT="${1:?usage: bootstrap_test.sh <path to bootstrap.sh>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0; fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

mkdir -p "$work/repo/ts/packages/new" "$work/repo/ts/packages/old" \
         "$work/repo/ts/packages/priv" "$work/bin"
printf '{"name":"@v/new","version":"0.4.0"}\n'  >"$work/repo/ts/packages/new/package.json"
printf '{"name":"@v/old","version":"0.4.0"}\n'  >"$work/repo/ts/packages/old/package.json"
printf '{"name":"@v/priv","version":"0.4.0","private":true}\n' >"$work/repo/ts/packages/priv/package.json"

cat >"$work/bin/npm" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  whoami) [ -n "${STUB_LOGGED_IN:-}" ] && { echo ipv1337; exit 0; }; exit 1 ;;
  login)  echo "login" >>"$CALLS"; exit 0 ;;
  view)   for n in ${STUB_ON_REGISTRY:-}; do [ "$n" = "$2" ] && exit 0; done; exit 1 ;;
  install) echo "install" >>"$CALLS"; exit 0 ;;
  run)    echo "build" >>"$CALLS"; [ -n "${STUB_BUILD_FAILS:-}" ] && exit 1; exit 0 ;;
  publish) echo "publish:$(basename "$PWD")" >>"$CALLS"
           [ -n "${STUB_PUBLISH_FAILS:-}" ] && exit 1; exit 0 ;;
esac
exit 0
EOF
chmod +x "$work/bin/npm"
printf '#!/usr/bin/env bash\necho SETUP_RAN\n' >"$work/bin/fake_setup.sh"
chmod +x "$work/bin/fake_setup.sh"

run() { # <env...> -- <args...>
    : >"$work/calls"
    local envs=() args=()
    while [ "$#" -gt 0 ]; do [ "$1" = "--" ] && { shift; break; }; envs+=("$1"); shift; done
    [ "$#" -gt 0 ] && args=("$@")
    out="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" \
        BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" TS_DIR=ts \
        SETUP_SH="$work/bin/fake_setup.sh" NPM_TP_TTY_OK=1 \
        ${envs[@]+"${envs[@]}"} bash "$SCRIPT" ${args[@]+"${args[@]}"} 2>&1 </dev/null)"
    rc=$?
}

echo "--- only never-published, non-private packages are candidates ---"
run STUB_LOGGED_IN=1 STUB_ON_REGISTRY="@v/old" --
if grep -q 'publish:new' "$work/calls" && ! grep -q 'publish:old' "$work/calls"; then
    pass "publishes the missing package and leaves the existing one alone"
else
    fail "wrong publish set: $(tr '\n' ';' <"$work/calls")"
fi
if grep -q 'publish:priv' "$work/calls"; then
    fail "published a PRIVATE package"
else
    pass "a private package is never published"
fi

echo "--- build must precede publish ---"
# main is dist/index.js. Publishing first uploads a package with no entry point,
# and npm accepts it, so this ordering is the difference between a working
# package and a broken one that looks fine.
_b="$(grep -n 'build' "$work/calls" | head -1 | cut -d: -f1)"
_p="$(grep -n 'publish:' "$work/calls" | head -1 | cut -d: -f1)"
if [ -n "$_b" ] && [ -n "$_p" ] && [ "$_b" -lt "$_p" ]; then
    pass "the workspace is built before anything is published"
else
    fail "published before building: $(tr '\n' ';' <"$work/calls")"
fi

echo "--- hand-off to setup.sh ---"
if printf '%s' "$out" | grep -q 'SETUP_RAN'; then
    pass "hands off so the new package gets a trusted publisher immediately"
else
    fail "no hand-off; the next release would fail exactly as before"
fi

echo "--- nothing to do is a clean no-op ---"
run STUB_LOGGED_IN=1 STUB_ON_REGISTRY="@v/new @v/old" --
if [ "$rc" = "0" ] && [ ! -s "$work/calls" ]; then
    pass "everything already on the registry: no build, no publish, exit 0"
else
    fail "did work when there was none: rc=$rc $(tr '\n' ';' <"$work/calls")"
fi

echo "--- dry run touches nothing ---"
run STUB_LOGGED_IN=1 STUB_ON_REGISTRY="@v/old" -- --dry-run
if [ "$rc" = "0" ] && ! grep -qE 'publish:|build' "$work/calls"; then
    pass "--dry-run neither builds nor publishes"
else
    fail "--dry-run had effects: rc=$rc $(tr '\n' ';' <"$work/calls")"
fi

echo "--- a failed build must not publish ---"
run STUB_LOGGED_IN=1 STUB_ON_REGISTRY="@v/old" STUB_BUILD_FAILS=1 --
if [ "$rc" != "0" ] && ! grep -q 'publish:' "$work/calls"; then
    pass "a broken build stops the run before any publish"
else
    fail "published despite a failed build: rc=$rc $(tr '\n' ';' <"$work/calls")"
fi

echo "--- a failed publish is reported and blocks the hand-off ---"
run STUB_LOGGED_IN=1 STUB_ON_REGISTRY="@v/old" STUB_PUBLISH_FAILS=1 --
if [ "$rc" != "0" ] && ! printf '%s' "$out" | grep -q 'SETUP_RAN'; then
    pass "a failed publish exits non-zero and does not claim success"
else
    fail "a failed publish was swallowed: rc=$rc"
fi

echo "--- refuses to act without a login ---"
: >"$work/calls"
out="$(cd "$work/repo" && env PATH="$work/bin:/usr/bin:/bin" \
    BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" TS_DIR=ts \
    SETUP_SH="$work/bin/fake_setup.sh" STUB_ON_REGISTRY="@v/old" \
    bash "$SCRIPT" --no-login 2>&1 </dev/null)"; rc=$?
if [ "$rc" != "0" ] && ! grep -q 'publish:' "$work/calls"; then
    pass "--no-login refuses rather than attempting an unauthenticated publish"
else
    fail "proceeded without a login: rc=$rc"
fi

echo
if [ "$fail_n" -gt 0 ]; then echo "FAILED: $fail_n"; exit 1; fi
echo "ALL PASS ($pass_n)"
