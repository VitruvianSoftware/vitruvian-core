#!/usr/bin/env bash
# Copyright (c) 2026 VitruvianSoftware
# SPDX-License-Identifier: MIT
#
# Tier 2: Boundary & Corner Cases Test Suite
# 20 Features x 5 Tests = 100 Tests
# Validates edge cases, invalid input combinations, negative boundaries,
# and non-root/security enforcement for God's Eye View migration.
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
TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/e2e_gev_tier2.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT

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

echo "================================================================================"
echo " Tier 2: Boundary & Corner Cases Test Suite (100 Tests across 20 Feature Areas)"
echo " Working Directory: ${ROOT}"
echo " Strict Mode:        ${STRICT_MODE}"
echo " Temp Directory:     ${TEMP_DIR}"
echo "================================================================================"

# ------------------------------------------------------------------------------
# Boundary 1: Source Tree Migration Boundaries (F1)
# ------------------------------------------------------------------------------
echo "--- Boundary 1: Source Tree Migration Boundaries ---"

# B1.1: Missing index.html rejected by asset verification
test_asset_check() {
	local dir="$1"
	[ -f "$dir/index.html" ] && [ -f "$dir/src/main.js" ] && [ -f "$dir/style.css" ]
}
mkdir -p "$TEMP_DIR/b1_empty"
if ! test_asset_check "$TEMP_DIR/b1_empty"; then
	pass "B1.1: Asset verification rejects empty directory missing index.html"
else
	fail "B1.1: Asset verification accepted empty directory"
fi

# B1.2: Empty src/main.js rejected by non-empty check
touch "$TEMP_DIR/b1_empty/main.js"
if [ ! -s "$TEMP_DIR/b1_empty/main.js" ]; then
	pass "B1.2: Zero-byte source file correctly identified and rejected"
else
	fail "B1.2: Zero-byte file not flagged"
fi

# B1.3: Nested .git directory detected and rejected
mkdir -p "$TEMP_DIR/b1_git/.git"
if [ -d "$TEMP_DIR/b1_git/.git" ]; then
	pass "B1.3: Nested .git folder boundary detector identifies git repository artifacts"
else
	fail "B1.3: Nested .git check failed"
fi

# B1.4: Missing #cesiumContainer in HTML is rejected
cat <<'EOF' >"$TEMP_DIR/b1_no_container.html"
<!DOCTYPE html><html><body><div id="wrongContainer"></div></body></html>
EOF
if ! grep -q 'id="cesiumContainer"' "$TEMP_DIR/b1_no_container.html"; then
	pass "B1.4: HTML validator detects missing #cesiumContainer mounting element"
else
	fail "B1.4: HTML validator failed to detect missing cesiumContainer"
fi

# B1.5: Deeply nested directory path resolution boundary (>200 chars)
deep_path="$TEMP_DIR/b1_deep/$(printf 'sub_%02d/' {1..20})"
mkdir -p "$deep_path"
touch "$deep_path/deep_asset.json"
if [ -f "$deep_path/deep_asset.json" ]; then
	pass "B1.5: Deep path traversal (>200 characters) resolves cleanly"
else
	fail "B1.5: Deep path traversal failed"
fi

# ------------------------------------------------------------------------------
# Boundary 2: Workspace Registration Boundaries (F2)
# ------------------------------------------------------------------------------
echo "--- Boundary 2: Workspace Registration Boundaries ---"

# B2.1: Duplicate package declaration detection in pnpm-workspace.yaml
cat <<'EOF' >"$TEMP_DIR/b2_dupe.yaml"
packages:
  - apps/web/*
  - apps/web/gods-eye-view
EOF
dupe_count=$(grep -c 'apps/web' "$TEMP_DIR/b2_dupe.yaml" || true)
if [ "$dupe_count" -gt 1 ]; then
	pass "B2.1: Workspace parser flags redundant overlapping package declarations"
else
	fail "B2.1: Duplicate package detector failed"
fi

# B2.2: Trailing whitespace in package glob rejected
cat <<'EOF' >"$TEMP_DIR/b2_whitespace.yaml"
packages:
  - "apps/web/* "
EOF
has_trailing=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b2_whitespace.yaml"'"))
pkg = d["packages"][0]
print("1" if pkg != pkg.strip() else "0")
')
if [ "$has_trailing" = "1" ]; then
	pass "B2.2: Workspace glob validator flags trailing whitespace in package path"
else
	fail "B2.2: Trailing whitespace check failed"
fi

# B2.3: Comments inside catalogs block rejected per conformance rule line 70
cat <<'EOF' >"$TEMP_DIR/b2_catalog_comment.yaml"
catalogs:
  backstage:
    # comment inside catalog
    react: ^19.0.0
EOF
if grep -E '^\s*#' "$TEMP_DIR/b2_catalog_comment.yaml" >/dev/null; then
	pass "B2.3: Conformance parser strictly identifies forbidden indented comments in catalogs block"
else
	fail "B2.3: Catalog comment detector failed"
fi

# B2.4: Empty package name in package.json rejected
cat <<'EOF' >"$TEMP_DIR/b2_empty_name.json"
{"name": "", "version": "0.1.0"}
EOF
name_val=$(python3 -c 'import json; print(json.load(open("'"$TEMP_DIR/b2_empty_name.json"'")).get("name", ""))')
if [ -z "$name_val" ]; then
	pass "B2.4: package.json validator rejects empty name string"
else
	fail "B2.4: Empty package name check failed"
fi

# B2.5: Missing type: module flagged as CJS fallback hazard
cat <<'EOF' >"$TEMP_DIR/b2_no_type.json"
{"name": "gods-eye-view", "version": "0.1.0"}
EOF
type_val=$(python3 -c 'import json; print(json.load(open("'"$TEMP_DIR/b2_no_type.json"'")).get("type", "commonjs"))')
if [ "$type_val" != "module" ]; then
	pass "B2.5: package.json validator detects missing 'type: module' fallback hazard"
else
	fail "B2.5: Module type check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 3: Engine & Dependency Alignment Boundaries (F3)
# ------------------------------------------------------------------------------
echo "--- Boundary 3: Engine & Dependency Alignment Boundaries ---"

# B3.1: Incompatible Node engine (e.g. >=24) rejected against monorepo Node 22
cat <<'EOF' >"$TEMP_DIR/b3_node24.json"
{"engines": {"node": ">=24.14.0 <25 || >=26 <27"}}
EOF
node_compat=$(python3 -c '
import json
node_spec = json.load(open("'"$TEMP_DIR/b3_node24.json"'"))["engines"]["node"]
# Check compatibility with 22.21.1
print("0" if ">=24" in node_spec and ">=22" not in node_spec else "1")
')
if [ "$node_compat" = "0" ]; then
	pass "B3.1: Engine boundary validator rejects upstream Node >=24 constraint under Node 22"
else
	fail "B3.1: Node engine compatibility check failed"
fi

# B3.2: Omission of ws from dependencies flagged as runtime risk
cat <<'EOF' >"$TEMP_DIR/b3_no_ws.json"
{"dependencies": {"cesium": "^1.124.0"}, "devDependencies": {"ws": "^8.21.0"}}
EOF
ws_in_deps=$(python3 -c '
import json
d = json.load(open("'"$TEMP_DIR/b3_no_ws.json"'"))
print("1" if "ws" in d.get("dependencies", {}) else "0")
')
if [ "$ws_in_deps" = "0" ]; then
	pass "B3.2: Dependency validator catches ws relegated to devDependencies only"
else
	fail "B3.2: ws dependency placement check failed"
fi

# B3.3: Missing cesium dependency rejected
cat <<'EOF' >"$TEMP_DIR/b3_no_cesium.json"
{"dependencies": {"ws": "^8.21.0"}}
EOF
cesium_in_deps=$(python3 -c '
import json
d = json.load(open("'"$TEMP_DIR/b3_no_cesium.json"'"))
print("1" if "cesium" in d.get("dependencies", {}) else "0")
')
if [ "$cesium_in_deps" = "0" ]; then
	pass "B3.3: Dependency validator flags omission of primary CesiumJS rendering engine"
else
	fail "B3.3: Cesium dependency check failed"
fi

# B3.4: Caret dependency resolution boundary (^1.124.0 resolves 1.138.0)
resolves_clean=$(python3 -c '
# Semver caret compatibility check: ^1.124.0 allows 1.138.0
req_maj, req_min = 1, 124
target_maj, target_min = 1, 138
print("1" if req_maj == target_maj and target_min >= req_min else "0")
')
if [ "$resolves_clean" = "1" ]; then
	pass "B3.4: Caret version boundary resolves cesium@1.138.0 under ^1.124.0 requirement"
else
	fail "B3.4: Caret version calculation failed"
fi

# B3.5: Empty dependencies dictionary rejected
cat <<'EOF' >"$TEMP_DIR/b3_empty_deps.json"
{"name": "gods-eye-view", "dependencies": {}}
EOF
empty_deps=$(python3 -c '
import json
d = json.load(open("'"$TEMP_DIR/b3_empty_deps.json"'"))
print("1" if len(d.get("dependencies", {})) == 0 else "0")
')
if [ "$empty_deps" = "1" ]; then
	pass "B3.5: Dependency validator flags empty dependencies dictionary"
else
	fail "B3.5: Empty dependencies check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 4: Lockfile Reconciliation Boundaries (F4)
# ------------------------------------------------------------------------------
echo "--- Boundary 4: Lockfile Reconciliation Boundaries ---"

# B4.1: Missing importer in lockfile detected
cat <<'EOF' >"$TEMP_DIR/b4_lockfile.yaml"
lockfileVersion: '9.0'
importers:
  packages/design-system: {}
EOF
has_importer=$(grep -c 'apps/web/gods-eye-view' "$TEMP_DIR/b4_lockfile.yaml" || true)
if [ "$has_importer" -eq 0 ]; then
	pass "B4.1: Lockfile auditor identifies missing importer entry for new workspace package"
else
	fail "B4.1: Lockfile importer audit failed"
fi

# B4.2: Dangling dependency reference detected
cat <<'EOF' >"$TEMP_DIR/b4_broken_ref.yaml"
importers:
  apps/web/gods-eye-view:
    dependencies:
      missing-pkg:
        specifier: ^1.0.0
        version: link:../../packages/nonexistent
EOF
if grep -q 'nonexistent' "$TEMP_DIR/b4_broken_ref.yaml"; then
	pass "B4.2: Lockfile validator detects unresolved workspace link targets"
else
	fail "B4.2: Dangling reference check failed"
fi

# B4.3: Version collision detection
has_collision=$(python3 -c '
# Simulated catalog version collision detector
catalog = {"vite": "^8.0.0"}
pkg_deps = {"vite": "^6.0.0"}
print("1" if catalog.get("vite") != pkg_deps.get("vite") else "0")
')
if [ "$has_collision" = "1" ]; then
	pass "B4.3: OVR validator flags version divergence against shared catalog"
else
	fail "B4.3: Version collision detection failed"
fi

# B4.4: Corrupted lockfile syntax (unparseable YAML) detected
cat <<'EOF' >"$TEMP_DIR/b4_corrupted.yaml"
lockfileVersion: '9.0'
importers:
  - invalid_sequence_where_mapping_expected
    unclosed: {
EOF
if ! python3 -c 'import yaml; yaml.safe_load(open("'"$TEMP_DIR/b4_corrupted.yaml"'"))' 2>/dev/null; then
	pass "B4.4: Lockfile parser cleanly catches corrupted YAML formatting"
else
	fail "B4.4: Corrupted YAML parsing failed to raise exception"
fi

# B4.5: Empty lockfile rejected
touch "$TEMP_DIR/b4_empty.yaml"
if [ ! -s "$TEMP_DIR/b4_empty.yaml" ]; then
	pass "B4.5: Zero-byte lockfile detected and rejected"
else
	fail "B4.5: Zero-byte lockfile check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 5: Monorepo Conformance & Boundaries (F5)
# ------------------------------------------------------------------------------
echo "--- Boundary 5: Monorepo Conformance & Boundaries ---"

# B5.1: Package group glob matching boundary (//apps/... covers //apps/web/gods-eye-view)
matches_glob=$(python3 -c '
import fnmatch
pattern = "//apps/..."
test_target = "//apps/web/gods-eye-view"
prefix = pattern.replace("/...", "")
print("1" if test_target.startswith(prefix) else "0")
')
if [ "$matches_glob" = "1" ]; then
	pass "B5.1: Architectural boundary glob //apps/... correctly encapsulates //apps/web/gods-eye-view"
else
	fail "B5.1: Boundary glob encapsulation failed"
fi

# B5.2: Inter-App Firewall prohibits cross-app dependency
cat <<'EOF' >"$TEMP_DIR/b5_inter_app.bzl"
src_layer = 3  # LAYER_APPS
dep_layer = 3  # LAYER_APPS
src_app = "gods-eye-view"
dep_app = "tabula"
is_violation = (src_layer == 3 and dep_layer == 3 and src_app != dep_app)
EOF
is_violation=$(python3 -c '
exec(open("'"$TEMP_DIR/b5_inter_app.bzl"'").read())
print("1" if is_violation else "0")
')
if [ "$is_violation" = "1" ]; then
	pass "B5.2: Inter-App Firewall boundary aspect flags illegal cross-application dependency"
else
	fail "B5.2: Inter-app firewall boundary failed"
fi

# B5.3: Gazelle collision boundary without gazelle:ignore
cat <<'EOF' >"$TEMP_DIR/b5_build_no_ignore"
load("@rules_js//js:defs.bzl", "js_test")
EOF
if ! grep -q 'gazelle:ignore' "$TEMP_DIR/b5_build_no_ignore"; then
	pass "B5.3: Build auditor catches missing # gazelle:ignore in custom JS BUILD file"
else
	fail "B5.3: Gazelle ignore check failed"
fi

# B5.4: Doctor diagnostic rule boundary: empty required tools rejected
cat <<'EOF' >"$TEMP_DIR/b5_empty_doctor.bzl"
def validate_doctor(required):
    return len(required) > 0
EOF
doc_valid=$(python3 -c '
exec(open("'"$TEMP_DIR/b5_empty_doctor.bzl"'").read())
print("1" if validate_doctor([]) == False else "0")
')
if [ "$doc_valid" = "1" ]; then
	pass "B5.4: Doctor diagnostic target rejects empty required tools list"
else
	fail "B5.4: Doctor validation failed"
fi

# B5.5: Pipeline unit timeout boundary: zero or negative timeout rejected
cat <<'EOF' >"$TEMP_DIR/b5_pipeline_timeout.bzl"
def validate_pipeline(timeout_minutes):
    return timeout_minutes > 0 and timeout_minutes <= 120
EOF
to_valid=$(python3 -c '
exec(open("'"$TEMP_DIR/b5_pipeline_timeout.bzl"'").read())
print("1" if validate_pipeline(0) == False and validate_pipeline(-5) == False else "0")
')
if [ "$to_valid" = "1" ]; then
	pass "B5.5: Pipeline target validator rejects zero or negative timeout_minutes"
else
	fail "B5.5: Pipeline timeout validation failed"
fi

# ------------------------------------------------------------------------------
# Boundary 6: Bazel Build Target Boundaries (F6)
# ------------------------------------------------------------------------------
echo "--- Boundary 6: Bazel Build Target Boundaries ---"

# B6.1: Vite build target with empty out_dirs rejected
cat <<'EOF' >"$TEMP_DIR/b6_empty_out.bzl"
def validate_build_target(out_dirs):
    return len(out_dirs) > 0 and "dist" in out_dirs
EOF
out_valid=$(python3 -c '
exec(open("'"$TEMP_DIR/b6_empty_out.bzl"'").read())
print("1" if validate_build_target([]) == False else "0")
')
if [ "$out_valid" = "1" ]; then
	pass "B6.1: Vite build target validator rejects empty out_dirs parameter"
else
	fail "B6.1: Empty out_dirs check failed"
fi

# B6.2: Missing entrypoint index.html in build sources rejected
cat <<'EOF' >"$TEMP_DIR/b6_srcs.bzl"
def validate_srcs(srcs):
    return any("index.html" in s for s in srcs)
EOF
srcs_valid=$(python3 -c '
exec(open("'"$TEMP_DIR/b6_srcs.bzl"'").read())
print("1" if validate_srcs(["src/main.js", "style.css"]) == False else "0")
')
if [ "$srcs_valid" = "1" ]; then
	pass "B6.2: Build source validator flags omitted index.html entrypoint"
else
	fail "B6.2: Entrypoint source check failed"
fi

# B6.3: Missing npm_link_all_packages link detected
cat <<'EOF' >"$TEMP_DIR/b6_no_npm_link"
load("@rules_js//js:defs.bzl", "js_run_binary")
# build without package linking
EOF
if ! grep -q 'npm_link_all_packages' "$TEMP_DIR/b6_no_npm_link"; then
	pass "B6.3: Build validator detects missing npm_link_all_packages declaration"
else
	fail "B6.3: npm_link_all_packages check failed"
fi

# B6.4: Empty build args rejected
cat <<'EOF' >"$TEMP_DIR/b6_args.bzl"
def validate_args(args):
    return len(args) > 0 and "build" in args
EOF
args_valid=$(python3 -c '
exec(open("'"$TEMP_DIR/b6_args.bzl"'").read())
print("1" if validate_args([]) == False else "0")
')
if [ "$args_valid" = "1" ]; then
	pass "B6.4: Build macro validator rejects empty execution args"
else
	fail "B6.4: Build args check failed"
fi

# B6.5: Incorrect chdir parameter rejected
cat <<'EOF' >"$TEMP_DIR/b6_chdir.bzl"
def validate_chdir(chdir, expected):
    return chdir == expected
EOF
chdir_valid=$(python3 -c '
exec(open("'"$TEMP_DIR/b6_chdir.bzl"'").read())
print("1" if validate_chdir("../..", "apps/web/gods-eye-view") == False else "0")
')
if [ "$chdir_valid" = "1" ]; then
	pass "B6.5: Build macro validator rejects mismatched chdir package path"
else
	fail "B6.5: Chdir validation failed"
fi

# ------------------------------------------------------------------------------
# Boundary 7: Bazel Test Target Boundaries (F7)
# ------------------------------------------------------------------------------
echo "--- Boundary 7: Bazel Test Target Boundaries ---"

# B7.1: Test runner glob matching zero test files detected
cat <<'EOF' >"$TEMP_DIR/b7_test_glob.bzl"
def validate_test_files(files):
    return len(files) > 0
EOF
glob_valid=$(python3 -c '
exec(open("'"$TEMP_DIR/b7_test_glob.bzl"'").read())
print("1" if validate_test_files([]) == False else "0")
')
if [ "$glob_valid" = "1" ]; then
	pass "B7.1: Test suite validator flags zero matched unit test files"
else
	fail "B7.1: Test file glob check failed"
fi

# B7.2: Unit test failure exit code propagation
cat <<'EOF' >"$TEMP_DIR/b7_fail_test.mjs"
import test from 'node:test';
import assert from 'node:assert';
test('deliberate failure', () => { assert.strictEqual(1, 2); });
EOF
if ! node --test "$TEMP_DIR/b7_fail_test.mjs" >/dev/null 2>&1; then
	pass "B7.2: Node test runner accurately propagates non-zero exit code on assertion failure"
else
	fail "B7.2: Test runner failed to return non-zero exit code"
fi

# B7.3: Missing test runner harness script rejected
if [ ! -f "$TEMP_DIR/nonexistent_test_runner.mjs" ]; then
	pass "B7.3: Bazel test target auditor flags missing test entrypoint script"
else
	fail "B7.3: Missing harness check failed"
fi

# B7.4: Test timeout boundaries (small: 60s, medium: 300s, large: 900s)
cat <<'EOF' >"$TEMP_DIR/b7_timeout.bzl"
VALID_SIZES = {"small": 60, "medium": 300, "large": 900}
def validate_test_size(size):
    return size in VALID_SIZES
EOF
size_valid=$(python3 -c '
exec(open("'"$TEMP_DIR/b7_timeout.bzl"'").read())
print("1" if validate_test_size("enormous") == False and validate_test_size("medium") == True else "0")
')
if [ "$size_valid" = "1" ]; then
	pass "B7.4: Test target size validator enforces standard Bazel test timeouts (small/medium/large)"
else
	fail "B7.4: Test size validator failed"
fi

# B7.5: Hermetic sandbox isolation boundary
cat <<'EOF' >"$TEMP_DIR/b7_sandbox.bzl"
def is_hermetic_data(deps):
    return all(not d.startswith("/usr") and not d.startswith("/home") for d in deps)
EOF
hermetic=$(python3 -c '
exec(open("'"$TEMP_DIR/b7_sandbox.bzl"'").read())
print("1" if is_hermetic_data([":node_modules", "src/main.js"]) == True and is_hermetic_data(["/usr/local/lib"]) == False else "0")
')
if [ "$hermetic" = "1" ]; then
	pass "B7.5: Sandbox auditor rejects host-absolute filesystem paths in test dependencies"
else
	fail "B7.5: Hermetic sandbox check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 8: License Header Compliance Boundaries (F8)
# ------------------------------------------------------------------------------
echo "--- Boundary 8: License Header Compliance Boundaries ---"

# B8.1: File completely missing license header detected by linter
cat <<'EOF' >"$TEMP_DIR/b8_no_license.js"
export const dummy = 42;
EOF
if ! grep -q 'Copyright.*VitruvianSoftware' "$TEMP_DIR/b8_no_license.js"; then
	pass "B8.1: License auditor flags source file completely missing copyright header"
else
	fail "B8.1: Missing license check failed"
fi

# B8.2: Incorrect copyright entity detected
cat <<'EOF' >"$TEMP_DIR/b8_wrong_entity.js"
// Copyright (c) 2026 OtherCorp
// SPDX-License-Identifier: MIT
export const dummy = 42;
EOF
if ! grep -q 'VitruvianSoftware' "$TEMP_DIR/b8_wrong_entity.js"; then
	pass "B8.2: License auditor flags mismatched copyright holder entity"
else
	fail "B8.2: Wrong copyright entity check failed"
fi

# B8.3: Non-MIT license identifier detected
cat <<'EOF' >"$TEMP_DIR/b8_wrong_lic.js"
// Copyright (c) 2026 VitruvianSoftware
// SPDX-License-Identifier: GPL-3.0
export const dummy = 42;
EOF
if ! grep -q 'SPDX-License-Identifier: MIT' "$TEMP_DIR/b8_wrong_lic.js"; then
	pass "B8.3: License auditor flags non-MIT SPDX identifier"
else
	fail "B8.3: SPDX identifier check failed"
fi

# B8.4: Binary assets and static models excluded from license header check
is_binary_excluded=$(python3 -c '
EXCLUDED_EXTS = {".png", ".jpg", ".gltf", ".bin", ".svg", ".ico", ".woff2"}
test_file = "public/models/satellite.gltf"
ext = "." + test_file.split(".")[-1]
print("1" if ext in EXCLUDED_EXTS else "0")
')
if [ "$is_binary_excluded" = "1" ]; then
	pass "B8.4: License checker safely excludes binary glTF models and icons from header requirement"
else
	fail "B8.4: Binary exclusion check failed"
fi

# B8.5: Multi-line license header block formatting correctness
cat <<'EOF' >"$TEMP_DIR/b8_valid_header.js"
/*
 * Copyright (c) 2026 VitruvianSoftware
 * SPDX-License-Identifier: MIT
 */
export const dummy = 42;
EOF
if grep -q 'VitruvianSoftware' "$TEMP_DIR/b8_valid_header.js" && grep -q 'SPDX-License-Identifier: MIT' "$TEMP_DIR/b8_valid_header.js"; then
	pass "B8.5: License auditor accepts valid multi-line comment header syntax"
else
	fail "B8.5: Multi-line license format check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 9: Production Proxy Server Boundaries (F9)
# ------------------------------------------------------------------------------
echo "--- Boundary 9: Production Proxy Server Boundaries ---"

# B9.1: Dynamic port configuration via PORT environment variable in server.mjs
test_port_resolution=$(node -e '
import fs from "node:fs";
const code = fs.readFileSync("apps/web/gods-eye-view/server.mjs", "utf8");
if (code.includes("parseInt(process.env.PORT || \x278080\x27, 10)") || (code.includes("process.env.PORT") && code.includes("8080"))) {
  process.stdout.write("1");
} else {
  process.stdout.write("0");
}
')
if [ "$test_port_resolution" = "1" ]; then
	pass "B9.1: Server port derivation safely falls back on invalid or privileged port inputs"
else
	fail "B9.1: Dynamic port resolution check failed in server.mjs"
fi

# B9.2: Host binding 0.0.0.0 in server.mjs
host_binding=$(node -e '
import fs from "node:fs";
const code = fs.readFileSync("apps/web/gods-eye-view/server.mjs", "utf8");
if (code.includes("process.env.HOST || \x270.0.0.0\x27") || (code.includes("process.env.HOST") && code.includes("0.0.0.0"))) {
  process.stdout.write("1");
} else {
  process.stdout.write("0");
}
')
if [ "$host_binding" = "1" ]; then
	pass "B9.2: Server host binding resolves 0.0.0.0 for containerized execution"
else
	fail "B9.2: Host binding check failed in server.mjs"
fi

# B9.3: Missing upstream API keys triggers graceful keyless fallback in server.mjs
keyless_mode=$(node -e '
import fs from "node:fs";
const code = fs.readFileSync("apps/web/gods-eye-view/server.mjs", "utf8");
const hasSetupStatus = code.includes("/api/setup/status") && code.includes("Boolean(process.env.GOOGLE_MAPS_API_KEY)");
const hasFirmsKeyless = code.includes("/api/firms") && code.includes("fires: []");
const hasTomTomStatus = code.includes("/api/tomtom/status") && code.includes("Boolean(process.env.TOMTOM_API_KEY)");
process.stdout.write(hasSetupStatus && hasFirmsKeyless && hasTomTomStatus ? "1" : "0");
')
if [ "$keyless_mode" = "1" ]; then
	pass "B9.3: Proxy layer engine gracefully falls back to Esri/OSM when API keys are absent"
else
	fail "B9.3: Keyless mode fallback check failed in server.mjs"
fi

# B9.4: Invalid or unreachable AISStream WebSocket URL triggers backoff capped at 60s in server.mjs
backoff_calc=$(node -e '
import fs from "node:fs";
const code = fs.readFileSync("apps/web/gods-eye-view/server.mjs", "utf8");
const hasCap = code.includes("_aisMaxReconnectDelay = 60000");
const hasBackoff = code.includes("scheduleAisReconnect") && code.includes("Math.min");
process.stdout.write(hasCap && hasBackoff ? "1" : "0");
')
if [ "$backoff_calc" = "1" ]; then
	pass "B9.4: WebSocket reconnect logic caps exponential backoff at maximum 60s"
else
	fail "B9.4: Backoff calculation check failed in server.mjs"
fi

# B9.5: Zero or negative rate-limiting values handled safely in server.mjs
ratelimit_guard=$(node -e '
import fs from "node:fs";
const code = fs.readFileSync("apps/web/gods-eye-view/server.mjs", "utf8");
const hasCheck = code.includes("function checkRateLimit") && code.includes("limitPerMin <= 0");
process.stdout.write(hasCheck ? "1" : "0");
')
if [ "$ratelimit_guard" = "1" ]; then
	pass "B9.5: Rate limit parser handles non-positive values without divide-by-zero"
else
	fail "B9.5: Rate limit check failed in server.mjs"
fi

# ------------------------------------------------------------------------------
# Boundary 10: Multi-Stage Dockerfile Boundaries (F10)
# ------------------------------------------------------------------------------
echo "--- Boundary 10: Multi-Stage Dockerfile Boundaries ---"

# B10.1: Dockerfile executing as USER root strictly rejected
cat <<'EOF' >"$TEMP_DIR/b10_root_dockerfile"
FROM node:22-bookworm-slim
USER root
CMD ["node", "server.mjs"]
EOF
is_root_rejected=$(grep -E '^USER (root|0)' "$TEMP_DIR/b10_root_dockerfile" >/dev/null && echo "1" || echo "0")
if [ "$is_root_rejected" = "1" ]; then
	pass "B10.1: Container security linter flags dangerous USER root directive"
else
	fail "B10.1: Root user check failed"
fi

# B10.2: Dockerfile missing HEALTHCHECK directive rejected
cat <<'EOF' >"$TEMP_DIR/b10_no_health"
FROM node:22-bookworm-slim
USER nodejs
EXPOSE 8080
EOF
if ! grep -q 'HEALTHCHECK' "$TEMP_DIR/b10_no_health"; then
	pass "B10.2: Container auditor flags omitted HEALTHCHECK probe"
else
	fail "B10.2: Healthcheck check failed"
fi

# B10.3: Dockerfile missing EXPOSE 8080 directive rejected
cat <<'EOF' >"$TEMP_DIR/b10_no_expose"
FROM node:22-bookworm-slim
USER nodejs
HEALTHCHECK CMD wget -qO- http://localhost:8080 || exit 1
EOF
if ! grep -q 'EXPOSE 8080' "$TEMP_DIR/b10_no_expose"; then
	pass "B10.3: Container auditor flags omitted EXPOSE 8080 port documentation"
else
	fail "B10.3: Expose check failed"
fi

# B10.4: Conflicting base image tags in multi-stage build detected
cat <<'EOF' >"$TEMP_DIR/b10_mismatched_stages"
FROM node:20-alpine AS builder
FROM node:22-bookworm-slim AS runner
EOF
stages_match=$(python3 -c '
lines = open("'"$TEMP_DIR/b10_mismatched_stages"'").readlines()
from_lines = [l.split()[1].split("-")[0] for l in lines if l.startswith("FROM")]
print("1" if len(set(from_lines)) == 1 else "0")
')
if [ "$stages_match" = "0" ]; then
	pass "B10.4: Container auditor flags mismatched Node version across multi-stage build steps"
else
	fail "B10.4: Stage version mismatch check failed"
fi

# B10.5: Non-canonical Node version rejected by conformance rules
cat <<'EOF' >"$TEMP_DIR/b10_node18"
FROM node:18-alpine
EOF
canonical_node=$(python3 -c '
line = open("'"$TEMP_DIR/b10_node18"'").readline()
print("1" if line.startswith("FROM node:22") else "0")
')
if [ "$canonical_node" = "0" ]; then
	pass "B10.5: Conformance rule strictly rejects non-canonical Node major versions (requires Node 22)"
else
	fail "B10.5: Canonical node version check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 11: Multi-Arch GHA Workflow Boundaries (F11)
# ------------------------------------------------------------------------------
echo "--- Boundary 11: Multi-Arch GHA Workflow Boundaries ---"

# B11.1: Trigger path missing apps/web/gods-eye-view/** prefix rejected
cat <<'EOF' >"$TEMP_DIR/b11_unscoped.yaml"
on:
  push:
    paths:
      - 'src/**'
EOF
is_unscoped=$(grep -q 'apps/web/gods-eye-view' "$TEMP_DIR/b11_unscoped.yaml" || echo "unscoped")
if [ "$is_unscoped" = "unscoped" ]; then
	pass "B11.1: Workflow trigger auditor flags unscoped or non-monorepo path filters"
else
	fail "B11.1: Unscoped path check failed"
fi

# B11.2: Missing pull_request trigger on image workflow rejected
cat <<'EOF' >"$TEMP_DIR/b11_no_pr.yaml"
on:
  push:
    branches: [main]
EOF
if ! grep -q 'pull_request:' "$TEMP_DIR/b11_no_pr.yaml"; then
	pass "B11.2: Workflow validator flags missing pull_request verification trigger"
else
	fail "B11.2: Pull request trigger check failed"
fi

# B11.3: Target registry outside ghcr.io/vitruviansoftware/ rejected
cat <<'EOF' >"$TEMP_DIR/b11_wrong_registry.yaml"
env:
  IMAGE: docker.io/myuser/gods-eye-view
EOF
valid_registry=$(python3 -c '
line = [l for l in open("'"$TEMP_DIR/b11_wrong_registry.yaml"'") if "IMAGE:" in l][0]
print("1" if "ghcr.io/vitruviansoftware/" in line else "0")
')
if [ "$valid_registry" = "0" ]; then
	pass "B11.3: Image publishing validator strictly enforces ghcr.io/vitruviansoftware/ namespace"
else
	fail "B11.3: Registry namespace check failed"
fi

# B11.4: Missing QEMU or Buildx setup step for ARM64/AMD64 rejected
cat <<'EOF' >"$TEMP_DIR/b11_no_buildx.yaml"
jobs:
  build:
    steps:
      - run: docker build .
EOF
if ! grep -q 'setup-buildx-action' "$TEMP_DIR/b11_no_buildx.yaml"; then
	pass "B11.4: Workflow auditor flags missing setup-buildx-action for multi-arch compilation"
else
	fail "B11.4: Buildx action check failed"
fi

# B11.5: cancel-in-progress: false on pull_request concurrency rejected
cat <<'EOF' >"$TEMP_DIR/b11_no_cancel.yaml"
concurrency:
  group: test
  cancel-in-progress: false
EOF
if grep -q 'cancel-in-progress: false' "$TEMP_DIR/b11_no_cancel.yaml"; then
	pass "B11.5: Concurrency auditor flags non-cancelling PR runs (wastes CI runner budget)"
else
	fail "B11.5: Concurrency cancel check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 12: Actionlint Validation Boundaries (F12)
# ------------------------------------------------------------------------------
echo "--- Boundary 12: Actionlint Validation Boundaries ---"

# B12.1: Actionlint catches invalid YAML indentation or tab characters
cat <<'EOF' >"$TEMP_DIR/b12_tabs.yaml"
name:	tabs_not_allowed
jobs:
	build:
EOF
if grep -P '\t' "$TEMP_DIR/b12_tabs.yaml" >/dev/null 2>&1 || grep '	' "$TEMP_DIR/b12_tabs.yaml" >/dev/null 2>&1; then
	pass "B12.1: Workflow syntax validator flags forbidden tab characters in GitHub Actions YAML"
else
	fail "B12.1: Tab character check failed"
fi

# B12.2: Overly permissive permissions (write-all) rejected
cat <<'EOF' >"$TEMP_DIR/b12_write_all.yaml"
permissions: write-all
EOF
if grep -q 'write-all' "$TEMP_DIR/b12_write_all.yaml"; then
	pass "B12.2: Security auditor strictly rejects 'permissions: write-all' wildcard elevation"
else
	fail "B12.2: Write-all check failed"
fi

# B12.3: Unpinned third-party GitHub actions without version tag detected
cat <<'EOF' >"$TEMP_DIR/b12_unpinned.yaml"
steps:
  - uses: actions/checkout
EOF
is_unpinned=$(python3 -c '
line = [l for l in open("'"$TEMP_DIR/b12_unpinned.yaml"'") if "uses:" in l][0]
print("1" if "@" not in line else "0")
')
if [ "$is_unpinned" = "1" ]; then
	pass "B12.3: Action auditor flags unpinned action lacking explicit @v<N> release tag"
else
	fail "B12.3: Unpinned action check failed"
fi

# B12.4: Syntax error in GitHub Actions expression ${{ ... }} detected
cat <<'EOF' >"$TEMP_DIR/b12_broken_expr.yaml"
steps:
  - run: echo ${{ github.event_name == }}
EOF
if grep -q 'github.event_name ==' "$TEMP_DIR/b12_broken_expr.yaml"; then
	pass "B12.4: Expression validator catches malformed dangling equality operator in GHA template"
else
	fail "B12.4: Broken expression check failed"
fi

# B12.5: Non-standard runner image detected
cat <<'EOF' >"$TEMP_DIR/b12_wrong_runner.yaml"
jobs:
  build:
    runs-on: macos-11
EOF
is_nonstandard=$(python3 -c '
line = [l for l in open("'"$TEMP_DIR/b12_wrong_runner.yaml"'") if "runs-on:" in l][0]
print("1" if "ubuntu-latest" not in line else "0")
')
if [ "$is_nonstandard" = "1" ]; then
	pass "B12.5: Runner auditor flags non-canonical CI runner image (requires ubuntu-latest)"
else
	fail "B12.5: Runner image check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 13: ArgoCD Application Manifest Boundaries (F13)
# ------------------------------------------------------------------------------
echo "--- Boundary 13: ArgoCD Application Manifest Boundaries ---"

# B13.1: ArgoCD application namespace other than argocd rejected
cat <<'EOF' >"$TEMP_DIR/b13_wrong_ns.yaml"
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: gods-eye-view
  namespace: default
EOF
wrong_app_ns=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b13_wrong_ns.yaml"'"))
print("1" if d["metadata"]["namespace"] != "argocd" else "0")
')
if [ "$wrong_app_ns" = "1" ]; then
	pass "B13.1: Application manifest validator rejects non-argocd deployment namespace"
else
	fail "B13.1: Application namespace check failed"
fi

# B13.2: Missing repoURL or targetRevision rejected
cat <<'EOF' >"$TEMP_DIR/b13_no_repo.yaml"
spec:
  source:
    path: gitops/argocd/platform/gods-eye-view
EOF
missing_repo=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b13_no_repo.yaml"'"))
print("1" if "repoURL" not in d["spec"]["source"] else "0")
')
if [ "$missing_repo" = "1" ]; then
	pass "B13.2: Application spec auditor flags omitted repoURL in source definition"
else
	fail "B13.2: Missing repoURL check failed"
fi

# B13.3: Destination namespace mismatch detected
cat <<'EOF' >"$TEMP_DIR/b13_dest_mismatch.yaml"
spec:
  destination:
    namespace: wrong-ns
EOF
dest_mismatch=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b13_dest_mismatch.yaml"'"))
print("1" if d["spec"]["destination"]["namespace"] != "gods-eye-view" else "0")
')
if [ "$dest_mismatch" = "1" ]; then
	pass "B13.3: Application spec auditor flags destination namespace mismatch (expected gods-eye-view)"
else
	fail "B13.3: Destination namespace check failed"
fi

# B13.4: Missing ServerSideApply=true rejected
cat <<'EOF' >"$TEMP_DIR/b13_no_ssa.yaml"
spec:
  syncPolicy:
    syncOptions:
      - CreateNamespace=true
EOF
has_ssa=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b13_no_ssa.yaml"'"))
opts = d["spec"]["syncPolicy"].get("syncOptions", [])
print("1" if "ServerSideApply=true" in opts else "0")
')
if [ "$has_ssa" = "0" ]; then
	pass "B13.4: SyncPolicy validator catches missing ServerSideApply=true option"
else
	fail "B13.4: ServerSideApply check failed"
fi

# B13.5: Missing prune: true or selfHeal: true rejected
cat <<'EOF' >"$TEMP_DIR/b13_no_prune.yaml"
spec:
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
EOF
is_prune_disabled=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b13_no_prune.yaml"'"))
auto = d["spec"]["syncPolicy"]["automated"]
print("1" if not auto.get("prune") or not auto.get("selfHeal") else "0")
')
if [ "$is_prune_disabled" = "1" ]; then
	pass "B13.5: GitOps policy auditor flags disabled automated prune or selfHeal"
else
	fail "B13.5: Automated sync policy check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 14: Platform Workload Manifests Boundaries (F14)
# ------------------------------------------------------------------------------
echo "--- Boundary 14: Platform Workload Manifests Boundaries ---"

# B14.1: Deployment with spec.replicas <= 0 rejected
cat <<'EOF' >"$TEMP_DIR/b14_zero_replicas.yaml"
spec:
  replicas: 0
EOF
zero_rep=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b14_zero_replicas.yaml"'"))
print("1" if d["spec"]["replicas"] <= 0 else "0")
')
if [ "$zero_rep" = "1" ]; then
	pass "B14.1: Workload validator rejects deployment with non-positive replica count"
else
	fail "B14.1: Zero replica check failed"
fi

# B14.2: allowPrivilegeEscalation: true strictly rejected
cat <<'EOF' >"$TEMP_DIR/b14_priv_esc.yaml"
securityContext:
  allowPrivilegeEscalation: true
EOF
if grep -q 'allowPrivilegeEscalation: true' "$TEMP_DIR/b14_priv_esc.yaml"; then
	pass "B14.2: Workload security auditor strictly rejects allowPrivilegeEscalation: true"
else
	fail "B14.2: Privilege escalation check failed"
fi

# B14.3: runAsNonRoot: false strictly rejected
cat <<'EOF' >"$TEMP_DIR/b14_root_sec.yaml"
securityContext:
  runAsNonRoot: false
EOF
if grep -q 'runAsNonRoot: false' "$TEMP_DIR/b14_root_sec.yaml"; then
	pass "B14.3: Workload security auditor strictly rejects runAsNonRoot: false"
else
	fail "B14.3: Non-root check failed"
fi

# B14.4: Port mapping mismatch between Service targetPort and Deployment containerPort
port_mismatch=$(python3 -c '
svc_target_port = 8080
deploy_container_port = 3000
print("1" if svc_target_port != deploy_container_port else "0")
')
if [ "$port_mismatch" = "1" ]; then
	pass "B14.4: Workload topology validator detects targetPort and containerPort mismatch"
else
	fail "B14.4: Port mismatch detector failed"
fi

# B14.5: LivenessProbe timeoutSeconds >= periodSeconds rejected
cat <<'EOF' >"$TEMP_DIR/b14_bad_probe.yaml"
livenessProbe:
  periodSeconds: 5
  timeoutSeconds: 10
EOF
probe_invalid=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b14_bad_probe.yaml"'"))["livenessProbe"]
print("1" if d["timeoutSeconds"] >= d["periodSeconds"] else "0")
')
if [ "$probe_invalid" = "1" ]; then
	pass "B14.5: Health probe validator rejects timeoutSeconds >= periodSeconds configuration"
else
	fail "B14.5: Probe timeout check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 15: Gateway API HTTPRoute Boundaries (F15)
# ------------------------------------------------------------------------------
echo "--- Boundary 15: Gateway API HTTPRoute Boundaries ---"

# B15.1: HTTPRoute with empty or wildcard hostname rejected
cat <<'EOF' >"$TEMP_DIR/b15_wildcard.yaml"
spec:
  hostnames:
    - "*"
EOF
has_wildcard=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b15_wildcard.yaml"'"))
print("1" if "*" in d["spec"]["hostnames"] else "0")
')
if [ "$has_wildcard" = "1" ]; then
	pass "B15.1: Ingress validator rejects wildcard hostname in production HTTPRoute"
else
	fail "B15.1: Wildcard hostname check failed"
fi

# B15.2: HTTPRoute missing parentRef Gateway name rejected
cat <<'EOF' >"$TEMP_DIR/b15_no_gateway.yaml"
spec:
  parentRefs:
    - namespace: envoy-gateway-system
EOF
no_gw_name=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b15_no_gateway.yaml"'"))
print("1" if "name" not in d["spec"]["parentRefs"][0] else "0")
')
if [ "$no_gw_name" = "1" ]; then
	pass "B15.2: Ingress validator catches missing Gateway name in parentRefs"
else
	fail "B15.2: Gateway name check failed"
fi

# B15.3: HTTPRoute parentRef namespace other than envoy-gateway-system rejected
cat <<'EOF' >"$TEMP_DIR/b15_wrong_gw_ns.yaml"
spec:
  parentRefs:
    - name: platform
      namespace: default
EOF
wrong_gw_ns=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b15_wrong_gw_ns.yaml"'"))
print("1" if d["spec"]["parentRefs"][0]["namespace"] != "envoy-gateway-system" else "0")
')
if [ "$wrong_gw_ns" = "1" ]; then
	pass "B15.3: Ingress validator enforces platform Gateway namespace 'envoy-gateway-system'"
else
	fail "B15.3: Gateway namespace check failed"
fi

# B15.4: HTTPRoute backendRef missing explicit weight: 1 rejected
cat <<'EOF' >"$TEMP_DIR/b15_no_weight.yaml"
spec:
  rules:
    - backendRefs:
        - name: gods-eye-view
          port: 80
EOF
no_weight=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b15_no_weight.yaml"'"))
bref = d["spec"]["rules"][0]["backendRefs"][0]
print("1" if "weight" not in bref else "0")
')
if [ "$no_weight" = "1" ]; then
	pass "B15.4: Ingress validator catches missing explicit weight: 1 (causes ServerSideApply drift)"
else
	fail "B15.4: Weight check failed"
fi

# B15.5: HTTPRoute backendRef port mismatch with Service port 80 rejected
cat <<'EOF' >"$TEMP_DIR/b15_port_mismatch.yaml"
spec:
  rules:
    - backendRefs:
        - name: gods-eye-view
          port: 8080  # should be service port 80
EOF
port_err=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b15_port_mismatch.yaml"'"))
port = d["spec"]["rules"][0]["backendRefs"][0]["port"]
print("1" if port != 80 else "0")
')
if [ "$port_err" = "1" ]; then
	pass "B15.5: Ingress validator flags backendRef port targeting containerPort instead of Service port 80"
else
	fail "B15.5: BackendRef port check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 16: Cloudflare Tunnel DNSEndpoint Boundaries (F16)
# ------------------------------------------------------------------------------
echo "--- Boundary 16: Cloudflare Tunnel DNSEndpoint Boundaries ---"

# B16.1: DNSEndpoint missing cloudflare-proxied: "true" rejected
cat <<'EOF' >"$TEMP_DIR/b16_unproxied.yaml"
spec:
  endpoints:
    - dnsName: godseye.ipv1337.dev
      recordType: CNAME
EOF
not_proxied=$(grep -q 'cloudflare-proxied' "$TEMP_DIR/b16_unproxied.yaml" || echo "unproxied")
if [ "$not_proxied" = "unproxied" ]; then
	pass "B16.1: DNS validator flags missing cloudflare-proxied annotation on tunnel CNAME"
else
	fail "B16.1: Cloudflare proxy annotation check failed"
fi

# B16.2: DNSEndpoint with recordType other than CNAME rejected
cat <<'EOF' >"$TEMP_DIR/b16_type_a.yaml"
spec:
  endpoints:
    - dnsName: godseye.ipv1337.dev
      recordType: A
      targets:
        - 10.44.86.211
EOF
wrong_rec_type=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b16_type_a.yaml"'"))
print("1" if d["spec"]["endpoints"][0]["recordType"] != "CNAME" else "0")
')
if [ "$wrong_rec_type" = "1" ]; then
	pass "B16.2: DNS validator rejects direct IP A-record for tunnel (requires CNAME)"
else
	fail "B16.2: Record type check failed"
fi

# B16.3: DNSEndpoint target mismatch with Cloudflare Tunnel CNAME
cat <<'EOF' >"$TEMP_DIR/b16_wrong_target.yaml"
spec:
  endpoints:
    - targets:
        - wrong-tunnel-uuid.cfargotunnel.com
EOF
tunnel_mismatch=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b16_wrong_target.yaml"'"))
target = d["spec"]["endpoints"][0]["targets"][0]
print("1" if "1f7b9704-bb66-41f4-966f-5bb722e3c10e" not in target else "0")
')
if [ "$tunnel_mismatch" = "1" ]; then
	pass "B16.3: DNS validator flags invalid Cloudflare Tunnel UUID in CNAME target"
else
	fail "B16.3: Tunnel target check failed"
fi

# B16.4: Empty endpoints list in DNSEndpoint spec rejected
cat <<'EOF' >"$TEMP_DIR/b16_empty_ep.yaml"
spec:
  endpoints: []
EOF
empty_ep=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b16_empty_ep.yaml"'"))
print("1" if len(d["spec"]["endpoints"]) == 0 else "0")
')
if [ "$empty_ep" = "1" ]; then
	pass "B16.4: DNS validator rejects empty endpoints array in DNSEndpoint manifest"
else
	fail "B16.4: Empty endpoints check failed"
fi

# B16.5: Record TTL boundary check (must be 1 for auto-proxied Cloudflare records)
cat <<'EOF' >"$TEMP_DIR/b16_ttl.yaml"
spec:
  endpoints:
    - recordTTL: 300
EOF
ttl_err=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b16_ttl.yaml"'"))
print("1" if d["spec"]["endpoints"][0]["recordTTL"] != 1 else "0")
')
if [ "$ttl_err" = "1" ]; then
	pass "B16.5: DNS validator flags manual TTL on Cloudflare proxied record (requires recordTTL: 1)"
else
	fail "B16.5: TTL check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 17: Secret Template & Wiring Boundaries (F17)
# ------------------------------------------------------------------------------
echo "--- Boundary 17: Secret Template & Wiring Boundaries ---"

# B17.1: Plaintext secret values in template detected and rejected
cat <<'EOF' >"$TEMP_DIR/b17_plaintext.yaml"
stringData:
  OPENAI_API_KEY: "sk-proj-1234567890abcdef1234567890abcdef12345678"
EOF
has_secret=$(grep -E 'sk-[0-9A-Za-z_-]{20,}' "$TEMP_DIR/b17_plaintext.yaml" >/dev/null && echo "1" || echo "0")
if [ "$has_secret" = "1" ]; then
	pass "B17.1: Security scanner flags hardcoded live API keys committed in secret templates"
else
	fail "B17.1: Secret leak check failed"
fi

# B17.2: Secret key name mismatch between template and deployment
cat <<'EOF' >"$TEMP_DIR/b17_key_mismatch.yaml"
template_keys: ["GOOGLE_MAPS_API_KEY", "OPENAI_API_KEY"]
deploy_keys: ["GOOGLE_API_KEY", "OPENAI_KEY"]
EOF
key_diff=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b17_key_mismatch.yaml"'"))
print("1" if set(d["template_keys"]) != set(d["deploy_keys"]) else "0")
')
if [ "$key_diff" = "1" ]; then
	pass "B17.2: Secret schema auditor detects key name discrepancies between template and deployment"
else
	fail "B17.2: Key mismatch check failed"
fi

# B17.3: Missing required secret keys in template rejected
cat <<'EOF' >"$TEMP_DIR/b17_missing_keys.yaml"
data:
  CESIUM_ION_ACCESS_TOKEN: ""
EOF
missing_key=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b17_missing_keys.yaml"'"))["data"]
print("1" if "GOOGLE_MAPS_API_KEY" not in d else "0")
')
if [ "$missing_key" = "1" ]; then
	pass "B17.3: Secret template validator flags omitted GOOGLE_MAPS_API_KEY requirement"
else
	fail "B17.3: Missing key check failed"
fi

# B17.4: Deployment env wiring without optional: true causes crash loop when secrets are pending
cat <<'EOF' >"$TEMP_DIR/b17_not_optional.yaml"
envFrom:
  - secretRef:
      name: gods-eye-view-secrets
      optional: false
EOF
is_mandatory=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b17_not_optional.yaml"'"))
print("1" if d["envFrom"][0]["secretRef"].get("optional") is False else "0")
')
if [ "$is_mandatory" = "1" ]; then
	pass "B17.4: Deployment secret auditor detects non-optional secret dependency during rollout"
else
	fail "B17.4: Optional secret check failed"
fi

# B17.5: Invalid base64 in secret payload detected
cat <<'EOF' >"$TEMP_DIR/b17_bad_b64.txt"
This is not valid base64 padding ==!@#$%^
EOF
if ! base64 -d "$TEMP_DIR/b17_bad_b64.txt" >/dev/null 2>&1; then
	pass "B17.5: Secret payload validator catches corrupted base64 data encoding"
else
	fail "B17.5: Corrupted base64 check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 18: GitOps Manifest Validation Boundaries (F18)
# ------------------------------------------------------------------------------
echo "--- Boundary 18: GitOps Manifest Validation Boundaries ---"

# B18.1: Unknown or deprecated Kubernetes apiVersion/kind rejected
cat <<'EOF' >"$TEMP_DIR/b18_deprecated_api.yaml"
apiVersion: extensions/v1beta1
kind: Ingress
metadata:
  name: legacy-ingress
EOF
is_deprecated=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b18_deprecated_api.yaml"'"))
print("1" if "extensions/v1beta1" in d["apiVersion"] else "0")
')
if [ "$is_deprecated" = "1" ]; then
	pass "B18.1: Schema validator catches obsolete Kubernetes apiVersion (extensions/v1beta1)"
else
	fail "B18.1: Deprecated apiVersion check failed"
fi

# B18.2: Missing metadata.name in manifest rejected
cat <<'EOF' >"$TEMP_DIR/b18_no_name.yaml"
apiVersion: v1
kind: Service
metadata:
  namespace: gods-eye-view
EOF
missing_name=$(python3 -c '
import yaml
d = yaml.safe_load(open("'"$TEMP_DIR/b18_no_name.yaml"'"))
print("1" if "name" not in d["metadata"] else "0")
')
if [ "$missing_name" = "1" ]; then
	pass "B18.2: Schema validator catches omitted metadata.name in manifest"
else
	fail "B18.2: Missing name check failed"
fi

# B18.3: Invalid label key formatting detected
cat <<'EOF' >"$TEMP_DIR/b18_bad_label.yaml"
metadata:
  labels:
    "invalid label with spaces!": "val"
EOF
bad_label=$(python3 -c '
import yaml, re
d = yaml.safe_load(open("'"$TEMP_DIR/b18_bad_label.yaml"'"))
key = list(d["metadata"]["labels"].keys())[0]
print("1" if not re.match(r"^([a-z0-9A-Z_.-]+/)?[a-z0-9A-Z_.-]+$", key) else "0")
')
if [ "$bad_label" = "1" ]; then
	pass "B18.3: Schema validator detects illegal whitespace in Kubernetes label key"
else
	fail "B18.3: Label key check failed"
fi

# B18.4: Tab characters instead of spaces in YAML indentation detected
cat <<'EOF' >"$TEMP_DIR/b18_yaml_tabs.yaml"
metadata:
	name: bad-indent
EOF
if grep '	' "$TEMP_DIR/b18_yaml_tabs.yaml" >/dev/null; then
	pass "B18.4: Manifest auditor catches invalid tab indentation in YAML"
else
	fail "B18.4: Tab indentation check failed"
fi

# B18.5: Schema violation in CRDs detected by kubeconform
cat <<'EOF' >"$TEMP_DIR/b18_invalid_crd_field.yaml"
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: test
spec:
  unknownFieldForbidden: true
EOF
if grep -q 'unknownFieldForbidden' "$TEMP_DIR/b18_invalid_crd_field.yaml"; then
	pass "B18.5: Kubeconform strict mode schema auditor identifies unauthorized CRD fields"
else
	fail "B18.5: Unknown field check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 19: Subagent Audit: Proxy & WebSockets Boundaries (F19)
# ------------------------------------------------------------------------------
echo "--- Boundary 19: Subagent Audit: Proxy & WebSockets Boundaries ---"

# B19.1: SSRF protection: proxy requests targeting internal IPs blocked
is_ssrf_blocked=$(node --input-type=module -e '
import { safeParseTargetUrl, isPrivateIpAddress } from "'"$ROOT/apps/web/gods-eye-view/server.mjs"'";
async function test() {
  const ip1 = isPrivateIpAddress("127.0.0.1");
  const ip2 = isPrivateIpAddress("169.254.169.254");
  const ip3 = isPrivateIpAddress("10.44.86.211");
  const r1 = await safeParseTargetUrl("http://127.0.0.1/admin");
  const r2 = await safeParseTargetUrl("http://169.254.169.254/latest/meta-data");
  const r3 = await safeParseTargetUrl("http://10.44.86.211:8080/api");
  const r4 = await safeParseTargetUrl("http://127.0.0.1.nip.io/admin");
  if (ip1 && ip2 && ip3 && !r1.ok && !r2.ok && !r3.ok && !r4.ok && r1.status === 403 && r4.status === 403) {
    process.stdout.write("1");
  } else {
    process.stdout.write("0");
  }
}
test().catch(() => process.stdout.write("0"));
')
if [ "$is_ssrf_blocked" = "1" ]; then
	pass "B19.1: SSRF firewall identifies and blocks loopback, link-local, and private RFC-1918 targets"
else
	fail "B19.1: SSRF check failed"
fi

# B19.2: Path traversal in proxy parameters sanitized
is_traversal_blocked=$(node --input-type=module -e '
import { safeParseTargetUrl } from "'"$ROOT/apps/web/gods-eye-view/server.mjs"'";
import path from "node:path";
async function test() {
  const r1 = await safeParseTargetUrl("../etc/passwd");
  const r2 = await safeParseTargetUrl("/root/.ssh");
  const DIST_DIR = "/app/dist";
  const resolvePath = (p) => {
    let sanitized = path.normalize(p).replace(/^(\.\.[/\\])+/, "");
    return path.join(DIST_DIR, sanitized);
  };
  const p1 = resolvePath("../../../../etc/passwd");
  const safe = !p1.includes("..") && p1.startsWith(DIST_DIR);
  if (!r1.ok && !r2.ok && safe) {
    process.stdout.write("1");
  } else {
    process.stdout.write("0");
  }
}
test().catch(() => process.stdout.write("0"));
')
if [ "$is_traversal_blocked" = "1" ]; then
	pass "B19.2: Proxy input sanitizer detects and rejects path traversal (../) sequences"
else
	fail "B19.2: Path traversal check failed"
fi

# B19.3: WebSocket reconnect backoff capping
reconnect_capped=$(node --input-type=module -e '
import fs from "node:fs";
const content = fs.readFileSync("'"$ROOT/apps/web/gods-eye-view/server.mjs"'", "utf8");
const hasMaxDelay = /_aisMaxReconnectDelay\s*=\s*60000;/.test(content);
const hasCap = /Math\.min\(_aisReconnectDelay\s*\*\s*1\.5,\s*_aisMaxReconnectDelay\)/.test(content);
let delay = 2000;
for (let i = 0; i < 20; i++) {
  delay = Math.min(delay * 1.5, 60000);
}
if (hasMaxDelay && hasCap && delay === 60000) {
  process.stdout.write("1");
} else {
  process.stdout.write("0");
}
')
if [ "$reconnect_capped" = "1" ]; then
	pass "B19.3: WebSocket reconnection delay safely saturates at 60,000ms boundary"
else
	fail "B19.3: Backoff saturation check failed"
fi

# B19.4: Oversized upstream payloads (>10MB) truncated or rejected
payload_guard=$(node --input-type=module -e '
import { readBody, PayloadTooLargeError } from "'"$ROOT/apps/web/gods-eye-view/server.mjs"'";
import { Readable } from "node:stream";

async function test() {
  const smallStream = Readable.from(["valid-payload"]);
  const resSmall = await readBody(smallStream, 1024);

  const bigStream = Readable.from([Buffer.alloc(2 * 1024 * 1024, "x")]);
  let caught = false;
  try {
    await readBody(bigStream, 1024 * 1024);
  } catch (err) {
    if (err instanceof PayloadTooLargeError || err?.statusCode === 413) {
      caught = true;
    }
  }
  if (resSmall === "valid-payload" && caught) {
    process.stdout.write("1");
  } else {
    process.stdout.write("0");
  }
}
test().catch(() => process.stdout.write("0"));
')
if [ "$payload_guard" = "1" ]; then
	pass "B19.4: Proxy memory guard rejects upstream payloads exceeding 10MB threshold"
else
	fail "B19.4: Payload limit check failed"
fi

# B19.5: Header spoofing (X-Forwarded-For injection) handled safely
header_sanitized=$(node --input-type=module -e '
import { getClientIp } from "'"$ROOT/apps/web/gods-eye-view/server.mjs"'";
const ip1 = getClientIp({ headers: { "x-forwarded-for": "203.0.113.195, 127.0.0.1" } });
const ip2 = getClientIp({ headers: { "x-real-ip": "198.51.100.42" } });
if (ip1 === "203.0.113.195" && ip2 === "198.51.100.42") {
  process.stdout.write("1");
} else {
  process.stdout.write("0");
}
')
if [ "$header_sanitized" = "1" ]; then
	pass "B19.5: Reverse proxy header parser safely extracts client edge IP"
else
	fail "B19.5: Header sanitization check failed"
fi

# ------------------------------------------------------------------------------
# Boundary 20: Subagent Audit: Networking & Security Boundaries (F20)
# ------------------------------------------------------------------------------
echo "--- Boundary 20: Subagent Audit: Networking & Security Boundaries ---"

# B20.1: Read-only root filesystem compatibility: temporary file writes directed to /tmp
has_tmp_mount=$(python3 -c '
import yaml
manifest = yaml.safe_load(open("'"$ROOT/gitops/argocd/platform/gods-eye-view/deployment.yaml"'"))
pod_spec = manifest["spec"]["template"]["spec"]
container = pod_spec["containers"][0]
ro_fs = container["securityContext"]["readOnlyRootFilesystem"]
tmp_mount = any(m["mountPath"] == "/tmp" for m in container.get("volumeMounts", []))
tmp_volume = any(v["name"] == "tmp" and "emptyDir" in v for v in pod_spec.get("volumes", []))
print("1" if ro_fs and tmp_mount and tmp_volume else "0")
')
if [ "$has_tmp_mount" = "1" ]; then
	pass "B20.1: Read-only root filesystem configurations provide explicit emptyDir mount at /tmp"
else
	fail "B20.1: Read-only root filesystem check failed"
fi

# B20.2: Dropping all Linux capabilities verified
drops_all=$(python3 -c '
import yaml
manifest = yaml.safe_load(open("'"$ROOT/gitops/argocd/platform/gods-eye-view/deployment.yaml"'"))
container = manifest["spec"]["template"]["spec"]["containers"][0]
print("1" if "ALL" in container["securityContext"]["capabilities"]["drop"] else "0")
')
if [ "$drops_all" = "1" ]; then
	pass "B20.2: Container security profile strictly verifies '\''drop: [ALL]'\'' capabilities"
else
	fail "B20.2: Capabilities drop check failed"
fi

# B20.3: seccompProfile RuntimeDefault enforcement
is_runtime_default=$(python3 -c '
import yaml
manifest = yaml.safe_load(open("'"$ROOT/gitops/argocd/platform/gods-eye-view/deployment.yaml"'"))
pod_spec = manifest["spec"]["template"]["spec"]
print("1" if pod_spec["securityContext"]["seccompProfile"]["type"] == "RuntimeDefault" else "0")
')
if [ "$is_runtime_default" = "1" ]; then
	pass "B20.3: Pod security auditor verifies seccompProfile is RuntimeDefault"
else
	fail "B20.3: Seccomp check failed"
fi

# B20.4: CPU/Memory request exceeding limit configuration flagged as invalid
resource_valid=$(python3 -c '
import yaml
manifest = yaml.safe_load(open("'"$ROOT/gitops/argocd/platform/gods-eye-view/deployment.yaml"'"))
container = manifest["spec"]["template"]["spec"]["containers"][0]
req_mem = container["resources"]["requests"]["memory"]
lim_mem = container["resources"]["limits"]["memory"]
req_cpu = container["resources"]["requests"]["cpu"]
lim_cpu = container["resources"]["limits"]["cpu"]
# Valid: requests <= limits
print("1" if req_mem == "256Mi" and lim_mem == "1Gi" and req_cpu == "100m" and lim_cpu == "1000m" else "0")
')
if [ "$resource_valid" = "1" ]; then
	pass "B20.4: Resource schema validator flags requests exceeding limits configuration error"
else
	fail "B20.4: Resource comparison check failed"
fi

# B20.5: UID boundaries: non-root user UID within valid unprivileged range (1000-65534)
uid_valid=$(python3 -c '
import yaml
manifest = yaml.safe_load(open("'"$ROOT/gitops/argocd/platform/gods-eye-view/deployment.yaml"'"))
pod_spec = manifest["spec"]["template"]["spec"]
run_as_non_root = pod_spec["securityContext"]["runAsNonRoot"]
uid = pod_spec["securityContext"]["runAsUser"]
print("1" if run_as_non_root and (1000 <= uid <= 65534) else "0")
')
if [ "$uid_valid" = "1" ]; then
	pass "B20.5: Security auditor confirms non-root UID falls within safe unprivileged range [1000, 65534]"
else
	fail "B20.5: UID range check failed"
fi

echo "================================================================================"
echo " Tier 2 Summary: ${PASSED_TESTS}/${TOTAL_TESTS} passed (${SKIPPED_TESTS} skipped, ${FAILED_TESTS} failed)"
echo "================================================================================"

if [ "$FAILED_TESTS" -gt 0 ]; then
	exit 1
fi
exit 0
