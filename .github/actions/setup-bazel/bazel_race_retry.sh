#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# A `bazel` wrapper for the self-hosted vitruvian-queue runners: it runs the
# command again when, and only when, it failed on the shared repo contents
# cache race.
#
# The race. The pool keeps Bazel's repo contents cache
# (~/.cache/bazel-repo/contents) on one NFS volume shared by every runner pod.
# Bazel 9.3.2 (and 9.3.3, and master as of 2026-11-25) moves a freshly fetched
# repo into contents/<predeclared inputs hash>/<uuid>, creating the
# contents/<hash> directory first with a check-then-create
# (LocalRepoContentsCache.moveToCache -> UnixFileSystem.createDirectoryAndParents):
# stat (missing), mkdir (EEXIST, because another pod just made it), lstat
# again to confirm it is a directory. On this NFS volume that last lstat can
# come back empty, and Bazel then fails the whole build with
#
#   error moving repo @@<repo> into the repo contents cache:
#   /home/runner/.cache/bazel-repo/contents/<hash> (File exists)
#
# It only happens the first time any pod fetches a repo the cache has never
# seen, while another pod fetches the same one: a dependency bump that adds
# repos, in the merge queue, where a dozen jobs start together. #5536's queue
# run 45708649713 lost build-test and license-check to it on 2026-11-25.
#
# Why a retry is enough. The losing pod's next attempt finds contents/<hash>
# already there (the stat succeeds, nothing is created), so that repo cannot
# race again. A bump that adds hundreds of repos can lose a different one on
# the next attempt, so this retries up to VITRUVIAN_BAZEL_RACE_RETRIES times
# (default 3); every attempt keeps the repos the last one fetched.
#
# What is never retried: a success; any failure whose stderr lacks that exact
# error; and a `bazel run` whose program had already started ("Running command
# line:" printed), so a program with side effects never runs twice.
#
# Remove this once Bazel tolerates a concurrent mkdir there and we are on that
# version. Not reported upstream as of 2026-11-25 (bazelbuild/bazel#32656, the
# open "move fresh fetches into the repo contents cache" change, does not
# touch this path).
#
# Usage:
#   bazel_race_retry.sh install <shim-dir>   from setup-bazel, once per job:
#       installs this file as <shim-dir>/bazel, records the real Bazel in
#       VITRUVIAN_REAL_BAZEL ($GITHUB_ENV) and puts <shim-dir> first on PATH
#       ($GITHUB_PATH) for the job's later steps.
#   bazel <args...>                          as the installed wrapper.

set -uo pipefail

SIGNATURE='error moving repo @@[^ ]+ into the repo contents cache: [^ ]+ \(File exists\)'

# The first executable `bazel` on PATH that is not in $1 (the shim's own dir).
find_real_bazel() {
	local exclude dir
	exclude="$(cd "$1" 2>/dev/null && pwd -P || printf '%s' "$1")"
	local IFS=:
	for dir in $PATH; do
		[ -n "$dir" ] || continue
		if [ "$(cd "$dir" 2>/dev/null && pwd -P)" = "$exclude" ]; then
			continue
		fi
		if [ -x "$dir/bazel" ] && [ ! -d "$dir/bazel" ]; then
			printf '%s\n' "$dir/bazel"
			return 0
		fi
	done
	return 1
}

install_shim() {
	local shim_dir="${1:?usage: bazel_race_retry.sh install <shim-dir>}"
	mkdir -p "$shim_dir" || return 1
	local real="${VITRUVIAN_REAL_BAZEL:-}"
	if [ -z "$real" ] || [ ! -x "$real" ] || [ "$real" -ef "$shim_dir/bazel" ]; then
		if ! real="$(find_real_bazel "$shim_dir")"; then
			echo "::warning title=Bazel race retry::no bazel on PATH; not installing the retry wrapper"
			return 0
		fi
	fi
	cp "${BASH_SOURCE[0]}" "$shim_dir/bazel" || return 1
	chmod 0755 "$shim_dir/bazel" || return 1
	if [ -n "${GITHUB_ENV:-}" ]; then
		printf 'VITRUVIAN_REAL_BAZEL=%s\n' "$real" >>"$GITHUB_ENV"
	fi
	if [ -n "${GITHUB_PATH:-}" ]; then
		printf '%s\n' "$shim_dir" >>"$GITHUB_PATH"
	fi
	echo "bazel race retry: $shim_dir/bazel wraps $real"
}

run_with_retry() {
	local self_dir real
	self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
	real="${VITRUVIAN_REAL_BAZEL:-}"
	if [ -z "$real" ] || [ ! -x "$real" ] || [ "$real" -ef "${BASH_SOURCE[0]}" ]; then
		if ! real="$(find_real_bazel "$self_dir")"; then
			echo "bazel race retry: cannot find the real bazel on PATH" >&2
			return 127
		fi
	fi

	local retries="${VITRUVIAN_BAZEL_RACE_RETRIES:-3}"
	local log
	log="$(mktemp "${RUNNER_TEMP:-${TMPDIR:-/tmp}}/bazel-stderr.XXXXXX")" || {
		"$real" "$@"
		return $?
	}
	# shellcheck disable=SC2064 # expand $log now
	trap "rm -f '$log'" EXIT

	exec 3>&1
	local attempt=0 status repo
	while :; do
		attempt=$((attempt + 1))
		# stdout goes straight through (fd 3); stderr is shown and kept in $log.
		"$real" "$@" 2>&1 1>&3 3>&- | tee "$log" >&2
		status=${PIPESTATUS[0]}
		if [ "$status" -eq 0 ] || [ "$attempt" -gt "$retries" ]; then
			return "$status"
		fi
		if ! grep -Eq "$SIGNATURE" "$log"; then
			return "$status"
		fi
		if grep -Fq 'Running command line:' "$log"; then
			return "$status" # `bazel run` had started its program
		fi
		repo="$(grep -Eo 'error moving repo @@[^ ]+' "$log" | head -n 1)"
		repo="${repo#error moving repo }"
		echo "::warning title=Bazel repo contents cache race::${repo} lost the race to another runner pod creating its cache entry (exit ${status}); running the same bazel command again (retry ${attempt} of ${retries})" >&2
	done
}

if [ "${1:-}" = "install" ] && [ "$(basename "${BASH_SOURCE[0]}")" != "bazel" ]; then
	shift
	install_shim "$@"
	exit $?
fi
run_with_retry "$@"
exit $?
