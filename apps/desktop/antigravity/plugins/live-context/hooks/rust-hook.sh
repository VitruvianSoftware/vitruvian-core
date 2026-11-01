#!/bin/sh
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Runs one of this plugin's hooks, which are written in Rust (hooks/src).
#
#   rust-hook.sh <crate> <main source> <fallback JSON>
#
# Antigravity runs a hook as a shell command from the plugin's folder, and a
# plugin is installed by copying that folder, so there is no build step to
# lean on. The first time a hook runs, this compiles it with `rustc -O` into
# ~/.cache/antigravity-plugins/<plugin>-<hook>-<sha256 of hooks/src>, and every
# later run reuses that binary (about 1-2 s once, then nothing). Editing the
# sources changes the hash, so the next run rebuilds.
#
# The sources use only Rust's standard library, so a bare `rustc` builds them:
# no cargo, no crates, no network. tools/agent-guard/hook.sh works the same way.
#
# When the hook cannot be built (no rustc, or it does not compile), this
# prints <fallback JSON> on stdout, which each hook words so the agent and the
# user are told the plugin is not running, and says why on stderr. It never
# silently does nothing. A build that failed is not retried on every call
# until the sources or the set of rustcs change.
#
# RUST_HOOK_RUSTC, if set, is the only rustc tried (tests use it).
#
# This file is identical in every plugin under apps/desktop/antigravity/plugins.

set -u

crate=$1
main=$2
fallback=$3

hooks_dir=$(cd "$(dirname "$0")" && pwd) || exit 1
src="$hooks_dir/src"
plugin=$(basename "$(dirname "$hooks_dir")")
name=$(basename "$main" .rs)

fail() {
	printf '%s hook (%s): %s\n' "$plugin" "$name" "$1" >&2
	printf '%s' "$fallback"
	exit 0
}

# Every rustc worth trying. The toolchains' own binaries come before rustup's
# proxy (~/.cargo/bin/rustc), which can stop to download a toolchain. A
# desktop app may start hooks with a short PATH, so PATH comes last.
rustcs() {
	if [ -n "${RUST_HOOK_RUSTC+set}" ]; then
		[ -x "$RUST_HOOK_RUSTC" ] && echo "$RUST_HOOK_RUSTC"
		return 0
	fi
	h=${HOME:-/nonexistent}
	for p in "$h"/.rustup/toolchains/*/bin/rustc \
		/opt/homebrew/bin/rustc /usr/local/bin/rustc "$h"/.cargo/bin/rustc; do
		[ -x "$p" ] && echo "$p"
	done
	command -v rustc 2>/dev/null
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

# Hash every source file's name and content, in a fixed order, plus which
# binary is wanted.
hash=$(
	{
		printf '%s\n' "$crate" "$main"
		cd "$src" || exit 1
		find . -name '*.rs' -type f | LC_ALL=C sort | while IFS= read -r f; do
			printf '%s\n' "$f"
			cat "$f"
		done
	} | sha256
) || fail "cannot read $src"
[ -n "$hash" ] || fail "cannot hash $src (no sha256sum, shasum or openssl)"

cache="${XDG_CACHE_HOME:-${HOME:-/nonexistent}/.cache}/antigravity-plugins"
bin="$cache/$plugin-$name-$hash"
log="$cache/$plugin-$name.log"

if [ ! -x "$bin" ]; then
	found=$(rustcs | tr '\n' ' ')
	[ -n "$found" ] ||
		fail "rustc not found, so the hook cannot be built. Install Rust from https://rustup.rs"
	if [ -f "$bin.failed" ] && [ "$(cat "$bin.failed" 2>/dev/null)" = "$found" ]; then
		fail "it did not build with $found; see $log"
	fi
	mkdir -p "$cache" 2>/dev/null || fail "cannot create $cache"
	: >"$log" 2>/dev/null
	built=
	for rc in $found; do
		# Build in a private folder and rename into place, so two hooks
		# starting at once never run a half-written binary. rustc links with
		# cc: make sure the system's is reachable.
		tmp=$(mktemp -d "$cache/.build.XXXXXX") || fail "cannot create a build folder in $cache"
		if PATH="$PATH:/usr/bin:/bin" "$rc" --edition 2021 -O --crate-type rlib \
			--crate-name "$crate" -o "$tmp/lib$crate.rlib" "$src/lib.rs" \
			</dev/null >>"$log" 2>&1 &&
			PATH="$PATH:/usr/bin:/bin" "$rc" --edition 2021 -O \
				--extern "$crate=$tmp/lib$crate.rlib" -o "$tmp/hook" "$src/$main" \
				</dev/null >>"$log" 2>&1 &&
			mv -f "$tmp/hook" "$bin"; then
			rm -rf "$tmp"
			built=1
			break
		fi
		rm -rf "$tmp"
	done
	if [ -z "$built" ]; then
		printf '%s' "$found" >"$bin.failed" 2>/dev/null
		fail "it does not build with $found; see $log"
	fi
	# Drop binaries and failure notes left by older sources.
	for old in "$cache/$plugin-$name-"*; do
		[ "$old" = "$bin" ] || rm -f "$old"
	done
fi

exec "$bin"
