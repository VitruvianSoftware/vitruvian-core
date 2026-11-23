#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Builds a standard-library-only Rust tool with plain rustc, outside Bazel,
# the way the scheduled workflows and package-desktop run these tools:
# <lib.rs> as crate <crate>, then <main.rs> linked against it, to
# <out_dir>/<crate>. When the tool's sources use vitruvian-pycompat or
# vitruvian-jq, those crates are built first and linked in. Every out-of-Bazel
# build of such a tool goes through here, so :rustc_build_test proves on each
# PR what they run.
#
#   rustc-build.sh <out_dir> <crate> <lib.rs> <main.rs> [rustc flags for the lib...]
#   rustc-build.sh --test <out_dir> <crate> <lib.rs> [rustc flags...]  # its unit tests, to <out_dir>/<crate>-test
#   rustc-build.sh --lib <out_dir> <crate> <lib.rs> [rustc flags...]   # rlib only, to <out_dir>/lib<crate>.rlib
#
# RUSTC names the compiler (default: rustc on PATH).
set -euo pipefail

mode=
case "${1:-}" in
--test | --lib)
	mode=$1
	shift
	if [ "$#" -lt 3 ]; then
		echo "usage: rustc-build.sh [--test|--lib] <out_dir> <crate> <lib.rs> [<main.rs>] [rustc flags...]" >&2
		exit 2
	fi
	set -- "$1" "$2" "$3" "-" "${@:4}"
	;;
esac
if [ "$#" -lt 4 ]; then
	echo "usage: rustc-build.sh [--test|--lib] <out_dir> <crate> <lib.rs> [<main.rs>] [rustc flags for the lib...]" >&2
	exit 2
fi
out=$1 crate=$2 lib=$3 main=$4
shift 4
rustc=${RUSTC:-rustc}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p "$out"
externs=()
# find -L: under Bazel the sources are symlinks, which grep -r skips.
if [ -n "$(find -L "$(dirname "$lib")" -name '*.rs' -exec grep -l vitruvian_pycompat {} + 2>/dev/null || true)" ]; then
	"$rustc" --edition 2021 --crate-type lib --crate-name vitruvian_pycompat \
		"$here/src/lib.rs" -o "$out/libvitruvian_pycompat.rlib"
	externs=(--extern "vitruvian_pycompat=$out/libvitruvian_pycompat.rlib")
fi
if [ -n "$(find -L "$(dirname "$lib")" -name '*.rs' -exec grep -l vitruvian_jq {} + 2>/dev/null || true)" ]; then
	repo_root=$(cd "$here/../../.." && pwd)
	jq_dir="$repo_root/packages/jq"
	jq_externs=()
	if [ -n "$(find -L "$jq_dir/src" -name '*.rs' -exec grep -l vitruvian_pycompat {} + 2>/dev/null || true)" ]; then
		if [ ! -f "$out/libvitruvian_pycompat.rlib" ]; then
			"$rustc" --edition 2021 --crate-type lib --crate-name vitruvian_pycompat \
				"$here/src/lib.rs" -o "$out/libvitruvian_pycompat.rlib"
			externs+=(--extern "vitruvian_pycompat=$out/libvitruvian_pycompat.rlib")
		fi
		jq_externs=(--extern "vitruvian_pycompat=$out/libvitruvian_pycompat.rlib")
	fi
	"$rustc" --edition 2021 --crate-type lib --crate-name vitruvian_jq \
		"$jq_dir/src/lib.rs" -L "$out" ${jq_externs[@]+"${jq_externs[@]}"} \
		-o "$out/libvitruvian_jq.rlib"
	externs+=(--extern "vitruvian_jq=$out/libvitruvian_jq.rlib")
fi
if [ "$mode" = --test ]; then
	"$rustc" --edition 2021 --test --crate-name "$crate" "$@" "$lib" \
		-L "$out" ${externs[@]+"${externs[@]}"} -o "$out/$crate-test"
	exit 0
fi
"$rustc" --edition 2021 --crate-type lib --crate-name "$crate" "$@" "$lib" \
	-L "$out" ${externs[@]+"${externs[@]}"} -o "$out/lib$crate.rlib"
if [ "$mode" = --lib ]; then
	exit 0
fi
"$rustc" --edition 2021 "$main" -L "$out" \
	--extern "$crate=$out/lib$crate.rlib" ${externs[@]+"${externs[@]}"} -o "$out/$crate"
