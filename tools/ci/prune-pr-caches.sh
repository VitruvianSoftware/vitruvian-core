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
# The SAME orphaning happens one ref deeper, and was missed for longer. A merge
# queue runs each entry on a temporary `refs/heads/gh-readonly-queue/<base>/
# pr-<n>-<sha>` branch, whose jobs save caches scoped to it, and GitHub deletes
# that branch the moment the entry leaves the queue. The cache outlives the only
# ref that could ever read it. Measured 2026-09-09: one such entry held 1.58 GiB
# -- larger than everything this script was reclaiming at the time.
#
# Measured on 2026-08-20: the repo held 222 entries / 11.10 GiB against a 10 GiB
# cap -- ALREADY over, and therefore already evicting. 94 of those entries
# (3.11 GiB) belonged to two PRs that had merged hours earlier. Deleting exactly
# those took the repo to 128 entries / 7.99 GiB, back under the cap.
#
# SAFETY. Only two ref shapes are ever considered:
#   refs/pull/<n>/merge                          -- and only once the PR's state
#                                                   is confirmed CLOSED or MERGED
#   refs/heads/gh-readonly-queue/<base>/pr-<n>-* -- and only once the branch is
#                                                   confirmed GONE (a 404 from
#                                                   the branches API, never a
#                                                   bare non-zero exit, so a
#                                                   network blip cannot read as
#                                                   "deleted")
# A cache is regenerable by construction; an open PR's cache, and a queue entry
# still in flight, are never touched. Both guards refuse to guess: an
# undeterminable state leaves the entry alone.
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
kept_live=0
# Running totals for the whole listing, so the caller gets the remaining budget
# without a second round of API calls -- and, more importantly, so the number is
# computed by code that has tests. The first version of this lived as an inline
# `run:` block in the workflow and was wrong: `gh api --paginate` with a --jq
# AGGREGATE emits one result PER PAGE, so `[...] | add` yielded two numbers and
# the arithmetic that consumed them died with a syntax error.
total_entries=0
total_bytes=0

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
# Is a merge-queue branch gone? Only an explicit 404 counts. A non-zero exit on
# its own is NOT proof of deletion -- a rate limit, a proxy hiccup or an expired
# token all exit non-zero too, and treating those as "deleted" would delete the
# cache of a queue entry that is still running. Answers are memoised per branch.
branch_gone() {
    local b="$1" f out rc
    f="${TMPDIR:-/tmp}/prune-queue-ref.$$.$(printf '%s' "$b" | tr -c 'A-Za-z0-9' '_')"
    if [ ! -f "$f" ]; then
        out="$("$GH" api "repos/${REPO}/branches/${b}" 2>&1)" && rc=0 || rc=$?
        if [ "$rc" -eq 0 ]; then
            echo no >"$f"
        elif grep -qiE '404|not found' <<<"$out"; then
            # Herestring, not a pipe: `grep -q` on a pipe exits 141 on SIGPIPE
            # once the input is large enough, which would read as "not a 404".
            echo yes >"$f"
        else
            echo unknown >"$f"
        fi
    fi
    cat "$f"
}
trap 'rm -f "${TMPDIR:-/tmp}"/prune-pr-state.$$.* "${TMPDIR:-/tmp}"/prune-queue-ref.$$.*' EXIT

while IFS=$'\t' read -r id size ref; do
    [ -n "${ref:-}" ] || continue
    total_entries=$((total_entries + 1))
    total_bytes=$((total_bytes + size))

    # Classify the ref FIRST. Everything below is gated on this, so a ref shape
    # that is neither of the two known-orphanable kinds is never a candidate --
    # in particular refs/heads/main, whose caches are the ones worth protecting.
    kind=""
    case "$ref" in
        */pull/*) kind="pr" ;;
        refs/heads/gh-readonly-queue/*) kind="queue" ;;
        *) continue ;;
    esac

    if [ "$kind" = "pr" ]; then
        num="$(echo "$ref" | cut -d/ -f3)"
    else
        # refs/heads/gh-readonly-queue/<base>/pr-<n>-<sha> -> <n>, so that the
        # on-close hook (prune-pr-caches.sh <pr>) also sweeps the queue branches
        # that PR left behind.
        leaf="${ref##*/}"
        leaf="${leaf#pr-}"
        num="${leaf%%-*}"
    fi
    [ -n "$ONLY_PR" ] && [ "$num" != "$ONLY_PR" ] && continue

    if [ "$kind" = "queue" ]; then
        case "$(branch_gone "${ref#refs/heads/}")" in
            yes) ;;
            no)
                kept_live=$((kept_live + 1))
                continue
                ;;
            *)
                log "queue ref ${ref}: existence undeterminable -- leaving its cache alone"
                continue
                ;;
        esac
        reason="queue branch deleted"
    else
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
        reason="PR ${st}"
    fi

    if [ -n "$DRY_RUN" ]; then
        log "DRY_RUN would delete cache ${id} ($((size / 1048576))MiB) from ${ref} (${reason})"
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

remaining_entries=$((total_entries - deleted))
remaining_bytes=$((total_bytes - freed))
[ -n "$DRY_RUN" ] && { remaining_entries=$total_entries; remaining_bytes=$total_bytes; }

log "deleted ${deleted} orphaned cache entr$([ "$deleted" -eq 1 ] && echo y || echo ies), freed $((freed / 1048576))MiB (left ${kept_open} belonging to open PRs, ${kept_live} to live queue entries)"
log "remaining: ${remaining_entries} entries, $((remaining_bytes / 1048576))MiB of the 10240MiB repo budget"
# One key=value PER LINE: this is appended straight to $GITHUB_OUTPUT by the
# workflow, and GitHub parses that file line by line. Space-separating them on
# a single line yields one output named "deleted" whose value is the rest of
# the string.
echo "deleted=${deleted}"
echo "freed_mib=$((freed / 1048576))"
echo "remaining_entries=${remaining_entries}"
echo "remaining_mib=$((remaining_bytes / 1048576))"
