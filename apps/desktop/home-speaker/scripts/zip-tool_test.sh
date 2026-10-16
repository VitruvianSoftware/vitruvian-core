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
# bin/tool runnable, no folder of its own and no links; the name the
# packaging helper uploads; and it refuses a version the manifest does not
# say. With the release's Google sign-in client in its environment it also
# ships google-oauth-client.json, holding both values; without it, no such
# file. Run against a stand-in binary and made-up client values; nothing is
# built.
set -euo pipefail

here="$TEST_SRCDIR/$TEST_WORKSPACE/apps/desktop/home-speaker"
version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$here/tool/vitruvian-tool.json" | head -1)"
work="$TEST_TMPDIR/work"
mkdir -p "$work"
printf '#!/bin/sh\necho tool\n' >"$work/tool-binary"
chmod 755 "$work/tool-binary"

# No sign-in client in the environment: the zip holds no client file.
out="$(env -u HOMESPEAKER_GOOGLE_CLIENT_ID -u HOMESPEAKER_GOOGLE_CLIENT_SECRET \
	bash "$here/scripts/zip-tool.sh" "$work/tool-binary" "$version" "$work/dist")"
asset="$work/dist/HomeSpeaker-$version-tool.zip"
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
test "$listed" = "bin/ bin/tool vitruvian-tool.json " || {
	echo "the zip holds: $listed"
	exit 1
}
mkdir -p "$work/unpacked"
unzip -q "$asset" -d "$work/unpacked"
test -x "$work/unpacked/bin/tool" || {
	echo "bin/tool is not runnable"
	exit 1
}
test "$("$work/unpacked/bin/tool")" = "tool" || {
	echo "bin/tool is not the binary given"
	exit 1
}

# The release's sign-in client, as publish.sh inherits it from the release
# job: the zip holds google-oauth-client.json with both values, which the
# extension reads beside its program (OAuthClientFile). A quote and a
# backslash in the made-up secret must survive as JSON.
client_id="made-up-client.apps.googleusercontent.com"
client_secret='made-up "secret" \ value' # gitleaks:allow
HOMESPEAKER_GOOGLE_CLIENT_ID="$client_id" HOMESPEAKER_GOOGLE_CLIENT_SECRET="$client_secret" \
	bash "$here/scripts/zip-tool.sh" "$work/tool-binary" "$version" "$work/dist-client" >/dev/null
client_asset="$work/dist-client/HomeSpeaker-$version-tool.zip"
listed="$(unzip -Z1 "$client_asset" | sort | tr '\n' ' ')"
test "$listed" = "bin/ bin/tool google-oauth-client.json vitruvian-tool.json " || {
	echo "with a sign-in client, the zip holds: $listed"
	exit 1
}
mkdir -p "$work/unpacked-client"
unzip -q "$client_asset" -d "$work/unpacked-client"
client_file="$work/unpacked-client/google-oauth-client.json"
test "$(plutil -extract client_id raw -o - "$client_file")" = "$client_id" || {
	echo "google-oauth-client.json does not hold the client id: $(cat "$client_file")"
	exit 1
}
test "$(plutil -extract client_secret raw -o - "$client_file")" = "$client_secret" || {
	echo "google-oauth-client.json does not hold the client secret"
	exit 1
}

# publish.sh gives the dist folder as `./dist`, a path relative to where it
# runs. The zip is made from inside a staging folder, so a relative path that
# was not made whole first named a file there: "Could not create output
# file", and the release's macOS build failed (PR #3211's first run).
mkdir -p "$work/elsewhere"
(cd "$work/elsewhere" && bash "$here/scripts/zip-tool.sh" "$work/tool-binary" "$version" ./dist >/dev/null) || {
	echo "a dist folder given as ./dist is refused"
	exit 1
}
test -f "$work/elsewhere/dist/HomeSpeaker-$version-tool.zip" || {
	echo "a dist folder given as ./dist: no zip in it"
	exit 1
}

if bash "$here/scripts/zip-tool.sh" "$work/tool-binary" "0.0.1" "$work/dist2" >/dev/null 2>&1; then
	echo "a version the manifest does not say was accepted"
	exit 1
fi
echo "zip-tool: OK (HomeSpeaker-$version-tool.zip, with the manifest at the top, and the sign-in client only when given)"
