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

# parity.sh — run INSIDE vitruvian-ci-runner: does the image have what the
# merge-queue jobs expect from GitHub's hosted ubuntu-26.04 image?
#
#   docker run --rm -v "$PWD/tools/ci-runner:/check:ro" <image> bash /check/parity.sh
#
# Run by the image's workflow before every push, so a missing tool fails there
# and not in the merge queue.
set -euo pipefail
fail=0
check() { if "$@" >/dev/null 2>&1; then echo "  ok: $*"; else echo "  FAIL: $*" >&2; fail=1; fi; }

. /etc/os-release
check test "$VERSION_ID" = 26.04
check test "$(id -un):$(id -u)" = runner:1001
check sudo -n true # setup-bazel's `sudo dpkg -i`
check sudo -n dpkg --version
for tool in git git-lfs curl jq python3 unzip zip xz zstd gcc g++ make tar gpg; do
  check command -v "$tool"
done
check test -x /home/runner/run.sh
check /home/runner/bin/Runner.Listener --version
# Bazel itself, at the repo's version, from a fresh bazelisk.
curl -fsSL -o /tmp/bazelisk https://github.com/bazelbuild/bazelisk/releases/download/v1.27.0/bazelisk-linux-amd64
chmod +x /tmp/bazelisk
check env USE_BAZEL_VERSION="${BAZEL_VERSION:-9.3.0}" /tmp/bazelisk --version

[ "$fail" -eq 0 ] && echo "parity: OK" || { echo "parity: FAILED" >&2; exit 1; }
