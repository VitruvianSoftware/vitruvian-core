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

# zip-tool.sh writes the zip the catalog pins: the manifest at the top,
# bin/tool and bin/vitruvian-remote-agent runnable, no folder of its own and
# no links, under the name the release uploads; it refuses a version the
# manifest does not say, and, when the release asks for universal programs,
# either program that is not one. Run against stand-in programs and a
# stand-in `lipo`; nothing is built and nothing real is run.
set -euo pipefail

here="$TEST_SRCDIR/$TEST_WORKSPACE/apps/mobile/android-remote/macmenu"
version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$here/tool/vitruvian-tool.json" | head -1)"
work="$TEST_TMPDIR/work"
mkdir -p "$work/bin"
# Each stand-in program says which it is, and, on its second line, the
# architectures the stand-in lipo below reports for it.
stand_in() {
	printf '#!/bin/sh\n# archs: %s\necho %s\n' "$2" "$1" >"$work/$1"
	chmod 755 "$work/$1"
}
stand_in tool "x86_64 arm64"
stand_in agent "x86_64 arm64"
stand_in thin-agent "arm64"
cat >"$work/bin/lipo" <<'LIPO'
#!/bin/sh
# lipo -archs <file>: the architectures the stand-in's second line names.
[ "$1" = "-archs" ] || exit 2
sed -n '2s/^# archs: //p' "$2"
LIPO
chmod 755 "$work/bin/lipo"

out="$(bash "$here/scripts/zip-tool.sh" "$work/tool" "$work/agent" "$version" "$work/dist")"
asset="$work/dist/VitruvianRemote-$version-tool.zip"
test -f "$asset" || {
	echo "no $asset"
	exit 1
}
grep -q '^size: [0-9][0-9]*$' <<<"$out" || {
	echo "no size line: $out"
	exit 1
}
grep -qE '^sha256: [0-9a-f]{64}$' <<<"$out" || {
	echo "no sha256 line: $out"
	exit 1
}
listed="$(unzip -Z1 "$asset" | sort | tr '\n' ' ')"
test "$listed" = "bin/ bin/tool bin/vitruvian-remote-agent vitruvian-tool.json " || {
	echo "the zip holds: $listed"
	exit 1
}
# No links: every entry is a folder or a plain file (zipinfo's first column).
if unzip -Z "$asset" | grep -q '^l'; then
	echo "the zip holds a link: $(unzip -Z "$asset")"
	exit 1
fi
mkdir -p "$work/unpacked"
unzip -q "$asset" -d "$work/unpacked"
for program in tool vitruvian-remote-agent; do
	test -x "$work/unpacked/bin/$program" || {
		echo "bin/$program is not runnable"
		exit 1
	}
done
test "$("$work/unpacked/bin/tool")" = "tool" || {
	echo "bin/tool is not the program given as the tool"
	exit 1
}
test "$("$work/unpacked/bin/vitruvian-remote-agent")" = "agent" || {
	echo "bin/vitruvian-remote-agent is not the program given as the agent"
	exit 1
}
cmp -s "$work/unpacked/vitruvian-tool.json" "$here/tool/vitruvian-tool.json" || {
	echo "the zip's vitruvian-tool.json is not tool/vitruvian-tool.json"
	exit 1
}

# The release passes the dist folder as a relative path. The zip is made from
# inside a staging folder, so a relative path that was not made whole first
# would name a file there (HomeSpeaker's release failed that way, PR #3211).
mkdir -p "$work/elsewhere"
(cd "$work/elsewhere" && bash "$here/scripts/zip-tool.sh" "$work/tool" "$work/agent" "$version" ./dist >/dev/null) || {
	echo "a dist folder given as ./dist is refused"
	exit 1
}
test -f "$work/elsewhere/dist/VitruvianRemote-$version-tool.zip" || {
	echo "a dist folder given as ./dist: no zip in it"
	exit 1
}

if bash "$here/scripts/zip-tool.sh" "$work/tool" "$work/agent" "0.0.1" "$work/dist-wrong-version" >/dev/null 2>&1; then
	echo "a version the manifest does not say was accepted"
	exit 1
fi

# What the release asks for: both programs universal. Both are, and it zips.
PATH="$work/bin:$PATH" REMOTE_TOOL_REQUIRE_UNIVERSAL=1 \
	bash "$here/scripts/zip-tool.sh" "$work/tool" "$work/agent" "$version" "$work/dist-universal" >/dev/null || {
	echo "two universal programs were refused"
	exit 1
}
# The agent holds only Apple silicon code: refused, naming it, and no zip.
if err="$(PATH="$work/bin:$PATH" REMOTE_TOOL_REQUIRE_UNIVERSAL=1 \
	bash "$here/scripts/zip-tool.sh" "$work/tool" "$work/thin-agent" "$version" "$work/dist-thin" 2>&1 >/dev/null)"; then
	echo "an agent with only Apple silicon code was accepted"
	exit 1
fi
grep -q "thin-agent" <<<"$err" || {
	echo "the refusal does not name the program: $err"
	exit 1
}
test ! -e "$work/dist-thin/VitruvianRemote-$version-tool.zip" || {
	echo "a refused build still left a zip"
	exit 1
}
echo "zip-tool: OK (VitruvianRemote-$version-tool.zip: the manifest at the top, bin/tool and bin/vitruvian-remote-agent)"
