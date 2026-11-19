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

# The GitHub Pages build must drop online rooms (there is no server there),
# and the server build must keep them. "Remote Battle" is the lobby button
# that opens online play.
set -euo pipefail
server_dist="$1"
static_dist="$2"

if ! grep -q "Remote Battle" "$server_dist"/assets/*.js; then
	echo "FAIL: the server build lost the Remote Battle button" >&2
	exit 1
fi
if grep -q "Remote Battle" "$static_dist"/assets/*.js; then
	echo "FAIL: the static (GitHub Pages) build still offers Remote Battle" >&2
	exit 1
fi
if [ ! -f "$static_dist/index.html" ]; then
	echo "FAIL: the static build has no index.html" >&2
	exit 1
fi
echo "OK: static build has no online play; server build keeps it"
