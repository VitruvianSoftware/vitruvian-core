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

# Tests for check-version-maps.sh against synthetic trees.
#
# The properties that matter are the two ways these maps go wrong in practice:
# an entry that drifts behind the repo (all 28 ts entries had), and a package the
# example uses that was never ADDED to the map (which leaves `workspace:*` in the
# exported mirror, unresolvable by npm).
set -uo pipefail
SCRIPT="${1:?usage: check_version_maps_test.sh <path to check-version-maps.sh>}"
SCRIPT="$(cd "$(dirname "$SCRIPT")" && pwd)/$(basename "$SCRIPT")"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
pass_n=0; fail_n=0
pass() { echo "  ✓ $1"; pass_n=$((pass_n + 1)); }
fail() { echo "  ✗ $1" >&2; fail_n=$((fail_n + 1)); }

mkpkg() { mkdir -p "$work/ts/$1"; printf '{"name":"@vitruviansoftware/foundation-%s","version":"%s"}\n' "$1" "$2" >"$work/ts/$1/package.json"; }
mkgo()  { mkdir -p "$work/go/$1"; printf '{"pulumi/library/go/pkg/%s":"%s"}\n' "$1" "$2" >"$work/go/$1/.release-please-manifest.json"; }
mkex()  { mkdir -p "$work/example"; python3 -c '
import json,sys
deps={("@vitruviansoftware/foundation-"+d):"workspace:*" for d in sys.argv[2:]}
json.dump({"name":"example","dependencies":deps}, open(sys.argv[1],"w"))' "$work/example/package.json" "$@"; }

sky() { # <ts entries> <go entries>
    cat >"$work/copy.bara.sky" <<EOF
_TS_EXAMPLE_LIB_VERSIONS = {
$1
}
_GO_EXAMPLE_LIB_VERSIONS = {
$2
}
EOF
}

run() {
    out="$(env SKY="$work/copy.bara.sky" TS_ROOT="$work/ts" GO_ROOT="$work/go" \
        TS_EXAMPLE="$work/example" BUILD_WORKSPACE_DIRECTORY="$work" \
        bash "$SCRIPT" 2>&1)"; rc=$?
}

mkpkg bootstrap 0.4.0; mkpkg network 0.5.0
mkgo  bootstrap 2.1.4; mkgo  iam 0.6.2
mkex  bootstrap network

echo "--- a map matching the repo passes ---"
sky '    "bootstrap": "0.4.0",
    "network": "0.5.0",' '    "bootstrap/v2": "2.1.4",
    "iam": "0.6.2",'
run
if [ "$rc" = "0" ]; then pass "in-sync maps exit 0"; else fail "clean maps rejected: $out"; fi

echo "--- a drifted ts entry is caught ---"
sky '    "bootstrap": "0.2.1",
    "network": "0.5.0",' '    "bootstrap/v2": "2.1.4",
    "iam": "0.6.2",'
run
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q 'ts  bootstrap.*map=0.2.1.*repo=0.4.0'; then
    pass "a stale ts version is reported with both values"
else
    fail "drift not caught: rc=$rc $(printf '%s' "$out" | tr '\n' '|')"
fi

echo "--- a drifted go entry is caught, including a /vN module path ---"
# `bootstrap/v2` is a Go major-version module path; the manifest lives at
# go/pkg/bootstrap. Naive lookup would report "no manifest" and mask real drift.
sky '    "bootstrap": "0.4.0",
    "network": "0.5.0",' '    "bootstrap/v2": "2.1.2",
    "iam": "0.6.2",'
run
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q 'go  bootstrap/v2.*map=2.1.2.*repo=2.1.4'; then
    pass "a /vN module key resolves to its manifest and drift is reported"
else
    fail "go drift not caught: rc=$rc $(printf '%s' "$out" | tr '\n' '|')"
fi

echo "--- a package the example uses but the map omits is caught ---"
# This is the failure that ships a mirror still containing `workspace:*`.
sky '    "bootstrap": "0.4.0",' '    "bootstrap/v2": "2.1.4",
    "iam": "0.6.2",'
run
if [ "$rc" != "0" ] && printf '%s' "$out" | grep -q 'network.*ABSENT from the map'; then
    pass "a missing entry is reported, not silently exported as workspace:*"
else
    fail "omission not caught: rc=$rc $(printf '%s' "$out" | tr '\n' '|')"
fi

echo "--- an unparseable file fails loudly, not silently green ---"
printf 'nothing here\n' >"$work/copy.bara.sky"
run
if [ "$rc" = "2" ]; then pass "a map that cannot be parsed exits 2"; else fail "unparseable file gave rc=$rc"; fi

echo
if [ "$fail_n" -gt 0 ]; then echo "FAILED: $fail_n"; exit 1; fi
echo "ALL PASS ($pass_n)"
