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
# The reference storybook must render with the SAME real typefaces the sync
# ships, or [FONT_MISSING] hides behind a matching fallback on both panels.
# tokens.css pulls IBM Plex Sans / JetBrains Mono from the Google Fonts CDN
# with an @import that Vite+lightningcss DROPS from the compiled stylesheet,
# so storybook itself renders on system fonts. Re-run this after every
# `storybook build -o .design-sync/sb-reference`.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ref="$here/sb-reference"
[ -f "$ref/iframe.html" ] || { echo "no sb-reference/iframe.html — build it first" >&2; exit 1; }
mkdir -p "$ref/ds-fonts"
cp "$here"/fonts/*.woff2 "$ref/ds-fonts/"
sed "s|url('./fonts/|url('./ds-fonts/|g" "$here/fonts.css" > "$ref/ds-fonts/fonts.css"
if grep -q 'ds-fonts/fonts.css' "$ref/iframe.html"; then
  echo "already injected"; exit 0
fi
perl -0pi -e 's|<head>|<head><link rel="stylesheet" href="./ds-fonts/fonts.css">|' "$ref/iframe.html"
grep -q 'ds-fonts/fonts.css' "$ref/iframe.html" && echo "injected into iframe.html"
