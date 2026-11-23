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
build=packages/pycompat/vitruvian-pycompat/rustc-build.sh
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

bash "$build" --lib "$out/appset-lib" appset_render \
	tools/gitops/appset-render/src/lib.rs -O
test -f "$out/appset-lib/libvitruvian_pycompat.rlib"
test -f "$out/appset-lib/libappset_render.rlib"
echo "PASS appset_render rlib builds with plain rustc (--lib) and links pycompat"

bash "$build" "$out/appset" appset_render \
	tools/gitops/appset-render/src/lib.rs tools/gitops/appset-render/src/main.rs -O
"$out/appset/appset_render" --help >/dev/null 2>&1
bash "$build" --test "$out/appset" appset_render tools/gitops/appset-render/src/lib.rs -O
"$out/appset/appset_render-test" >/dev/null
echo "PASS appset_render and its tests build with plain rustc and run"

bash "$build" "$out/pipeline" pipeline_status \
	tools/pipeline-status/src/lib.rs tools/pipeline-status/src/main.rs -O
test -f "$out/pipeline/libvitruvian_jq.rlib"
test -x "$out/pipeline/pipeline_status"
bash "$build" --test "$out/pipeline" pipeline_status tools/pipeline-status/src/lib.rs -O
"$out/pipeline/pipeline_status-test" >/dev/null
echo "PASS pipeline_status and its tests build with plain rustc (linking vitruvian_jq) and run"

bash "$build" "$out/osv" osv_scan tools/osv-scan/src/lib.rs tools/osv-scan/src/main.rs
test -f "$out/osv/libvitruvian_jq.rlib"
test -x "$out/osv/osv_scan"
echo "PASS osv_scan builds with plain rustc (linking vitruvian_jq)"

bash "$build" "$out/catalog-bump" catalog catalog/src/lib.rs catalog/src/bin/bump.rs
test -f "$out/catalog-bump/libvitruvian_pycompat.rlib"
"$out/catalog-bump/catalog" --help >/dev/null
bash "$build" "$out/catalog-dl" catalog catalog/src/lib.rs catalog/src/bin/check_downloads.rs -O
test -f "$out/catalog-dl/libvitruvian_pycompat.rlib"
"$out/catalog-dl/catalog" --help >/dev/null
echo "PASS catalog (bump and check_downloads) build with plain rustc (linking vitruvian_pycompat) and run"
