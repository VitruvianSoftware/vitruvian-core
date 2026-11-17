#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# The tools that scheduled workflows and package-desktop build with plain
# rustc still build that way and run: sync-downloads (site-sync-downloads,
# package-desktop --sync-downloads) and agent-app's permission-drift
# (agent-app-permissions), and release-scope with its tests (the required
# release-scope check). Their only CI is a schedule or a push to main, so
# without this a missing link surfaces the next morning, not on the PR.
set -euo pipefail

: "${REAL_RUSTC:?}"
export RUSTC
RUSTC=$(cd "$(dirname "$REAL_RUSTC")" && pwd)/$(basename "$REAL_RUSTC")
build=packages/rust/vitruvian-pycompat/rustc-build.sh
out=${TEST_TMPDIR:-$(mktemp -d)}

bash "$build" "$out/sync" sync_downloads \
	tools/sync-downloads/src/lib.rs tools/sync-downloads/src/main.rs
"$out/sync/sync_downloads" --help >/dev/null
echo "PASS sync_downloads builds with plain rustc and runs"

bash "$build" "$out/drift" permission_drift \
	tools/agent-app/src/lib.rs tools/agent-app/src/main.rs \
	--cfg 'feature="standalone_permission_drift"'
"$out/drift/permission_drift" --help >/dev/null
echo "PASS permission_drift builds with plain rustc and runs"

bash "$build" "$out/scope" release_scope \
	tools/release-scope/src/lib.rs tools/release-scope/src/main.rs
"$out/scope/release_scope" --help >/dev/null
bash "$build" --test "$out/scope" release_scope tools/release-scope/src/lib.rs
"$out/scope/release_scope-test" >/dev/null
echo "PASS release_scope and its tests build with plain rustc and run"
