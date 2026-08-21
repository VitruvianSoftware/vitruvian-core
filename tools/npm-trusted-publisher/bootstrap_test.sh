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

# Tests for bootstrap.sh with a stubbed npm.
#
# This publishes to a PUBLIC registry and npm restricts unpublish to 72h, so the
# properties worth pinning are the ones that prevent a bad publish. The sharpest
# one is the manifest guard: in the monorepo a dependency is written
# `"@pulumi/gcp": "catalog:"`, a pnpm-only protocol, and publishing that would
# upload a package NO consumer can install. The first version of this script
# published from the monorepo tree and was one working build away from doing it.
set -uo pipefail

SCRIPT="${1:?usage: bootstrap_test.sh <path to bootstrap.sh>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
pass_n=0; fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

# A stand-in for the MIRROR checkout: concrete versions, as copybara exports.
mk() { # <dir> <name> <depspec> [private]
  mkdir -p "$work/mirror/ts/packages/$1"
  python3 -c '
import json,sys
d={"name":sys.argv[2],"version":"0.4.0","main":"dist/index.js",
   "dependencies":{"@pulumi/gcp":sys.argv[3]}}
if len(sys.argv)>4 and sys.argv[4]=="private": d["private"]=True
json.dump(d,open(sys.argv[1],"w"))' "$work/mirror/ts/packages/$1/package.json" "$2" "$3" "${4:-}"
}
mkdir -p "$work/repo" "$work/bin" "$work/mirror/ts"
mk new  "@v/new"  "^8.0.0"
mk old  "@v/old"  "^8.0.0"
mk priv "@v/priv" "^8.0.0" private

cat >"$work/bin/npm" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  whoami) [ -n "${STUB_LOGGED_IN:-}" ] && { echo ipv1337; exit 0; }; exit 1 ;;
  login)  echo "login" >>"$CALLS"; exit 0 ;;
  view)   for n in ${STUB_ON_REGISTRY:-}; do [ "$n" = "$2" ] && exit 0; done; exit 1 ;;
  install) echo "install" >>"$CALLS"; exit 0 ;;
  run)    echo "build" >>"$CALLS"; [ -n "${STUB_BUILD_FAILS:-}" ] && exit 1; exit 0 ;;
  publish) echo "publish:$PWD" >>"$CALLS"
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
        BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" \
        MIRROR_DIR="$work/mirror" SETUP_SH="$work/bin/fake_setup.sh" NPM_TP_TTY_OK=1 \
        ${envs[@]+"${envs[@]}"} bash "$SCRIPT" ${args[@]+"${args[@]}"} 2>&1 </dev/null)"
    rc=$?
}

echo "--- THE guard: never publish a spec a consumer cannot resolve ---"
# `catalog:` is pnpm-only. Publishing it yields EUNSUPPORTEDPROTOCOL for every
# consumer, and npm only allows unpublish for 72h. Copybara rewrites these on
# export; if one survives, the rewrite regressed and we must stop.
for proto in "catalog:" "workspace:^1.0.0" "file:../x" "link:../x"; do
    mk new "@v/new" "$proto"
    run STUB_LOGGED_IN=1 STUB_ON_REGISTRY="@v/old" --
    if [ "$rc" != "0" ] && ! grep -q 'publish:' "$work/calls"; then
        pass "refuses to publish a \"$proto\" dependency"
    else
        fail "published an unresolvable \"$proto\" dep: rc=$rc $(tr '\n' ';' <"$work/calls")"
    fi
done
# The refusal message is read by someone deciding whether to override a safety
# guard. An unquoted expansion split each finding across four lines; keep each
# finding on ONE line so the offending dep and its spec stay together.
mk new "@v/new" "catalog:"
run STUB_LOGGED_IN=1 STUB_ON_REGISTRY="@v/old" --
if printf '%s' "$out" | grep -qE '@pulumi/gcp -> catalog: \(dependencies\)'; then
    pass "each offending dependency is reported on one readable line"
else
    fail "refusal message is mangled: $(printf '%s' "$out" | grep -A4 'cannot resolve' | tr '\n' '|')"
fi

mk new "@v/new" "^8.0.0"   # restore a publishable manifest

echo "--- publishes from the MIRROR tree, never from the monorepo ---"
run STUB_LOGGED_IN=1 STUB_ON_REGISTRY="@v/old" --
if grep -q "publish:$work/mirror/ts/packages/new" "$work/calls"; then
    pass "publishes out of the mirror checkout, where catalog: is already rewritten"
else
    fail "did not publish from the mirror: $(tr '\n' ';' <"$work/calls")"
fi
if grep -q "publish:$work/repo" "$work/calls"; then
    fail "published from the monorepo tree — that ships catalog: to the registry"
else
    pass "never publishes from the monorepo tree"
fi

echo "--- only never-published, non-private packages are candidates ---"
if grep -q 'packages/new' "$work/calls" && ! grep -q 'packages/old' "$work/calls"; then
    pass "publishes the missing package and leaves the existing one alone"
else
    fail "wrong publish set: $(tr '\n' ';' <"$work/calls")"
fi
if grep -q 'packages/priv' "$work/calls"; then
    fail "published a PRIVATE package"
else
    pass "a private package is never published"
fi

echo "--- build must precede publish ---"
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
    BUILD_WORKSPACE_DIRECTORY="$work/repo" CALLS="$work/calls" MIRROR_DIR="$work/mirror" \
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
