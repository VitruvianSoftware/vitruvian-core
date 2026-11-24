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

org="${REPO%%/*}"
if [[ -z "${org}" || "${org}" == "${REPO}" ]]; then
	echo "::error::REPO must be in owner/name format (got '${REPO}')" >&2
	exit 1
fi

put_body="$(printf '{"max_cache_size_gb":%s}' "${limit_gb}")"
org_failed=0
skip_repo_put=0
org_limit_gb=""

cleanup_org_get_err_file() {
	if [ -n "${org_get_err_file:-}" ]; then
		rm -f "${org_get_err_file}"
	fi
}
org_get_err_file="$(mktemp)"
trap cleanup_org_get_err_file EXIT
org_get_ok=0
if org_get_out="$("$GH" api \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"orgs/${org}/actions/cache/storage-limit" \
	--jq '.max_cache_size_gb' 2>"${org_get_err_file}")"; then
	org_get_ok=1
fi
org_get_err="$(<"${org_get_err_file}")"
rm -f "${org_get_err_file}"
org_get_err_file=""

if [ "${org_get_ok}" -eq 1 ] && [[ -n "${org_get_out}" && "${org_get_out}" != *$'\n'* && "${org_get_out}" =~ ^[1-9][0-9]*$ ]]; then
	org_limit_gb="${org_get_out}"
	if [ "${org_limit_gb}" -lt "${limit_gb}" ]; then
		if printf '%s' "${put_body}" | "$GH" api --method PUT \
			-H "Accept: application/vnd.github+json" \
			-H "X-GitHub-Api-Version: 2022-11-28" \
			"orgs/${org}/actions/cache/storage-limit" \
			--input - >/dev/null 2>&1; then
			org_deadline=$((SECONDS + ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS))
			org_confirmed=0
			org_got=""
			while true; do
				if org_got="$("$GH" api \
					-H "Accept: application/vnd.github+json" \
					-H "X-GitHub-Api-Version: 2022-11-28" \
					"orgs/${org}/actions/cache/storage-limit" \
					--jq '.max_cache_size_gb' 2>/dev/null)" && [ "${org_got}" = "${limit_gb}" ]; then
					org_confirmed=1
					break
				fi
				now="$SECONDS"
				if [ "${now}" -ge "${org_deadline}" ]; then
					break
				fi
				remaining=$((org_deadline - now))
				sleep_for="${ACTIONS_CACHE_LIMIT_POLL_INTERVAL_SECONDS}"
				if [ "${sleep_for}" -gt "${remaining}" ]; then
					sleep_for="${remaining}"
				fi
				sleep "${sleep_for}"
			done
			if [ "${org_confirmed}" -eq 0 ]; then
				echo "::error::Organization ${org} Actions cache storage limit is '${org_got}', want '${limit_gb}' after ${ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS}s" >&2
				org_failed=1
				skip_repo_put=1
			fi
		else
			echo "::error::Organization ${org} Actions cache storage limit is ${org_limit_gb} GB and ${REPO} cannot exceed it; the App needs organization Administration write permission, or a maintainer can raise it under organization Settings -> Actions -> General" >&2
			org_failed=1
		fi
	fi
else
	if [ -n "${org_get_err}" ]; then
		cr=$'\r'
		nl=$'\n'
		org_get_err_detail="${org_get_err//"${cr}"/ }"
		org_get_err_detail="${org_get_err_detail//"${nl}"/ }"
		echo "::warning::Could not read organization ${org} Actions cache storage limit (${org_get_err_detail}); continuing to repository limit for ${REPO}" >&2
	else
		echo "::warning::Could not read organization ${org} Actions cache storage limit; continuing to repository limit for ${REPO}" >&2
	fi
fi

put_failed=0
if [ "${skip_repo_put}" -eq 1 ]; then
	put_failed=1
elif ! put_out="$(printf '%s' "${put_body}" | "$GH" api --method PUT \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"repos/${REPO}/actions/cache/storage-limit" \
	--input - 2>&1)"; then
	echo "::error::PUT repos/${REPO}/actions/cache/storage-limit failed: ${put_out}" >&2
	put_failed=1
fi

if [ "${put_failed}" -eq 0 ]; then
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
		if [ "${org_failed}" -eq 0 ]; then
			exit 0
		fi
		exit 1
	fi

	echo "::error::Actions cache storage limit for ${REPO} is '${got}', want '${limit_gb}' after ${ACTIONS_CACHE_LIMIT_TIMEOUT_SECONDS}s" >&2
fi

live_gb=""
if live_gb="$("$GH" api \
	-H "Accept: application/vnd.github+json" \
	-H "X-GitHub-Api-Version: 2022-11-28" \
	"repos/${REPO}/actions/cache/storage-limit" \
	--jq '.max_cache_size_gb' 2>/dev/null)" && [[ -n "${live_gb}" && "${live_gb}" != *$'\n'* && "${live_gb}" =~ ^[1-9][0-9]*$ ]]; then
	if "$GH" variable set ACTIONS_CACHE_LIMIT_CONFIRMED_GB \
		--repo "${REPO}" \
		--body "${live_gb}"; then
		echo "Reconciled ACTIONS_CACHE_LIMIT_CONFIRMED_GB for ${REPO} to live limit: ${live_gb} GB" >&2
	else
		echo "::warning::Failed to update ACTIONS_CACHE_LIMIT_CONFIRMED_GB to live limit ${live_gb} GB for ${REPO}" >&2
	fi
else
	echo "Live Actions cache storage limit unavailable for ${REPO} (got '${live_gb}'); leaving ACTIONS_CACHE_LIMIT_CONFIRMED_GB unchanged" >&2
fi

exit 1
