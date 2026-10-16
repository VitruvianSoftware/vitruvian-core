#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Courier.app as Bazel built it holds a working engine. The helper reaches the bundle only through
# macos_application's additional_contents, and nothing else would notice it missing: the app builds, signs and
# opens, and only then says it cannot start its engine. So this opens the archive and looks:
#   - Contents/Helpers/courier-engine is an arm64 Mach-O executable,
#   - it runs, and answers --help with its usage line (exit 2),
#   - the bundle's version is COURIER_VERSION (the engine is stamped with the same constant),
#   - the icon and the English strings are in Contents/Resources.
#
# Usage: app_holds_engine_test.sh <version> <path>...
# The paths: the app rule's outputs (the .zip, or a Courier.app directory).
set -euo pipefail

version="${1:?Usage: app_holds_engine_test.sh <version> <path>...}"
shift

archive=""
app=""
for path in "$@"; do
	case "$path" in
	*.zip) archive="$path" ;;
	*Courier.app) app="$path" ;;
	*)
		# The app rule names its output without the extension; the archive is beside that name.
		if [ -e "$path.zip" ]; then archive="$path.zip"; fi
		;;
	esac
done
if [ -z "$app" ] && [ -n "$archive" ]; then
	unzip -q "$archive" -d "$TEST_TMPDIR/unzipped"
	app="$TEST_TMPDIR/unzipped/Courier.app"
fi
if [ -z "$app" ] || [ ! -d "$app" ]; then
	echo "FAIL: no Courier.app among the paths given: $*" >&2
	exit 2
fi

failed=0
fail() {
	echo "FAIL: $*" >&2
	failed=1
}

engine="$app/Contents/Helpers/courier-engine"
if [ ! -x "$engine" ]; then
	fail "Contents/Helpers/courier-engine is missing or not executable"
	echo "Contents holds:" >&2
	find "$app/Contents" -maxdepth 2 >&2
	exit 1
fi

kind="$(file -b "$engine")"
case "$kind" in
*"Mach-O 64-bit executable arm64"*) echo "ok: courier-engine is $kind" ;;
*) fail "courier-engine is not an arm64 Mach-O executable: $kind" ;;
esac

set +e
help="$("$engine" --help 2>&1)"
status=$?
set -e
if [ "$status" -eq 2 ] && [[ "$help" == *"usage: courier-engine --data DIR [--parent-fd N]"* ]]; then
	echo "ok: courier-engine --help exits 2 with its usage"
else
	fail "courier-engine --help exited $status with: $help"
fi

plist="$app/Contents/Info.plist"
for key in CFBundleShortVersionString CFBundleVersion; do
	got="$(plutil -extract "$key" raw -o - "$plist" 2>/dev/null || true)"
	if [ "$got" = "$version" ]; then
		echo "ok: $key is $version"
	else
		fail "$key is '$got', expected $version"
	fi
done

for resource in AppIcon.icns en.lproj/Localizable.strings; do
	if [ -f "$app/Contents/Resources/$resource" ]; then
		echo "ok: Contents/Resources/$resource"
	else
		fail "Contents/Resources/$resource is missing"
	fi
done

exit "$failed"
