#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Writes the Info.plist fragment that stamps the fan helper's version.
#
# The app compares this value with the registered daemon to decide whether the
# privileged helper must be re-registered, so it has to change whenever the
# helper binary or its launchd plist does. Same derivation as build.sh: a
# SHA-256 over the two files' SHA-256 digests.
#
# usage: helper_version_plist.sh <helper binary> <launchd plist> <out.plist>
set -euo pipefail

helper="$1"
launchd_plist="$2"
out="$3"

version="$(
	export LC_ALL=C
	/usr/bin/shasum -a 256 "$helper" "$launchd_plist" |
		/usr/bin/awk '{print $1}' | /usr/bin/shasum -a 256 |
		/usr/bin/awk '{print $1}'
)"

cat >"$out" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>VorssaintFanControlHelperVersion</key>
	<string>${version}</string>
</dict>
</plist>
EOF
