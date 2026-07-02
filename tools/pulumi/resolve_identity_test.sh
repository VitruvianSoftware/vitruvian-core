#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
#
# SPDX-License-Identifier: MIT
#
# Unit tests for resolve_identity.sh. The resolver path is passed as $1 (via the
# sh_test `args` + `$(location)`); under `bazel test` the CWD is the runfiles
# root, so that relative path resolves.
set -euo pipefail

RESOLVER="${1:?resolver path must be passed as the first arg}"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
map="$tmp/map.tsv"

cat >"$map" <<'MAP'
# comment — should be ignored
#
infrastructure/pulumi/accounts/personal    james.nguyen@gmail.com   personal-llc   Personal Cloud Run + DNS
-    james@abrial.ai   -   abrial future (reference only)
MAP

fail() { echo "FAIL: $1" >&2; exit 1; }

# 1. Known dir → "account<TAB>project" (purpose column has spaces; must not leak)
got="$(bash "$RESOLVER" "$map" "infrastructure/pulumi/accounts/personal")"
want="$(printf 'james.nguyen@gmail.com\tpersonal-llc')"
[ "$got" = "$want" ] || fail "known dir: got [$got] want [$want]"

# 2. Unknown dir → empty
got="$(bash "$RESOLVER" "$map" "infrastructure/pulumi/platform/repo_config")"
[ -z "$got" ] || fail "unknown dir should be empty, got [$got]"

# 3. The "-" reference placeholder is never matched
got="$(bash "$RESOLVER" "$map" "-")"
[ -z "$got" ] || fail "'-' placeholder should never match, got [$got]"

# 4. Missing map file → empty, exit 0
got="$(bash "$RESOLVER" "$tmp/nope.tsv" "infrastructure/pulumi/accounts/personal")"
[ -z "$got" ] || fail "missing map should be empty, got [$got]"

echo "PASS: resolve_identity.sh"
