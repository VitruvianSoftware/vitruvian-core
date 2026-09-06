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
# Everything that must be fresh BEFORE package-build.mjs runs.
# Referenced by config.json's buildCmd, so the §7 re-sync driver runs it too.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"
pkg="$root/packages/design-system"

# 1. The design system's own dist/ -- the converter bundles this into
#    window.Vitruvian. Plain tsc, per the package's "build" script.
( cd "$pkg" && "$root/node_modules/.bin/tsc" -p tsconfig.json )

# 2. The full-vocabulary stylesheet. See tailwind-entry.css for why this
#    exists: a rendered design gets static CSS with no Tailwind compiler, so
#    the utility language has to be force-generated rather than scraped.

"$root/.ds-sync/node_modules/.bin/tailwindcss" \
  -i "$here/tailwind-entry.css" \
  -o "$pkg/dist/vitruvian.built.css"

echo "prepare: dist/ + dist/vitruvian.built.css ready"
