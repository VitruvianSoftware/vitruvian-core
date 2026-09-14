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
#
# pair.sh -- open a pairing window for the phone showing <code>.
#
#   bazel run //mobile/android/remote/macagent:pair -- 482917
#
# It runs the agent binary the repo just built with its `pair` subcommand,
# and writes only to ~/.config/vitruvian-remote-agent. The INSTALLED agent --
# a different copy of the same binary, running as a login item -- picks the
# pairing up on its next request, because it re-reads those files rather than
# caching them at start. So this works without stopping or restarting
# anything, and it does not matter that the two binaries are separate files.
set -euo pipefail

if [ "$#" -lt 1 ]; then
	echo "usage: bazel run //mobile/android/remote/macagent:pair -- <six-digit code from the phone>" >&2
	exit 2
fi

# Same runfiles dance as install.sh: under `bazel run` the binary lives in a
# tree beside this script, at a fixed package path.
RUNFILES="${RUNFILES_DIR:-$0.runfiles}"
SRC_DIR="${RUNFILES}/_main/apps/mobile/android-remote/macagent"
if [ ! -d "$SRC_DIR" ]; then
	SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
BIN="${SRC_DIR}/macagent_/macagent"
[ -x "$BIN" ] || BIN="${SRC_DIR}/macagent"
if [ ! -x "$BIN" ]; then
	echo "pair.sh: built agent not found under ${SRC_DIR} (run via: bazel run //apps/mobile/android-remote/macagent:pair -- <code>)" >&2
	exit 1
fi

exec "$BIN" pair "$@"
