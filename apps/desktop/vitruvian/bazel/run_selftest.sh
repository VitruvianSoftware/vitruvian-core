#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Bazel test wrapper for the app's runtime health check (`--selftest`).
#
# The self test reads resources through Bundle.main (the menu bar icon, the
# symbol gallery), so it has to run from inside the assembled bundle, not from
# a bare binary. rules_apple emits the bundle as a .zip unless tree-artifact
# outputs are on; accept either.
#
# usage: run_selftest.sh <executable name> <the bundle target's files...>
# The bundle target's files are its `bazel run` launcher plus the archive (or
# the .app with tree-artifact outputs); the archive is picked out of them.
set -euo pipefail

executable="$1"
shift
bundle=""
for candidate in "$@"; do
	case "$candidate" in
	*.zip | *.app)
		bundle="$candidate"
		break
		;;
	esac
done
if [[ -z "$bundle" ]]; then
	for candidate in "$@"; do
		if [[ -e "$candidate.zip" ]]; then
			bundle="$candidate.zip"
			break
		fi
	done
fi

case "$bundle" in
*.zip)
	# ditto keeps the extended attributes and code signature intact.
	/usr/bin/ditto -x -k "$bundle" "$TEST_TMPDIR/bundle"
	app="$(find "$TEST_TMPDIR/bundle" -maxdepth 1 -name '*.app' -print -quit)"
	;;
*.app) app="$bundle" ;;
*)
	echo "no .zip or .app among the bundle outputs: $*" >&2
	exit 2
	;;
esac

[[ -n "${app:-}" && -x "$app/Contents/MacOS/$executable" ]] || {
	echo "no executable Contents/MacOS/$executable in ${app:-<missing bundle>}" >&2
	exit 1
}

/usr/bin/codesign --verify --deep --strict "$app"
exec "$app/Contents/MacOS/$executable" --selftest
