#!/bin/sh
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Prints the whole-disk device (/dev/diskN) of every attachment of one disk
# image, read from `hdiutil info` on stdin:
#   hdiutil info | Tools/dmg-image-devices.sh <path to the image>
# An image can be attached more than once. A `hdiutil create` that fails with
# "Resource busy" can leave its half-made image attached with no mount point,
# so the only way to find it again is by the image's path. Tools/make-dmg.sh
# detaches each device this prints.
set -eu

awk -v image="$1" '
/^=+$/ { mine = 0; next }
/^image-(path|alias)[ \t]*:/ {
	path = $0
	sub(/^[^:]*:[ \t]*/, "", path)
	if (path == image) mine = 1
	next
}
mine && /^\/dev\/disk[0-9]+[ \t]/ { print $1 }
'
