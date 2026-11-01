#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Runs one of this plugin's hooks, which are written in Rust (hooks/src).
#
#   rust-hook.sh <crate> <main source> <fallback JSON>
#
# Antigravity runs a hook as a shell command from the plugin's folder, with a
# few seconds' timeout, and a plugin is installed by copying that folder, so
# there is no build step to lean on. The hook is compiled with `rustc -O` into
# ~/.cache/antigravity-plugins/<plugin>-<hook>-<sha256>, where the hash covers
# this launcher, the rustc flags and every file in hooks/src. Editing any of
# them gives a new hash and so a rebuild.
#
# The build never runs inside the hook's timeout. On a cache miss this starts
# it in its own session (so the host killing the hook's process group does
# not kill it) and answers with <fallback JSON> at once; a later run uses the
# binary. The sources use only Rust's standard library, so a bare `rustc`
# builds them: no cargo, no crates, no network.
#
# This always prints a valid answer and exits 0. Whenever the hook cannot run
# (no rustc, building, a failed build, a broken cached binary, an unsafe cache
# folder) it prints <fallback JSON>, which each hook words so the agent and the
# user are told the plugin is not running, and says why on stderr. A failed
# build is retried after RUST_HOOK_RETRY_MIN minutes (default 10), so
# installing a compiler recovers without a source change.
#
# RUST_HOOK_RUSTC, if set, is the only rustc tried (tests use it).
#
# This file is identical in every plugin under apps/desktop/antigravity/plugins
# (//apps/desktop/antigravity:shared_files_test checks it).

umask 077

crate=${1:-}
main=${2:-}
fallback=${3:-'{}'}
flags="--edition 2021 -O"
retry_min=${RUST_HOOK_RETRY_MIN:-10}
self=$0

answer_fallback() {
	printf '%s hook (%s): %s\n' "${plugin:-plugin}" "${name:-hook}" "$1" >&2
	printf '%s' "$fallback"
	exit 0
}

[ -n "$crate" ] && [ -n "$main" ] || answer_fallback "usage: rust-hook.sh <crate> <main source> <fallback JSON>"
hooks_dir=$(cd "$(dirname "$self")" && pwd) || answer_fallback "cannot find the hooks folder"
src="$hooks_dir/src"
plugin=$(basename "$(dirname "$hooks_dir")")
name=$(basename "$main" .rs)

# Every rustc worth trying, one per line, best first: PATH's, then rustup's
# toolchains newest first (their own binaries, not the proxy, which can stop
# to download), then Homebrew's.
rustcs() {
	if [ -n "${RUST_HOOK_RUSTC+set}" ]; then
		[ -x "$RUST_HOOK_RUSTC" ] && printf '%s\n' "$RUST_HOOK_RUSTC"
		return 0
	fi
	command -v rustc 2>/dev/null
	h=${HOME:-/nonexistent}
	# shellcheck disable=SC2012 # toolchain folder names have no newlines
	ls -td "$h"/.rustup/toolchains/*/ 2>/dev/null | while IFS= read -r t; do
		[ -x "${t}bin/rustc" ] && printf '%s\n' "${t}bin/rustc"
	done
	for p in /opt/homebrew/bin/rustc /usr/local/bin/rustc; do
		[ -x "$p" ] && printf '%s\n' "$p"
	done
	return 0
}

sha256() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 | cut -d' ' -f1
	else
		openssl dgst -sha256 | sed 's/^.* //'
	fi
}

# Modified within the last <minutes> minutes?
recent() { [ -n "$(find "$1" -prune -mmin "-$2" 2>/dev/null)" ]; }

# --- Build mode: run detached by the launcher below -------------------------
if [ "${RUST_HOOK_BUILD:-}" = 1 ]; then
	bin=$RUST_HOOK_BIN
	log=$RUST_HOOK_LOG
	cache=$(dirname "$bin")
	tmp=
	trap 'rm -rf "$tmp" "$bin.lock"' EXIT
	trap 'exit 1' HUP INT TERM
	# Tell the launcher this process is out of the hook's process group.
	: >"$bin.lock/detached"
	# Leftovers of builds that were killed.
	find "$cache" -maxdepth 1 -name '.build.*' -mmin +60 -exec rm -rf {} + 2>/dev/null
	tmp=$(mktemp -d "$cache/.build.XXXXXX") || exit 1
	{
		date
		echo "building $bin"
	} >"$log"
	found=$(rustcs)
	[ -n "$found" ] || echo "no rustc found" >>"$log"
	ok=
	while IFS= read -r rc; do
		[ -n "$rc" ] || continue
		echo "trying $rc" >>"$log"
		# rustc links with cc: make sure the system's is reachable.
		# shellcheck disable=SC2086 # $flags is a fixed word list
		if PATH="$PATH:/usr/bin:/bin" "$rc" $flags --crate-type rlib \
			--crate-name "$crate" -o "$tmp/lib$crate.rlib" "$src/lib.rs" \
			</dev/null >>"$log" 2>&1 &&
			PATH="$PATH:/usr/bin:/bin" "$rc" $flags \
				--extern "$crate=$tmp/lib$crate.rlib" -o "$tmp/hook" "$src/$main" \
				</dev/null >>"$log" 2>&1 &&
			mv -f "$tmp/hook" "$bin"; then
			ok=1
			break
		fi
	done <<EOF
$found
EOF
	if [ -n "$ok" ]; then
		echo "built" >>"$log"
		for old in "$cache/$plugin-$name-"*; do
			case "$old" in "$bin" | "$bin.lock") ;; *) rm -rf "$old" ;; esac
		done
	else
		date +%s >"$bin.failed"
	fi
	exit 0
fi

# --- Launcher -----------------------------------------------------------------

hash=$(
	{
		printf '%s\n' "$crate" "$main" "$flags"
		cat "$hooks_dir/rust-hook.sh"
		cd "$src" && find . -name '*.rs' -type f | LC_ALL=C sort | while IFS= read -r f; do
			printf '%s\n' "$f"
			cat "$f"
		done
	} | sha256
)
case "$hash" in
[0-9a-f]*) ;;
*) answer_fallback "cannot hash $src (no sha256sum, shasum or openssl)" ;;
esac

cache="${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/antigravity-plugins"
mkdir -p "$cache" 2>/dev/null || answer_fallback "cannot create $cache"
# Only run binaries from a folder nobody else can write to: a real folder
# (not a symlink) that we own, not group- or world-writable.
if [ -z "$(find "$cache" -maxdepth 0 -type d -user "$(id -u)" ! -perm -020 ! -perm -002 2>/dev/null)" ]; then
	answer_fallback "refusing $cache: it must be a folder you own that nobody else can write to (not a symlink; chmod 700)"
fi

bin="$cache/$plugin-$name-$hash"
log="$cache/$plugin-$name.log"

if [ -f "$bin" ]; then
	# Read the payload exactly (keeping trailing newlines), then run the hook
	# on it. If the binary cannot run, or dies without answering, throw it
	# away so the next run rebuilds, and answer with the fallback.
	payload=$(
		cat
		printf x
	)
	payload=${payload%x}
	out=$(printf '%s' "$payload" | "$bin")
	status=$?
	if [ "$status" -eq 126 ] || [ "$status" -eq 127 ] ||
		{ [ "$status" -ne 0 ] && [ -z "$out" ]; }; then
		rm -f "$bin"
		printf '%s hook (%s): the cached hook failed (exit %s); removed it to rebuild\n' \
			"$plugin" "$name" "$status" >&2
	else
		[ "$status" -eq 0 ] || printf '%s hook (%s): exited %s\n' "$plugin" "$name" "$status" >&2
		printf '%s' "$out"
		exit 0
	fi
fi

# A cache miss: build in the background, answer now.
if [ -f "$bin.failed" ] && recent "$bin.failed" "$retry_min"; then
	answer_fallback "the last build failed; retrying $retry_min minutes after it. See $log"
fi
[ -n "$(rustcs)" ] ||
	answer_fallback "rustc not found, so the hook cannot be built. Install Rust from https://rustup.rs"
if [ -d "$bin.lock" ] && recent "$bin.lock" 10; then
	answer_fallback "being built in the background; see $log"
fi
rm -rf "$bin.lock" "$bin.failed"
mkdir "$bin.lock" 2>/dev/null || answer_fallback "being built in the background; see $log"

# Its own session where possible (setsid, or Perl's), else its own process
# group (job control); stdio detached so the host is not kept waiting.
export RUST_HOOK_BUILD=1 RUST_HOOK_BIN="$bin" RUST_HOOK_LOG="$log"
if command -v setsid >/dev/null 2>&1; then
	setsid sh "$self" "$crate" "$main" "$fallback" </dev/null >/dev/null 2>&1 &
elif command -v perl >/dev/null 2>&1; then
	perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV or exit 1' \
		sh "$self" "$crate" "$main" "$fallback" </dev/null >/dev/null 2>&1 &
else
	set -m
	sh "$self" "$crate" "$main" "$fallback" </dev/null >/dev/null 2>&1 &
fi
# Answer only once the builder is out of our process group, so the host
# killing that group as soon as we answer cannot take the build with it.
i=0
while [ ! -e "$bin.lock/detached" ] && [ "$i" -lt 40 ]; do
	sleep 0.05
	i=$((i + 1))
done
answer_fallback "building in the background (first run, or the sources changed); see $log"
