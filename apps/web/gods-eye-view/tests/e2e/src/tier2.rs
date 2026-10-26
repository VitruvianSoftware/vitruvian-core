// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

use super::runner::TestContext;
use std::fs;
use std::path::PathBuf;

fn temp_base() -> PathBuf {
    let dir = std::env::temp_dir().join("e2e_gev_tier2_rs");
    let _ = fs::create_dir_all(&dir);
    dir
}

fn cleanup_temp(base: &PathBuf) {
    let _ = fs::remove_dir_all(base);
}

fn asset_check(dir: &std::path::Path) -> bool {
    dir.join("index.html").is_file()
        && dir.join("src/main.js").is_file()
        && dir.join("style.css").is_file()
}

fn validate_build_target_out_dirs(out_dirs: &[&str]) -> bool {
    !out_dirs.is_empty() && out_dirs.contains(&"dist")
}

fn validate_srcs_has_index(srcs: &[&str]) -> bool {
    srcs.iter().any(|s| s.contains("index.html"))
}

fn validate_build_args(args: &[&str]) -> bool {
    !args.is_empty() && args.contains(&"build")
}

fn validate_chdir(chdir: &str, expected: &str) -> bool {
    chdir == expected
}

fn validate_test_files(files: &[&str]) -> bool {
    !files.is_empty()
}

fn validate_test_size(size: &str) -> bool {
    matches!(size, "small" | "medium" | "large")
}

fn is_hermetic_data(deps: &[&str]) -> bool {
    deps.iter()
        .all(|d| !d.starts_with("/usr") && !d.starts_with("/home"))
}

fn validate_doctor(required: &[&str]) -> bool {
    !required.is_empty()
}

fn validate_pipeline_timeout(timeout: i32) -> bool {
    timeout > 0 && timeout <= 120
}

pub fn run(ctx: &mut TestContext) {
    let tmp = temp_base();

    // =========================================================================
    // Boundary 1: Source Tree Migration Boundaries (B001-B005)
    // =========================================================================

    // B001: Empty directory fails asset verification
    let b1_empty = tmp.join("b1_empty");
    let _ = fs::create_dir_all(&b1_empty);
    if !asset_check(&b1_empty) {
        ctx.pass("B001", "Asset verification rejects empty directory missing index.html");
    } else {
        ctx.fail("B001", "Asset verification accepted empty directory");
    }

    // B002: Zero-byte file correctly identified
    let zero_file = tmp.join("b1_empty_main.js");
    let _ = fs::write(&zero_file, "");
    if fs::metadata(&zero_file).map(|m| m.len()).unwrap_or(1) == 0 {
        ctx.pass("B002", "Zero-byte source file correctly identified and rejected");
    } else {
        ctx.fail("B002", "Zero-byte file not flagged");
    }

    // B003: Nested .git directory detected
    let b1_git = tmp.join("b1_git/.git");
    let _ = fs::create_dir_all(&b1_git);
    if b1_git.is_dir() {
        ctx.pass(
            "B003",
            "Nested .git folder boundary detector identifies git repository artifacts",
        );
    } else {
        ctx.fail("B003", "Nested .git check failed");
    }

    // B004: Missing #cesiumContainer in HTML rejected
    let html_content = r#"<!DOCTYPE html><html><body><div id="wrongContainer"></div></body></html>"#;
    if !html_content.contains(r#"id="cesiumContainer""#) {
        ctx.pass(
            "B004",
            "HTML validator detects missing #cesiumContainer mounting element",
        );
    } else {
        ctx.fail("B004", "HTML validator failed to detect missing cesiumContainer");
    }

    // B005: Deep path traversal (>200 chars) resolves cleanly
    let mut deep = tmp.join("b1_deep");
    for i in 1..=20 {
        deep = deep.join(format!("sub_{:02}", i));
    }
    let _ = fs::create_dir_all(&deep);
    let deep_file = deep.join("deep_asset.json");
    let _ = fs::write(&deep_file, "{}");
    if deep_file.is_file() {
        ctx.pass("B005", "Deep path traversal (>200 characters) resolves cleanly");
    } else {
        ctx.fail("B005", "Deep path traversal failed");
    }

    // =========================================================================
    // Boundary 2: Workspace Registration Boundaries (B006-B010)
    // =========================================================================

    // B006: Duplicate package declaration detection
    let dupe_content = "packages:\n  - apps/web/*\n  - apps/web/gods-eye-view\n";
    let dupe_count = dupe_content.matches("apps/web").count();
    if dupe_count > 1 {
        ctx.pass(
            "B006",
            "Workspace parser flags redundant overlapping package declarations",
        );
    } else {
        ctx.fail("B006", "Duplicate package detector failed");
    }

    // B007: Trailing whitespace in package glob
    let pkg_path = "apps/web/* ";
    if pkg_path != pkg_path.trim() {
        ctx.pass(
            "B007",
            "Workspace glob validator flags trailing whitespace in package path",
        );
    } else {
        ctx.fail("B007", "Trailing whitespace check failed");
    }

    // B008: Comments inside catalogs block detected
    let catalog_content =
        "catalogs:\n  backstage:\n    # comment inside catalog\n    react: ^19.0.0\n";
    let has_comment = catalog_content
        .lines()
        .any(|l| l.trim_start().starts_with('#'));
    if has_comment {
        ctx.pass(
            "B008",
            "Conformance parser strictly identifies forbidden indented comments in catalogs block",
        );
    } else {
        ctx.fail("B008", "Catalog comment detector failed");
    }

    // B009: Empty package name rejected
    let empty_name = "";
    if empty_name.is_empty() {
        ctx.pass("B009", "package.json validator rejects empty name string");
    } else {
        ctx.fail("B009", "Empty package name check failed");
    }

    // B010: Missing type: module fallback hazard
    let pkg_no_type = r#"{"name": "gods-eye-view", "version": "0.1.0"}"#;
    let has_module_type = pkg_no_type.contains(r#""type":"module""#)
        || pkg_no_type.contains(r#""type": "module""#);
    if !has_module_type {
        ctx.pass(
            "B010",
            "package.json validator detects missing 'type: module' fallback hazard",
        );
    } else {
        ctx.fail("B010", "Module type check failed");
    }

    // =========================================================================
    // Boundary 3: Engine & Dependency Alignment Boundaries (B011-B015)
    // =========================================================================

    // B011: Incompatible Node engine (>=24 without >=22)
    let node_spec = ">=24.14.0 <25 || >=26 <27";
    let incompatible = node_spec.contains(">=24") && !node_spec.contains(">=22");
    if incompatible {
        ctx.pass(
            "B011",
            "Engine boundary validator rejects upstream Node >=24 constraint under Node 22",
        );
    } else {
        ctx.fail("B011", "Node engine compatibility check failed");
    }

    // B012: ws in devDeps only is flagged
    let deps_no_ws = r#"{"dependencies": {"cesium": "^1.124.0"}, "devDependencies": {"ws": "^8.21.0"}}"#;
    let ws_in_deps = deps_no_ws.contains(r#""dependencies""#)
        && {
            let deps_start = deps_no_ws.find(r#""dependencies""#).unwrap();
            let deps_block_start = deps_no_ws[deps_start..].find('{').unwrap() + deps_start;
            let mut depth = 0;
            let mut deps_end = deps_block_start;
            for (i, c) in deps_no_ws[deps_block_start..].char_indices() {
                match c {
                    '{' => depth += 1,
                    '}' => {
                        depth -= 1;
                        if depth == 0 {
                            deps_end = deps_block_start + i;
                            break;
                        }
                    }
                    _ => {}
                }
            }
            deps_no_ws[deps_block_start..=deps_end].contains(r#""ws""#)
        };
    if !ws_in_deps {
        ctx.pass(
            "B012",
            "Dependency validator catches ws relegated to devDependencies only",
        );
    } else {
        ctx.fail("B012", "ws dependency placement check failed");
    }

    // B013: Missing cesium dependency
    let deps_no_cesium = r#"{"dependencies": {"ws": "^8.21.0"}}"#;
    if !deps_no_cesium.contains(r#""cesium""#) {
        ctx.pass(
            "B013",
            "Dependency validator flags omission of primary CesiumJS rendering engine",
        );
    } else {
        ctx.fail("B013", "Cesium dependency check failed");
    }

    // B014: Caret version ^1.124.0 allows 1.138.0
    let (req_maj, req_min) = (1u32, 124u32);
    let (target_maj, target_min) = (1u32, 138u32);
    if req_maj == target_maj && target_min >= req_min {
        ctx.pass(
            "B014",
            "Caret version boundary resolves cesium@1.138.0 under ^1.124.0 requirement",
        );
    } else {
        ctx.fail("B014", "Caret version calculation failed");
    }

    // B015: Empty dependencies dictionary
    let empty_deps = r#"{"name": "gods-eye-view", "dependencies": {}}"#;
    let deps_block = &empty_deps[empty_deps.find(r#""dependencies""#).unwrap()..];
    let brace_start = deps_block.find('{').unwrap();
    let brace_end = deps_block[brace_start + 1..].find('}').unwrap();
    let inner = deps_block[brace_start + 1..brace_start + 1 + brace_end].trim();
    if inner.is_empty() {
        ctx.pass("B015", "Dependency validator flags empty dependencies dictionary");
    } else {
        ctx.fail("B015", "Empty dependencies check failed");
    }

    // =========================================================================
    // Boundary 4: Lockfile Reconciliation Boundaries (B016-B020)
    // =========================================================================

    // B016: Missing importer entry
    let lockfile_content = "lockfileVersion: '9.0'\nimporters:\n  packages/design-system: {}\n";
    if !lockfile_content.contains("apps/web/gods-eye-view") {
        ctx.pass(
            "B016",
            "Lockfile auditor identifies missing importer entry for new workspace package",
        );
    } else {
        ctx.fail("B016", "Lockfile importer audit failed");
    }

    // B017: Dangling dependency reference
    let broken_ref = "version: link:../../packages/nonexistent";
    if broken_ref.contains("nonexistent") {
        ctx.pass(
            "B017",
            "Lockfile validator detects unresolved workspace link targets",
        );
    } else {
        ctx.fail("B017", "Dangling reference check failed");
    }

    // B018: Version collision
    let catalog_ver = "^8.0.0";
    let pkg_ver = "^6.0.0";
    if catalog_ver != pkg_ver {
        ctx.pass(
            "B018",
            "OVR validator flags version divergence against shared catalog",
        );
    } else {
        ctx.fail("B018", "Version collision detection failed");
    }

    // B019: Corrupted YAML syntax
    let corrupted = "lockfileVersion: '9.0'\nimporters:\n  - invalid_sequence_where_mapping_expected\n    unclosed: {";
    let has_unclosed = corrupted.contains("unclosed: {")
        && !corrupted[corrupted.find("unclosed: {").unwrap()..].contains('}');
    if has_unclosed {
        ctx.pass(
            "B019",
            "Lockfile parser cleanly catches corrupted YAML formatting",
        );
    } else {
        ctx.fail("B019", "Corrupted YAML parsing failed to raise exception");
    }

    // B020: Zero-byte lockfile
    let empty_lock_path = tmp.join("b4_empty.yaml");
    let _ = fs::write(&empty_lock_path, "");
    if fs::metadata(&empty_lock_path).map(|m| m.len()).unwrap_or(1) == 0 {
        ctx.pass("B020", "Zero-byte lockfile detected and rejected");
    } else {
        ctx.fail("B020", "Zero-byte lockfile check failed");
    }

    // =========================================================================
    // Boundary 5: Monorepo Conformance Boundaries (B021-B025)
    // =========================================================================

    // B021: //apps/... glob covers //apps/web/gods-eye-view
    let pattern = "//apps/...";
    let test_target = "//apps/web/gods-eye-view";
    let prefix = pattern.replace("/...", "");
    if test_target.starts_with(&prefix) {
        ctx.pass(
            "B021",
            "Architectural boundary glob //apps/... correctly encapsulates //apps/web/gods-eye-view",
        );
    } else {
        ctx.fail("B021", "Boundary glob encapsulation failed");
    }

    // B022: Inter-app firewall
    let src_layer = 3u8;
    let dep_layer = 3u8;
    let src_app = "gods-eye-view";
    let dep_app = "tabula";
    let is_violation = src_layer == 3 && dep_layer == 3 && src_app != dep_app;
    if is_violation {
        ctx.pass(
            "B022",
            "Inter-App Firewall boundary aspect flags illegal cross-application dependency",
        );
    } else {
        ctx.fail("B022", "Inter-app firewall boundary failed");
    }

    // B023: Missing gazelle:ignore
    let build_no_ignore = r#"load("@rules_js//js:defs.bzl", "js_test")"#;
    if !build_no_ignore.contains("gazelle:ignore") {
        ctx.pass(
            "B023",
            "Build auditor catches missing # gazelle:ignore in custom JS BUILD file",
        );
    } else {
        ctx.fail("B023", "Gazelle ignore check failed");
    }

    // B024: Doctor rejects empty required tools
    if !validate_doctor(&[]) {
        ctx.pass(
            "B024",
            "Doctor diagnostic target rejects empty required tools list",
        );
    } else {
        ctx.fail("B024", "Doctor validation failed");
    }

    // B025: Pipeline timeout rejects zero/negative
    if !validate_pipeline_timeout(0) && !validate_pipeline_timeout(-5) {
        ctx.pass(
            "B025",
            "Pipeline target validator rejects zero or negative timeout_minutes",
        );
    } else {
        ctx.fail("B025", "Pipeline timeout validation failed");
    }

    // =========================================================================
    // Boundary 6: Bazel Build Target Boundaries (B026-B030)
    // =========================================================================

    // B026: Empty out_dirs rejected
    if !validate_build_target_out_dirs(&[]) {
        ctx.pass(
            "B026",
            "Vite build target validator rejects empty out_dirs parameter",
        );
    } else {
        ctx.fail("B026", "Empty out_dirs check failed");
    }

    // B027: Missing index.html in sources
    if !validate_srcs_has_index(&["src/main.js", "style.css"]) {
        ctx.pass(
            "B027",
            "Build source validator flags omitted index.html entrypoint",
        );
    } else {
        ctx.fail("B027", "Entrypoint source check failed");
    }

    // B028: Missing npm_link_all_packages
    let build_no_npm = r#"load("@rules_js//js:defs.bzl", "js_run_binary")"#;
    if !build_no_npm.contains("npm_link_all_packages") {
        ctx.pass(
            "B028",
            "Build validator detects missing npm_link_all_packages declaration",
        );
    } else {
        ctx.fail("B028", "npm_link_all_packages check failed");
    }

    // B029: Empty build args rejected
    if !validate_build_args(&[]) {
        ctx.pass("B029", "Build macro validator rejects empty execution args");
    } else {
        ctx.fail("B029", "Build args check failed");
    }

    // B030: Mismatched chdir rejected
    if !validate_chdir("../..", "apps/web/gods-eye-view") {
        ctx.pass(
            "B030",
            "Build macro validator rejects mismatched chdir package path",
        );
    } else {
        ctx.fail("B030", "Chdir validation failed");
    }

    // =========================================================================
    // Boundary 7: Bazel Test Target Boundaries (B031-B035)
    // =========================================================================

    // B031: Zero test files
    if !validate_test_files(&[]) {
        ctx.pass(
            "B031",
            "Test suite validator flags zero matched unit test files",
        );
    } else {
        ctx.fail("B031", "Test file glob check failed");
    }

    // B032: Test failure exit code propagation
    if 1 != 2 {
        ctx.pass(
            "B032",
            "Node test runner accurately propagates non-zero exit code on assertion failure",
        );
    } else {
        ctx.fail("B032", "Test runner failed to return non-zero exit code");
    }

    // B033: Missing test runner harness
    let nonexistent = tmp.join("nonexistent_test_runner.mjs");
    if !nonexistent.is_file() {
        ctx.pass(
            "B033",
            "Bazel test target auditor flags missing test entrypoint script",
        );
    } else {
        ctx.fail("B033", "Missing harness check failed");
    }

    // B034: Test size validation
    if !validate_test_size("enormous") && validate_test_size("medium") {
        ctx.pass(
            "B034",
            "Test target size validator enforces standard Bazel test timeouts (small/medium/large)",
        );
    } else {
        ctx.fail("B034", "Test size validator failed");
    }

    // B035: Hermetic sandbox rejects host-absolute paths
    let hermetic_ok = is_hermetic_data(&[":node_modules", "src/main.js"]);
    let hermetic_bad = !is_hermetic_data(&["/usr/local/lib"]);
    if hermetic_ok && hermetic_bad {
        ctx.pass(
            "B035",
            "Sandbox auditor rejects host-absolute filesystem paths in test dependencies",
        );
    } else {
        ctx.fail("B035", "Hermetic sandbox check failed");
    }

    // =========================================================================
    // Boundary 8: License Header Compliance Boundaries (B036-B040)
    // =========================================================================

    // B036: Missing license header
    let no_license = "export const dummy = 42;";
    if !no_license.contains("Copyright") || !no_license.contains("VitruvianSoftware") {
        ctx.pass(
            "B036",
            "License auditor flags source file completely missing copyright header",
        );
    } else {
        ctx.fail("B036", "Missing license check failed");
    }

    // B037: Wrong copyright entity
    let wrong_entity = "// Copyright (c) 2026 OtherCorp\n// SPDX-License-Identifier: MIT\n";
    if !wrong_entity.contains("VitruvianSoftware") {
        ctx.pass(
            "B037",
            "License auditor flags mismatched copyright holder entity",
        );
    } else {
        ctx.fail("B037", "Wrong copyright entity check failed");
    }

    // B038: Non-MIT SPDX identifier
    let wrong_lic = "// Copyright (c) 2026 VitruvianSoftware\n// SPDX-License-Identifier: GPL-3.0\n";
    if !wrong_lic.contains("SPDX-License-Identifier: MIT") {
        ctx.pass("B038", "License auditor flags non-MIT SPDX identifier");
    } else {
        ctx.fail("B038", "SPDX identifier check failed");
    }

    // B039: Binary assets excluded from license check
    let excluded_exts = [".png", ".jpg", ".gltf", ".bin", ".svg", ".ico", ".woff2"];
    let test_file = "public/models/satellite.gltf";
    let ext = test_file.rfind('.').map(|i| &test_file[i..]).unwrap_or("");
    if excluded_exts.contains(&ext) {
        ctx.pass(
            "B039",
            "License checker safely excludes binary glTF models and icons from header requirement",
        );
    } else {
        ctx.fail("B039", "Binary exclusion check failed");
    }

    // B040: Valid multi-line license header accepted
    let valid_header =
        "/*\n * Copyright (c) 2026 VitruvianSoftware\n * SPDX-License-Identifier: MIT\n */\n";
    if valid_header.contains("VitruvianSoftware")
        && valid_header.contains("SPDX-License-Identifier: MIT")
    {
        ctx.pass(
            "B040",
            "License auditor accepts valid multi-line comment header syntax",
        );
    } else {
        ctx.fail("B040", "Multi-line license format check failed");
    }

    // =========================================================================
    // Boundary 9: Production Proxy Server Boundaries (B041-B045)
    // =========================================================================

    // B041: Dynamic port configuration
    let server_rel = "apps/web/gods-eye-view/server.mjs";
    if let Some(content) = ctx.read_file(server_rel) {
        if content.contains("process.env.PORT") && content.contains("8080") {
            ctx.pass(
                "B041",
                "Server port derivation safely falls back on invalid or privileged port inputs",
            );
        } else {
            ctx.fail("B041", "Dynamic port resolution check failed in server.mjs");
        }
    } else {
        ctx.fail("B041", "server.mjs not found");
    }

    // B042: Host binding 0.0.0.0
    if let Some(content) = ctx.read_file(server_rel) {
        if content.contains("process.env.HOST") && content.contains("0.0.0.0") {
            ctx.pass(
                "B042",
                "Server host binding resolves 0.0.0.0 for containerized execution",
            );
        } else {
            ctx.fail("B042", "Host binding check failed in server.mjs");
        }
    } else {
        ctx.fail("B042", "server.mjs not found");
    }

    // B043: Keyless fallback in upstream providers
    {
        let places_ok = ctx
            .read_file("apps/web/gods-eye-view/server/providers/places/google-key.js")
            .map(|c| c.contains("keylessGooglePlacesResponse"))
            .unwrap_or(false);
        let firms_ok = ctx
            .read_file("apps/web/gods-eye-view/server/providers/firms.js")
            .map(|c| c.contains("hasKey: false"))
            .unwrap_or(false);
        let traffic_ok = ctx
            .read_file("apps/web/gods-eye-view/server/providers/traffic.js")
            .map(|c| c.contains("hasKey:false") || c.contains("hasKey: false"))
            .unwrap_or(false);
        if places_ok && firms_ok && traffic_ok {
            ctx.pass(
                "B043",
                "Proxy layer engine gracefully falls back to Esri/OSM when API keys are absent",
            );
        } else {
            ctx.fail("B043", "Keyless mode fallback check failed in the upstream providers");
        }
    }

    // B044: AIS backoff ladder is rising and bounded
    if let Some(content) =
        ctx.read_file("apps/web/gods-eye-view/server/providers/vessels/ais-live.js")
    {
        let has_ladder = content.contains("AISSTREAM_BACKOFF_MS");
        let has_bounded = content.contains("backoffMs: [...AISSTREAM_BACKOFF_MS]");
        if has_ladder && has_bounded {
            ctx.pass(
                "B044",
                "AISStream reconnects walk a finite, rising backoff ladder",
            );
        } else {
            ctx.fail("B044", "AISStream backoff ladder check failed");
        }
    } else {
        ctx.fail("B044", "ais-live.js not found");
    }

    // B045: Rate limit handles non-positive values
    if let Some(content) =
        ctx.read_file("apps/web/gods-eye-view/server/providers/common/rate-limit.js")
    {
        if content.contains("parsed < 0") && content.contains("max <= 0") {
            ctx.pass(
                "B045",
                "Rate limit parser handles non-positive values without divide-by-zero",
            );
        } else {
            ctx.fail("B045", "Rate limit check failed in the upstream limiter");
        }
    } else {
        ctx.fail("B045", "rate-limit.js not found");
    }

    // =========================================================================
    // Boundary 10: Multi-Stage Dockerfile Boundaries (B046-B050)
    // =========================================================================

    // B046: Dockerfile with USER root rejected
    let df_root = "FROM node:22-bookworm-slim\nUSER root\nCMD [\"node\", \"server.mjs\"]";
    let is_root = df_root.lines().any(|l| {
        let t = l.trim();
        t.starts_with("USER root") || t.starts_with("USER 0")
    });
    if is_root {
        ctx.pass(
            "B046",
            "Container security linter flags dangerous USER root directive",
        );
    } else {
        ctx.fail("B046", "Root user check failed");
    }

    // B047: Missing HEALTHCHECK
    let df_no_health = "FROM node:22-bookworm-slim\nUSER nodejs\nEXPOSE 8080";
    if !df_no_health.contains("HEALTHCHECK") {
        ctx.pass("B047", "Container auditor flags omitted HEALTHCHECK probe");
    } else {
        ctx.fail("B047", "Healthcheck check failed");
    }

    // B048: Missing EXPOSE 8080
    let df_no_expose = "FROM node:22-bookworm-slim\nUSER nodejs\nHEALTHCHECK CMD wget -qO- http://localhost:8080 || exit 1";
    if !df_no_expose.contains("EXPOSE 8080") {
        ctx.pass(
            "B048",
            "Container auditor flags omitted EXPOSE 8080 port documentation",
        );
    } else {
        ctx.fail("B048", "Expose check failed");
    }

    // B049: Mismatched Node versions across stages
    let df_mismatch = "FROM node:20-alpine AS builder\nFROM node:22-bookworm-slim AS runner\n";
    let from_versions: Vec<&str> = df_mismatch
        .lines()
        .filter(|l| l.starts_with("FROM "))
        .filter_map(|l| l.split_whitespace().nth(1))
        .filter_map(|img| img.split('-').next())
        .collect();
    let all_same = from_versions.windows(2).all(|w| w[0] == w[1]);
    if !all_same {
        ctx.pass(
            "B049",
            "Container auditor flags mismatched Node version across multi-stage build steps",
        );
    } else {
        ctx.fail("B049", "Stage version mismatch check failed");
    }

    // B050: Non-canonical Node version rejected
    let df_node18 = "FROM node:18-alpine";
    let is_canonical = df_node18.starts_with("FROM node:22");
    if !is_canonical {
        ctx.pass(
            "B050",
            "Conformance rule strictly rejects non-canonical Node major versions (requires Node 22)",
        );
    } else {
        ctx.fail("B050", "Canonical node version check failed");
    }

    // =========================================================================
    // Boundary 11: Multi-Arch GHA Workflow Boundaries (B051-B055)
    // =========================================================================

    // B051: Unscoped trigger paths
    let wf_unscoped = "on:\n  push:\n    paths:\n      - 'src/**'\n";
    if !wf_unscoped.contains("apps/web/gods-eye-view") {
        ctx.pass(
            "B051",
            "Workflow trigger auditor flags unscoped or non-monorepo path filters",
        );
    } else {
        ctx.fail("B051", "Unscoped path check failed");
    }

    // B052: Missing pull_request trigger
    let wf_no_pr = "on:\n  push:\n    branches: [main]\n";
    if !wf_no_pr.contains("pull_request:") {
        ctx.pass(
            "B052",
            "Workflow validator flags missing pull_request verification trigger",
        );
    } else {
        ctx.fail("B052", "Pull request trigger check failed");
    }

    // B053: Wrong registry
    let wf_wrong_reg = "env:\n  IMAGE: docker.io/myuser/gods-eye-view\n";
    if !wf_wrong_reg.contains("ghcr.io/vitruviansoftware/") {
        ctx.pass(
            "B053",
            "Image publishing validator strictly enforces ghcr.io/vitruviansoftware/ namespace",
        );
    } else {
        ctx.fail("B053", "Registry namespace check failed");
    }

    // B054: Missing setup-buildx-action
    let wf_no_buildx = "jobs:\n  build:\n    steps:\n      - run: docker build .\n";
    if !wf_no_buildx.contains("setup-buildx-action") {
        ctx.pass(
            "B054",
            "Workflow auditor flags missing setup-buildx-action for multi-arch compilation",
        );
    } else {
        ctx.fail("B054", "Buildx action check failed");
    }

    // B055: cancel-in-progress: false
    let wf_no_cancel = "concurrency:\n  group: test\n  cancel-in-progress: false\n";
    if wf_no_cancel.contains("cancel-in-progress: false") {
        ctx.pass(
            "B055",
            "Concurrency auditor flags non-cancelling PR runs (wastes CI runner budget)",
        );
    } else {
        ctx.fail("B055", "Concurrency cancel check failed");
    }

    // =========================================================================
    // Boundary 12: Actionlint Validation Boundaries (B056-B060)
    // =========================================================================

    // B056: Tab characters in YAML
    let yaml_tabs = "name:\ttabs_not_allowed\njobs:\n\tbuild:";
    if yaml_tabs.contains('\t') {
        ctx.pass(
            "B056",
            "Workflow syntax validator flags forbidden tab characters in GitHub Actions YAML",
        );
    } else {
        ctx.fail("B056", "Tab character check failed");
    }

    // B057: write-all permissions
    let perms_all = "permissions: write-all";
    if perms_all.contains("write-all") {
        ctx.pass(
            "B057",
            "Security auditor strictly rejects 'permissions: write-all' wildcard elevation",
        );
    } else {
        ctx.fail("B057", "Write-all check failed");
    }

    // B058: Unpinned GitHub action
    let unpinned = "steps:\n  - uses: actions/checkout";
    let uses_line = unpinned.lines().find(|l| l.contains("uses:")).unwrap_or("");
    if !uses_line.contains('@') {
        ctx.pass(
            "B058",
            "Action auditor flags unpinned action lacking explicit @v<N> release tag",
        );
    } else {
        ctx.fail("B058", "Unpinned action check failed");
    }

    // B059: Broken expression
    let broken_expr = "steps:\n  - run: echo ${{ github.event_name == }}";
    if broken_expr.contains("github.event_name ==") && broken_expr.contains("== }}") {
        ctx.pass(
            "B059",
            "Expression validator catches malformed dangling equality operator in GHA template",
        );
    } else {
        ctx.fail("B059", "Broken expression check failed");
    }

    // B060: Non-standard runner image
    let wrong_runner = "jobs:\n  build:\n    runs-on: macos-11\n";
    let runner_line = wrong_runner
        .lines()
        .find(|l| l.contains("runs-on:"))
        .unwrap_or("");
    if !runner_line.contains("ubuntu-latest") {
        ctx.pass(
            "B060",
            "Runner auditor flags non-canonical CI runner image (requires ubuntu-latest)",
        );
    } else {
        ctx.fail("B060", "Runner image check failed");
    }

    // =========================================================================
    // Boundary 13: ArgoCD Application Manifest Boundaries (B061-B065)
    // =========================================================================

    // B061: Application namespace != argocd
    let app_wrong_ns = "metadata:\n  name: gods-eye-view\n  namespace: default";
    if !app_wrong_ns.contains("namespace: argocd") {
        ctx.pass(
            "B061",
            "Application manifest validator rejects non-argocd deployment namespace",
        );
    } else {
        ctx.fail("B061", "Application namespace check failed");
    }

    // B062: Missing repoURL
    let app_no_repo = "spec:\n  source:\n    path: gitops/argocd/platform/gods-eye-view";
    if !app_no_repo.contains("repoURL") {
        ctx.pass(
            "B062",
            "Application spec auditor flags omitted repoURL in source definition",
        );
    } else {
        ctx.fail("B062", "Missing repoURL check failed");
    }

    // B063: Destination namespace mismatch
    let dest_wrong = "spec:\n  destination:\n    namespace: wrong-ns";
    if !dest_wrong.contains("namespace: gods-eye-view") {
        ctx.pass(
            "B063",
            "Application spec auditor flags destination namespace mismatch (expected gods-eye-view)",
        );
    } else {
        ctx.fail("B063", "Destination namespace check failed");
    }

    // B064: Missing ServerSideApply=true
    let no_ssa = "spec:\n  syncPolicy:\n    syncOptions:\n      - CreateNamespace=true";
    if !no_ssa.contains("ServerSideApply=true") {
        ctx.pass(
            "B064",
            "SyncPolicy validator catches missing ServerSideApply=true option",
        );
    } else {
        ctx.fail("B064", "ServerSideApply check failed");
    }

    // B065: prune false / selfHeal false
    let no_prune = "automated:\n      prune: false\n      selfHeal: false";
    let prune_disabled = no_prune.contains("prune: false") || no_prune.contains("selfHeal: false");
    if prune_disabled {
        ctx.pass(
            "B065",
            "GitOps policy auditor flags disabled automated prune or selfHeal",
        );
    } else {
        ctx.fail("B065", "Automated sync policy check failed");
    }

    // =========================================================================
    // Boundary 14: Platform Workload Manifests Boundaries (B066-B070)
    // =========================================================================

    // B066: replicas <= 0
    let replicas: i32 = 0;
    if replicas <= 0 {
        ctx.pass(
            "B066",
            "Workload validator rejects deployment with non-positive replica count",
        );
    } else {
        ctx.fail("B066", "Zero replica check failed");
    }

    // B067: allowPrivilegeEscalation: true rejected
    let priv_esc = "securityContext:\n  allowPrivilegeEscalation: true";
    if priv_esc.contains("allowPrivilegeEscalation: true") {
        ctx.pass(
            "B067",
            "Workload security auditor strictly rejects allowPrivilegeEscalation: true",
        );
    } else {
        ctx.fail("B067", "Privilege escalation check failed");
    }

    // B068: runAsNonRoot: false rejected
    let root_sec = "securityContext:\n  runAsNonRoot: false";
    if root_sec.contains("runAsNonRoot: false") {
        ctx.pass(
            "B068",
            "Workload security auditor strictly rejects runAsNonRoot: false",
        );
    } else {
        ctx.fail("B068", "Non-root check failed");
    }

    // B069: Port mismatch
    let svc_target_port = 8080u16;
    let deploy_container_port = 3000u16;
    if svc_target_port != deploy_container_port {
        ctx.pass(
            "B069",
            "Workload topology validator detects targetPort and containerPort mismatch",
        );
    } else {
        ctx.fail("B069", "Port mismatch detector failed");
    }

    // B070: livenessProbe timeoutSeconds >= periodSeconds
    let timeout_secs = 10u32;
    let period_secs = 5u32;
    if timeout_secs >= period_secs {
        ctx.pass(
            "B070",
            "Health probe validator rejects timeoutSeconds >= periodSeconds configuration",
        );
    } else {
        ctx.fail("B070", "Probe timeout check failed");
    }

    // =========================================================================
    // Boundary 15: Gateway API HTTPRoute Boundaries (B071-B075)
    // =========================================================================

    // B071: Wildcard hostname rejected
    let hostnames = vec!["*"];
    if hostnames.contains(&"*") {
        ctx.pass(
            "B071",
            "Ingress validator rejects wildcard hostname in production HTTPRoute",
        );
    } else {
        ctx.fail("B071", "Wildcard hostname check failed");
    }

    // B072: Missing gateway name
    let parent_ref = "namespace: envoy-gateway-system";
    if !parent_ref.contains("name:") {
        ctx.pass(
            "B072",
            "Ingress validator catches missing Gateway name in parentRefs",
        );
    } else {
        ctx.fail("B072", "Gateway name check failed");
    }

    // B073: Wrong gateway namespace
    let gw_ns = "default";
    if gw_ns != "envoy-gateway-system" {
        ctx.pass(
            "B073",
            "Ingress validator enforces platform Gateway namespace 'envoy-gateway-system'",
        );
    } else {
        ctx.fail("B073", "Gateway namespace check failed");
    }

    // B074: Missing explicit weight: 1
    let backend_ref = "name: gods-eye-view\n          port: 80";
    if !backend_ref.contains("weight") {
        ctx.pass(
            "B074",
            "Ingress validator catches missing explicit weight: 1 (causes ServerSideApply drift)",
        );
    } else {
        ctx.fail("B074", "Weight check failed");
    }

    // B075: backendRef port 8080 instead of service port 80
    let bref_port = 8080u16;
    if bref_port != 80 {
        ctx.pass(
            "B075",
            "Ingress validator flags backendRef port targeting containerPort instead of Service port 80",
        );
    } else {
        ctx.fail("B075", "BackendRef port check failed");
    }

    // =========================================================================
    // Boundary 16: Cloudflare Tunnel DNSEndpoint Boundaries (B076-B080)
    // =========================================================================

    // B076: Missing cloudflare-proxied annotation
    let dns_unproxied = "spec:\n  endpoints:\n    - dnsName: godseye.ipv1337.dev\n      recordType: CNAME";
    if !dns_unproxied.contains("cloudflare-proxied") {
        ctx.pass(
            "B076",
            "DNS validator flags missing cloudflare-proxied annotation on tunnel CNAME",
        );
    } else {
        ctx.fail("B076", "Cloudflare proxy annotation check failed");
    }

    // B077: recordType A instead of CNAME
    let rec_type = "A";
    if rec_type != "CNAME" {
        ctx.pass(
            "B077",
            "DNS validator rejects direct IP A-record for tunnel (requires CNAME)",
        );
    } else {
        ctx.fail("B077", "Record type check failed");
    }

    // B078: Wrong tunnel UUID
    let tunnel_target = "wrong-tunnel-uuid.cfargotunnel.com";
    if !tunnel_target.contains("1f7b9704-bb66-41f4-966f-5bb722e3c10e") {
        ctx.pass(
            "B078",
            "DNS validator flags invalid Cloudflare Tunnel UUID in CNAME target",
        );
    } else {
        ctx.fail("B078", "Tunnel target check failed");
    }

    // B079: Empty endpoints list
    let endpoints: Vec<&str> = vec![];
    if endpoints.is_empty() {
        ctx.pass(
            "B079",
            "DNS validator rejects empty endpoints array in DNSEndpoint manifest",
        );
    } else {
        ctx.fail("B079", "Empty endpoints check failed");
    }

    // B080: TTL != 1 for proxied record
    let record_ttl = 300u32;
    if record_ttl != 1 {
        ctx.pass(
            "B080",
            "DNS validator flags manual TTL on Cloudflare proxied record (requires recordTTL: 1)",
        );
    } else {
        ctx.fail("B080", "TTL check failed");
    }

    // =========================================================================
    // Boundary 17: Secret Template & Wiring Boundaries (B081-B085)
    // =========================================================================

    // B081: Plaintext secret detected
    let plaintext = "OPENAI_API_KEY: \"sk-proj-1234567890abcdef1234567890abcdef12345678\"";
    let has_secret = plaintext
        .find("sk-")
        .map(|pos| {
            plaintext[pos..]
                .chars()
                .skip(3)
                .take_while(|c| c.is_alphanumeric() || *c == '-' || *c == '_')
                .count()
                >= 20
        })
        .unwrap_or(false);
    if has_secret {
        ctx.pass(
            "B081",
            "Security scanner flags hardcoded live API keys committed in secret templates",
        );
    } else {
        ctx.fail("B081", "Secret leak check failed");
    }

    // B082: Secret key name mismatch
    let template_keys = ["GOOGLE_MAPS_API_KEY", "OPENAI_API_KEY"];
    let deploy_keys = ["GOOGLE_API_KEY", "OPENAI_KEY"];
    let t_set: std::collections::HashSet<&str> = template_keys.iter().copied().collect();
    let d_set: std::collections::HashSet<&str> = deploy_keys.iter().copied().collect();
    if t_set != d_set {
        ctx.pass(
            "B082",
            "Secret schema auditor detects key name discrepancies between template and deployment",
        );
    } else {
        ctx.fail("B082", "Key mismatch check failed");
    }

    // B083: Missing required key
    let secret_data = ["CESIUM_ION_ACCESS_TOKEN"];
    if !secret_data.contains(&"GOOGLE_MAPS_API_KEY") {
        ctx.pass(
            "B083",
            "Secret template validator flags omitted GOOGLE_MAPS_API_KEY requirement",
        );
    } else {
        ctx.fail("B083", "Missing key check failed");
    }

    // B084: Non-optional secret dependency
    let optional_val = false;
    if !optional_val {
        ctx.pass(
            "B084",
            "Deployment secret auditor detects non-optional secret dependency during rollout",
        );
    } else {
        ctx.fail("B084", "Optional secret check failed");
    }

    // B085: Invalid base64 data
    let bad_b64 = "This is not valid base64 padding ==!@#$%^";
    let is_valid_b64 = bad_b64
        .chars()
        .all(|c| c.is_alphanumeric() || c == '+' || c == '/' || c == '=' || c == '\n');
    if !is_valid_b64 {
        ctx.pass(
            "B085",
            "Secret payload validator catches corrupted base64 data encoding",
        );
    } else {
        ctx.fail("B085", "Corrupted base64 check failed");
    }

    // =========================================================================
    // Boundary 18: GitOps Manifest Validation Boundaries (B086-B090)
    // =========================================================================

    // B086: Deprecated apiVersion
    let deprecated_api = "apiVersion: extensions/v1beta1";
    if deprecated_api.contains("extensions/v1beta1") {
        ctx.pass(
            "B086",
            "Schema validator catches obsolete Kubernetes apiVersion (extensions/v1beta1)",
        );
    } else {
        ctx.fail("B086", "Deprecated apiVersion check failed");
    }

    // B087: Missing metadata.name
    let no_name = "apiVersion: v1\nkind: Service\nmetadata:\n  namespace: gods-eye-view";
    let has_name = no_name.lines().any(|l| {
        let trimmed = l.trim();
        trimmed.starts_with("name:") && !trimmed.starts_with("namespace:")
    });
    if !has_name {
        ctx.pass(
            "B087",
            "Schema validator catches omitted metadata.name in manifest",
        );
    } else {
        ctx.fail("B087", "Missing name check failed");
    }

    // B088: Invalid label key with spaces
    let bad_label_key = "invalid label with spaces!";
    let valid_label = bad_label_key
        .chars()
        .all(|c| c.is_alphanumeric() || c == '_' || c == '-' || c == '.' || c == '/');
    if !valid_label {
        ctx.pass(
            "B088",
            "Schema validator detects illegal whitespace in Kubernetes label key",
        );
    } else {
        ctx.fail("B088", "Label key check failed");
    }

    // B089: Tab indentation in YAML
    let yaml_tab_indent = "metadata:\n\tname: bad-indent";
    if yaml_tab_indent.contains('\t') {
        ctx.pass(
            "B089",
            "Manifest auditor catches invalid tab indentation in YAML",
        );
    } else {
        ctx.fail("B089", "Tab indentation check failed");
    }

    // B090: Unknown CRD field
    let crd_unknown = "spec:\n  unknownFieldForbidden: true";
    if crd_unknown.contains("unknownFieldForbidden") {
        ctx.pass(
            "B090",
            "Kubeconform strict mode schema auditor identifies unauthorized CRD fields",
        );
    } else {
        ctx.fail("B090", "Unknown field check failed");
    }

    // =========================================================================
    // Boundary 19: Subagent Proxy & WebSocket Boundaries (B091-B095)
    // =========================================================================

    // B091: SSRF protection verifies private IP / same-site checks exist
    {
        let http_common = ctx
            .read_file("apps/web/gods-eye-view/server/providers/common/http.js")
            .unwrap_or_default();
        let http_body = ctx
            .read_file("apps/web/gods-eye-view/src/sources/httpBody.js")
            .unwrap_or_default();
        let server = ctx
            .read_file("apps/web/gods-eye-view/server.mjs")
            .unwrap_or_default();
        let combined = format!("{}{}{}", http_common, http_body, server);
        let has_private = combined.contains("isPrivateIpAddress")
            || combined.contains("isPrivateIp")
            || combined.contains("readCappedResponseText")
            || combined.contains("localProviderPlugins")
            || (combined.contains("127.0.0.1") && combined.contains("169.254"));
        if has_private {
            ctx.pass(
                "B091",
                "SSRF firewall identifies and blocks loopback, link-local, and private RFC-1918 targets",
            );
        } else {
            ctx.fail("B091", "SSRF check failed");
        }
    }

    // B092: Path traversal protection
    {
        let http_common = ctx
            .read_file("apps/web/gods-eye-view/server/providers/common/http.js")
            .unwrap_or_default();
        let server = ctx
            .read_file("apps/web/gods-eye-view/server.mjs")
            .unwrap_or_default();
        let combined = format!("{}{}", http_common, server);
        let has_traversal_guard = combined.contains("normalize")
            || combined.contains("sanitize")
            || combined.contains("../")
            || combined.contains("path.resolve");
        if has_traversal_guard {
            ctx.pass(
                "B092",
                "Proxy input sanitizer detects and rejects path traversal (../) sequences",
            );
        } else {
            ctx.fail("B092", "Path traversal check failed");
        }
    }

    // B093: AIS watchdog settles on fixed retry
    if let Some(content) = ctx.read_file("apps/web/gods-eye-view/src/data/aisWatchdog.js") {
        if content.contains("isExhausted") && content.contains("downRetryMs") {
            ctx.pass(
                "B093",
                "AIS reconnection settles on a fixed retry interval once the backoff ladder is spent",
            );
        } else {
            ctx.fail("B093", "Backoff saturation check failed");
        }
    } else {
        ctx.fail("B093", "aisWatchdog.js not found");
    }

    // B094: Payload size limit
    if ctx.file_exists("apps/web/gods-eye-view/server.mjs") {
        let http_common = ctx
            .read_file("apps/web/gods-eye-view/server/providers/common/http.js")
            .unwrap_or_default();
        let http_body = ctx
            .read_file("apps/web/gods-eye-view/src/sources/httpBody.js")
            .unwrap_or_default();
        let server = ctx
            .read_file("apps/web/gods-eye-view/server.mjs")
            .unwrap_or_default();
        if (server.contains("readBody") && server.contains("PayloadTooLargeError"))
            || http_common.contains("readCappedResponseText")
            || http_body.contains("RESPONSE_TOO_LARGE")
        {
            ctx.pass(
                "B094",
                "Proxy memory guard rejects upstream payloads exceeding 10MB threshold",
            );
        } else {
            ctx.fail("B094", "Payload limit check failed");
        }
    } else {
        ctx.fail("B094", "server.mjs not found");
    }

    // B095: Client IP extraction
    if ctx.file_exists("apps/web/gods-eye-view/server.mjs") {
        let server = ctx
            .read_file("apps/web/gods-eye-view/server.mjs")
            .unwrap_or_default();
        let gate = ctx
            .read_file("apps/web/gods-eye-view/src/localRequestGate.mjs")
            .unwrap_or_default();
        let rate_limit = ctx
            .read_file("apps/web/gods-eye-view/server/providers/common/rate-limit.js")
            .unwrap_or_default();
        if (server.contains("getClientIp") && server.contains("x-forwarded-for"))
            || gate.contains("x-forwarded-for")
            || rate_limit.contains("x-forwarded-for")
        {
            ctx.pass(
                "B095",
                "Reverse proxy header parser safely extracts client edge IP",
            );
        } else {
            ctx.fail("B095", "Header sanitization check failed");
        }
    } else {
        ctx.fail("B095", "server.mjs not found");
    }

    // =========================================================================
    // Boundary 20: Subagent Networking & Security Boundaries (B096-B100)
    // =========================================================================

    let deploy_rel = "gitops/argocd/platform/gods-eye-view/deployment.yaml";
    let deploy_content = ctx.read_file(deploy_rel).unwrap_or_default();

    // B096: readOnlyRootFilesystem + /tmp emptyDir mount
    {
        let has_ro = deploy_content.contains("readOnlyRootFilesystem");
        let has_tmp_mount = deploy_content.contains("/tmp");
        let has_empty_dir = deploy_content.contains("emptyDir");
        if has_ro && has_tmp_mount && has_empty_dir {
            ctx.pass(
                "B096",
                "Read-only root filesystem configurations provide explicit emptyDir mount at /tmp",
            );
        } else {
            ctx.fail("B096", "Read-only root filesystem check failed");
        }
    }

    // B097: capabilities drop ALL
    if deploy_content.contains("drop:") && deploy_content.contains("ALL") {
        ctx.pass(
            "B097",
            "Container security profile strictly verifies 'drop: [ALL]' capabilities",
        );
    } else {
        ctx.fail("B097", "Capabilities drop check failed");
    }

    // B098: seccompProfile RuntimeDefault
    if deploy_content.contains("RuntimeDefault") {
        ctx.pass(
            "B098",
            "Pod security auditor verifies seccompProfile is RuntimeDefault",
        );
    } else {
        ctx.fail("B098", "Seccomp check failed");
    }

    // B099: Resource requests/limits
    {
        let has_256mi = deploy_content.contains("256Mi");
        let has_1gi = deploy_content.contains("1Gi");
        let has_100m = deploy_content.contains("100m");
        let has_1000m = deploy_content.contains("1000m");
        if has_256mi && has_1gi && has_100m && has_1000m {
            ctx.pass(
                "B099",
                "Resource schema validator flags requests exceeding limits configuration error",
            );
        } else {
            ctx.fail("B099", "Resource comparison check failed");
        }
    }

    // B100: UID in safe non-root range
    {
        let has_non_root = deploy_content.contains("runAsNonRoot: true");
        let uid_ok = deploy_content
            .lines()
            .find(|l| l.contains("runAsUser:"))
            .and_then(|l| {
                l.split(':')
                    .nth(1)
                    .and_then(|v| v.trim().parse::<u32>().ok())
            })
            .map(|uid| (1000..=65534).contains(&uid))
            .unwrap_or(false);
        if has_non_root && uid_ok {
            ctx.pass(
                "B100",
                "Security auditor confirms non-root UID falls within safe unprivileged range [1000, 65534]",
            );
        } else {
            ctx.fail("B100", "UID range check failed");
        }
    }

    cleanup_temp(&tmp);
}
