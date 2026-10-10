#!/bin/bash
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

# An app Bazel built holds the copy of Mermaid its diagram cards draw with.
#
# The chat view is a library, and its copy of Mermaid reaches an app only
# because the library lists it as `data` and the app rule copies a library's
# data into Contents/Resources. Nothing fails when that stops: the app builds,
# signs and opens, and only its diagram cards say they cannot draw. So this
# opens the archive Bazel built and looks.
#
# Both Mac apps that show the chat run it, each on its own archive (the
# Vitruvian desktop app from its own BUILD file). The scripts beside this one
# check the app a SwiftPM release packages instead.
#
# Usage: bazel_app_holds_mermaid_test.sh <app name> <path>...
# The paths, in any order: the app rule's output (the .zip, or that name
# without the extension), and the two files the library ships (mermaid.min.js
# and mermaid-LICENSE.txt) as they are in the source tree.
set -euo pipefail

app_name="${1:?Usage: bazel_app_holds_mermaid_test.sh <app name> <path>...}"
shift

archive=""
script=""
licence=""
for path in "$@"; do
	case "$path" in
	*.zip) archive="$path" ;;
	*/mermaid.min.js) script="$path" ;;
	*/mermaid-LICENSE.txt) licence="$path" ;;
	*)
		# The app rule names its output without the extension; the archive
		# is beside that name.
		if [ -e "$path.zip" ]; then archive="$path.zip"; fi
		;;
	esac
done
for needed in archive script licence; do
	if [ -z "${!needed}" ]; then
		echo "no ${needed} among the paths given: $*" >&2
		exit 2
	fi
done

resources="${app_name}.app/Contents/Resources"
failed=0
for source in "$script" "$licence"; do
	name="$(basename "$source")"
	inside="${resources}/${name}"
	want="$(shasum -a 256 "$source" | awk '{print $1}')"
	# The file's bytes straight from the archive. A file that is not there
	# makes unzip fail, and is reported as missing rather than as a hash of
	# nothing.
	if ! unzip -p "$archive" "$inside" >"$TEST_TMPDIR/$name" 2>/dev/null; then
		echo "FAIL: ${inside} is not in $(basename "$archive")" >&2
		failed=1
		continue
	fi
	got="$(shasum -a 256 "$TEST_TMPDIR/$name" | awk '{print $1}')"
	if [ "$got" != "$want" ]; then
		echo "FAIL: ${inside} is not the file in the source tree: SHA-256 ${got}, expected ${want}" >&2
		failed=1
		continue
	fi
	echo "ok: ${inside} (SHA-256 ${got})"
done

if [ "$failed" -ne 0 ]; then
	echo "$(basename "$archive") holds, under Contents/Resources:" >&2
	unzip -Z1 "$archive" "${resources}/*" >&2 || true
	exit 1
fi
