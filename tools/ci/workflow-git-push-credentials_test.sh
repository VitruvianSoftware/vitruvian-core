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

# Guard: a workflow that checks out with `persist-credentials: false` leaves
# git with no credentials, so a bare `git push` dies with "could not read
# Username". Every workflow that pushes this way must first give git a
# credential (`gh auth setup-git`, or a ~/.git-credentials file) or push to an
# explicit URL. site-sync-downloads shipped without it and failed its first run.

set -uo pipefail

ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)"
fails=0

for wf in "${ROOT}"/.github/workflows/*.y*ml; do
	grep -q 'persist-credentials: false' "$wf" || continue
	# A second checkout that keeps an App token's credentials is fine.
	grep -q 'persist-credentials: allow' "$wf" && continue
	# Only a push to the named remote needs stored credentials.
	grep -Eq 'git push[^|]* origin' "$wf" || continue
	if grep -Eq 'gh auth setup-git|\.git-credentials|credential\.helper|extraheader' "$wf"; then
		printf '  ✓ %s\n' "$(basename "$wf")"
	else
		printf '  ✗ %s: pushes to origin with no git credentials configured\n' "$(basename "$wf")" >&2
		fails=$((fails + 1))
	fi
done

[ "$fails" -eq 0 ]
