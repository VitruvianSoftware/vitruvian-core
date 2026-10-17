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

# require-pinned-actions.sh — every action from outside this repo is pinned to a
# full commit SHA (with the version in a trailing comment, which Dependabot
# keeps in step). A tag can be moved to different code after review; a commit
# cannot. Local `./` actions and reusable workflows are exempt. The devx
# scaffold templates are checked too: Dependabot cannot see a `.tmpl`, and every
# repo devx creates starts from these pins.
#
# Run from the repository root. Both the required `actionlint` check
# (.github/workflows/actionlint.yaml) and `bazel run //tools/ci:actionlint`
# call this, so the two cannot disagree.

set -uo pipefail

dirs=()
for d in .github/workflows .github/actions apps/cli/devx/internal/scaffold/templates; do
  [ -d "$d" ] && dirs+=("$d")
done
[ ${#dirs[@]} -gt 0 ] || exit 0

unpinned="$(grep -rnE '^[[:space:]]*(-[[:space:]]*)?uses:[[:space:]]*[^.#[:space:]]' "${dirs[@]}" |
  grep -vE '@[0-9a-f]{40}([[:space:]]|$)' || true)"
if [ -n "$unpinned" ]; then
  echo "::error::Actions must be pinned to a full commit SHA, e.g. 'owner/action@<40-hex sha> # v1.2.3':"
  echo "$unpinned"
  exit 1
fi
