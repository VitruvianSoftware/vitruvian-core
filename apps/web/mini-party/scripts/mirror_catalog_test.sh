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

# The mirror installs with plain npm, so the export rewrites every
# `"<dep>": "catalog:"` in package.json to the version in
# _MINI_PARTY_CATALOG_VERSIONS (tools/copybara/copy.bara.sky). This checks
# each such dep has an entry there, equal to the root pnpm catalog's.
set -euo pipefail
package_json="$1"
workspace="$2"
copybara="$3"

deps=$(sed -n 's/^ *"\([^"]*\)": "catalog:".*/\1/p' "$package_json")
if [ -z "$deps" ]; then
	echo "OK: package.json uses no catalog: versions"
	exit 0
fi

# The `_MINI_PARTY_CATALOG_VERSIONS = { ... }` block.
map=$(sed -n '/^_MINI_PARTY_CATALOG_VERSIONS = {/,/^}/p' "$copybara")
# The top-level `catalog:` block of pnpm-workspace.yaml (two-space entries).
catalog=$(sed -n '/^catalog:/,/^[^ ]/p' "$workspace")

status=0
for dep in $deps; do
	want=$(printf '%s\n' "$catalog" | sed -n "s/^  \"\{0,1\}$dep\"\{0,1\}: *\(.*\)$/\1/p" | head -1)
	got=$(printf '%s\n' "$map" | sed -n "s/^ *\"$dep\": \"\([^\"]*\)\",\{0,1\}$/\1/p" | head -1)
	if [ -z "$want" ]; then
		echo "FAIL: $dep is catalog: in package.json but not in the pnpm catalog" >&2
		status=1
	elif [ "$got" != "$want" ]; then
		echo "FAIL: $dep: the mirror export writes '${got:-nothing}', the catalog says '$want'" >&2
		echo "      fix _MINI_PARTY_CATALOG_VERSIONS in tools/copybara/copy.bara.sky" >&2
		status=1
	fi
done
[ "$status" -eq 0 ] && echo "OK: mirror versions match the catalog for: $deps"
exit "$status"
