#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# Copyright (C) 2026 VitruvianSoftware

# Runs the compiled Tools/MakeIcon.swift for a Bazel genrule.
#
# MakeIcon finds its masters at <dir of argv[0]>/../Resources/Brand and writes
# AppIcon.icns, MenuBarIcon.png, MenuBarIcon@2x.png and BrandMark.png next to
# the iconset directory it is given. Stage that layout in a scratch directory,
# then copy the four products to the declared outputs.
#
# usage: make_icons.sh <MakeIcon binary> <Resources/Brand dir> <out dir of the 4 outputs>
set -euo pipefail

tool="$1"
brand="$2"
out_dir="$3"

scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

mkdir -p "$scratch/Tools" "$scratch/Resources" "$scratch/build"
cp "$tool" "$scratch/Tools/MakeIcon"
ln -s "$PWD/$brand" "$scratch/Resources/Brand"

"$scratch/Tools/MakeIcon" "$scratch/build/AppIcon.iconset"

for product in AppIcon.icns MenuBarIcon.png MenuBarIcon@2x.png BrandMark.png; do
	cp "$scratch/build/$product" "$out_dir/$product"
done
