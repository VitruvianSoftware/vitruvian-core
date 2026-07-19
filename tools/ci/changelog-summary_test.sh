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

# Regression guard for tools/ci/changelog-summary.sh: fixture-backed assertions
# that release-block extraction, version selection, heading nesting, and the
# never-fail degradation all behave. Runs on the runner's awk (portability).

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/changelog-summary.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# The script writes to $GITHUB_STEP_SUMMARY when set; unset so we capture stdout.
unset GITHUB_STEP_SUMMARY

CL="$TMP/CHANGELOG.md"
cat >"$CL" <<'EOF'
# Changelog

## [1.3.0](https://example/compare/v1.2.0...v1.3.0) (2026-07-19)


### Features

* **thing:** add the new thing ([#42](https://example/issues/42))

## [1.2.0](https://example/compare/v1.1.0...v1.2.0) (2026-07-01)


### Bug Fixes

* **thing:** fix the old thing ([#7](https://example/issues/7))
EOF

fail=0
want() { # <desc> <substring> <output>
  if printf '%s' "$3" | grep -qF -- "$2"; then echo "ok   - $1"; else
    echo "FAIL - $1 (missing: $2)"; fail=1; fi
}
absent() { # <desc> <substring> <output>
  if printf '%s' "$3" | grep -qF -- "$2"; then
    echo "FAIL - $1 (unexpected: $2)"; fail=1; else echo "ok   - $1"; fi
}
exit0() { # <desc> <rc>
  if [ "$2" -eq 0 ]; then echo "ok   - $1"; else echo "FAIL - $1 (exit $2)"; fail=1; fi
}

# 1) top (most recent) block, nested one heading level, with the panel title
out="$(bash "$SCRIPT" "$CL" "" "demo")"
want   "panel title"           "## 📓 demo — release notes" "$out"
want   "top: latest as h3"     "### [1.3.0]"                "$out"
want   "top: feature as h4"    "#### Features"              "$out"
want   "top: latest content"   "add the new thing"         "$out"
absent "top: excludes older"   "fix the old thing"         "$out"

# 2) a specific (older) version
out="$(bash "$SCRIPT" "$CL" "1.2.0" "demo")"
want   "pin: 1.2.0 block"      "### [1.2.0]"                "$out"
want   "pin: 1.2.0 content"    "fix the old thing"         "$out"
absent "pin: excludes latest"  "add the new thing"         "$out"

# 3) a v-prefixed version normalizes
out="$(bash "$SCRIPT" "$CL" "v1.3.0" "demo")"
want   "vprefix normalizes"    "### [1.3.0]"               "$out"

# 4) an unknown version -> graceful note, exit 0
out="$(bash "$SCRIPT" "$CL" "9.9.9" "demo")"; rc=$?
want   "unknown-version note"  "not found"                 "$out"
exit0  "unknown-version exit0" "$rc"

# 5) a missing file -> graceful note, exit 0
out="$(bash "$SCRIPT" "$TMP/nope.md" "" "ghost")"; rc=$?
want   "missing-file note"     "No changelog found"        "$out"
exit0  "missing-file exit0"    "$rc"

# 6) default panel title derives from the changelog's dir name
out="$(bash "$SCRIPT" "$CL")"
want   "default title"         "## 📓 $(basename "$TMP")"  "$out"

if [ "$fail" -ne 0 ]; then echo "changelog-summary_test: FAILURES"; exit 1; fi
echo "changelog-summary_test: all passed"
