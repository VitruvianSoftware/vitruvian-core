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

# Keeps the planner's dependency maps under git refs instead of only in the
# Actions cache (#2841).
#
# WHY. A map ("which tests depend on each package", ~5 KiB, one per main
# commit; see tools/pipeline/plan/rdepsmap.go) lets build-test and Presubmit
# pick affected targets in milliseconds instead of a 5-10 minute whole-repo
# query. They were saved only in the Actions cache, and the repo sits over its
# 10 GiB cache budget, so GitHub evicts whatever was read least recently:
# on 2026-10-07 four maps that restored fine at 21:22-21:39 UTC were all gone
# by 21:55 and both jobs fell back to the query. A git ref is never evicted,
# costs no cache budget, and (the repo being public) is read without a token.
#
# HOW. The map for commit <sha> is stored as a blob at refs/rdeps-map/<sha>.
# Refs outside refs/heads and refs/tags trigger no workflow and are not fetched
# by a normal clone.
#
# Usage:
#   rdeps-map-ref.sh save  <map.json> <sha>   publish the map for <sha>
#   rdeps-map-ref.sh fetch <out.json> <base>  get the map for <base>, or for
#                                             its nearest first-parent ancestor
#                                             up to RDEPS_MAP_MAX_BEHIND back
#   rdeps-map-ref.sh prune                    drop maps for commits no longer
#                                             among the last RDEPS_MAP_KEEP
#
# `fetch` prints nothing to stdout but `commit=<sha>` (also appended to
# $GITHUB_OUTPUT when set), empty when no map was found. Finding none is not an
# error: the caller falls back to the Actions cache and then the live query.
# The planner still checks any map against the commit it is used for.
#
# Env: GH_TOKEN (needed to save/prune; optional to fetch), RDEPS_MAP_REMOTE
# (default origin), RDEPS_MAP_MAX_BEHIND (default 9), RDEPS_MAP_KEEP (default 300).
set -euo pipefail

REMOTE="${RDEPS_MAP_REMOTE:-origin}"
PREFIX="refs/rdeps-map"
MAX_BEHIND="${RDEPS_MAP_MAX_BEHIND:-9}"
KEEP="${RDEPS_MAP_KEEP:-300}"

log() { echo "rdeps-map-ref: $*" >&2; }

# The workflows check out with persist-credentials: false, so pass the token
# per command, the way actions/checkout itself does.
auth_git() {
  if [ -n "${GH_TOKEN:-}" ]; then
    git -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $(printf 'x-access-token:%s' "${GH_TOKEN}" | base64 | tr -d '\n')" "$@"
  else
    git "$@"
  fi
}

is_sha() { [[ "$1" =~ ^[0-9a-f]{40}$ ]]; }

# map_commit <file>: the commit a map says it describes ("" if unreadable).
map_commit() { jq -r '.commit // ""' "$1" 2>/dev/null || true; }

cmd="${1:-}"
case "${cmd}" in
  save)
    file="${2:?usage: save <map.json> <sha>}" sha="${3:?usage: save <map.json> <sha>}"
    is_sha "${sha}" || { log "not a full commit sha: ${sha}"; exit 2; }
    # Never publish a map under the wrong commit: a reader trusts the ref name.
    got="$(map_commit "${file}")"
    [ "${got}" = "${sha}" ] || { log "refusing to save: ${file} describes '${got}', not ${sha}"; exit 1; }
    blob="$(git hash-object -w "${file}")"
    auth_git push --quiet "${REMOTE}" "+${blob}:${PREFIX}/${sha}"
    log "saved the map for ${sha:0:12} at ${PREFIX}/${sha:0:12}..."
    ;;

  fetch)
    out="${2:?usage: fetch <out.json> <base>}" base="${3:-}"
    found=""
    if [ -n "${base}" ] && base_sha="$(git rev-parse --verify --quiet "${base}^{commit}")"; then
      remote_refs="$(auth_git ls-remote "${REMOTE}" "${PREFIX}/*" 2>/dev/null | awk '{print $2}' || true)"
      behind=0
      for c in $(git rev-list --first-parent -n "$((MAX_BEHIND + 1))" "${base_sha}"); do
        if printf '%s\n' "${remote_refs}" | grep -qxF "${PREFIX}/${c}"; then
          tmp="$(mktemp)"
          if auth_git fetch --quiet --no-tags "${REMOTE}" "${PREFIX}/${c}" 2>/dev/null &&
            git cat-file blob FETCH_HEAD > "${tmp}" 2>/dev/null &&
            [ "$(map_commit "${tmp}")" = "${c}" ]; then
            mv "${tmp}" "${out}"
            found="${c}"
            log "found the map for ${c:0:12} (${behind} commit(s) behind the diff base)"
            break
          fi
          rm -f "${tmp}"
          log "the map at ${PREFIX}/${c:0:12}... is unreadable or mislabelled -- skipped"
        fi
        behind=$((behind + 1))
      done
    fi
    [ -n "${found}" ] || log "no map under ${PREFIX}/ for the diff base or its last ${MAX_BEHIND} ancestors"
    echo "commit=${found}"
    if [ -n "${GITHUB_OUTPUT:-}" ]; then echo "commit=${found}" >> "${GITHUB_OUTPUT}"; fi
    ;;

  prune)
    head_sha="$(git rev-parse HEAD)"
    # The job's checkout is shallow; deepen just enough to know what is recent.
    auth_git fetch --quiet --no-tags --depth="${KEEP}" "${REMOTE}" "${head_sha}" 2>/dev/null || true
    keep="$(git rev-list --first-parent -n "${KEEP}" "${head_sha}")"
    # Refuse to guess: with almost no history in hand, "not recent" means nothing.
    if [ "$(printf '%s\n' "${keep}" | grep -c .)" -lt 2 ]; then
      log "not enough history to tell which maps are old -- pruning nothing"
      exit 0
    fi
    stale=()
    while read -r ref; do
      [ -n "${ref}" ] || continue
      printf '%s\n' "${keep}" | grep -qxF "${ref#"${PREFIX}"/}" || stale+=("${ref}")
    done < <(auth_git ls-remote "${REMOTE}" "${PREFIX}/*" | awk '{print $2}')
    if [ "${#stale[@]}" -eq 0 ]; then
      log "nothing to prune"
      exit 0
    fi
    for ((i = 0; i < ${#stale[@]}; i += 50)); do
      auth_git push --quiet "${REMOTE}" --delete "${stale[@]:i:50}"
    done
    log "pruned ${#stale[@]} map(s) older than the last ${KEEP} commits"
    ;;

  *)
    log "usage: rdeps-map-ref.sh save <map.json> <sha> | fetch <out.json> <base> | prune"
    exit 2
    ;;
esac
