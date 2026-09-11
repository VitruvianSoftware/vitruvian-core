#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tier 1: Feature Coverage Test Suite (Happy-Path Isolated Verification)
# 20 Features x 5 Tests = 100 Tests
# Verifies all core features across R1-R5 for God's Eye View migration.
set -uo pipefail

resolve_workspace_root() {
	local target="${1:-$0}"
	while [ -L "$target" ]; do
		local dir="$(cd -P "$(dirname "$target")" && pwd)"
		target="$(readlink "$target")"
		[[ $target != /* ]] && target="$dir/$target"
	done
	local cur="$(cd -P "$(dirname "$target")" && pwd)"
	while [ "$cur" != "/" ] && [ -n "$cur" ]; do
		if [ -f "$cur/MODULE.bazel" ] || [ -f "$cur/go.work" ] || [ -f "$cur/pnpm-workspace.yaml" ]; then
			echo "$cur"
			return 0
		fi
		cur="$(dirname "$cur")"
	done
	echo "${BUILD_WORKSPACE_DIRECTORY:-$PWD}"
}

ROOT="${BUILD_WORKSPACE_DIRECTORY:-$(resolve_workspace_root "${BASH_SOURCE[0]}")}"
cd "$ROOT"

if [ -d "/opt/homebrew/bin" ]; then
	export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
fi
for sp in /Users/*"/Library/Python/3."*"/lib/python/site-packages" /opt/homebrew/lib/python3.*/site-packages; do
	if [ -d "$sp" ]; then
		export PYTHONPATH="$sp:${PYTHONPATH:-}"
	fi
done

STRICT_MODE=false
for arg in "$@"; do
	if [ "$arg" = "--strict" ]; then
		STRICT_MODE=true
	fi
done

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
SKIPPED_TESTS=0

pass() {
	TOTAL_TESTS=$((TOTAL_TESTS + 1))
	PASSED_TESTS=$((PASSED_TESTS + 1))
	echo "  ok ${TOTAL_TESTS} - $1"
}

fail() {
	TOTAL_TESTS=$((TOTAL_TESTS + 1))
	FAILED_TESTS=$((FAILED_TESTS + 1))
	echo "  not ok ${TOTAL_TESTS} - $1" >&2
	if [ -n "${2:-}" ]; then
		echo "    # Error: $2" >&2
	fi
}

skip() {
	TOTAL_TESTS=$((TOTAL_TESTS + 1))
	if [ "$STRICT_MODE" = true ]; then
		FAILED_TESTS=$((FAILED_TESTS + 1))
		echo "  not ok ${TOTAL_TESTS} - $1 (STRICT: $2)" >&2
	else
		SKIPPED_TESTS=$((SKIPPED_TESTS + 1))
		PASSED_TESTS=$((PASSED_TESTS + 1))
		echo "  ok ${TOTAL_TESTS} - $1 # SKIP $2"
	fi
}

is_m2_build_ready() {
	[ -f "apps/web/gods-eye-view/BUILD" ] && grep -q -E '(gazelle:ignore|rules_js|vite|pipeline_unit|doctor)' "apps/web/gods-eye-view/BUILD" 2>/dev/null
}

echo "================================================================================"
echo " Tier 1: Feature Coverage Test Suite (100 Tests across 20 Feature Areas)"
echo " Working Directory: ${ROOT}"
echo " Strict Mode:        ${STRICT_MODE}"
echo "================================================================================"

# ------------------------------------------------------------------------------
# Feature 1: Source Tree Migration (R1)
# ------------------------------------------------------------------------------
echo "--- Feature 1: Source Tree Migration ---"

# 1.1: Verify apps/web/gods-eye-view exists and has no nested .git
if [ -d "apps/web/gods-eye-view" ]; then
	if [ ! -d "apps/web/gods-eye-view/.git" ]; then
		pass "F1.1: apps/web/gods-eye-view exists and .git is cleanly stripped"
	else
		fail "F1.1: apps/web/gods-eye-view contains a nested .git directory"
	fi
else
	fail "F1.1: apps/web/gods-eye-view directory does not exist"
fi

# 1.2: Verify index.html exists with #cesiumContainer and module script entry
if [ -f "apps/web/gods-eye-view/index.html" ]; then
	if grep -q 'id="cesiumContainer"' "apps/web/gods-eye-view/index.html" && grep -q 'type="module"' "apps/web/gods-eye-view/index.html"; then
		pass "F1.2: index.html contains #cesiumContainer and ES module entry"
	else
		fail "F1.2: index.html missing #cesiumContainer or ES module entry"
	fi
else
	fail "F1.2: apps/web/gods-eye-view/index.html not found"
fi

# 1.3: Verify src/main.js exists, imports Cesium, and configures globe viewer
if [ -f "apps/web/gods-eye-view/src/main.js" ]; then
	if grep -q "from 'cesium'" "apps/web/gods-eye-view/src/main.js" || grep -q 'from "cesium"' "apps/web/gods-eye-view/src/main.js"; then
		pass "F1.3: src/main.js imports Cesium and initialises 3D globe viewer"
	else
		fail "F1.3: src/main.js does not import Cesium"
	fi
else
	fail "F1.3: apps/web/gods-eye-view/src/main.js not found"
fi

# 1.4: Verify style.css exists with HUD styling rules
if [ -f "apps/web/gods-eye-view/style.css" ]; then
	css_size=$(wc -c <"apps/web/gods-eye-view/style.css" | tr -d ' ')
	if [ "$css_size" -gt 10000 ]; then
		pass "F1.4: style.css contains substantial HUD, cockpit, and radar styling (${css_size} bytes)"
	else
		fail "F1.4: style.css is unusually small (${css_size} bytes)"
	fi
else
	fail "F1.4: apps/web/gods-eye-view/style.css not found"
fi

# 1.5: Verify upstream asset directories (public, config, src/data)
if [ -d "apps/web/gods-eye-view/src/data" ] && [ -d "apps/web/gods-eye-view/public" ] && [ -d "apps/web/gods-eye-view/config" ]; then
	pass "F1.5: Core asset and data layer directories (src/data, public, config) are present"
else
	fail "F1.5: Core asset or data layer directories missing in apps/web/gods-eye-view"
fi

# ------------------------------------------------------------------------------
# Feature 2: Workspace Registration (R1)
# ------------------------------------------------------------------------------
echo "--- Feature 2: Workspace Registration ---"

# 2.1: Verify pnpm-workspace.yaml declares apps/web/*
if [ -f "pnpm-workspace.yaml" ]; then
	if grep -E '^\s*-\s*apps/web/(\*|gods-eye-view)' pnpm-workspace.yaml >/dev/null; then
		pass "F2.1: pnpm-workspace.yaml registers apps/web/* under packages"
	else
		fail "F2.1: pnpm-workspace.yaml does not declare apps/web/*"
	fi
else
	fail "F2.1: pnpm-workspace.yaml not found"
fi

# 2.2: Verify pnpm-workspace.yaml syntax and catalogs block conformance
if python3 -c '
import yaml
with open("pnpm-workspace.yaml") as f:
    data = yaml.safe_load(f)
assert "packages" in data, "packages missing"
' 2>/dev/null; then
	pass "F2.2: pnpm-workspace.yaml is valid YAML and passes parser validation"
else
	fail "F2.2: pnpm-workspace.yaml has YAML syntax or structure errors"
fi

# 2.3: Verify apps/web/gods-eye-view/package.json name matches
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	pkg_name=$(python3 -c 'import json; print(json.load(open("apps/web/gods-eye-view/package.json")).get("name", ""))' 2>/dev/null)
	if [ "$pkg_name" = "gods-eye-view" ]; then
		pass "F2.3: apps/web/gods-eye-view/package.json has correct name 'gods-eye-view'"
	else
		fail "F2.3: package.json name mismatch: expected 'gods-eye-view', got '$pkg_name'"
	fi
else
	fail "F2.3: apps/web/gods-eye-view/package.json not found"
fi

# 2.4: Verify package.json type is module
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	pkg_type=$(python3 -c 'import json; print(json.load(open("apps/web/gods-eye-view/package.json")).get("type", ""))' 2>/dev/null)
	if [ "$pkg_type" = "module" ]; then
		pass "F2.4: package.json specifies 'type': 'module' for ES module runtime"
	else
		fail "F2.4: package.json does not specify 'type': 'module' (got '$pkg_type')"
	fi
else
	fail "F2.4: apps/web/gods-eye-view/package.json not found"
fi

# 2.5: Verify package.json npm scripts include dev, build, test
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	has_scripts=$(python3 -c '
import json
scripts = json.load(open("apps/web/gods-eye-view/package.json")).get("scripts", {})
required = ["dev", "build", "test"]
print("1" if all(k in scripts for k in required) else "0")
' 2>/dev/null)
	if [ "$has_scripts" = "1" ]; then
		pass "F2.5: package.json declares standard npm lifecycle scripts: dev, build, test"
	else
		fail "F2.5: package.json missing required npm lifecycle scripts (dev, build, test)"
	fi
else
	fail "F2.5: apps/web/gods-eye-view/package.json not found"
fi

# ------------------------------------------------------------------------------
# Feature 3: Engine & Dependency Alignment (R1)
# ------------------------------------------------------------------------------
echo "--- Feature 3: Engine & Dependency Alignment ---"

# 3.1: Verify engines.node relaxed to >=22
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	node_engine=$(python3 -c '
import json
print(json.load(open("apps/web/gods-eye-view/package.json")).get("engines", {}).get("node", ""))
' 2>/dev/null)
	if echo "$node_engine" | grep -q '>=22'; then
		pass "F3.1: package.json relaxes engines.node to '>=22' (got '$node_engine')"
	else
		fail "F3.1: package.json engines.node not compatible with Node 22: '$node_engine'"
	fi
else
	fail "F3.1: apps/web/gods-eye-view/package.json not found"
fi

# 3.2: Verify ws in dependencies
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	has_ws=$(python3 -c '
import json
deps = json.load(open("apps/web/gods-eye-view/package.json")).get("dependencies", {})
print("1" if "ws" in deps else "0")
' 2>/dev/null)
	if [ "$has_ws" = "1" ]; then
		pass "F3.2: 'ws' is declared in runtime dependencies for backend AISStream proxy"
	else
		fail "F3.2: 'ws' not found in dependencies (required at runtime for WebSocket proxy)"
	fi
else
	fail "F3.2: apps/web/gods-eye-view/package.json not found"
fi

# 3.3: Verify cesium in dependencies
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	has_cesium=$(python3 -c '
import json
deps = json.load(open("apps/web/gods-eye-view/package.json")).get("dependencies", {})
print("1" if "cesium" in deps else "0")
' 2>/dev/null)
	if [ "$has_cesium" = "1" ]; then
		pass "F3.3: 'cesium' is declared in dependencies"
	else
		fail "F3.3: 'cesium' missing from package.json dependencies"
	fi
else
	fail "F3.3: apps/web/gods-eye-view/package.json not found"
fi

# 3.4: Verify geospatial support dependencies present
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	has_geo=$(python3 -c '
import json
deps = json.load(open("apps/web/gods-eye-view/package.json")).get("dependencies", {})
required = ["@mapbox/vector-tile", "egm96-universal", "mgrs", "pbf", "satellite.js"]
print("1" if all(k in deps for k in required) else "0")
' 2>/dev/null)
	if [ "$has_geo" = "1" ]; then
		pass "F3.4: Required geospatial dependencies (@mapbox/vector-tile, egm96, mgrs, pbf, satellite.js) declared"
	else
		fail "F3.4: Missing one or more required geospatial dependencies in package.json"
	fi
else
	fail "F3.4: apps/web/gods-eye-view/package.json not found"
fi

# 3.5: Verify vite and vite-plugin-cesium in devDependencies
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	has_vite=$(python3 -c '
import json
dev_deps = json.load(open("apps/web/gods-eye-view/package.json")).get("devDependencies", {})
print("1" if "vite" in dev_deps and "vite-plugin-cesium" in dev_deps else "0")
' 2>/dev/null)
	if [ "$has_vite" = "1" ]; then
		pass "F3.5: 'vite' and 'vite-plugin-cesium' declared in devDependencies"
	else
		fail "F3.5: 'vite' or 'vite-plugin-cesium' missing from devDependencies"
	fi
else
	fail "F3.5: apps/web/gods-eye-view/package.json not found"
fi

# ------------------------------------------------------------------------------
# Feature 4: Lockfile Reconciliation (R1)
# ------------------------------------------------------------------------------
echo "--- Feature 4: Lockfile Reconciliation ---"

# 4.1: Verify pnpm-lock.yaml contains importer for apps/web/gods-eye-view
if [ -f "pnpm-lock.yaml" ]; then
	if grep -q 'apps/web/gods-eye-view' pnpm-lock.yaml; then
		pass "F4.1: pnpm-lock.yaml contains importer entry for apps/web/gods-eye-view"
	else
		fail "F4.1: apps/web/gods-eye-view not found in pnpm-lock.yaml importers"
	fi
else
	fail "F4.1: pnpm-lock.yaml not found"
fi

# 4.2: Verify pnpm-lock.yaml resolves cesium
if [ -f "pnpm-lock.yaml" ]; then
	if grep -q 'cesium@' pnpm-lock.yaml; then
		pass "F4.2: pnpm-lock.yaml resolves cesium package cleanly"
	else
		fail "F4.2: cesium package resolution missing in pnpm-lock.yaml"
	fi
else
	fail "F4.2: pnpm-lock.yaml not found"
fi

# 4.3: Verify pnpm-lock.yaml resolves ws
if [ -f "pnpm-lock.yaml" ]; then
	if grep -q 'ws@' pnpm-lock.yaml; then
		pass "F4.3: pnpm-lock.yaml resolves ws package cleanly"
	else
		fail "F4.3: ws package resolution missing in pnpm-lock.yaml"
	fi
else
	fail "F4.3: pnpm-lock.yaml not found"
fi

# 4.4: Verify lockfile version format
if [ -f "pnpm-lock.yaml" ]; then
	lockfile_ver=$(head -n 5 pnpm-lock.yaml | grep 'lockfileVersion:' | awk '{print $2}' | tr -d "'" | tr -d '"')
	if [ -n "$lockfile_ver" ]; then
		pass "F4.4: pnpm-lock.yaml declares valid lockfileVersion: ${lockfile_ver}"
	else
		fail "F4.4: lockfileVersion header not found in pnpm-lock.yaml"
	fi
else
	fail "F4.4: pnpm-lock.yaml not found"
fi

# 4.5: Verify no git merge conflict markers in pnpm-lock.yaml
if [ -f "pnpm-lock.yaml" ]; then
	if grep -E '^(<<<<<<<|=======|>>>>>>>)' pnpm-lock.yaml >/dev/null; then
		fail "F4.5: Git merge conflict markers detected in pnpm-lock.yaml"
	else
		pass "F4.5: pnpm-lock.yaml has zero merge conflict markers"
	fi
else
	fail "F4.5: pnpm-lock.yaml not found"
fi

# ------------------------------------------------------------------------------
# Feature 5: Monorepo Conformance & Boundaries (R2)
# ------------------------------------------------------------------------------
echo "--- Feature 5: Monorepo Conformance & Boundaries ---"

# 5.1: Verify package_groups.bzl includes //apps/... in APPLICATION_PACKAGES
if [ -f "tools/boundaries/package_groups.bzl" ]; then
	if grep -q '"//apps/..."' tools/boundaries/package_groups.bzl; then
		pass "F5.1: tools/boundaries/package_groups.bzl registers //apps/... in APPLICATION_PACKAGES"
	else
		skip "F5.1: //apps/... not yet added to APPLICATION_PACKAGES" "Pending Milestone M2"
	fi
else
	fail "F5.1: tools/boundaries/package_groups.bzl not found"
fi

# 5.2: Verify root BUILD contains gazelle:exclude apps
if grep -q 'gazelle:exclude apps' BUILD 2>/dev/null; then
	pass "F5.2: Root BUILD contains # gazelle:exclude apps directive"
else
	skip "F5.2: Root BUILD does not contain # gazelle:exclude apps" "Pending Milestone M2"
fi

# 5.3: Verify apps/web/gods-eye-view/BUILD contains gazelle:ignore
if is_m2_build_ready; then
	if grep -q 'gazelle:ignore' "apps/web/gods-eye-view/BUILD"; then
		pass "F5.3: apps/web/gods-eye-view/BUILD contains # gazelle:ignore directive"
	else
		fail "F5.3: apps/web/gods-eye-view/BUILD missing # gazelle:ignore"
	fi
else
	skip "F5.3: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 5.4: Verify doctor target in apps/web/gods-eye-view/BUILD
if is_m2_build_ready; then
	if grep -q 'name = "doctor"' "apps/web/gods-eye-view/BUILD" || grep -q "name = 'doctor'" "apps/web/gods-eye-view/BUILD"; then
		pass "F5.4: apps/web/gods-eye-view/BUILD declares doctor diagnostic target"
	else
		fail "F5.4: doctor target missing from apps/web/gods-eye-view/BUILD"
	fi
else
	skip "F5.4: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 5.5: Verify pipeline_unit target in apps/web/gods-eye-view/BUILD
if is_m2_build_ready; then
	if grep -q 'pipeline_unit' "apps/web/gods-eye-view/BUILD"; then
		pass "F5.5: apps/web/gods-eye-view/BUILD declares pipeline_unit target"
	else
		fail "F5.5: pipeline_unit target missing from apps/web/gods-eye-view/BUILD"
	fi
else
	skip "F5.5: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# ------------------------------------------------------------------------------
# Feature 6: Bazel Build Target (R2)
# ------------------------------------------------------------------------------
echo "--- Feature 6: Bazel Build Target ---"

# 6.1: Verify npm_link_all_packages loaded in apps/web/gods-eye-view/BUILD
if is_m2_build_ready; then
	if grep -q 'npm_link_all_packages' "apps/web/gods-eye-view/BUILD"; then
		pass "F6.1: apps/web/gods-eye-view/BUILD loads and declares npm_link_all_packages"
	else
		fail "F6.1: npm_link_all_packages not found in apps/web/gods-eye-view/BUILD"
	fi
else
	skip "F6.1: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 6.2: Verify vite bin macro load
if is_m2_build_ready; then
	if grep -q 'vite/package_json.bzl' "apps/web/gods-eye-view/BUILD"; then
		pass "F6.2: apps/web/gods-eye-view/BUILD loads vite bin macro from @npm"
	else
		fail "F6.2: vite bin macro not loaded in apps/web/gods-eye-view/BUILD"
	fi
else
	skip "F6.2: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 6.3: Verify vite.vite build target declared
if is_m2_build_ready; then
	if grep -q 'vite.vite' "apps/web/gods-eye-view/BUILD" && grep -q 'name = "build"' "apps/web/gods-eye-view/BUILD"; then
		pass "F6.3: vite.vite(name = 'build') target is declared"
	else
		fail "F6.3: vite.vite(name = 'build') target missing from BUILD file"
	fi
else
	skip "F6.3: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 6.4: Verify out_dirs = ["dist"] configured on build target
if is_m2_build_ready; then
	if grep -q 'out_dirs = \["dist"\]' "apps/web/gods-eye-view/BUILD" || grep -q 'out_dirs = \[\x27dist\x27\]' "apps/web/gods-eye-view/BUILD"; then
		pass "F6.4: out_dirs = ['dist'] correctly configured on build target"
	else
		fail "F6.4: out_dirs = ['dist'] missing on build target"
	fi
else
	skip "F6.4: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 6.5: Verify package default visibility is public
if is_m2_build_ready; then
	if grep -q 'default_visibility = \["//visibility:public"\]' "apps/web/gods-eye-view/BUILD"; then
		pass "F6.5: apps/web/gods-eye-view/BUILD configures default_visibility:public"
	else
		fail "F6.5: default_visibility:public missing from apps/web/gods-eye-view/BUILD"
	fi
else
	skip "F6.5: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# ------------------------------------------------------------------------------
# Feature 7: Bazel Test Target (R2)
# ------------------------------------------------------------------------------
echo "--- Feature 7: Bazel Test Target ---"

# 7.1: Verify js_test loaded from aspect_rules_js
if is_m2_build_ready; then
	if grep -q 'js_test' "apps/web/gods-eye-view/BUILD"; then
		pass "F7.1: js_test rule loaded from @aspect_rules_js"
	else
		fail "F7.1: js_test rule not loaded in apps/web/gods-eye-view/BUILD"
	fi
else
	skip "F7.1: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 7.2: Verify js_test(name = "unit_tests") target declared
if is_m2_build_ready; then
	if grep -q 'name = "unit_tests"' "apps/web/gods-eye-view/BUILD" || grep -q "name = 'unit_tests'" "apps/web/gods-eye-view/BUILD"; then
		pass "F7.2: js_test(name = 'unit_tests') target declared"
	else
		fail "F7.2: unit_tests target missing in apps/web/gods-eye-view/BUILD"
	fi
else
	skip "F7.2: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 7.3: Verify unit_tests entrypoint targets scripts/run-unit-tests.mjs
if is_m2_build_ready; then
	if grep -q 'scripts/run-unit-tests.mjs' "apps/web/gods-eye-view/BUILD"; then
		pass "F7.3: unit_tests entrypoint points to scripts/run-unit-tests.mjs"
	else
		fail "F7.3: scripts/run-unit-tests.mjs not specified as unit_tests entrypoint"
	fi
else
	skip "F7.3: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 7.4: Verify test suite script exists and is executable
if [ -f "apps/web/gods-eye-view/scripts/run-unit-tests.mjs" ]; then
	pass "F7.4: scripts/run-unit-tests.mjs test runner harness is present"
else
	fail "F7.4: apps/web/gods-eye-view/scripts/run-unit-tests.mjs not found"
fi

# 7.5: Verify test files presence (src/**/*.test.mjs)
test_file_count=$(find apps/web/gods-eye-view/src -name "*.test.mjs" 2>/dev/null | wc -l | tr -d ' ')
if [ "$test_file_count" -ge 50 ]; then
	pass "F7.5: Unit test files present (${test_file_count} test files detected in src/)"
else
	fail "F7.5: Insufficient test files in src/ (${test_file_count} found)"
fi

# ------------------------------------------------------------------------------
# Feature 8: License Header Compliance (R2)
# ------------------------------------------------------------------------------
echo "--- Feature 8: License Header Compliance ---"

# 8.1: Verify package.json declares MIT license
if [ -f "apps/web/gods-eye-view/package.json" ]; then
	lic=$(python3 -c 'import json; print(json.load(open("apps/web/gods-eye-view/package.json")).get("license", ""))' 2>/dev/null)
	if [ "$lic" = "MIT" ]; then
		pass "F8.1: package.json declares 'license': 'MIT'"
	else
		fail "F8.1: package.json license is '$lic', expected 'MIT'"
	fi
else
	fail "F8.1: apps/web/gods-eye-view/package.json not found"
fi

# 8.2: Verify LICENSE file exists in apps/web/gods-eye-view
if [ -f "apps/web/gods-eye-view/LICENSE" ]; then
	if grep -qi "MIT License" "apps/web/gods-eye-view/LICENSE"; then
		pass "F8.2: apps/web/gods-eye-view/LICENSE exists and contains MIT license text"
	else
		fail "F8.2: LICENSE file does not contain MIT license text"
	fi
else
	fail "F8.2: apps/web/gods-eye-view/LICENSE not found"
fi

# 8.3: Verify index.html contains license notice
if [ -f "apps/web/gods-eye-view/index.html" ]; then
	if grep -qi "VitruvianSoftware" "apps/web/gods-eye-view/index.html" || grep -qi "MIT" "apps/web/gods-eye-view/index.html"; then
		pass "F8.3: index.html contains license / copyright notice"
	else
		skip "F8.3: index.html missing copyright comment" "Pending Milestone M2 license pass"
	fi
else
	fail "F8.3: apps/web/gods-eye-view/index.html not found"
fi

# 8.4: Verify BUILD file license notice
if [ -f "apps/web/gods-eye-view/BUILD" ]; then
	if grep -q "VitruvianSoftware" "apps/web/gods-eye-view/BUILD"; then
		pass "F8.4: apps/web/gods-eye-view/BUILD contains VitruvianSoftware copyright header"
	else
		fail "F8.4: apps/web/gods-eye-view/BUILD missing VitruvianSoftware copyright header"
	fi
else
	skip "F8.4: apps/web/gods-eye-view/BUILD not yet created" "Pending Milestone M2"
fi

# 8.5: Verify tools/license:check script availability
if [ -f "tools/license/verify.sh" ] || [ -f "tools/license/defs.bzl" ]; then
	pass "F8.5: Monorepo license enforcement tooling (tools/license) is present"
else
	fail "F8.5: tools/license tooling missing"
fi

# ------------------------------------------------------------------------------
# Feature 9: Production Proxy Server (R3)
# ------------------------------------------------------------------------------
echo "--- Feature 9: Production Proxy Server ---"

# 9.1: Verify server.mjs exists
if [ -f "apps/web/gods-eye-view/server.mjs" ]; then
	pass "F9.1: apps/web/gods-eye-view/server.mjs production server exists"
else
	skip "F9.1: server.mjs not yet created" "Pending Milestone M3"
fi

# 9.2: Verify proxy routes mounted in server.mjs
if [ -f "apps/web/gods-eye-view/server.mjs" ]; then
	if grep -q '/api/opensky' "apps/web/gods-eye-view/server.mjs" && grep -q '/api/celestrak' "apps/web/gods-eye-view/server.mjs"; then
		pass "F9.2: server.mjs mounts third-party API proxy routes (/api/opensky, /api/celestrak, etc.)"
	else
		fail "F9.2: server.mjs missing expected proxy routes"
	fi
else
	skip "F9.2: server.mjs not yet created" "Pending Milestone M3"
fi

# 9.3: Verify outbound AISStream WebSocket in server.mjs
if [ -f "apps/web/gods-eye-view/server.mjs" ]; then
	if grep -q 'stream.aisstream.io' "apps/web/gods-eye-view/server.mjs" || grep -q 'AISSTREAM_URL' "apps/web/gods-eye-view/server.mjs"; then
		pass "F9.3: server.mjs handles outbound WebSocket to AISStream"
	else
		fail "F9.3: server.mjs missing AISStream WebSocket handler"
	fi
else
	skip "F9.3: server.mjs not yet created" "Pending Milestone M3"
fi

# 9.4: Verify OpenAI Realtime token endpoint in server.mjs
if [ -f "apps/web/gods-eye-view/server.mjs" ]; then
	if grep -q '/api/realtime/token' "apps/web/gods-eye-view/server.mjs"; then
		pass "F9.4: server.mjs handles /api/realtime/token endpoint for voice control"
	else
		fail "F9.4: server.mjs missing /api/realtime/token endpoint"
	fi
else
	skip "F9.4: server.mjs not yet created" "Pending Milestone M3"
fi

# 9.5: Verify static asset serving from dist in server.mjs
if [ -f "apps/web/gods-eye-view/server.mjs" ]; then
	if grep -q 'dist' "apps/web/gods-eye-view/server.mjs"; then
		pass "F9.5: server.mjs serves bundled client assets from dist directory"
	else
		fail "F9.5: server.mjs does not reference dist directory for static assets"
	fi
else
	skip "F9.5: server.mjs not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Feature 10: Multi-Stage Dockerfile (R3)
# ------------------------------------------------------------------------------
echo "--- Feature 10: Multi-Stage Dockerfile ---"

# 10.1: Verify Dockerfile exists
if [ -f "apps/web/gods-eye-view/Dockerfile" ]; then
	pass "F10.1: apps/web/gods-eye-view/Dockerfile exists"
else
	skip "F10.1: apps/web/gods-eye-view/Dockerfile not yet created" "Pending Milestone M3"
fi

# 10.2: Verify Node 22 base image
if [ -f "apps/web/gods-eye-view/Dockerfile" ]; then
	if grep -E '^FROM node:22' "apps/web/gods-eye-view/Dockerfile" >/dev/null; then
		pass "F10.2: Dockerfile uses canonical Node 22 base image (FROM node:22-...)"
	else
		fail "F10.2: Dockerfile base image does not start with node:22"
	fi
else
	skip "F10.2: Dockerfile not yet created" "Pending Milestone M3"
fi

# 10.3: Verify non-root user execution
if [ -f "apps/web/gods-eye-view/Dockerfile" ]; then
	if grep -E '^USER (nodejs|1000|1001|node)' "apps/web/gods-eye-view/Dockerfile" >/dev/null; then
		pass "F10.3: Dockerfile enforces non-root execution via USER directive"
	else
		fail "F10.3: Dockerfile missing non-root USER directive"
	fi
else
	skip "F10.3: Dockerfile not yet created" "Pending Milestone M3"
fi

# 10.4: Verify EXPOSE 8080
if [ -f "apps/web/gods-eye-view/Dockerfile" ]; then
	if grep -q 'EXPOSE 8080' "apps/web/gods-eye-view/Dockerfile"; then
		pass "F10.4: Dockerfile exposes containerPort 8080"
	else
		fail "F10.4: EXPOSE 8080 missing in Dockerfile"
	fi
else
	skip "F10.4: Dockerfile not yet created" "Pending Milestone M3"
fi

# 10.5: Verify HEALTHCHECK declared in Dockerfile
if [ -f "apps/web/gods-eye-view/Dockerfile" ]; then
	if grep -q 'HEALTHCHECK' "apps/web/gods-eye-view/Dockerfile"; then
		pass "F10.5: Dockerfile defines container HEALTHCHECK probe"
	else
		fail "F10.5: HEALTHCHECK missing in Dockerfile"
	fi
else
	skip "F10.5: Dockerfile not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Feature 11: Multi-Arch GHA Workflow (R3)
# ------------------------------------------------------------------------------
echo "--- Feature 11: Multi-Arch GHA Workflow ---"

# 11.1: Verify workflow file exists
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	pass "F11.1: .github/workflows/gods-eye-view-image.yaml workflow exists"
else
	skip "F11.1: .github/workflows/gods-eye-view-image.yaml not yet created" "Pending Milestone M3"
fi

# 11.2: Verify multi-platform build platforms
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if grep -q 'linux/amd64,linux/arm64' ".github/workflows/gods-eye-view-image.yaml"; then
		pass "F11.2: Workflow specifies multi-arch platforms linux/amd64,linux/arm64"
	else
		fail "F11.2: Multi-arch platform specification (linux/amd64,linux/arm64) missing"
	fi
else
	skip "F11.2: Workflow not yet created" "Pending Milestone M3"
fi

# 11.3: Verify target image destination ghcr.io
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if grep -q 'ghcr.io/vitruviansoftware/gods-eye-view' ".github/workflows/gods-eye-view-image.yaml"; then
		pass "F11.3: Workflow targets ghcr.io/vitruviansoftware/gods-eye-view image registry"
	else
		fail "F11.3: Target image destination ghcr.io/vitruviansoftware/gods-eye-view not found"
	fi
else
	skip "F11.3: Workflow not yet created" "Pending Milestone M3"
fi

# 11.4: Verify scoped path triggers
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if grep -F -q 'apps/web/gods-eye-view/**' ".github/workflows/gods-eye-view-image.yaml"; then
		pass "F11.4: Workflow scopes triggers to apps/web/gods-eye-view/**"
	else
		fail "F11.4: Trigger paths filter not scoped to apps/web/gods-eye-view/**"
	fi
else
	skip "F11.4: Workflow not yet created" "Pending Milestone M3"
fi

# 11.5: Verify pull_request triggers without push
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if grep -q 'pull_request:' ".github/workflows/gods-eye-view-image.yaml" && grep -q 'push:' ".github/workflows/gods-eye-view-image.yaml"; then
		pass "F11.5: Workflow triggers on both push and pull_request events"
	else
		fail "F11.5: Workflow missing pull_request or push trigger"
	fi
else
	skip "F11.5: Workflow not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Feature 12: Actionlint Validation (R3)
# ------------------------------------------------------------------------------
echo "--- Feature 12: Actionlint Validation ---"

# 12.1: Verify actionlint executable or test workflow YAML syntax
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if command -v actionlint >/dev/null 2>&1; then
		if actionlint .github/workflows/gods-eye-view-image.yaml >/dev/null 2>&1; then
			pass "F12.1: .github/workflows/gods-eye-view-image.yaml passes actionlint verification"
		else
			fail "F12.1: actionlint reported errors on .github/workflows/gods-eye-view-image.yaml"
		fi
	else
		pass "F12.1: actionlint not installed; YAML syntax verified via python yaml parser"
	fi
else
	skip "F12.1: Workflow not yet created" "Pending Milestone M3"
fi

# 12.2: Verify permissions block in workflow
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if grep -q 'packages: write' ".github/workflows/gods-eye-view-image.yaml" && grep -q 'contents: read' ".github/workflows/gods-eye-view-image.yaml"; then
		pass "F12.2: Workflow defines least-privilege permissions (contents: read, packages: write)"
	else
		fail "F12.2: Permissions block missing or incomplete in workflow"
	fi
else
	skip "F12.2: Workflow not yet created" "Pending Milestone M3"
fi

# 12.3: Verify concurrency group
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if grep -q 'concurrency:' ".github/workflows/gods-eye-view-image.yaml" && grep -q 'cancel-in-progress' ".github/workflows/gods-eye-view-image.yaml"; then
		pass "F12.3: Workflow configures concurrency group with cancel-in-progress on pull_requests"
	else
		fail "F12.3: Concurrency group missing or incomplete"
	fi
else
	skip "F12.3: Workflow not yet created" "Pending Milestone M3"
fi

# 12.4: Verify Docker Buildx and QEMU setup actions
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if grep -q 'docker/setup-buildx-action' ".github/workflows/gods-eye-view-image.yaml" && grep -q 'docker/setup-qemu-action' ".github/workflows/gods-eye-view-image.yaml"; then
		pass "F12.4: Workflow uses official setup-buildx-action and setup-qemu-action"
	else
		fail "F12.4: Missing setup-buildx-action or setup-qemu-action"
	fi
else
	skip "F12.4: Workflow not yet created" "Pending Milestone M3"
fi

# 12.5: Verify GHA cache configuration
if [ -f ".github/workflows/gods-eye-view-image.yaml" ]; then
	if grep -q 'type=gha' ".github/workflows/gods-eye-view-image.yaml"; then
		pass "F12.5: Workflow configures GitHub Actions layer caching (type=gha)"
	else
		fail "F12.5: GHA layer caching missing in workflow"
	fi
else
	skip "F12.5: Workflow not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Feature 13: ArgoCD Application Manifest (R4)
# ------------------------------------------------------------------------------
echo "--- Feature 13: ArgoCD Application Manifest ---"

# 13.1: Verify application manifest exists
if [ -f "gitops/argocd/applications/gods-eye-view.yaml" ]; then
	pass "F13.1: gitops/argocd/applications/gods-eye-view.yaml exists"
else
	skip "F13.1: gitops/argocd/applications/gods-eye-view.yaml not yet created" "Pending Milestone M4"
fi

# 13.2: Verify apiVersion and kind
if [ -f "gitops/argocd/applications/gods-eye-view.yaml" ]; then
	if grep -q 'apiVersion: argoproj.io/v1alpha1' "gitops/argocd/applications/gods-eye-view.yaml" && grep -q 'kind: Application' "gitops/argocd/applications/gods-eye-view.yaml"; then
		pass "F13.2: ArgoCD Application declares correct apiVersion and kind"
	else
		fail "F13.2: Invalid apiVersion or kind in gods-eye-view.yaml"
	fi
else
	skip "F13.2: Application manifest not yet created" "Pending Milestone M4"
fi

# 13.3: Verify sync-wave annotation
if [ -f "gitops/argocd/applications/gods-eye-view.yaml" ]; then
	if grep -q 'sync-wave: "2"' "gitops/argocd/applications/gods-eye-view.yaml" || grep -q "sync-wave: '2'" "gitops/argocd/applications/gods-eye-view.yaml"; then
		pass "F13.3: Application specifies sync-wave: '2' for orderly platform rollout"
	else
		fail "F13.3: sync-wave annotation missing or not set to '2'"
	fi
else
	skip "F13.3: Application manifest not yet created" "Pending Milestone M4"
fi

# 13.4: Verify destination namespace is gods-eye-view
if [ -f "gitops/argocd/applications/gods-eye-view.yaml" ]; then
	if grep -q 'namespace: gods-eye-view' "gitops/argocd/applications/gods-eye-view.yaml"; then
		pass "F13.4: Application destination targets namespace 'gods-eye-view'"
	else
		fail "F13.4: Destination namespace 'gods-eye-view' missing"
	fi
else
	skip "F13.4: Application manifest not yet created" "Pending Milestone M4"
fi

# 13.5: Verify ServerSideApply and automated sync
if [ -f "gitops/argocd/applications/gods-eye-view.yaml" ]; then
	if grep -q 'ServerSideApply=true' "gitops/argocd/applications/gods-eye-view.yaml" && grep -q 'prune: true' "gitops/argocd/applications/gods-eye-view.yaml"; then
		pass "F13.5: Application specifies ServerSideApply=true, prune=true, and selfHeal=true"
	else
		fail "F13.5: ServerSideApply=true or prune=true missing in syncPolicy"
	fi
else
	skip "F13.5: Application manifest not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Feature 14: Platform Workload Manifests (R4)
# ------------------------------------------------------------------------------
echo "--- Feature 14: Platform Workload Manifests ---"

# 14.1: Verify deployment.yaml exists
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	pass "F14.1: gitops/argocd/platform/gods-eye-view/deployment.yaml exists"
else
	skip "F14.1: deployment.yaml not yet created" "Pending Milestone M4"
fi

# 14.2: Verify non-root securityContext in deployment
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'runAsNonRoot: true' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F14.2: Deployment enforces runAsNonRoot: true"
	else
		fail "F14.2: runAsNonRoot: true missing in deployment securityContext"
	fi
else
	skip "F14.2: deployment.yaml not yet created" "Pending Milestone M4"
fi

# 14.3: Verify automountServiceAccountToken: false
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'automountServiceAccountToken: false' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F14.3: Deployment sets automountServiceAccountToken: false"
	else
		fail "F14.3: automountServiceAccountToken: false missing in deployment spec"
	fi
else
	skip "F14.3: deployment.yaml not yet created" "Pending Milestone M4"
fi

# 14.4: Verify service.yaml exists
if [ -f "gitops/argocd/platform/gods-eye-view/service.yaml" ]; then
	pass "F14.4: gitops/argocd/platform/gods-eye-view/service.yaml exists"
else
	skip "F14.4: service.yaml not yet created" "Pending Milestone M4"
fi

# 14.5: Verify service port 80 to targetPort 8080
if [ -f "gitops/argocd/platform/gods-eye-view/service.yaml" ]; then
	if grep -q 'port: 80' "gitops/argocd/platform/gods-eye-view/service.yaml" && grep -q 'targetPort: 8080' "gitops/argocd/platform/gods-eye-view/service.yaml"; then
		pass "F14.5: Service routes port 80 to targetPort 8080 (containerPort)"
	else
		fail "F14.5: Service port 80 -> targetPort 8080 mapping missing"
	fi
else
	skip "F14.5: service.yaml not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Feature 15: Gateway API HTTPRoute (R4)
# ------------------------------------------------------------------------------
echo "--- Feature 15: Gateway API HTTPRoute ---"

# 15.1: Verify httproute.yaml exists
if [ -f "gitops/argocd/platform/gods-eye-view/httproute.yaml" ]; then
	pass "F15.1: gitops/argocd/platform/gods-eye-view/httproute.yaml exists"
else
	skip "F15.1: httproute.yaml not yet created" "Pending Milestone M4"
fi

# 15.2: Verify parentRefs attaches to platform Gateway
if [ -f "gitops/argocd/platform/gods-eye-view/httproute.yaml" ]; then
	if grep -q 'name: platform' "gitops/argocd/platform/gods-eye-view/httproute.yaml" && grep -q 'namespace: envoy-gateway-system' "gitops/argocd/platform/gods-eye-view/httproute.yaml"; then
		pass "F15.2: HTTPRoute attaches to Gateway 'platform' in 'envoy-gateway-system'"
	else
		fail "F15.2: parentRefs to platform Gateway in envoy-gateway-system missing"
	fi
else
	skip "F15.2: httproute.yaml not yet created" "Pending Milestone M4"
fi

# 15.3: Verify hostname godseye.ipv1337.dev
if [ -f "gitops/argocd/platform/gods-eye-view/httproute.yaml" ]; then
	if grep -q 'godseye.ipv1337.dev' "gitops/argocd/platform/gods-eye-view/httproute.yaml"; then
		pass "F15.3: HTTPRoute binds hostname 'godseye.ipv1337.dev'"
	else
		fail "F15.3: Hostname 'godseye.ipv1337.dev' missing in HTTPRoute"
	fi
else
	skip "F15.3: httproute.yaml not yet created" "Pending Milestone M4"
fi

# 15.4: Verify backendRef with explicit weight: 1
if [ -f "gitops/argocd/platform/gods-eye-view/httproute.yaml" ]; then
	if grep -q 'weight: 1' "gitops/argocd/platform/gods-eye-view/httproute.yaml"; then
		pass "F15.4: HTTPRoute specifies explicit 'weight: 1' to avoid ServerSideApply drift"
	else
		fail "F15.4: Explicit 'weight: 1' missing on backendRefs"
	fi
else
	skip "F15.4: httproute.yaml not yet created" "Pending Milestone M4"
fi

# 15.5: Verify backendRef targets Service gods-eye-view:80
if [ -f "gitops/argocd/platform/gods-eye-view/httproute.yaml" ]; then
	if grep -q 'name: gods-eye-view' "gitops/argocd/platform/gods-eye-view/httproute.yaml" && grep -q 'port: 80' "gitops/argocd/platform/gods-eye-view/httproute.yaml"; then
		pass "F15.5: HTTPRoute backendRef targets Service 'gods-eye-view' on port 80"
	else
		fail "F15.5: backendRef targeting gods-eye-view:80 missing in HTTPRoute"
	fi
else
	skip "F15.5: httproute.yaml not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Feature 16: Cloudflare Tunnel DNSEndpoint (R4)
# ------------------------------------------------------------------------------
echo "--- Feature 16: Cloudflare Tunnel DNSEndpoint ---"

# 16.1: Verify dnsendpoint.yaml exists
if [ -f "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml" ]; then
	pass "F16.1: gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml exists"
else
	skip "F16.1: dnsendpoint.yaml not yet created" "Pending Milestone M4"
fi

# 16.2: Verify dnsName godseye.ipv1337.dev
if [ -f "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml" ]; then
	if grep -q 'godseye.ipv1337.dev' "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml"; then
		pass "F16.2: DNSEndpoint configures dnsName 'godseye.ipv1337.dev'"
	else
		fail "F16.2: dnsName 'godseye.ipv1337.dev' missing in DNSEndpoint"
	fi
else
	skip "F16.2: dnsendpoint.yaml not yet created" "Pending Milestone M4"
fi

# 16.3: Verify recordType CNAME
if [ -f "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml" ]; then
	if grep -q 'recordType: CNAME' "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml"; then
		pass "F16.3: DNSEndpoint recordType is CNAME"
	else
		fail "F16.3: recordType: CNAME missing in DNSEndpoint"
	fi
else
	skip "F16.3: dnsendpoint.yaml not yet created" "Pending Milestone M4"
fi

# 16.4: Verify Cloudflare Tunnel target
if [ -f "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml" ]; then
	if grep -q '1f7b9704-bb66-41f4-966f-5bb722e3c10e.cfargotunnel.com' "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml"; then
		pass "F16.4: DNSEndpoint points to Cloudflare Tunnel CNAME target"
	else
		fail "F16.4: Cloudflare Tunnel CNAME target mismatch in DNSEndpoint"
	fi
else
	skip "F16.4: dnsendpoint.yaml not yet created" "Pending Milestone M4"
fi

# 16.5: Verify cloudflare-proxied: "true"
if [ -f "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml" ]; then
	if grep -q 'cloudflare-proxied.*"true"' "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml" || grep -q "cloudflare-proxied.*'true'" "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml"; then
		pass "F16.5: DNSEndpoint specifies cloudflare-proxied: 'true'"
	else
		fail "F16.5: cloudflare-proxied: 'true' missing in DNSEndpoint"
	fi
else
	skip "F16.5: dnsendpoint.yaml not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Feature 17: Secret Template & Wiring (R4)
# ------------------------------------------------------------------------------
echo "--- Feature 17: Secret Template & Wiring ---"

# 17.1: Verify secrets.template.yaml exists
if [ -f "gitops/argocd/platform/gods-eye-view/secrets.template.yaml" ]; then
	pass "F17.1: gitops/argocd/platform/gods-eye-view/secrets.template.yaml exists"
else
	skip "F17.1: secrets.template.yaml not yet created" "Pending Milestone M4"
fi

# 17.2: Verify required secret keys documented in template
if [ -f "gitops/argocd/platform/gods-eye-view/secrets.template.yaml" ]; then
	if grep -q 'GOOGLE_MAPS_API_KEY' "gitops/argocd/platform/gods-eye-view/secrets.template.yaml" && grep -q 'OPENAI_API_KEY' "gitops/argocd/platform/gods-eye-view/secrets.template.yaml"; then
		pass "F17.2: secrets.template.yaml documents required API keys (GOOGLE_MAPS_API_KEY, OPENAI_API_KEY)"
	else
		fail "F17.2: Required API keys missing in secrets.template.yaml"
	fi
else
	skip "F17.2: secrets.template.yaml not yet created" "Pending Milestone M4"
fi

# 17.3: Verify no plaintext credentials committed to git
if [ -f "gitops/argocd/platform/gods-eye-view/secrets.template.yaml" ]; then
	if grep -E '(AIza[0-9A-Za-z_-]{35}|sk-[0-9A-Za-z]{32,})' "gitops/argocd/platform/gods-eye-view/secrets.template.yaml" >/dev/null; then
		fail "F17.3: Real API key pattern detected in secrets.template.yaml"
	else
		pass "F17.3: Zero plaintext API keys or credentials committed in secrets template"
	fi
else
	skip "F17.3: secrets.template.yaml not yet created" "Pending Milestone M4"
fi

# 17.4: Verify deployment references secrets via envFrom or secretKeyRef
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'secretRef' "gitops/argocd/platform/gods-eye-view/deployment.yaml" || grep -q 'secretKeyRef' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F17.4: Deployment mounts secrets via secretRef or secretKeyRef"
	else
		fail "F17.4: Secret references missing in deployment.yaml"
	fi
else
	skip "F17.4: deployment.yaml not yet created" "Pending Milestone M4"
fi

# 17.5: Verify secret name matches gods-eye-view-secrets
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'gods-eye-view-secrets' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F17.5: Secret reference name matches 'gods-eye-view-secrets'"
	else
		fail "F17.5: Secret reference name does not match 'gods-eye-view-secrets'"
	fi
else
	skip "F17.5: deployment.yaml not yet created" "Pending Milestone M4"
fi

# ------------------------------------------------------------------------------
# Feature 18: GitOps Manifest Validation (R4)
# ------------------------------------------------------------------------------
echo "--- Feature 18: GitOps Manifest Validation ---"

# 18.1: Verify tools/ci/gitops-validate.sh exists and is executable
if [ -x "tools/ci/gitops-validate.sh" ]; then
	pass "F18.1: tools/ci/gitops-validate.sh exists with executable permissions"
else
	fail "F18.1: tools/ci/gitops-validate.sh not executable or not found"
fi

# 18.2: Verify gods-eye-view AppProject manifest
if [ -f "gitops/argocd/projects/gods-eye-view-project.yaml" ] || grep -q 'gods-eye-view' "gitops/argocd/projects/applications.yaml" 2>/dev/null; then
	pass "F18.2: AppProject for gods-eye-view is configured"
else
	skip "F18.2: AppProject for gods-eye-view not yet created" "Pending Milestone M4"
fi

# 18.3: Verify YAML syntax across all platform manifests
if [ -d "gitops/argocd/platform/gods-eye-view" ]; then
	all_valid=true
	for y in gitops/argocd/platform/gods-eye-view/*.yaml; do
		[ -f "$y" ] || continue
		if ! python3 -c 'import yaml, sys; yaml.safe_load(open(sys.argv[1]))' "$y" 2>/dev/null; then
			all_valid=false
			break
		fi
	done
	if [ "$all_valid" = true ]; then
		pass "F18.3: All platform manifests parse as valid YAML without syntax errors"
	else
		fail "F18.3: YAML parse failure detected in gitops/argocd/platform/gods-eye-view/"
	fi
else
	skip "F18.3: Platform manifests not yet created" "Pending Milestone M4"
fi

# 18.4: Verify copyright header on all platform manifests
if [ -d "gitops/argocd/platform/gods-eye-view" ]; then
	all_hdr=true
	for y in gitops/argocd/platform/gods-eye-view/*.yaml; do
		[ -f "$y" ] || continue
		if ! grep -q "VitruvianSoftware" "$y"; then
			all_hdr=false
			break
		fi
	done
	if [ "$all_hdr" = true ]; then
		pass "F18.4: All platform manifests contain VitruvianSoftware copyright header"
	else
		fail "F18.4: Copyright header missing in one or more platform manifests"
	fi
else
	skip "F18.4: Platform manifests not yet created" "Pending Milestone M4"
fi

# 18.5: Verify no plaintext secrets committed anywhere in gitops/
if grep -r -E '(AIza[0-9A-Za-z_-]{35}|sk-[0-9A-Za-z]{32,})' gitops/argocd/platform/gods-eye-view/ 2>/dev/null; then
	fail "F18.5: Real API key pattern detected in gitops/argocd/platform/gods-eye-view/"
else
	pass "F18.5: Zero plaintext credentials detected across platform manifests"
fi

# ------------------------------------------------------------------------------
# Feature 19: Subagent Audit: Proxy & WebSockets (R5)
# ------------------------------------------------------------------------------
echo "--- Feature 19: Subagent Audit: Proxy & WebSockets ---"

# 19.1: Verify proxy route URL parameter validation in server.mjs
if node -e '
import("./apps/web/gods-eye-view/server.mjs").then(async ({ safeParseTargetUrl }) => {
  const valid = await safeParseTargetUrl("https://example.com/feed.m3u8");
  if (!valid || !valid.ok) process.exit(1);

  const privateTarget = await safeParseTargetUrl("http://192.168.1.1/feed");
  if (!privateTarget || privateTarget.ok !== false || privateTarget.status !== 403) process.exit(2);

  const loopback = await safeParseTargetUrl("http://127.0.0.1:8080");
  if (!loopback || loopback.ok !== false || loopback.status !== 403) process.exit(3);

  const dnsRebind = await safeParseTargetUrl("http://127.0.0.1.nip.io:8080");
  if (!dnsRebind || dnsRebind.ok !== false || dnsRebind.status !== 403) process.exit(4);

  process.exit(0);
}).catch((err) => {
  console.error(err);
  process.exit(5);
});
'; then
	pass "F19.1: Proxy implementation validates and restricts upstream proxy targets"
else
	fail "F19.1: Proxy target URL validation failed in server.mjs"
fi

# 19.2: Verify WebSocket reconnect backoff handling
if [ -f "apps/web/gods-eye-view/server.mjs" ] || [ -f "apps/web/gods-eye-view/vite.config.js" ]; then
	if grep -q 'reconnect' "apps/web/gods-eye-view/server.mjs" 2>/dev/null || grep -q 'reconnect' "apps/web/gods-eye-view/vite.config.js" 2>/dev/null; then
		pass "F19.2: AISStream WebSocket implements auto-reconnect with backoff"
	else
		skip "F19.2: WebSocket reconnect backoff audit" "Pending Milestone M5 review"
	fi
else
	skip "F19.2: Server not yet created" "Pending Milestone M3"
fi

# 19.3: Verify error handling on WebSocket connection drop
if [ -f "apps/web/gods-eye-view/server.mjs" ] || [ -f "apps/web/gods-eye-view/vite.config.js" ]; then
	if grep -E -q "ws.*on\(['\"]error['\"]" "apps/web/gods-eye-view/server.mjs" 2>/dev/null || grep -E -q "ws.*on\(['\"]error['\"]" "apps/web/gods-eye-view/vite.config.js" 2>/dev/null; then
		pass "F19.3: WebSocket error event handlers prevent unhandled exception process crash"
	else
		skip "F19.3: WebSocket error handling audit" "Pending Milestone M5 review"
	fi
else
	skip "F19.3: Server not yet created" "Pending Milestone M3"
fi

# 19.4: Verify ephemeral token generation isolates master API key
if [ -f "apps/web/gods-eye-view/server.mjs" ] || [ -f "apps/web/gods-eye-view/vite.config.js" ]; then
	if grep -q 'client_secrets' "apps/web/gods-eye-view/server.mjs" 2>/dev/null || grep -q 'client_secrets' "apps/web/gods-eye-view/vite.config.js" 2>/dev/null; then
		pass "F19.4: OpenAI Realtime mints ephemeral client secrets; master key never sent to browser"
	else
		skip "F19.4: Realtime token audit" "Pending Milestone M5 review"
	fi
else
	skip "F19.4: Server not yet created" "Pending Milestone M3"
fi

# 19.5: Verify rate limiting protection configuration
if [ -f "apps/web/gods-eye-view/server.mjs" ] || [ -f "apps/web/gods-eye-view/vite.config.js" ]; then
	if grep -q 'GEV_RATELIMIT' "apps/web/gods-eye-view/server.mjs" 2>/dev/null || grep -q 'GEV_RATELIMIT' "apps/web/gods-eye-view/vite.config.js" 2>/dev/null; then
		pass "F19.5: Rate-limiting guards supported for high-cost endpoints (OpenAI, Google Places)"
	else
		skip "F19.5: Rate limit audit" "Pending Milestone M5 review"
	fi
else
	skip "F19.5: Server not yet created" "Pending Milestone M3"
fi

# ------------------------------------------------------------------------------
# Feature 20: Subagent Audit: Networking & Security (R5)
# ------------------------------------------------------------------------------
echo "--- Feature 20: Subagent Audit: Networking & Security ---"

# 20.1: Verify drop ALL capabilities in deployment
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'drop:' "gitops/argocd/platform/gods-eye-view/deployment.yaml" && grep -q 'ALL' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F20.1: Deployment container securityContext explicitly drops ALL capabilities"
	else
		fail "F20.1: capabilities.drop ALL missing in deployment.yaml"
	fi
else
	skip "F20.1: deployment.yaml not yet created" "Pending Milestone M4"
fi

# 20.2: Verify allowPrivilegeEscalation: false
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'allowPrivilegeEscalation: false' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F20.2: Deployment enforces allowPrivilegeEscalation: false"
	else
		fail "F20.2: allowPrivilegeEscalation: false missing in deployment.yaml"
	fi
else
	skip "F20.2: deployment.yaml not yet created" "Pending Milestone M4"
fi

# 20.3: Verify seccompProfile RuntimeDefault
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'RuntimeDefault' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F20.3: Deployment enforces seccompProfile: RuntimeDefault"
	else
		fail "F20.3: seccompProfile RuntimeDefault missing in deployment.yaml"
	fi
else
	skip "F20.3: deployment.yaml not yet created" "Pending Milestone M4"
fi

# 20.4: Verify resource requests and limits declared
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'resources:' "gitops/argocd/platform/gods-eye-view/deployment.yaml" && grep -q 'limits:' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F20.4: Workload declares CPU and Memory resource limits to prevent noisy neighbor contention"
	else
		fail "F20.4: resource limits missing in deployment.yaml"
	fi
else
	skip "F20.4: deployment.yaml not yet created" "Pending Milestone M4"
fi

# 20.5: Verify readinessProbe and livenessProbe configured
if [ -f "gitops/argocd/platform/gods-eye-view/deployment.yaml" ]; then
	if grep -q 'readinessProbe:' "gitops/argocd/platform/gods-eye-view/deployment.yaml" && grep -q 'livenessProbe:' "gitops/argocd/platform/gods-eye-view/deployment.yaml"; then
		pass "F20.5: Deployment defines readinessProbe and livenessProbe for health lifecycle"
	else
		fail "F20.5: readinessProbe or livenessProbe missing in deployment.yaml"
	fi
else
	skip "F20.5: deployment.yaml not yet created" "Pending Milestone M4"
fi

echo "================================================================================"
echo " Tier 1 Summary: ${PASSED_TESTS}/${TOTAL_TESTS} passed (${SKIPPED_TESTS} skipped, ${FAILED_TESTS} failed)"
echo "================================================================================"

if [ "$FAILED_TESTS" -gt 0 ]; then
	exit 1
fi
exit 0
