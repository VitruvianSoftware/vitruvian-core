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

. "${OS_RELEASE_PATH:-/etc/os-release}"
check test "$VERSION_ID" = 26.04
check test "$(id -un):$(id -u)" = runner:1001
check sudo -n true # setup-bazel's `sudo dpkg -i`
check sudo -n dpkg --version
for tool in git git-lfs gh curl jq python3 node npm npx shellcheck unzip zip xz zstd gcc g++ make tar gpg; do
  check command -v "$tool"
done
check test -x "${RUNNER_HOME:-/home/runner}/run.sh"
check "${RUNNER_HOME:-/home/runner}/bin/Runner.Listener" --version
# Bazel: the jobs run `bazel` directly, as on the hosted image, so both names
# must be on the PATH (not fetched at check time), at the repo's version.
check command -v bazel
check command -v bazelisk
check env USE_BAZEL_VERSION="${BAZEL_VERSION:-9.3.0}" bazel --version

[ "$fail" -eq 0 ] && echo "parity: OK" || { echo "parity: FAILED" >&2; exit 1; }
