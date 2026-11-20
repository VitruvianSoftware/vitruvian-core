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

# release_approvals.sh <out.json>
#
# Turns a `release` event into the commit list the plan guard reads Allow-destroy
# approvals from. A push event carries its commits; a release event does not. A
# release delivers every commit merged since the product's previous release, so
# the approvals are read from exactly those: the commits in
# <previous tag>...<this tag>, from GitHub's compare API.
#
# Writes {"commits":[{"message":...},...]} to <out.json>, the shape
# `guarded-up --allow-destroy-from-event` reads. It never fails the job: if the
# range cannot be read in full (no previous release, API error, more commits
# than it pages through) it writes {} and warns, and the guard then approves
# nothing, so every delete or replace is refused. Failing closed is the point.
#
# Needs: GITHUB_EVENT_PATH (the release payload), GITHUB_REPOSITORY, GH_TOKEN
# (contents: read is enough), gh and jq.
set -uo pipefail

out="${1:?usage: release_approvals.sh <out.json>}"
max_pages="${RELEASE_APPROVALS_MAX_PAGES:-30}" # 100 commits a page

refuse() {
  echo "::warning::plan-guard: no Allow-destroy approvals were read for this release ($1); every delete or replace will be refused" >&2
  echo '{}' >"$out"
  exit 0
}

: >"$out" || exit 1
command -v gh >/dev/null 2>&1 || refuse "gh is not installed"
command -v jq >/dev/null 2>&1 || refuse "jq is not installed"
[ -n "${GITHUB_REPOSITORY:-}" ] || refuse "GITHUB_REPOSITORY is unset"
[ -r "${GITHUB_EVENT_PATH:-}" ] || refuse "the event payload is unreadable"

tag="$(jq -r '.release.tag_name // empty' "$GITHUB_EVENT_PATH")"
published="$(jq -r '.release.published_at // empty' "$GITHUB_EVENT_PATH")"
[ -n "$tag" ] && [ -n "$published" ] || refuse "the event is not a published release"
case "$tag" in
  *v[0-9]*) ;;
  *) refuse "tag $tag has no -v<version> suffix" ;;
esac
prefix="${tag%v*}v" # oauth-user-inspector-v1.16.1 -> oauth-user-inspector-v

# The newest published release of the same product before this one. A prefix
# match on "<product>-v" keeps oauth-user-inspector-infra-v* out of it.
prev="$(gh api --paginate "repos/${GITHUB_REPOSITORY}/releases?per_page=100" \
  --jq ".[] | select(.draft | not) | select(.published_at != null)
        | select(.tag_name | startswith(\"${prefix}\")) | select(.tag_name != \"${tag}\")
        | select(.published_at < \"${published}\") | [.published_at, .tag_name] | @tsv" 2>/dev/null |
  sort -r | head -n1 | cut -f2)" || refuse "the releases list could not be read"
[ -n "$prev" ] || refuse "no earlier ${prefix}* release to compare with"

messages="$(mktemp)"
trap 'rm -f "$messages"' EXIT
total=""
page=1
while [ "$page" -le "$max_pages" ]; do
  body="$(gh api "repos/${GITHUB_REPOSITORY}/compare/${prev}...${tag}?per_page=100&page=${page}" 2>/dev/null)" ||
    refuse "the compare ${prev}...${tag} could not be read"
  [ -n "$total" ] || total="$(jq -r '.total_commits // empty' <<<"$body")"
  n="$(jq -r '.commits | length' <<<"$body" 2>/dev/null)" || refuse "the compare response is not JSON"
  [ "$n" -gt 0 ] || break
  jq -c '.commits[] | {message: .commit.message}' <<<"$body" >>"$messages"
  got="$(wc -l <"$messages" | tr -d ' ')"
  [ -n "$total" ] && [ "$got" -ge "$total" ] && break
  page=$((page + 1))
done
got="$(wc -l <"$messages" | tr -d ' ')"
[ -n "$total" ] || refuse "the compare response has no total_commits"
[ "$got" -eq "$total" ] || refuse "read ${got} of ${total} commits in ${prev}...${tag}"

jq -s '{commits: .}' "$messages" >"$out" || refuse "could not write ${out}"
echo "plan-guard: reading Allow-destroy approvals from the ${got} commit(s) in ${prev}...${tag}" >&2
