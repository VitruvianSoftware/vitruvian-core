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

GH="${GH:-gh}"
REPO="${REPO:?REPO must be set}"
GH_TOKEN="${GH_TOKEN:?GH_TOKEN must be set}"
export GH_TOKEN
LIMIT_FILE="${LIMIT_FILE:-infrastructure/pulumi/platform/repo-config/actions-cache-limit-gb.txt}"
ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS="${ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS:-60}"
ACTIONS_CACHE_LIMIT_POLL_INTERVAL_SECONDS="${ACTIONS_CACHE_LIMIT_POLL_INTERVAL_SECONDS:-5}"

if [ ! -f "${LIMIT_FILE}" ]; then
	echo "::error::actions cache limit file not found: ${LIMIT_FILE}" >&2
	exit 1
fi

raw="$(<"${LIMIT_FILE}")"
ws=$' \t\r\n'
limit_gb="${raw#"${raw%%[!$ws]*}"}"
limit_gb="${limit_gb%"${limit_gb##*[!$ws]}"}"

if [[ -z "${limit_gb}" || "${limit_gb}" == *$'\n'* || ! "${limit_gb}" =~ ^[1-9][0-9]*$ ]]; then
	echo "::error::${LIMIT_FILE} must contain a positive integer (got '${limit_gb}')" >&2
	exit 1
fi

if [[ ! "${ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS}" =~ ^[0-9]+$ ]]; then
	echo "::error::ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS must be a non-negative integer" >&2
	exit 1
fi

if [[ ! "${ACTIONS_CACHE_LIMIT_POLL_INTERVAL_SECONDS}" =~ ^[1-9][0-9]*$ ]]; then
	echo "::error::ACTIONS_CACHE_LIMIT_POLL_INTERVAL_SECONDS must be a positive integer" >&2
	exit 1
fi

put_body="$(printf '{"max_cache_size_gb":%s}' "${limit_gb}")"
if ! put_out="$(printf '%s' "${put_body}" | "$GH" api --method PUT \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"repos/${REPO}/actions/cache/storage-limit" \
	--input - 2>&1)"; then
	echo "::error::PUT repos/${REPO}/actions/cache/storage-limit failed: ${put_out}" >&2
	exit 1
fi

deadline=$((SECONDS + ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS))
confirmed=0
got=""
while true; do
	if got="$("$GH" api \
		-H "Accept: application/vnd.github+json" \
		-H "X-GitHub-Api-Version: 2022-11-28" \
		"repos/${REPO}/actions/cache/storage-limit" \
		--jq '.max_cache_size_gb')" && [ "${got}" = "${limit_gb}" ]; then
		confirmed=1
		break
	fi
	now="$SECONDS"
	if [ "${now}" -ge "${deadline}" ]; then
		break
	fi
	remaining=$((deadline - now))
	sleep_for="${ACTIONS_CACHE_LIMIT_POLL_INTERVAL_SECONDS}"
	if [ "${sleep_for}" -gt "${remaining}" ]; then
		sleep_for="${remaining}"
	fi
	sleep "${sleep_for}"
done

if [ "${confirmed}" -eq 1 ]; then
	"$GH" variable set ACTIONS_CACHE_LIMIT_CONFIRMED_GB \
		--repo "${REPO}" \
		--body "${limit_gb}"
	echo "Actions cache storage limit confirmed for ${REPO}: ${limit_gb} GB"
	exit 0
fi

echo "::error::Actions cache storage limit for ${REPO} is '${got}', want '${limit_gb}' after ${ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS}s" >&2
exit 1
