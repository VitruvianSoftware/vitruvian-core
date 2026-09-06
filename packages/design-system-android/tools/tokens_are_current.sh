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
# Fails when the checked-in VitruvianTokens.kt is not what the generator
# produces from tokens.json. Editing the Kotlin by hand is the failure this
# catches; the fix is always to change tokens.json and regenerate.
#
# The regenerated file is run through ktfmt before the diff, because the
# checked-in copy is formatted by the repo's formatter like every other
# Kotlin file. Without that step this test would fail on whitespace the
# moment anyone ran `bazel run //:tidy`.
set -euo pipefail

# --- runfiles bootstrap (https://github.com/bazelbuild/bazel/tree/master/tools/bash) ---
# shellcheck disable=SC1090,SC1091
source "${RUNFILES_DIR:-/dev/null}/bazel_tools/tools/bash/runfiles/runfiles.bash" 2>/dev/null ||
  source "$(grep -sm1 "^bazel_tools/tools/bash/runfiles/runfiles.bash " "${RUNFILES_MANIFEST_FILE:-/dev/null}" | cut -f2- -d' ')" 2>/dev/null ||
  {
    echo >&2 "ERROR: cannot locate the bash runfiles library"
    exit 1
  }
# --- end runfiles bootstrap ---

generator_path="$(rlocation "${GENERATOR}")"
ktfmt_path="$(rlocation "${KTFMT}")"
tokens_path="$(rlocation "${TOKENS}")"
header_path="$(rlocation "${HEADER}")"
checked_in_path="$(rlocation "${CHECKED_IN}")"

workdir="$(mktemp -d)"
trap 'rm -rf "${workdir}"' EXIT
regenerated="${workdir}/VitruvianTokens.kt"

"${generator_path}" --tokens "${tokens_path}" --header "${header_path}" --out "${regenerated}"
"${ktfmt_path}" "${regenerated}" >/dev/null

if ! diff -u "${checked_in_path}" "${regenerated}"; then
  cat >&2 <<'MSG'

VitruvianTokens.kt is out of date with packages/design-system/src/tokens.json.

Regenerate it, then format:

  bazel run //packages/design-system-android/tools:gen_tokens -- \
    --tokens "$PWD/packages/design-system/src/tokens.json" \
    --header "$PWD/packages/design-system-android/tools/kt_license_header.txt" \
    --out "$PWD/packages/design-system-android/src/main/kotlin/dev/vitruvian/design/VitruvianTokens.kt"
  bazel run //:tidy

MSG
  exit 1
fi
