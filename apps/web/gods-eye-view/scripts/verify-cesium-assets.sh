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

set -euo pipefail

# Locate the dist/cesium directory from runfiles or current directory
CANDIDATES=(
  "${RUNFILES_DIR:-}/_main/apps/web/gods-eye-view/dist"
  "${TEST_SRCDIR:-}/_main/apps/web/gods-eye-view/dist"
  "apps/web/gods-eye-view/dist"
  "dist"
)

DIST_DIR=""
for candidate in "${CANDIDATES[@]}"; do
  if [[ -n "$candidate" && -d "$candidate/cesium" ]]; then
    DIST_DIR="$candidate"
    break
  fi
done

if [[ -z "$DIST_DIR" ]]; then
  echo "ERROR: dist/cesium directory not found in runfiles or cwd." >&2
  echo "Checked locations: ${CANDIDATES[*]}" >&2
  exit 1
fi

echo "Verifying Cesium runtime assets in $DIST_DIR/cesium ..."

test -f "$DIST_DIR/cesium/Cesium.js" || { echo "MISSING: Cesium.js" >&2; exit 1; }
test -f "$DIST_DIR/cesium/Widgets/widgets.css" || { echo "MISSING: Widgets/widgets.css" >&2; exit 1; }
test -d "$DIST_DIR/cesium/Workers" || { echo "MISSING: Workers/" >&2; exit 1; }
test -d "$DIST_DIR/cesium/ThirdParty" || { echo "MISSING: ThirdParty/" >&2; exit 1; }

asset_count=$(ls -A "$DIST_DIR/cesium/Assets" | wc -l)
if [ "$asset_count" -le 0 ]; then
  echo "MISSING: Assets directory is empty" >&2
  exit 1
fi

echo "All Cesium runtime assets verified successfully in $DIST_DIR/cesium ($asset_count assets in Assets/)."
