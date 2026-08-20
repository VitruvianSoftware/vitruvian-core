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

# prune-pr-caches.sh — delete GitHub Actions caches belonging to CLOSED pull
# requests.
#
# WHY. The repo shares one 10 GiB Actions cache budget. Over it, GitHub evicts
# by LRU -- so wasted space is not merely untidy, it silently evicts the entries
# other lanes depend on. `llvm-contents-v1` (2.2 GiB) exists precisely because
# uncached LLVM extraction cost 98-264s of variance in build-test (#1039); it is
# the natural LRU victim of anything that crowds the budget.
#
# A PR-scoped cache is readable ONLY from that PR's own ref, so the moment the
# PR closes the entry can never be read again -- but GitHub keeps it until it
# goes 7 days without access. Image-building PRs leave ~1.5 GiB behind each.
#
# Measured on 2026-08-20: the repo held 222 entries / 11.10 GiB against a 10 GiB
# cap -- ALREADY over, and therefore already evicting. 94 of those entries
# (3.11 GiB) belonged to two PRs that had merged hours earlier. Deleting exactly
# those took the repo to 128 entries / 7.99 GiB, back under the cap.
#
# SAFETY. Only caches on `refs/pull/<n>/merge` are ever considered, and only
# after the PR's state is confirmed CLOSED or MERGED. A cache is regenerable by
# construction; an open PR's cache is never touched.
#
# Usage:
#   prune-pr-caches.sh            # sweep every closed PR's caches
#   prune-pr-caches.sh <pr>       # just this PR (the on-close hook)
#   DRY_RUN=1 prune-pr-caches.sh  # report, delete nothing
#
# Env: REPO (owner/name), GH_TOKEN. Exit 0 on success, 2 on setup error.
set -euo pipefail

REPO="${REPO:-VitruvianSoftware/vitruvian-core}"
GH="${GH:-gh}"
ONLY_PR="${1:-}"
DRY_RUN="${DRY_RUN:-}"

log() { echo "prune-pr-caches: $*" >&2; }

command -v "$GH" >/dev/null 2>&1 || {
    log "gh not found on PATH"
    exit 2
}

listing="$("$GH" api --paginate "repos/${REPO}/actions/caches?per_page=100" \
    --jq '.actions_caches[] | [.id, .size_in_bytes, .ref] | @tsv' 2>/dev/null || true)"
if [ -z "$listing" ]; then
    log "no caches found (or the listing call failed) -- nothing to do"
    exit 0
fi

deleted=0
freed=0
kept_open=0

# Cache PR states so a sweep asks about each PR once, not once per entry.
state_of() {
    # Two statements, not one `local a= b=$a`: under `set -u` bash evaluates
    # the whole declaration before the earlier name is in scope, so the second
    # initialiser sees an unbound n.
    local n="$1"
    local f="${TMPDIR:-/tmp}/prune-pr-state.$$.${n}"
    if [ ! -f "$f" ]; then
        "$GH" pr view "$n" --repo "$REPO" --json state --jq '.state' >"$f" 2>/dev/null || echo "" >"$f"
    fi
    cat "$f"
}
trap 'rm -f "${TMPDIR:-/tmp}"/prune-pr-state.$$.*' EXIT

while IFS=$'\t' read -r id size ref; do
    [ -n "${ref:-}" ] || continue
    case "$ref" in */pull/*) ;; *) continue ;; esac
    num="$(echo "$ref" | cut -d/ -f3)"
    [ -n "$ONLY_PR" ] && [ "$num" != "$ONLY_PR" ] && continue

    st="$(state_of "$num")"
    case "$st" in
        MERGED | CLOSED) ;;
        OPEN)
            kept_open=$((kept_open + 1))
            continue
            ;;
        *)
            # Unknown state: refuse to guess. Leaving a cache costs space;
            # deleting a live PR's cache costs that PR a cold rebuild.
            log "PR #${num}: state unknown ('${st}') -- leaving its caches alone"
            continue
            ;;
    esac

    if [ -n "$DRY_RUN" ]; then
        log "DRY_RUN would delete cache ${id} ($((size / 1048576))MiB) from ${ref} (PR ${st})"
        deleted=$((deleted + 1))
        freed=$((freed + size))
        continue
    fi
    if "$GH" api -X DELETE "repos/${REPO}/actions/caches/${id}" >/dev/null 2>&1; then
        deleted=$((deleted + 1))
        freed=$((freed + size))
    else
        log "failed to delete cache ${id} from ${ref}"
    fi
done <<EOF
$listing
EOF

log "deleted ${deleted} orphaned cache entr$([ "$deleted" -eq 1 ] && echo y || echo ies), freed $((freed / 1048576))MiB (left ${kept_open} belonging to open PRs)"
echo "deleted=${deleted} freed_mib=$((freed / 1048576))"
