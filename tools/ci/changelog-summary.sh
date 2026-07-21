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

# changelog-summary.sh -- render a component's release notes into the GitHub
# Actions run page (a job summary), so an operator can read WHAT is shipping
# before approving a gated deploy. It complements pulumi-summary.sh (which shows
# the resource diff AFTER approval); this shows the human changelog BEFORE it.
#
# Appends a markdown panel to $GITHUB_STEP_SUMMARY, or prints to stdout when run
# locally (no $GITHUB_STEP_SUMMARY). It NEVER fails the caller: a missing file or
# an unmatched version is reported as a note and the script still exits 0 -- a
# changelog is informational and must not be able to block a deploy.
#
# Usage:
#   changelog-summary.sh <changelog-path> [version] [title]
#     <changelog-path>  a release-please / Keep-a-Changelog CHANGELOG.md
#     [version]         a specific release (e.g. 1.2.4 or v1.2.4); empty selects
#                       the most recent (top) release block
#     [title]           panel heading label; defaults to the component dir name

# The backticks in the note printf formats below are literal markdown code spans,
# not command substitution -- values arrive via printf's %s arguments.
# shellcheck disable=SC2016
#
# Deliberately NO `set -e`: this script must not abort the calling step. (-u and
# pipefail are safe -- every variable below is guarded.)
set -uo pipefail

CHANGELOG=""
VERSION=""
TITLE=""
RANGE=""
SCOPE_PATH=""

# Positionals stay backward compatible (<changelog> [version] [title]); the
# deploy-scope flags may follow in any order.
pos=0
while [ $# -gt 0 ]; do
  case "$1" in
    --range) RANGE="${2:-}"; shift 2 || shift ;;
    --path)  SCOPE_PATH="${2:-}"; shift 2 || shift ;;
    *)
      pos=$((pos + 1))
      case "$pos" in
        1) CHANGELOG="$1" ;;
        2) VERSION="$1" ;;
        3) TITLE="$1" ;;
      esac
      shift
      ;;
  esac
done

if [ -z "$CHANGELOG" ]; then
  echo "changelog-summary: usage: changelog-summary.sh <changelog-path> [version] [title] [--range A..B] [--path PATHSPEC]" >&2
  exit 2
fi
if [ -z "$TITLE" ]; then
  TITLE="$(basename "$(dirname "$CHANGELOG")")"
fi

# Under Actions, append to the run's job summary; locally, print to stdout.
emit() { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then cat >>"$GITHUB_STEP_SUMMARY"; else cat; fi; }

# WHAT IS SHIPPING. A hand-maintained changelog drifts (oauth-user-inspector's
# sat unchanged across 69 commits while this panel kept rendering the vendoring
# note), and a stale panel above an approval button is worse than none. So when
# the caller passes the deployed commit range, lead with the commits themselves
# -- derived from git, they cannot go stale. Same never-fail contract as below.
if [ -n "$RANGE" ]; then
  pathargs=()
  [ -n "$SCOPE_PATH" ] && pathargs=(-- "$SCOPE_PATH")
  if commits="$(git log --no-merges --format='* %s' "$RANGE" \
      ${pathargs[@]+"${pathargs[@]}"} 2>/dev/null)"; then
    if [ -n "$commits" ]; then
      printf '## 🚢 %s — shipping in this deploy\n\n%s\n\n' "$TITLE" "$commits" | emit
    else
      printf '## 🚢 %s — shipping in this deploy\n\n_No commits in `%s`%s._\n\n' \
        "$TITLE" "$RANGE" "${SCOPE_PATH:+ touching \`$SCOPE_PATH\`}" | emit
    fi
  else
    printf '## 🚢 %s — shipping in this deploy\n\n_Scope could not be determined for `%s` (unknown revision, or a shallow clone without that history)._\n\n' \
      "$TITLE" "$RANGE" | emit
  fi
fi

if [ ! -f "$CHANGELOG" ]; then
  printf '## 📓 %s\n\n_No changelog found at `%s`._\n\n' "$TITLE" "$CHANGELOG" | emit
  exit 0
fi

ver="${VERSION#v}"

# release-please headings look like `## [1.2.4](compare-url) (2026-07-18)`. Print
# the matching release block -- or the first (top / most recent) block when no
# version is given -- stopping at the next `## ` release heading.
block="$(
  awk -v ver="$ver" '
    /^## / {
      if (capturing) exit
      hv = ""
      if (match($0, /\[[^]]+\]/)) hv = substr($0, RSTART + 1, RLENGTH - 2)
      if (ver == "" || hv == ver) { capturing = 1; print; next }
      next
    }
    capturing { print }
  ' "$CHANGELOG"
)"

if [ -z "$block" ]; then
  printf '## 📓 %s\n\n_Release notes for `%s` not found in `%s`._\n\n' \
    "$TITLE" "${VERSION:-latest}" "$CHANGELOG" | emit
  exit 0
fi

# Nest the block one heading level deeper (## -> ###, ### -> ####, ...) so the
# release `## [x.y.z]` heading sits as a subheading under our panel title.
{
  printf '## 📓 %s — release notes\n\n' "$TITLE"
  printf '%s\n' "$block" | sed 's/^\(#\{1,\}\)/#\1/'
  printf '\n---\n\n'
} | emit
