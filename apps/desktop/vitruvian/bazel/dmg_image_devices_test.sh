#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Tools/dmg-image-devices.sh against what `hdiutil info` printed on the macOS
# runner the day a release died: a failed `hdiutil create` had left rw.dmg
# attached as /dev/disk13 with no mount point, and make-dmg.sh could not find
# it to detach it.
#
# usage: dmg_image_devices_test.sh <dmg-image-devices.sh> <hdiutil info dump>
set -euo pipefail

script="$1"
dump="$2"
fail=0

expect() {
	local what="$1" image="$2" want="$3" got
	got="$(sh "$script" "$image" <"$dump" | tr '\n' ' ')"
	if [[ "$got" != "$want" ]]; then
		echo "FAIL: $what: want '$want', got '$got'" >&2
		fail=1
	fi
}

work=/var/folders/5n/5t77mfb93jd7q8v9s6f0dn0m0000gn/T/tmp.CoP6rzGdbe
expect "the image by the path mktemp gave" "$work/rw.dmg" "/dev/disk13 "
expect "the image by its resolved path" "/private$work/rw.dmg" "/dev/disk13 "
expect "an image that is not attached" "$work/rw-2.dmg" ""
expect "a path that only starts another image's" "$work/rw" ""

# Two attachments of one image: both devices, and never a partition (disk7s1).
twice="$(mktemp)"
trap 'rm -f "$twice"' EXIT
printf '%s\n' \
	'================================================' \
	'image-path      : /tmp/a b/rw.dmg' \
	$'/dev/disk7\tGUID_partition_scheme\t' \
	$'/dev/disk7s1\t48465300-0000-11AA-AA11-00306543ECAC\t/Volumes/Vitruvian' \
	'================================================' \
	'image-path      : /tmp/other.dmg' \
	$'/dev/disk8\tGUID_partition_scheme\t' \
	'================================================' \
	'image-path      : /tmp/a b/rw.dmg' \
	$'/dev/disk9\tGUID_partition_scheme\t' >"$twice"
dump="$twice"
expect "an image attached twice" "/tmp/a b/rw.dmg" "/dev/disk7 /dev/disk9 "

exit "$fail"
