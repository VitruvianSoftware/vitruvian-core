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

# verify.sh — CONTENT-enforcing license check (issue #457).
#
# `//tools/license:check` (addlicense -check) is presence-only: it verifies that
# a recognized license header EXISTS, but NOT that it is MIT or that the holder
# is "VitruvianSoftware" — an Apache-2.0 header with a wrong holder passes it
# clean. This closes that gap:
#   1. Every first-party app ships an MIT LICENSE with the VitruvianSoftware holder.
#   2. Any source file that CARRIES a license header must be MIT + VitruvianSoftware
#      (files with NO header are addlicense's job — presence — so they are skipped
#      here to avoid double-flagging; addlicense still enforces presence).
#
# Run: `bazel run //tools/license:verify`. Wired into the required license-check
# CI job so the "MIT enforced repo-wide" invariant is real, not asserted.

set -euo pipefail

cd "${BUILD_WORKSPACE_DIRECTORY:-$(git rev-parse --show-toplevel)}"

fail=0
note() {
  echo "license-verify: FAIL — $*" >&2
  fail=1
}

# --- 1. Every first-party app has an MIT LICENSE + VitruvianSoftware holder. ---
for app in tabula oauth-user-inspector devx homelab mcp-slack nexus-agent; do
  lf="${app}/LICENSE"
  if [ ! -f "${lf}" ]; then
    note "${lf} is missing"
    continue
  fi
  if [ "$(head -1 "${lf}" | tr -d '\r')" != "MIT License" ]; then
    note "${lf} is not an MIT License (first line is not 'MIT License')"
  fi
  if ! grep -qE "Copyright \(c\) [0-9]{4} VitruvianSoftware" "${lf}"; then
    note "${lf} does not carry 'Copyright (c) <year> VitruvianSoftware'"
  fi
done

# --- 2. Any source header present must be MIT + VitruvianSoftware. ------------
# Only files that ALREADY carry a copyright/license header are content-checked;
# header-less files are left to addlicense (presence). This catches a wrong
# license (e.g. Apache) or a wrong holder that addlicense -check waves through.
while IFS= read -r f; do
  hdr="$(head -30 "${f}")"
  # Skip files with no license header at all (addlicense enforces presence).
  printf '%s' "${hdr}" | grep -qiE "copyright|licensed under|SPDX-License-Identifier" || continue
  # It has a header, so it MUST be the MIT permission grant with the right holder.
  if ! printf '%s' "${hdr}" | grep -q "Permission is hereby granted, free of charge"; then
    note "${f}: has a non-MIT license header"
    continue
  fi
  if ! printf '%s' "${hdr}" | grep -qE "Copyright \(c\) [0-9]{4} VitruvianSoftware"; then
    note "${f}: license header holder is not 'VitruvianSoftware'"
  fi
done < <(git ls-files '*.go' '*.ts' '*.tsx' '*.js' '*.mjs' '*.cjs' '*.swift' |
  grep -vE '(^|/)(node_modules|dist|dist-server|bazel-[^/]*)/|\.d\.ts$|/internal/scaffold/templates/' |
  grep -vE '^pulumi/(library|examples)/')

if [ "${fail}" -ne 0 ]; then
  echo "license-verify: FAILED — first-party LICENSE files and source headers must be MIT + 'VitruvianSoftware'." >&2
  exit 1
fi
echo "license-verify: OK — all first-party LICENSE files + source headers are MIT + VitruvianSoftware."
