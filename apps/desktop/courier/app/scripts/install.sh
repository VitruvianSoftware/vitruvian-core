#!/bin/bash
# Copyright 2026 VitruvianSoftware
# SPDX-License-Identifier: AGPL-3.0-or-later
#
# Puts the Courier.app Bazel built into /Applications, with Courier's own Telegram app ID in it.
#
#   bazel run --config=macos-app //apps/desktop/courier/app:install [-- --dest DIR]
#
# It builds nothing itself beyond what `bazel run` builds for it (Courier.zip, as a dependency). It
#   1. unpacks the zip into a temporary folder,
#   2. adds the Telegram app ID and signs the app again (inject-app-credentials.sh, with --allow-missing: a Mac
#      with no keys in the store still gets an app, which asks for them),
#   3. quits the Courier that is installed at the destination if it is running, and waits for its engine to stop,
#   4. replaces DIR/Courier.app (DIR is /Applications unless --dest says otherwise),
#   5. checks the installed app with `codesign --verify --deep --strict`.
# Only the Courier at the destination is quit, so a copy somewhere else keeps running.
#
# Usage (as bazel run passes it): install.sh <inject-app-credentials.sh> <Courier.zip> [--dest DIR]
set -euo pipefail

injector="${1:?Usage: install.sh <inject-app-credentials.sh> <Courier.zip> [--dest DIR]}"
archive="${2:?Usage: install.sh <inject-app-credentials.sh> <Courier.zip> [--dest DIR]}"
shift 2

dest="/Applications"
while [ "$#" -gt 0 ]; do
	case "$1" in
	--dest)
		dest="${2:?--dest needs a folder}"
		shift
		;;
	*)
		echo "install: unknown argument $1" >&2
		exit 2
		;;
	esac
	shift
done

# `bazel run` gives every output of the app rule, space separated: the archive is the .zip among them.
chosen=""
for candidate in $archive; do
	case "$candidate" in
	*.zip) chosen="$candidate" ;;
	*) if [ -z "$chosen" ] && [ -f "$candidate.zip" ]; then chosen="$candidate.zip"; fi ;;
	esac
done
if [ -n "$chosen" ]; then archive="$chosen"; fi
if [ ! -f "$archive" ]; then
	echo "install: no Courier.zip at $archive" >&2
	exit 2
fi
if [ ! -d "$dest" ]; then
	echo "install: $dest is not a folder" >&2
	exit 2
fi
dest="$(cd "$dest" && pwd)"
installed="$dest/Courier.app"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/courier-install.XXXXXX")"
trap 'rm -rf "$scratch"' EXIT

unzip -q "$archive" -d "$scratch/unpacked"
app="$scratch/unpacked/Courier.app"
if [ ! -d "$app" ]; then
	echo "install: the archive holds no Courier.app" >&2
	exit 1
fi

# The injector says what it did; with no keys in the store it says so and carries on.
"$injector" --allow-missing "$app"
if [ ! -f "$app/Contents/Resources/TelegramApp.plist" ]; then
	echo "Note: this Courier has no Telegram app ID built in, so it will ask for Telegram keys when Telegram is added."
fi

# Quit the Courier installed at the destination, by its path, and wait for its engine to go.
engine_running() { pgrep -f "$installed/Contents/Helpers/courier-engine" >/dev/null 2>&1; }
app_running() { pgrep -f "$installed/Contents/MacOS/Courier" >/dev/null 2>&1; }
if app_running || engine_running; then
	echo "Quitting the Courier installed in $dest..."
	osascript -e "quit app \"$installed\"" >/dev/null 2>&1 || true
	waited=0
	while { app_running || engine_running; } && [ "$waited" -lt 30 ]; do
		sleep 1
		waited=$((waited + 1))
	done
	if app_running || engine_running; then
		echo "install: Courier is still running after 30 seconds. Quit it and run this again; nothing was replaced." >&2
		exit 1
	fi
fi

# ditto keeps the signature and every attribute; the old app goes only when the new one is in place beside it.
ditto "$app" "$dest/.Courier.app.new"
rm -rf "$installed"
mv "$dest/.Courier.app.new" "$installed"

if ! codesign --verify --deep --strict "$installed"; then
	echo "install: the installed app does not pass codesign --verify." >&2
	exit 1
fi
echo "Installed $installed."
