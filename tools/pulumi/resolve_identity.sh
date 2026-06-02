#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Resolve the GCP account + project declared for a Pulumi project directory in
# the identity map. Used by tools/pulumi/pulumi_cmd.sh and unit-tested directly.
#
# Usage:  resolve_identity.sh <map_file> <infra_dir>
# Output: "<account>\t<gcp_project>" when <infra_dir> is listed (and is not the
#         "-" reference placeholder); nothing otherwise. Exits 0 on all normal
#         paths; exits non-zero only if called with missing/empty arguments.
set -euo pipefail

map="${1:?usage: resolve_identity.sh <map_file> <infra_dir>}"
dir="${2:?usage: resolve_identity.sh <map_file> <infra_dir>}"

[ -f "$map" ] || exit 0

awk -v d="$dir" '
  $1 ~ /^#/ { next }          # comment lines
  NF == 0   { next }          # blank lines
  $1 == "-" { next }          # reference-only rows
  $1 == d   { printf "%s\t%s\n", $2, $3; exit }
' "$map"
