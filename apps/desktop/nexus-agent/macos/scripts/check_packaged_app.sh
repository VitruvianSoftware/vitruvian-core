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

set -euo pipefail

# check_packaged_app.sh — Is this NexusAgent.app one a release may publish?
# Usage: ./check_packaged_app.sh <path to NexusAgent.app> <architecture>...
#
# Example: ./check_packaged_app.sh /tmp/dist-universal/NexusAgent.app arm64 x86_64
#
# bundle.sh stops when the chat view's resources are missing beside the
# executable. This looks at what came out instead, the way the app will:
# - the copy of Mermaid is where NexusAgentMermaidPage looks for it, and is
#   the file THIRD_PARTY_NOTICES.md records, byte for byte;
# - Mermaid's licence is beside it;
# - the executable can be run and is built for exactly the named processors;
# - the signature covers everything in the bundle.
# The app is read, never opened.

APP="${1:?Usage: check_packaged_app.sh <NexusAgent.app> <architecture>...}"
shift
if [ "$#" -eq 0 ]; then
	echo "error: name the architectures the executable must have" >&2
	exit 2
fi
WANT_ARCHS="$(printf '%s\n' "$@" | sort | tr '\n' ' ')"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NOTICES="${SCRIPT_DIR}/../../THIRD_PARTY_NOTICES.md"
SCRIPT_NAME="mermaid.min.js"
LICENCE_NAME="mermaid-LICENSE.txt"
UI_RESOURCES="NexusAgent_NexusAgentUI.bundle"
EXECUTABLE="${APP}/Contents/MacOS/NexusAgent"

fail() {
	echo "error: $*" >&2
	if [ -d "${APP}" ]; then
		echo "       ${APP} holds:" >&2
		(cd "${APP}" && find . -type f | sort | sed 's/^/         /' >&2)
	fi
	exit 1
}

echo "==> Checking ${APP}"
[ -d "${APP}" ] || fail "no app at ${APP}"

# The hash is written down once, in the notices, where a person bumping
# Mermaid updates it. A row that is missing or reworded fails here rather than
# letting every app pass against an empty value. (The backquotes are the
# table's own, matched as text.)
# shellcheck disable=SC2016
WANT_SHA="$(sed -n 's/^| SHA-256 of the file | `\([0-9a-f]\{64\}\)` |$/\1/p' "${NOTICES}")"
[ "${#WANT_SHA}" -eq 64 ] || fail "no 'SHA-256 of the file' row with one hash in ${NOTICES}"

# The places NexusAgentMermaidPage.scriptDirectories(for:) tries, in its
# order: the app's resources, then the executable's folder; in each, the
# folder itself, SwiftPM's resource folder, and that folder laid out as a
# bundle. Keep this list in step with that function.
FOUND=""
for root in "${APP}/Contents/Resources" "${APP}/Contents/MacOS"; do
	for dir in "${root}" "${root}/${UI_RESOURCES}" "${root}/${UI_RESOURCES}/Contents/Resources"; do
		if [ -z "${FOUND}" ] && [ -r "${dir}/${SCRIPT_NAME}" ]; then
			FOUND="${dir}"
		fi
	done
done
[ -n "${FOUND}" ] || fail "${SCRIPT_NAME} is in none of the places the app looks"
echo "    ✓ ${SCRIPT_NAME} found in ${FOUND#"${APP}/"}"

GOT_SHA="$(shasum -a 256 "${FOUND}/${SCRIPT_NAME}" | awk '{print $1}')"
[ "${GOT_SHA}" = "${WANT_SHA}" ] ||
	fail "${SCRIPT_NAME} is not the recorded file: SHA-256 ${GOT_SHA}, THIRD_PARTY_NOTICES.md says ${WANT_SHA}"
echo "    ✓ it is the recorded file (SHA-256 ${GOT_SHA})"

[ -s "${FOUND}/${LICENCE_NAME}" ] || fail "${LICENCE_NAME} is missing or empty beside ${SCRIPT_NAME}"
echo "    ✓ ${LICENCE_NAME} is beside it"

[ -f "${EXECUTABLE}" ] || fail "no executable at Contents/MacOS/NexusAgent"
[ -x "${EXECUTABLE}" ] || fail "Contents/MacOS/NexusAgent is not executable"
GOT_ARCHS="$(lipo -archs "${EXECUTABLE}" | tr ' ' '\n' | sed '/^$/d' | sort | tr '\n' ' ')"
[ "${GOT_ARCHS}" = "${WANT_ARCHS}" ] ||
	fail "the executable is built for '${GOT_ARCHS% }', expected '${WANT_ARCHS% }'"
echo "    ✓ executable, built for ${GOT_ARCHS% }"

# bundle.sh signs the whole bundle after copying the resources in. A file
# added or changed afterwards, or left out of the seal, fails here.
codesign --verify --deep --strict "${APP}" || fail "the signature does not verify"
echo "    ✓ signature verifies"

echo "==> ${APP} is complete"
