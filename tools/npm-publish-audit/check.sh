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

# check.sh — compare every PUBLIC npm package in this repo against what is
# actually on the registry, and fail if any is behind.
#
# WHY THIS EXISTS. Publishing broke on 2026-05-07 and said nothing for three
# months. The release job swallowed npm publish failures with a warning and
# exited 0, so the workflow reported success while ALL 31 public packages fell
# behind and three were never published at all. A green pipeline and a published
# package had quietly stopped being the same thing, and nothing could tell them
# apart -- not even the mirror alerting, which keys on a run concluding failure.
#
# This is the falsifiable check for that: it asks the registry, not the
# pipeline. Fixed in #1861 (fail on real publish errors) and migrated to trusted
# publishing in the same series; this asserts the OUTCOME rather than the
# mechanism, so it stays true whatever we authenticate with next.
#
# Usage:  bazel run //tools/npm-publish-audit:check
# Env:    NPM (default npm), ROOTS (default the two publishing roots)
# Exit:   0 all current · 1 something is behind · 2 setup error
set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
NPM="${NPM:-npm}"
command -v "$NPM" >/dev/null 2>&1 || {
    echo "npm-publish-audit: npm not on PATH" >&2
    exit 2
}

# Every package.json that is a PUBLISHED package: public, versioned, and under a
# root we actually publish from. `private: true` packages are skipped by design.
manifests="$(find pulumi/library/ts/packages mcp-slack -maxdepth 2 -name package.json \
    -not -path '*/node_modules/*' 2>/dev/null | sort)"
[ -n "$manifests" ] || {
    echo "npm-publish-audit: found no package manifests -- the layout moved" >&2
    exit 2
}

# Provenance preflight. Trusted publishing signs every publish with a sigstore
# provenance bundle, and npm REJECTS the publish (E422) when package.json does
# not declare a repository matching the one the provenance came from:
#
#   422 Unprocessable Entity - Error verifying sigstore provenance bundle:
#   package.json: "repository.url" is "", expected to match
#   "https://github.com/VitruvianSoftware/mcp-slack" from provenance
#
# That is a publish-blocking defect discoverable WITHOUT publishing, so check it
# here rather than finding out at release time -- which is how mcp-slack 1.10.0
# failed. A wrong `directory` is not itself fatal but points consumers at the
# wrong source, and 10 of 31 packages had one copy-pasted from a sibling.
prov_bad=0

# <manifest> <expected-directory-or-empty>
check_provenance() {
    _mf="$1"
    _want_dir="$2"
    _url="$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
r=d.get("repository") or {}
print(r if isinstance(r,str) else (r.get("url") or ""))
' "$_mf")"
    if [ -z "$_url" ]; then
        printf '  %-56s NO repository.url -- provenance publish will be REJECTED\n' "$_mf"
        prov_bad=$((prov_bad + 1))
        return
    fi
    if [ -n "$_want_dir" ]; then
        _dir="$(python3 -c '
import json,sys
print(((json.load(open(sys.argv[1])).get("repository") or {}).get("directory")) or "")
' "$_mf")"
        if [ "$_dir" != "$_want_dir" ]; then
            printf '  %-56s repository.directory=%s want=%s\n' "$_mf" "${_dir:-<none>}" "$_want_dir"
            prov_bad=$((prov_bad + 1))
        fi
    fi
}

behind=0
checked=0
while IFS= read -r mf; do
    [ -n "$mf" ] || continue
    read -r name version private <<EOF2
$(python3 -c '
import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("name",""), d.get("version",""), str(bool(d.get("private",False))).lower())
' "$mf")
EOF2
    [ -n "$name" ] && [ "$private" = "false" ] || continue
    [ -n "$version" ] || continue
    checked=$((checked + 1))
    case "$mf" in
        pulumi/library/ts/packages/*) check_provenance "$mf" "ts/packages/$(basename "$(dirname "$mf")")" ;;
        *) check_provenance "$mf" "" ;;
    esac
    live="$("$NPM" view "$name" dist-tags.latest 2>/dev/null || true)"
    if [ -z "$live" ]; then
        printf '  %-56s repo=%-10s registry=NOT PUBLISHED\n' "$name" "$version"
        behind=$((behind + 1))
    elif [ "$live" != "$version" ]; then
        printf '  %-56s repo=%-10s registry=%s  BEHIND\n' "$name" "$version" "$live"
        behind=$((behind + 1))
    fi
done <<EOF3
$manifests
EOF3

if [ "$prov_bad" -gt 0 ]; then
    echo "npm-publish-audit: $prov_bad package(s) have a repository field that will fail provenance verification." >&2
    echo "  Trusted publishing signs each publish; npm rejects it with E422 when this does not match." >&2
    exit 1
fi
if [ "$behind" -gt 0 ]; then
    echo "npm-publish-audit: $behind of $checked package(s) are not on the registry at their repo version." >&2
    echo "  A release that reported success but published nothing looks exactly like this." >&2
    echo "  See docs/engineering/npm-trusted-publishing.md." >&2
    exit 1
fi
echo "npm-publish-audit: all $checked published package(s) match the registry."
