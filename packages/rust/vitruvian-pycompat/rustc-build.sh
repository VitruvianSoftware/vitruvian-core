#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Builds a standard-library-only Rust tool with plain rustc, outside Bazel,
# the way the scheduled workflows and package-desktop run these tools:
# <lib.rs> as crate <crate>, then <main.rs> linked against it, to
# <out_dir>/<crate>. When the tool's sources use vitruvian-pycompat, that
# crate is built first and linked in. Every out-of-Bazel build of such a tool
# goes through here, so :rustc_build_test proves on each PR what they run.
#
#   rustc-build.sh <out_dir> <crate> <lib.rs> <main.rs> [rustc flags for the lib...]
#
# RUSTC names the compiler (default: rustc on PATH).
set -euo pipefail

if [ "$#" -lt 4 ]; then
	echo "usage: rustc-build.sh <out_dir> <crate> <lib.rs> <main.rs> [rustc flags for the lib...]" >&2
	exit 2
fi
out=$1 crate=$2 lib=$3 main=$4
shift 4
rustc=${RUSTC:-rustc}
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

mkdir -p "$out"
externs=()
# find -L: under Bazel the sources are symlinks, which grep -r skips.
if find -L "$(dirname "$lib")" -name '*.rs' -exec grep -l vitruvian_pycompat {} + 2>/dev/null | grep -q .; then
	"$rustc" --edition 2021 --crate-type lib --crate-name vitruvian_pycompat \
		"$here/src/lib.rs" -o "$out/libvitruvian_pycompat.rlib"
	externs=(--extern "vitruvian_pycompat=$out/libvitruvian_pycompat.rlib")
fi
"$rustc" --edition 2021 --crate-type lib --crate-name "$crate" "$@" "$lib" \
	-L "$out" ${externs[@]+"${externs[@]}"} -o "$out/lib$crate.rlib"
"$rustc" --edition 2021 "$main" -L "$out" \
	--extern "$crate=$out/lib$crate.rlib" -o "$out/$crate"
