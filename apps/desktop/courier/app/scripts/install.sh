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
# Only the Courier at the destination is quit (matched by its exact path), so a copy somewhere else keeps
# running. If it does not quit in ten seconds, or the quit is refused, its processes are sent SIGTERM; after 30
# seconds the install gives up and replaces nothing. The old app is put aside, and put back if anything fails.
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

# The Courier installed at the destination: its app and its engine, matched against the whole command line and
# anchored to this exact path, so another Courier.app (~/Applications, say) is never mistaken for it.
regex_escape() { printf '%s' "$1" | sed 's/[][\\.*^$+?(){}|\/]/\\&/g'; }
patterns=()
for prefix in "$installed" "$(cd "$dest" && pwd -P)/Courier.app"; do
	escaped="$(regex_escape "$prefix")"
	patterns+=("^$escaped/Contents/MacOS/Courier( |\$)" "^$escaped/Contents/Helpers/courier-engine( |\$)")
done
running_pids() {
	local pattern
	for pattern in "${patterns[@]}"; do pgrep -f "$pattern" 2>/dev/null || true; done | sort -u
}
if [ -n "$(running_pids)" ]; then
	echo "Quitting the Courier installed in $dest..."
	osascript -e "quit app \"$installed\"" >/dev/null 2>&1 || true
	waited=0
	while [ -n "$(running_pids)" ] && [ "$waited" -lt 30 ]; do
		sleep 1
		waited=$((waited + 1))
		# Not quit in ten seconds (or the quit was refused): ask the processes themselves to stop.
		if [ "$waited" -eq 10 ]; then
			for pid in $(running_pids); do kill -TERM "$pid" 2>/dev/null || true; done
		fi
	done
	if [ -n "$(running_pids)" ]; then
		echo "install: Courier is still running after 30 seconds. Quit it and run this again; nothing was replaced." >&2
		exit 1
	fi
fi

# ditto keeps the signature and every attribute. The old app is moved aside, not deleted, until the new one is in
# place and passes codesign --verify; any failure, or an interrupt, puts it back.
staging="$dest/.Courier.app.new"
aside="$dest/.Courier.app.old"
trap 'rm -rf "$scratch" "$staging"' EXIT
rm -rf "$staging"

# A run that was interrupted (a power cut, a kill -9) can leave the old app aside. If the installed app is missing,
# that folder may hold the only copy: put it back before anything else. If both are there, the installed one is
# the new app of that run, which may not have been checked: keep whichever passes codesign --verify.
if [ -e "$aside" ]; then
	if [ ! -e "$installed" ]; then
		mv "$aside" "$installed"
		echo "Note: an earlier install was interrupted; the Courier it had set aside is back in $dest."
	elif codesign --verify --deep --strict "$installed" >/dev/null 2>&1; then
		rm -rf "$aside"
	else
		rm -rf "$installed"
		mv "$aside" "$installed"
		echo "Note: an earlier install was interrupted; the Courier it had set aside is back in $dest."
	fi
fi

ditto "$app" "$staging"

# From here the destination changes. What to undo is read from what is on disk, so an interrupt at any moment is
# handled: the old app, if there was one, goes back; on a first install the half-installed app is removed.
had_old=0
if [ -e "$installed" ]; then had_old=1; fi
restore() {
	trap '' INT TERM HUP
	if [ "$had_old" -eq 1 ]; then
		if [ -e "$aside" ]; then
			rm -rf "$installed"
			mv "$aside" "$installed"
		fi
		echo "install: $1 The previous Courier is back in place." >&2
	else
		rm -rf "$installed"
		echo "install: $1 Nothing was installed." >&2
	fi
	exit 1
}
trap 'restore "Interrupted."' INT TERM HUP
if [ "$had_old" -eq 1 ]; then mv "$installed" "$aside"; fi
mv "$staging" "$installed" || restore "Could not move the new app into place."
codesign --verify --deep --strict "$installed" || restore "The new app does not pass codesign --verify."
rm -rf "$aside"
trap - INT TERM HUP
echo "Installed $installed."
