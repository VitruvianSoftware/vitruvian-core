#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Tools/beta-publish-guard.sh: what a beta publish does for each way the commit
# it is publishing can relate to the commit the rolling tag points at. The case
# that matters is "behind": run 39344645560 published an older commit's DMGs
# over a newer commit's, because nothing looked at the tag first.
#
# usage: beta_publish_guard_test.sh <beta-publish-guard.sh>
set -euo pipefail

script="$1"
fail=0

expect() {
	local what="$1" status="$2" want="$3" got
	got="$(sh "$script" "$status")"
	if [[ "$got" != "$want" ]]; then
		echo "FAIL: $what ('$status'): want '$want', got '$got'" >&2
		fail=1
	fi
}

expect "this commit is newer than the tag's" ahead publish
expect "a re-run of the commit the tag points at" identical publish
expect "the tag does not exist yet" absent publish
expect "the release already holds a newer build" behind skip
expect "the two commits have diverged" diverged refuse
expect "a status we do not know" something-new refuse
expect "no status at all" "" refuse

# A skip is not an error: the job must go green.
if ! sh "$script" behind >/dev/null; then
	echo "FAIL: skipping a stale publish must exit 0" >&2
	fail=1
fi

exit "$fail"
