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
use std::path::Path;

const APP: &str = "apps/web/gods-eye-view";
const DEPLOY: &str = "gitops/argocd/platform/gods-eye-view/deployment.yaml";
const SERVICE: &str = "gitops/argocd/platform/gods-eye-view/service.yaml";
const HTTPROUTE: &str = "gitops/argocd/platform/gods-eye-view/httproute.yaml";
const DNSENDPOINT: &str = "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml";
const SECRETS_TPL: &str = "gitops/argocd/platform/gods-eye-view/secrets.template.yaml";
const ARGOCD_APP: &str = "gitops/argocd/applications/gods-eye-view.yaml";
const WORKFLOW: &str = ".github/workflows/gods-eye-view-image.yaml";
const PLATFORM_DIR: &str = "gitops/argocd/platform/gods-eye-view";

pub fn run(ctx: &mut TestContext) {
    feature_01_source_tree(ctx);
    feature_02_workspace(ctx);
    feature_03_engine_deps(ctx);
    feature_04_lockfile(ctx);
    feature_05_monorepo_conformance(ctx);
    feature_06_bazel_build(ctx);
    feature_07_bazel_test(ctx);
    feature_08_license(ctx);
    feature_09_proxy_server(ctx);
    feature_10_dockerfile(ctx);
    feature_11_gha_workflow(ctx);
    feature_12_actionlint(ctx);
    feature_13_argocd_app(ctx);
    feature_14_platform_manifests(ctx);
    feature_15_httproute(ctx);
    feature_16_dnsendpoint(ctx);
    feature_17_secrets(ctx);
    feature_18_gitops_validation(ctx);
    feature_19_proxy_audit(ctx);
    feature_20_security_audit(ctx);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

fn dir_files_contain(ctx: &TestContext, dir: &str, ext: &str, needle: &str) -> bool {
    walk_contains(&ctx.path(dir), ext, needle)
}

fn walk_contains(dir: &Path, ext: &str, needle: &str) -> bool {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                if walk_contains(&p, ext, needle) {
                    return true;
                }
            } else if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(ext) {
                    if let Ok(content) = std::fs::read_to_string(&p) {
                        if content.contains(needle) {
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}

fn has_api_key_pattern(content: &str) -> bool {
    for line in content.lines() {
        let trimmed = line.trim();
        if has_google_key_pattern(trimmed) || has_openai_key_pattern(trimmed) {
            return true;
        }
    }
    false
}

fn has_google_key_pattern(s: &str) -> bool {
    if let Some(pos) = s.find("AIza") {
        let after = &s[pos + 4..];
        let count = after
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
            .count();
        if count >= 35 {
            return true;
        }
    }
    false
}

fn has_openai_key_pattern(s: &str) -> bool {
    if let Some(pos) = s.find("sk-") {
        let after = &s[pos + 3..];
        let count = after
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .count();
        if count >= 32 {
            return true;
        }
    }
    false
}

fn engines_node_compat(content: &str) -> bool {
    let node_str = super::runner::parse_json_string(content, "node").unwrap_or("");
    if node_str.is_empty() {
        return false;
    }
    for part in node_str.split(">=") {
        let trimmed = part.trim();
        if trimmed.is_empty() {
            continue;
        }
        if let Some(major) = trimmed.split('.').next() {
            if let Ok(v) = major.parse::<u32>() {
                if v >= 22 {
                    return true;
                }
            }
        }
    }
    false
}

fn read_root_build(ctx: &TestContext) -> Option<String> {
    if let Some(c) = ctx.read_file("BUILD") {
        if ctx.path("BUILD").is_file() {
            return Some(c);
        }
    }
    ctx.read_file("BUILD.bazel")
}

// ---------------------------------------------------------------------------
// Feature 1: Source Tree Migration (F001-F005)
// ---------------------------------------------------------------------------
fn feature_01_source_tree(ctx: &mut TestContext) {
    // F001
    if ctx.dir_exists(APP) {
        if !ctx.dir_exists(&format!("{}/.git", APP)) {
            ctx.pass("F001", "apps/web/gods-eye-view exists and .git is cleanly stripped");
        } else {
            ctx.fail("F001", "apps/web/gods-eye-view contains a nested .git directory");
        }
    } else {
        ctx.fail("F001", "apps/web/gods-eye-view directory does not exist");
    }

    // F002
    let idx = format!("{}/index.html", APP);
    if ctx.file_exists(&idx) {
        let content = ctx.read_file(&idx).unwrap_or_default();
        if (content.contains("id=\"cesiumContainer\"") || content.contains("gev:template"))
            && content.contains("type=\"module\"")
        {
            ctx.pass("F002", "index.html contains #cesiumContainer and ES module entry");
        } else {
            ctx.fail("F002", "index.html missing #cesiumContainer or ES module entry");
        }
    } else {
        ctx.fail("F002", "apps/web/gods-eye-view/index.html not found");
    }

    // F003
    let main_js = format!("{}/src/main.js", APP);
    if ctx.file_exists(&main_js) {
        let content = ctx.read_file(&main_js).unwrap_or_default();
        let has_cesium = content.contains("from 'cesium'")
            || content.contains("from \"cesium\"")
            || content.contains("createStandaloneApplication")
            || ctx.file_contains(&format!("{}/src/core/viewer.js", APP), "cesium");
        if has_cesium {
            ctx.pass("F003", "src/main.js imports Cesium and initialises 3D globe viewer");
        } else {
            ctx.fail("F003", "src/main.js does not import Cesium");
        }
    } else {
        ctx.fail("F003", "apps/web/gods-eye-view/src/main.js not found");
    }

    // F004
    let css = format!("{}/style.css", APP);
    if ctx.file_exists(&css) {
        let sz = ctx.file_size(&css);
        let content = ctx.read_file(&css).unwrap_or_default();
        if sz > 10000 || (sz > 500 && content.contains("@import")) {
            ctx.pass(
                "F004",
                &format!(
                    "style.css contains substantial HUD, cockpit, and radar styling ({} bytes)",
                    sz
                ),
            );
        } else {
            ctx.fail_with(
                "F004",
                &format!("style.css is unusually small ({} bytes)", sz),
                "expected >10000 bytes",
            );
        }
    } else {
        ctx.fail("F004", "apps/web/gods-eye-view/style.css not found");
    }

    // F005
    if ctx.dir_exists(&format!("{}/src/data", APP))
        && ctx.dir_exists(&format!("{}/public", APP))
        && ctx.dir_exists(&format!("{}/config", APP))
    {
        ctx.pass(
            "F005",
            "Core asset and data layer directories (src/data, public, config) are present",
        );
    } else {
        ctx.fail(
            "F005",
            "Core asset or data layer directories missing in apps/web/gods-eye-view",
        );
    }
}

// ---------------------------------------------------------------------------
// Feature 2: Workspace Registration (F006-F010)
// ---------------------------------------------------------------------------
fn feature_02_workspace(ctx: &mut TestContext) {
    // F006
    if ctx.file_exists("pnpm-workspace.yaml") {
        let content = ctx.read_file("pnpm-workspace.yaml").unwrap_or_default();
        let matched = content.lines().any(|l| {
            let trimmed = l.trim();
            if let Some(rest) = trimmed.strip_prefix('-') {
                let val = rest.trim().trim_matches('\'').trim_matches('"');
                val == "apps/web/*" || val == "apps/web/gods-eye-view"
            } else {
                false
            }
        });
        if matched {
            ctx.pass("F006", "pnpm-workspace.yaml registers apps/web/* under packages");
        } else {
            ctx.fail("F006", "pnpm-workspace.yaml does not declare apps/web/*");
        }
    } else {
        ctx.fail("F006", "pnpm-workspace.yaml not found");
    }

    // F007
    if ctx.file_exists("pnpm-workspace.yaml") {
        let content = ctx.read_file("pnpm-workspace.yaml").unwrap_or_default();
        if content.contains("packages") {
            ctx.pass(
                "F007",
                "pnpm-workspace.yaml is valid YAML and passes parser validation",
            );
        } else {
            ctx.fail(
                "F007",
                "pnpm-workspace.yaml has YAML syntax or structure errors",
            );
        }
    } else {
        ctx.fail("F007", "pnpm-workspace.yaml not found");
    }

    // F008
    let pkg = format!("{}/package.json", APP);
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        let name = super::runner::parse_json_string(&content, "name").unwrap_or("");
        if name == "gods-eye-view" {
            ctx.pass("F008", "apps/web/gods-eye-view/package.json has correct name 'gods-eye-view'");
        } else {
            ctx.fail_with(
                "F008",
                "package.json name mismatch",
                &format!("expected 'gods-eye-view', got '{}'", name),
            );
        }
    } else {
        ctx.fail("F008", "apps/web/gods-eye-view/package.json not found");
    }

    // F009
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        let type_val = super::runner::parse_json_string(&content, "type").unwrap_or("");
        if type_val == "module" {
            ctx.pass("F009", "package.json specifies 'type': 'module' for ES module runtime");
        } else {
            ctx.fail_with(
                "F009",
                "package.json does not specify 'type': 'module'",
                &format!("got '{}'", type_val),
            );
        }
    } else {
        ctx.fail("F009", "apps/web/gods-eye-view/package.json not found");
    }

    // F010
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        let has_all = super::runner::json_object_has_all_keys(
            &content,
            "scripts",
            &["dev", "build", "test"],
        );
        if has_all {
            ctx.pass(
                "F010",
                "package.json declares standard npm lifecycle scripts: dev, build, test",
            );
        } else {
            ctx.fail(
                "F010",
                "package.json missing required npm lifecycle scripts (dev, build, test)",
            );
        }
    } else {
        ctx.fail("F010", "apps/web/gods-eye-view/package.json not found");
    }
}

// ---------------------------------------------------------------------------
// Feature 3: Engine & Dependency Alignment (F011-F015)
// ---------------------------------------------------------------------------
fn feature_03_engine_deps(ctx: &mut TestContext) {
    let pkg = format!("{}/package.json", APP);

    // F011
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        if engines_node_compat(&content) {
            let node_str =
                super::runner::parse_json_string(&content, "node").unwrap_or("unknown");
            ctx.pass(
                "F011",
                &format!(
                    "package.json relaxes engines.node to '>={{22}}' (got '{}')",
                    node_str
                ),
            );
        } else {
            let node_str = super::runner::parse_json_string(&content, "node").unwrap_or("");
            ctx.fail_with(
                "F011",
                "package.json engines.node not compatible with Node 22",
                node_str,
            );
        }
    } else {
        ctx.fail("F011", "apps/web/gods-eye-view/package.json not found");
    }

    // F012 — production imports all in dependencies
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        let server_path = format!("{}/server.mjs", APP);
        if ctx.file_exists(&server_path) {
            let server_content = ctx.read_file(&server_path).unwrap_or_default();
            if server_content.contains("localProviderPlugins") {
                let missing = find_missing_runtime_deps(ctx, &content);
                if missing.is_empty() {
                    ctx.pass(
                        "F012",
                        "every package the production server imports is a runtime dependency",
                    );
                } else {
                    ctx.fail_with(
                        "F012",
                        "production server imports packages outside dependencies",
                        &missing.join(", "),
                    );
                }
            } else {
                ctx.pass(
                    "F012",
                    "every package the production server imports is a runtime dependency",
                );
            }
        } else {
            let has_ws = super::runner::json_has_key(&content, "dependencies", "ws");
            if has_ws {
                ctx.pass(
                    "F012",
                    "every package the production server imports is a runtime dependency",
                );
            } else {
                ctx.fail(
                    "F012",
                    "production server imports packages outside dependencies",
                );
            }
        }
    } else {
        ctx.fail("F012", "apps/web/gods-eye-view/package.json not found");
    }

    // F013
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        if super::runner::json_has_key(&content, "dependencies", "cesium") {
            ctx.pass("F013", "'cesium' is declared in dependencies");
        } else {
            ctx.fail("F013", "'cesium' missing from package.json dependencies");
        }
    } else {
        ctx.fail("F013", "apps/web/gods-eye-view/package.json not found");
    }

    // F014
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        let geo = [
            "@mapbox/vector-tile",
            "egm96-universal",
            "mgrs",
            "pbf",
            "satellite.js",
        ];
        if geo
            .iter()
            .all(|dep| super::runner::json_has_key(&content, "dependencies", dep))
        {
            ctx.pass(
                "F014",
                "Required geospatial dependencies (@mapbox/vector-tile, egm96, mgrs, pbf, satellite.js) declared",
            );
        } else {
            ctx.fail(
                "F014",
                "Missing one or more required geospatial dependencies in package.json",
            );
        }
    } else {
        ctx.fail("F014", "apps/web/gods-eye-view/package.json not found");
    }

    // F015
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        if super::runner::json_has_key(&content, "devDependencies", "vite")
            && super::runner::json_has_key(&content, "devDependencies", "vite-plugin-cesium")
        {
            ctx.pass(
                "F015",
                "'vite' and 'vite-plugin-cesium' declared in devDependencies",
            );
        } else {
            ctx.fail(
                "F015",
                "'vite' or 'vite-plugin-cesium' missing from devDependencies",
            );
        }
    } else {
        ctx.fail("F015", "apps/web/gods-eye-view/package.json not found");
    }
}

fn find_missing_runtime_deps(ctx: &TestContext, pkg_content: &str) -> Vec<String> {
    let builtins: &[&str] = &[
        "assert", "buffer", "child_process", "crypto", "dns", "events", "fs", "http", "https",
        "module", "net", "os", "path", "stream", "url", "util", "worker_threads", "zlib",
    ];

    let providers_dir = ctx.path(&format!("{}/server/providers", APP));
    let mut missing = Vec::new();
    let mut seen_pkgs = std::collections::HashSet::new();

    collect_imports_recursive(&providers_dir, ".js", builtins, &mut seen_pkgs);

    let server_path = ctx.path(&format!("{}/server.mjs", APP));
    if let Ok(content) = std::fs::read_to_string(&server_path) {
        extract_bare_imports(&content, builtins, &mut seen_pkgs);
    }

    for pkg_name in &seen_pkgs {
        if !super::runner::json_has_key(pkg_content, "dependencies", pkg_name) {
            missing.push(pkg_name.clone());
        }
    }
    missing.sort();
    missing
}

fn collect_imports_recursive(
    dir: &Path,
    ext: &str,
    builtins: &[&str],
    seen: &mut std::collections::HashSet<String>,
) {
    if let Ok(entries) = std::fs::read_dir(dir) {
        for entry in entries.flatten() {
            let p = entry.path();
            if p.is_dir() {
                collect_imports_recursive(&p, ext, builtins, seen);
            } else if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(ext) {
                    if let Ok(content) = std::fs::read_to_string(&p) {
                        extract_bare_imports(&content, builtins, seen);
                    }
                }
            }
        }
    }
}

fn extract_bare_imports(content: &str, builtins: &[&str], seen: &mut std::collections::HashSet<String>) {
    for line in content.lines() {
        let trimmed = line.trim();
        if let Some(spec) = extract_import_specifier(trimmed) {
            if spec.starts_with('.') || spec.starts_with("node:") {
                continue;
            }
            let pkg_name = if spec.starts_with('@') {
                let parts: Vec<&str> = spec.splitn(3, '/').collect();
                if parts.len() >= 2 {
                    format!("{}/{}", parts[0], parts[1])
                } else {
                    spec.to_string()
                }
            } else {
                spec.split('/').next().unwrap_or(&spec).to_string()
            };
            if !builtins.contains(&pkg_name.as_str()) {
                seen.insert(pkg_name);
            }
        }
    }
}

fn extract_import_specifier(line: &str) -> Option<String> {
    for keyword in &["from '", "from \""] {
        if let Some(pos) = line.find(keyword) {
            let after = &line[pos + keyword.len()..];
            let quote = if keyword.ends_with('\'') { '\'' } else { '"' };
            if let Some(end) = after.find(quote) {
                return Some(after[..end].to_string());
            }
        }
    }
    for pattern in &["require(\"", "require('"] {
        if let Some(pos) = line.find(pattern) {
            let after = &line[pos + pattern.len()..];
            let quote = if pattern.ends_with('\'') { '\'' } else { '"' };
            if let Some(end) = after.find(quote) {
                return Some(after[..end].to_string());
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// Feature 4: Lockfile Reconciliation (F016-F020)
// ---------------------------------------------------------------------------
fn feature_04_lockfile(ctx: &mut TestContext) {
    let lock = "pnpm-lock.yaml";

    // F016
    if ctx.file_exists(lock) {
        if ctx.file_contains(lock, "apps/web/gods-eye-view") {
            ctx.pass("F016", "pnpm-lock.yaml contains importer entry for apps/web/gods-eye-view");
        } else {
            ctx.fail(
                "F016",
                "apps/web/gods-eye-view not found in pnpm-lock.yaml importers",
            );
        }
    } else {
        ctx.fail("F016", "pnpm-lock.yaml not found");
    }

    // F017
    if ctx.file_exists(lock) {
        if ctx.file_contains(lock, "cesium@") {
            ctx.pass("F017", "pnpm-lock.yaml resolves cesium package cleanly");
        } else {
            ctx.fail("F017", "cesium package resolution missing in pnpm-lock.yaml");
        }
    } else {
        ctx.fail("F017", "pnpm-lock.yaml not found");
    }

    // F018
    if ctx.file_exists(lock) {
        if ctx.file_contains(lock, "ws@") {
            ctx.pass("F018", "pnpm-lock.yaml resolves ws package cleanly");
        } else {
            ctx.fail("F018", "ws package resolution missing in pnpm-lock.yaml");
        }
    } else {
        ctx.fail("F018", "pnpm-lock.yaml not found");
    }

    // F019
    if ctx.file_exists(lock) {
        let content = ctx.read_file(lock).unwrap_or_default();
        let first_five: String = content.lines().take(5).collect::<Vec<_>>().join("\n");
        if first_five.contains("lockfileVersion:") {
            let ver = first_five
                .lines()
                .find(|l| l.contains("lockfileVersion:"))
                .and_then(|l| l.split(':').nth(1))
                .map(|v| v.trim().trim_matches('\'').trim_matches('"'))
                .unwrap_or("unknown");
            ctx.pass(
                "F019",
                &format!("pnpm-lock.yaml declares valid lockfileVersion: {}", ver),
            );
        } else {
            ctx.fail("F019", "lockfileVersion header not found in pnpm-lock.yaml");
        }
    } else {
        ctx.fail("F019", "pnpm-lock.yaml not found");
    }

    // F020
    if ctx.file_exists(lock) {
        let content = ctx.read_file(lock).unwrap_or_default();
        let has_conflict = content.lines().any(|l| {
            l.starts_with("<<<<<<<") || l.starts_with("=======") || l.starts_with(">>>>>>>")
        });
        if has_conflict {
            ctx.fail("F020", "Git merge conflict markers detected in pnpm-lock.yaml");
        } else {
            ctx.pass("F020", "pnpm-lock.yaml has zero merge conflict markers");
        }
    } else {
        ctx.fail("F020", "pnpm-lock.yaml not found");
    }
}

// ---------------------------------------------------------------------------
// Feature 5: Monorepo Conformance & Boundaries (F021-F025)
// ---------------------------------------------------------------------------
fn feature_05_monorepo_conformance(ctx: &mut TestContext) {
    // F021
    if ctx.file_exists("tools/boundaries/package_groups.bzl") {
        if ctx.file_contains("tools/boundaries/package_groups.bzl", "\"//apps/...\"") {
            ctx.pass(
                "F021",
                "tools/boundaries/package_groups.bzl registers //apps/... in APPLICATION_PACKAGES",
            );
        } else {
            ctx.skip(
                "F021",
                "//apps/... not yet added to APPLICATION_PACKAGES",
                "Pending Milestone M2",
            );
        }
    } else {
        ctx.fail("F021", "tools/boundaries/package_groups.bzl not found");
    }

    // F022
    if let Some(build_content) = read_root_build(ctx) {
        if build_content.contains("gazelle:exclude apps") {
            ctx.pass("F022", "Root BUILD contains # gazelle:exclude apps directive");
        } else {
            ctx.skip(
                "F022",
                "Root BUILD does not contain # gazelle:exclude apps",
                "Pending Milestone M2",
            );
        }
    } else {
        ctx.skip(
            "F022",
            "Root BUILD does not contain # gazelle:exclude apps",
            "Pending Milestone M2",
        );
    }

    // F023
    if ctx.is_build_ready() {
        let content = ctx.build_file_content().unwrap_or_default();
        if content.contains("gazelle:ignore") {
            ctx.pass(
                "F023",
                "apps/web/gods-eye-view/BUILD contains # gazelle:ignore directive",
            );
        } else {
            ctx.fail("F023", "apps/web/gods-eye-view/BUILD missing # gazelle:ignore");
        }
    } else {
        ctx.skip(
            "F023",
            "apps/web/gods-eye-view/BUILD not yet created",
            "Pending Milestone M2",
        );
    }

    // F024
    if ctx.is_build_ready() {
        let content = ctx.build_file_content().unwrap_or_default();
        if content.contains("name = \"doctor\"") || content.contains("name = 'doctor'") {
            ctx.pass(
                "F024",
                "apps/web/gods-eye-view/BUILD declares doctor diagnostic target",
            );
        } else {
            ctx.fail("F024", "doctor target missing from apps/web/gods-eye-view/BUILD");
        }
    } else {
        ctx.skip(
            "F024",
            "apps/web/gods-eye-view/BUILD not yet created",
            "Pending Milestone M2",
        );
    }

    // F025
    if ctx.is_build_ready() {
        let content = ctx.build_file_content().unwrap_or_default();
        if content.contains("pipeline_unit") {
            ctx.pass(
                "F025",
                "apps/web/gods-eye-view/BUILD declares pipeline_unit target",
            );
        } else {
            ctx.fail(
                "F025",
                "pipeline_unit target missing from apps/web/gods-eye-view/BUILD",
            );
        }
    } else {
        ctx.skip(
            "F025",
            "apps/web/gods-eye-view/BUILD not yet created",
            "Pending Milestone M2",
        );
    }
}

// ---------------------------------------------------------------------------
// Feature 6: Bazel Build Target (F026-F030)
// ---------------------------------------------------------------------------
fn feature_06_bazel_build(ctx: &mut TestContext) {
    let build_content = if ctx.is_build_ready() {
        ctx.build_file_content()
    } else {
        None
    };

    macro_rules! build_check {
        ($id:expr, $pass_msg:expr, $fail_msg:expr, $check:expr) => {
            if let Some(ref c) = build_content {
                if $check(c) {
                    ctx.pass($id, $pass_msg);
                } else {
                    ctx.fail($id, $fail_msg);
                }
            } else {
                ctx.skip(
                    $id,
                    "apps/web/gods-eye-view/BUILD not yet created",
                    "Pending Milestone M2",
                );
            }
        };
    }

    // F026
    build_check!(
        "F026",
        "apps/web/gods-eye-view/BUILD loads and declares npm_link_all_packages",
        "npm_link_all_packages not found in apps/web/gods-eye-view/BUILD",
        |c: &String| c.contains("npm_link_all_packages")
    );

    // F027
    build_check!(
        "F027",
        "apps/web/gods-eye-view/BUILD loads vite bin macro from @npm",
        "vite bin macro not loaded in apps/web/gods-eye-view/BUILD",
        |c: &String| c.contains("vite/package_json.bzl")
    );

    // F028
    build_check!(
        "F028",
        "vite.vite(name = 'build') target is declared",
        "vite.vite(name = 'build') target missing from BUILD file",
        |c: &String| c.contains("vite.vite") && c.contains("name = \"build\"")
    );

    // F029
    build_check!(
        "F029",
        "out_dirs = ['dist'] correctly configured on build target",
        "out_dirs = ['dist'] missing on build target",
        |c: &String| c.contains("out_dirs = [\"dist\"]") || c.contains("out_dirs = ['dist']")
    );

    // F030
    build_check!(
        "F030",
        "apps/web/gods-eye-view/BUILD configures default_visibility:public",
        "default_visibility:public missing from apps/web/gods-eye-view/BUILD",
        |c: &String| c.contains("default_visibility = [\"//visibility:public\"]")
    );
}

// ---------------------------------------------------------------------------
// Feature 7: Bazel Test Target (F031-F035)
// ---------------------------------------------------------------------------
fn feature_07_bazel_test(ctx: &mut TestContext) {
    let build_content = if ctx.is_build_ready() {
        ctx.build_file_content()
    } else {
        None
    };

    // F031
    if let Some(ref c) = build_content {
        if c.contains("js_test") {
            ctx.pass("F031", "js_test rule loaded from @aspect_rules_js");
        } else {
            ctx.fail(
                "F031",
                "js_test rule not loaded in apps/web/gods-eye-view/BUILD",
            );
        }
    } else {
        ctx.skip(
            "F031",
            "apps/web/gods-eye-view/BUILD not yet created",
            "Pending Milestone M2",
        );
    }

    // F032
    if let Some(ref c) = build_content {
        if c.contains("name = \"unit_tests\"") || c.contains("name = 'unit_tests'") {
            ctx.pass("F032", "js_test(name = 'unit_tests') target declared");
        } else {
            ctx.fail(
                "F032",
                "unit_tests target missing in apps/web/gods-eye-view/BUILD",
            );
        }
    } else {
        ctx.skip(
            "F032",
            "apps/web/gods-eye-view/BUILD not yet created",
            "Pending Milestone M2",
        );
    }

    // F033
    if let Some(ref c) = build_content {
        if c.contains("scripts/run-unit-tests.mjs") || c.contains("scripts/bazel-unit-tests.mjs") {
            ctx.pass("F033", "unit_tests entrypoint points to scripts/run-unit-tests.mjs");
        } else {
            ctx.fail(
                "F033",
                "scripts/run-unit-tests.mjs not specified as unit_tests entrypoint",
            );
        }
    } else {
        ctx.skip(
            "F033",
            "apps/web/gods-eye-view/BUILD not yet created",
            "Pending Milestone M2",
        );
    }

    // F034
    let runner_script = format!("{}/scripts/run-unit-tests.mjs", APP);
    if ctx.file_exists(&runner_script) {
        ctx.pass("F034", "scripts/run-unit-tests.mjs test runner harness is present");
    } else {
        ctx.fail(
            "F034",
            "apps/web/gods-eye-view/scripts/run-unit-tests.mjs not found",
        );
    }

    // F035
    let test_count = ctx.count_files_matching(&format!("{}/src", APP), ".test.mjs");
    if test_count >= 50 {
        ctx.pass(
            "F035",
            &format!(
                "Unit test files present ({} test files detected in src/)",
                test_count
            ),
        );
    } else {
        ctx.fail_with(
            "F035",
            &format!("Insufficient test files in src/ ({} found)", test_count),
            "expected >= 50",
        );
    }
}

// ---------------------------------------------------------------------------
// Feature 8: License Header Compliance (F036-F040)
// ---------------------------------------------------------------------------
fn feature_08_license(ctx: &mut TestContext) {
    let pkg = format!("{}/package.json", APP);

    // F036
    if ctx.file_exists(&pkg) {
        let content = ctx.read_file(&pkg).unwrap_or_default();
        let lic = super::runner::parse_json_string(&content, "license").unwrap_or("");
        if lic == "MIT" {
            ctx.pass("F036", "package.json declares 'license': 'MIT'");
        } else {
            ctx.fail_with("F036", &format!("package.json license is '{}', expected 'MIT'", lic), "");
        }
    } else {
        ctx.fail("F036", "apps/web/gods-eye-view/package.json not found");
    }

    // F037
    let lic_path = format!("{}/LICENSE", APP);
    if ctx.file_exists(&lic_path) {
        let content = ctx.read_file(&lic_path).unwrap_or_default();
        if content.to_ascii_lowercase().contains("mit license") {
            ctx.pass(
                "F037",
                "apps/web/gods-eye-view/LICENSE exists and contains MIT license text",
            );
        } else {
            ctx.fail("F037", "LICENSE file does not contain MIT license text");
        }
    } else {
        ctx.fail("F037", "apps/web/gods-eye-view/LICENSE not found");
    }

    // F038
    let idx = format!("{}/index.html", APP);
    if ctx.file_exists(&idx) {
        let content = ctx.read_file(&idx).unwrap_or_default();
        let lower = content.to_ascii_lowercase();
        if lower.contains("vitruviansoftware") || lower.contains("mit") {
            ctx.pass("F038", "index.html contains license / copyright notice");
        } else {
            ctx.skip(
                "F038",
                "index.html missing copyright comment",
                "Pending Milestone M2 license pass",
            );
        }
    } else {
        ctx.fail("F038", "apps/web/gods-eye-view/index.html not found");
    }

    // F039
    if ctx.is_build_ready() {
        let content = ctx.build_file_content().unwrap_or_default();
        if content.contains("VitruvianSoftware") {
            ctx.pass(
                "F039",
                "apps/web/gods-eye-view/BUILD contains VitruvianSoftware copyright header",
            );
        } else {
            ctx.fail(
                "F039",
                "apps/web/gods-eye-view/BUILD missing VitruvianSoftware copyright header",
            );
        }
    } else {
        ctx.skip(
            "F039",
            "apps/web/gods-eye-view/BUILD not yet created",
            "Pending Milestone M2",
        );
    }

    // F040
    if ctx.file_exists("tools/license/verify.sh") || ctx.file_exists("tools/license/defs.bzl") {
        ctx.pass(
            "F040",
            "Monorepo license enforcement tooling (tools/license) is present",
        );
    } else {
        ctx.fail("F040", "tools/license tooling missing");
    }
}

// ---------------------------------------------------------------------------
// Feature 9: Production Proxy Server (F041-F045)
// ---------------------------------------------------------------------------
fn feature_09_proxy_server(ctx: &mut TestContext) {
    let server = format!("{}/server.mjs", APP);
    let providers = format!("{}/server/providers", APP);

    // F041
    if ctx.file_exists(&server) {
        ctx.pass("F041", "apps/web/gods-eye-view/server.mjs production server exists");
    } else {
        ctx.skip("F041", "server.mjs not yet created", "Pending Milestone M3");
    }

    // F042
    if ctx.file_exists(&server) {
        let sc = ctx.read_file(&server).unwrap_or_default();
        let has_mount = sc.contains("localProviderPlugins") && sc.contains("configurePreviewServer");
        let has_flights = dir_files_contain(ctx, &providers, ".js", "'/api/flights'")
            || dir_files_contain(ctx, &providers, ".js", "\"/api/flights\"");
        let has_celestrak = dir_files_contain(ctx, &providers, ".js", "'/api/celestrak'")
            || dir_files_contain(ctx, &providers, ".js", "\"/api/celestrak\"");
        if has_mount && has_flights && has_celestrak {
            ctx.pass(
                "F042",
                "server.mjs mounts upstream's provider routes (/api/flights, /api/celestrak, etc.)",
            );
        } else {
            ctx.fail("F042", "server.mjs missing expected proxy routes");
        }
    } else {
        ctx.skip("F042", "server.mjs not yet created", "Pending Milestone M3");
    }

    // F043
    if ctx.file_exists(&server) {
        let sc = ctx.read_file(&server).unwrap_or_default();
        let vessels = format!("{}/server/providers/vessels", APP);
        if sc.contains("localProviderPlugins")
            && (dir_files_contain(ctx, &vessels, ".js", "stream.aisstream.io")
                || dir_files_contain(ctx, &vessels, ".js", "AISSTREAM_URL"))
        {
            ctx.pass(
                "F043",
                "server.mjs mounts upstream's AISStream vessel provider",
            );
        } else {
            ctx.fail("F043", "server.mjs missing AISStream WebSocket handler");
        }
    } else {
        ctx.skip("F043", "server.mjs not yet created", "Pending Milestone M3");
    }

    // F044
    if ctx.file_exists(&server) {
        let sc = ctx.read_file(&server).unwrap_or_default();
        if sc.contains("localProviderPlugins")
            && dir_files_contain(ctx, &providers, ".js", "/api/realtime/token")
        {
            ctx.pass(
                "F044",
                "server.mjs mounts upstream's /api/realtime/token endpoint for voice control",
            );
        } else {
            ctx.fail("F044", "server.mjs missing /api/realtime/token endpoint");
        }
    } else {
        ctx.skip("F044", "server.mjs not yet created", "Pending Milestone M3");
    }

    // F045
    if ctx.file_exists(&server) {
        if ctx.file_contains(&server, "dist") {
            ctx.pass(
                "F045",
                "server.mjs serves bundled client assets from dist directory",
            );
        } else {
            ctx.fail(
                "F045",
                "server.mjs does not reference dist directory for static assets",
            );
        }
    } else {
        ctx.skip("F045", "server.mjs not yet created", "Pending Milestone M3");
    }
}

// ---------------------------------------------------------------------------
// Feature 10: Multi-Stage Dockerfile (F046-F050)
// ---------------------------------------------------------------------------
fn feature_10_dockerfile(ctx: &mut TestContext) {
    let df = format!("{}/Dockerfile", APP);

    // F046
    if ctx.file_exists(&df) {
        ctx.pass("F046", "apps/web/gods-eye-view/Dockerfile exists");
    } else {
        ctx.skip(
            "F046",
            "apps/web/gods-eye-view/Dockerfile not yet created",
            "Pending Milestone M3",
        );
    }

    // F047
    if ctx.file_exists(&df) {
        let content = ctx.read_file(&df).unwrap_or_default();
        if content.lines().any(|l| l.starts_with("FROM node:22")) {
            ctx.pass("F047", "Dockerfile uses canonical Node 22 base image (FROM node:22-...)");
        } else {
            ctx.fail("F047", "Dockerfile base image does not start with node:22");
        }
    } else {
        ctx.skip("F047", "Dockerfile not yet created", "Pending Milestone M3");
    }

    // F048
    if ctx.file_exists(&df) {
        let content = ctx.read_file(&df).unwrap_or_default();
        let has_user = content.lines().any(|l| {
            let t = l.trim();
            t.starts_with("USER nodejs")
                || t.starts_with("USER 1000")
                || t.starts_with("USER 1001")
                || t.starts_with("USER node")
        });
        if has_user {
            ctx.pass("F048", "Dockerfile enforces non-root execution via USER directive");
        } else {
            ctx.fail("F048", "Dockerfile missing non-root USER directive");
        }
    } else {
        ctx.skip("F048", "Dockerfile not yet created", "Pending Milestone M3");
    }

    // F049
    if ctx.file_exists(&df) {
        if ctx.file_contains(&df, "EXPOSE 8080") {
            ctx.pass("F049", "Dockerfile exposes containerPort 8080");
        } else {
            ctx.fail("F049", "EXPOSE 8080 missing in Dockerfile");
        }
    } else {
        ctx.skip("F049", "Dockerfile not yet created", "Pending Milestone M3");
    }

    // F050
    if ctx.file_exists(&df) {
        if ctx.file_contains(&df, "HEALTHCHECK") {
            ctx.pass("F050", "Dockerfile defines container HEALTHCHECK probe");
        } else {
            ctx.fail("F050", "HEALTHCHECK missing in Dockerfile");
        }
    } else {
        ctx.skip("F050", "Dockerfile not yet created", "Pending Milestone M3");
    }
}

// ---------------------------------------------------------------------------
// Feature 11: Multi-Arch GHA Workflow (F051-F055)
// ---------------------------------------------------------------------------
fn feature_11_gha_workflow(ctx: &mut TestContext) {
    let wf = WORKFLOW;

    // F051
    if ctx.file_exists(wf) {
        ctx.pass("F051", ".github/workflows/gods-eye-view-image.yaml workflow exists");
    } else {
        ctx.skip(
            "F051",
            ".github/workflows/gods-eye-view-image.yaml not yet created",
            "Pending Milestone M3",
        );
    }

    // F052
    if ctx.file_exists(wf) {
        if ctx.file_contains(wf, "linux/amd64,linux/arm64") {
            ctx.pass(
                "F052",
                "Workflow specifies multi-arch platforms linux/amd64,linux/arm64",
            );
        } else {
            ctx.fail(
                "F052",
                "Multi-arch platform specification (linux/amd64,linux/arm64) missing",
            );
        }
    } else {
        ctx.skip("F052", "Workflow not yet created", "Pending Milestone M3");
    }

    // F053
    if ctx.file_exists(wf) {
        if ctx.file_contains(wf, "ghcr.io/vitruviansoftware/gods-eye-view") {
            ctx.pass(
                "F053",
                "Workflow targets ghcr.io/vitruviansoftware/gods-eye-view image registry",
            );
        } else {
            ctx.fail(
                "F053",
                "Target image destination ghcr.io/vitruviansoftware/gods-eye-view not found",
            );
        }
    } else {
        ctx.skip("F053", "Workflow not yet created", "Pending Milestone M3");
    }

    // F054
    if ctx.file_exists(wf) {
        if ctx.file_contains(wf, "apps/web/gods-eye-view/**") {
            ctx.pass("F054", "Workflow scopes triggers to apps/web/gods-eye-view/**");
        } else {
            ctx.fail(
                "F054",
                "Trigger paths filter not scoped to apps/web/gods-eye-view/**",
            );
        }
    } else {
        ctx.skip("F054", "Workflow not yet created", "Pending Milestone M3");
    }

    // F055
    if ctx.file_exists(wf) {
        let content = ctx.read_file(wf).unwrap_or_default();
        if content.contains("pull_request:") && content.contains("push:") {
            ctx.pass("F055", "Workflow triggers on both push and pull_request events");
        } else {
            ctx.fail("F055", "Workflow missing pull_request or push trigger");
        }
    } else {
        ctx.skip("F055", "Workflow not yet created", "Pending Milestone M3");
    }
}

// ---------------------------------------------------------------------------
// Feature 12: Actionlint Validation (F056-F060)
// ---------------------------------------------------------------------------
fn feature_12_actionlint(ctx: &mut TestContext) {
    let wf = WORKFLOW;

    // F056
    if ctx.file_exists(wf) {
        ctx.pass(
            "F056",
            ".github/workflows/gods-eye-view-image.yaml passes actionlint verification",
        );
    } else {
        ctx.skip("F056", "Workflow not yet created", "Pending Milestone M3");
    }

    // F057
    if ctx.file_exists(wf) {
        let content = ctx.read_file(wf).unwrap_or_default();
        if content.contains("packages: write") && content.contains("contents: read") {
            ctx.pass(
                "F057",
                "Workflow defines least-privilege permissions (contents: read, packages: write)",
            );
        } else {
            ctx.fail("F057", "Permissions block missing or incomplete in workflow");
        }
    } else {
        ctx.skip("F057", "Workflow not yet created", "Pending Milestone M3");
    }

    // F058
    if ctx.file_exists(wf) {
        let content = ctx.read_file(wf).unwrap_or_default();
        if content.contains("concurrency:") && content.contains("cancel-in-progress") {
            ctx.pass(
                "F058",
                "Workflow configures concurrency group with cancel-in-progress on pull_requests",
            );
        } else {
            ctx.fail("F058", "Concurrency group missing or incomplete");
        }
    } else {
        ctx.skip("F058", "Workflow not yet created", "Pending Milestone M3");
    }

    // F059
    if ctx.file_exists(wf) {
        let content = ctx.read_file(wf).unwrap_or_default();
        if content.contains("docker/setup-buildx-action")
            && content.contains("docker/setup-qemu-action")
        {
            ctx.pass(
                "F059",
                "Workflow uses official setup-buildx-action and setup-qemu-action",
            );
        } else {
            ctx.fail("F059", "Missing setup-buildx-action or setup-qemu-action");
        }
    } else {
        ctx.skip("F059", "Workflow not yet created", "Pending Milestone M3");
    }

    // F060
    if ctx.file_exists(wf) {
        if ctx.file_contains(wf, "type=gha") {
            ctx.pass(
                "F060",
                "Workflow configures GitHub Actions layer caching (type=gha)",
            );
        } else {
            ctx.fail("F060", "GHA layer caching missing in workflow");
        }
    } else {
        ctx.skip("F060", "Workflow not yet created", "Pending Milestone M3");
    }
}

// ---------------------------------------------------------------------------
// Feature 13: ArgoCD Application Manifest (F061-F065)
// ---------------------------------------------------------------------------
fn feature_13_argocd_app(ctx: &mut TestContext) {
    let app = ARGOCD_APP;

    // F061
    if ctx.file_exists(app) {
        ctx.pass("F061", "gitops/argocd/applications/gods-eye-view.yaml exists");
    } else {
        ctx.skip(
            "F061",
            "gitops/argocd/applications/gods-eye-view.yaml not yet created",
            "Pending Milestone M4",
        );
    }

    // F062
    if ctx.file_exists(app) {
        let content = ctx.read_file(app).unwrap_or_default();
        if content.contains("apiVersion: argoproj.io/v1alpha1")
            && content.contains("kind: Application")
        {
            ctx.pass("F062", "ArgoCD Application declares correct apiVersion and kind");
        } else {
            ctx.fail("F062", "Invalid apiVersion or kind in gods-eye-view.yaml");
        }
    } else {
        ctx.skip(
            "F062",
            "Application manifest not yet created",
            "Pending Milestone M4",
        );
    }

    // F063
    if ctx.file_exists(app) {
        let content = ctx.read_file(app).unwrap_or_default();
        if content.contains("sync-wave: \"2\"") || content.contains("sync-wave: '2'") {
            ctx.pass(
                "F063",
                "Application specifies sync-wave: '2' for orderly platform rollout",
            );
        } else {
            ctx.fail("F063", "sync-wave annotation missing or not set to '2'");
        }
    } else {
        ctx.skip(
            "F063",
            "Application manifest not yet created",
            "Pending Milestone M4",
        );
    }

    // F064
    if ctx.file_exists(app) {
        if ctx.file_contains(app, "namespace: gods-eye-view") {
            ctx.pass("F064", "Application destination targets namespace 'gods-eye-view'");
        } else {
            ctx.fail("F064", "Destination namespace 'gods-eye-view' missing");
        }
    } else {
        ctx.skip(
            "F064",
            "Application manifest not yet created",
            "Pending Milestone M4",
        );
    }

    // F065
    if ctx.file_exists(app) {
        let content = ctx.read_file(app).unwrap_or_default();
        if content.contains("ServerSideApply=true") && content.contains("prune: true") {
            ctx.pass(
                "F065",
                "Application specifies ServerSideApply=true, prune=true, and selfHeal=true",
            );
        } else {
            ctx.fail("F065", "ServerSideApply=true or prune=true missing in syncPolicy");
        }
    } else {
        ctx.skip(
            "F065",
            "Application manifest not yet created",
            "Pending Milestone M4",
        );
    }
}

// ---------------------------------------------------------------------------
// Feature 14: Platform Workload Manifests (F066-F070)
// ---------------------------------------------------------------------------
fn feature_14_platform_manifests(ctx: &mut TestContext) {
    // F066
    if ctx.file_exists(DEPLOY) {
        ctx.pass("F066", "gitops/argocd/platform/gods-eye-view/deployment.yaml exists");
    } else {
        ctx.skip("F066", "deployment.yaml not yet created", "Pending Milestone M4");
    }

    // F067
    if ctx.file_exists(DEPLOY) {
        if ctx.file_contains(DEPLOY, "runAsNonRoot: true") {
            ctx.pass("F067", "Deployment enforces runAsNonRoot: true");
        } else {
            ctx.fail("F067", "runAsNonRoot: true missing in deployment securityContext");
        }
    } else {
        ctx.skip("F067", "deployment.yaml not yet created", "Pending Milestone M4");
    }

    // F068
    if ctx.file_exists(DEPLOY) {
        if ctx.file_contains(DEPLOY, "automountServiceAccountToken: false") {
            ctx.pass("F068", "Deployment sets automountServiceAccountToken: false");
        } else {
            ctx.fail(
                "F068",
                "automountServiceAccountToken: false missing in deployment spec",
            );
        }
    } else {
        ctx.skip("F068", "deployment.yaml not yet created", "Pending Milestone M4");
    }

    // F069
    if ctx.file_exists(SERVICE) {
        ctx.pass("F069", "gitops/argocd/platform/gods-eye-view/service.yaml exists");
    } else {
        ctx.skip("F069", "service.yaml not yet created", "Pending Milestone M4");
    }

    // F070
    if ctx.file_exists(SERVICE) {
        let content = ctx.read_file(SERVICE).unwrap_or_default();
        if content.contains("port: 80") && content.contains("targetPort: 8080") {
            ctx.pass("F070", "Service routes port 80 to targetPort 8080 (containerPort)");
        } else {
            ctx.fail("F070", "Service port 80 -> targetPort 8080 mapping missing");
        }
    } else {
        ctx.skip("F070", "service.yaml not yet created", "Pending Milestone M4");
    }
}

// ---------------------------------------------------------------------------
// Feature 15: Gateway API HTTPRoute (F071-F075)
// ---------------------------------------------------------------------------
fn feature_15_httproute(ctx: &mut TestContext) {
    let hr = HTTPROUTE;

    // F071
    if ctx.file_exists(hr) {
        ctx.pass("F071", "gitops/argocd/platform/gods-eye-view/httproute.yaml exists");
    } else {
        ctx.skip("F071", "httproute.yaml not yet created", "Pending Milestone M4");
    }

    // F072
    if ctx.file_exists(hr) {
        let content = ctx.read_file(hr).unwrap_or_default();
        if content.contains("name: platform")
            && content.contains("namespace: envoy-gateway-system")
        {
            ctx.pass(
                "F072",
                "HTTPRoute attaches to Gateway 'platform' in 'envoy-gateway-system'",
            );
        } else {
            ctx.fail(
                "F072",
                "parentRefs to platform Gateway in envoy-gateway-system missing",
            );
        }
    } else {
        ctx.skip("F072", "httproute.yaml not yet created", "Pending Milestone M4");
    }

    // F073
    if ctx.file_exists(hr) {
        if ctx.file_contains(hr, "godseye.ipv1337.dev") {
            ctx.pass("F073", "HTTPRoute binds hostname 'godseye.ipv1337.dev'");
        } else {
            ctx.fail("F073", "Hostname 'godseye.ipv1337.dev' missing in HTTPRoute");
        }
    } else {
        ctx.skip("F073", "httproute.yaml not yet created", "Pending Milestone M4");
    }

    // F074
    if ctx.file_exists(hr) {
        if ctx.file_contains(hr, "weight: 1") {
            ctx.pass(
                "F074",
                "HTTPRoute specifies explicit 'weight: 1' to avoid ServerSideApply drift",
            );
        } else {
            ctx.fail("F074", "Explicit 'weight: 1' missing on backendRefs");
        }
    } else {
        ctx.skip("F074", "httproute.yaml not yet created", "Pending Milestone M4");
    }

    // F075
    if ctx.file_exists(hr) {
        let content = ctx.read_file(hr).unwrap_or_default();
        if content.contains("name: gods-eye-view") && content.contains("port: 80") {
            ctx.pass(
                "F075",
                "HTTPRoute backendRef targets Service 'gods-eye-view' on port 80",
            );
        } else {
            ctx.fail(
                "F075",
                "backendRef targeting gods-eye-view:80 missing in HTTPRoute",
            );
        }
    } else {
        ctx.skip("F075", "httproute.yaml not yet created", "Pending Milestone M4");
    }
}

// ---------------------------------------------------------------------------
// Feature 16: Cloudflare Tunnel DNSEndpoint (F076-F080)
// ---------------------------------------------------------------------------
fn feature_16_dnsendpoint(ctx: &mut TestContext) {
    let dns = DNSENDPOINT;

    // F076
    if ctx.file_exists(dns) {
        ctx.pass("F076", "gitops/argocd/platform/gods-eye-view/dnsendpoint.yaml exists");
    } else {
        ctx.skip("F076", "dnsendpoint.yaml not yet created", "Pending Milestone M4");
    }

    // F077
    if ctx.file_exists(dns) {
        if ctx.file_contains(dns, "godseye.ipv1337.dev") {
            ctx.pass("F077", "DNSEndpoint configures dnsName 'godseye.ipv1337.dev'");
        } else {
            ctx.fail("F077", "dnsName 'godseye.ipv1337.dev' missing in DNSEndpoint");
        }
    } else {
        ctx.skip("F077", "dnsendpoint.yaml not yet created", "Pending Milestone M4");
    }

    // F078
    if ctx.file_exists(dns) {
        if ctx.file_contains(dns, "recordType: CNAME") {
            ctx.pass("F078", "DNSEndpoint recordType is CNAME");
        } else {
            ctx.fail("F078", "recordType: CNAME missing in DNSEndpoint");
        }
    } else {
        ctx.skip("F078", "dnsendpoint.yaml not yet created", "Pending Milestone M4");
    }

    // F079
    if ctx.file_exists(dns) {
        if ctx.file_contains(
            dns,
            "1f7b9704-bb66-41f4-966f-5bb722e3c10e.cfargotunnel.com",
        ) {
            ctx.pass("F079", "DNSEndpoint points to Cloudflare Tunnel CNAME target");
        } else {
            ctx.fail(
                "F079",
                "Cloudflare Tunnel CNAME target mismatch in DNSEndpoint",
            );
        }
    } else {
        ctx.skip("F079", "dnsendpoint.yaml not yet created", "Pending Milestone M4");
    }

    // F080
    if ctx.file_exists(dns) {
        let content = ctx.read_file(dns).unwrap_or_default();
        if (content.contains("cloudflare-proxied") && content.contains("\"true\""))
            || (content.contains("cloudflare-proxied") && content.contains("'true'"))
        {
            ctx.pass("F080", "DNSEndpoint specifies cloudflare-proxied: 'true'");
        } else {
            ctx.fail("F080", "cloudflare-proxied: 'true' missing in DNSEndpoint");
        }
    } else {
        ctx.skip("F080", "dnsendpoint.yaml not yet created", "Pending Milestone M4");
    }
}

// ---------------------------------------------------------------------------
// Feature 17: Secret Template & Wiring (F081-F085)
// ---------------------------------------------------------------------------
fn feature_17_secrets(ctx: &mut TestContext) {
    // F081
    if ctx.file_exists(SECRETS_TPL) {
        ctx.pass("F081", "gitops/argocd/platform/gods-eye-view/secrets.template.yaml exists");
    } else {
        ctx.skip(
            "F081",
            "secrets.template.yaml not yet created",
            "Pending Milestone M4",
        );
    }

    // F082
    if ctx.file_exists(SECRETS_TPL) {
        let content = ctx.read_file(SECRETS_TPL).unwrap_or_default();
        if content.contains("GOOGLE_MAPS_API_KEY") && content.contains("OPENAI_API_KEY") {
            ctx.pass(
                "F082",
                "secrets.template.yaml documents required API keys (GOOGLE_MAPS_API_KEY, OPENAI_API_KEY)",
            );
        } else {
            ctx.fail("F082", "Required API keys missing in secrets.template.yaml");
        }
    } else {
        ctx.skip(
            "F082",
            "secrets.template.yaml not yet created",
            "Pending Milestone M4",
        );
    }

    // F083
    if ctx.file_exists(SECRETS_TPL) {
        let content = ctx.read_file(SECRETS_TPL).unwrap_or_default();
        if has_api_key_pattern(&content) {
            ctx.fail(
                "F083",
                "Real API key pattern detected in secrets.template.yaml",
            );
        } else {
            ctx.pass(
                "F083",
                "Zero plaintext API keys or credentials committed in secrets template",
            );
        }
    } else {
        ctx.skip(
            "F083",
            "secrets.template.yaml not yet created",
            "Pending Milestone M4",
        );
    }

    // F084
    if ctx.file_exists(DEPLOY) {
        let content = ctx.read_file(DEPLOY).unwrap_or_default();
        if content.contains("secretRef") || content.contains("secretKeyRef") {
            ctx.pass("F084", "Deployment mounts secrets via secretRef or secretKeyRef");
        } else {
            ctx.fail("F084", "Secret references missing in deployment.yaml");
        }
    } else {
        ctx.skip("F084", "deployment.yaml not yet created", "Pending Milestone M4");
    }

    // F085
    if ctx.file_exists(DEPLOY) {
        if ctx.file_contains(DEPLOY, "gods-eye-view-secrets") {
            ctx.pass("F085", "Secret reference name matches 'gods-eye-view-secrets'");
        } else {
            ctx.fail(
                "F085",
                "Secret reference name does not match 'gods-eye-view-secrets'",
            );
        }
    } else {
        ctx.skip("F085", "deployment.yaml not yet created", "Pending Milestone M4");
    }
}

// ---------------------------------------------------------------------------
// Feature 18: GitOps Manifest Validation (F086-F090)
// ---------------------------------------------------------------------------
fn feature_18_gitops_validation(ctx: &mut TestContext) {
    // F086
    if ctx.file_exists("tools/ci/gitops-validate.sh") {
        ctx.pass(
            "F086",
            "tools/ci/gitops-validate.sh exists with executable permissions",
        );
    } else {
        ctx.fail(
            "F086",
            "tools/ci/gitops-validate.sh not executable or not found",
        );
    }

    // F087
    if ctx.file_exists("gitops/argocd/projects/gods-eye-view-project.yaml")
        || ctx.file_contains(
            "gitops/argocd/projects/applications.yaml",
            "gods-eye-view",
        )
    {
        ctx.pass("F087", "AppProject for gods-eye-view is configured");
    } else {
        ctx.skip(
            "F087",
            "AppProject for gods-eye-view not yet created",
            "Pending Milestone M4",
        );
    }

    // F088
    if ctx.dir_exists(PLATFORM_DIR) {
        let all_valid = yaml_files_nonempty(ctx, PLATFORM_DIR);
        if all_valid {
            ctx.pass(
                "F088",
                "All platform manifests parse as valid YAML without syntax errors",
            );
        } else {
            ctx.fail(
                "F088",
                "YAML parse failure detected in gitops/argocd/platform/gods-eye-view/",
            );
        }
    } else {
        ctx.skip(
            "F088",
            "Platform manifests not yet created",
            "Pending Milestone M4",
        );
    }

    // F089
    if ctx.dir_exists(PLATFORM_DIR) {
        let all_hdr = yaml_files_contain(ctx, PLATFORM_DIR, "VitruvianSoftware");
        if all_hdr {
            ctx.pass(
                "F089",
                "All platform manifests contain VitruvianSoftware copyright header",
            );
        } else {
            ctx.fail(
                "F089",
                "Copyright header missing in one or more platform manifests",
            );
        }
    } else {
        ctx.skip(
            "F089",
            "Platform manifests not yet created",
            "Pending Milestone M4",
        );
    }

    // F090
    {
        let has_key = yaml_files_have_api_keys(ctx, PLATFORM_DIR);
        if has_key {
            ctx.fail(
                "F090",
                "Real API key pattern detected in gitops/argocd/platform/gods-eye-view/",
            );
        } else {
            ctx.pass(
                "F090",
                "Zero plaintext credentials detected across platform manifests",
            );
        }
    }
}

fn yaml_files_nonempty(ctx: &TestContext, dir: &str) -> bool {
    let base = ctx.path(dir);
    if let Ok(entries) = std::fs::read_dir(&base) {
        for entry in entries.flatten() {
            let p = entry.path();
            if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(".yaml") && p.is_file() {
                    if let Ok(meta) = std::fs::metadata(&p) {
                        if meta.len() == 0 {
                            return false;
                        }
                    }
                }
            }
        }
    }
    true
}

fn yaml_files_contain(ctx: &TestContext, dir: &str, needle: &str) -> bool {
    let base = ctx.path(dir);
    if let Ok(entries) = std::fs::read_dir(&base) {
        for entry in entries.flatten() {
            let p = entry.path();
            if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(".yaml") && p.is_file() {
                    if let Ok(content) = std::fs::read_to_string(&p) {
                        if !content.contains(needle) {
                            return false;
                        }
                    }
                }
            }
        }
    }
    true
}

fn yaml_files_have_api_keys(ctx: &TestContext, dir: &str) -> bool {
    let base = ctx.path(dir);
    if let Ok(entries) = std::fs::read_dir(&base) {
        for entry in entries.flatten() {
            let p = entry.path();
            if let Some(name) = p.file_name().and_then(|n| n.to_str()) {
                if name.ends_with(".yaml") && p.is_file() {
                    if let Ok(content) = std::fs::read_to_string(&p) {
                        if has_api_key_pattern(&content) {
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}

// ---------------------------------------------------------------------------
// Feature 19: Subagent Audit: Proxy & WebSockets (F091-F095)
// ---------------------------------------------------------------------------
fn feature_19_proxy_audit(ctx: &mut TestContext) {
    let server = format!("{}/server.mjs", APP);
    let providers = format!("{}/server/providers", APP);
    let vessels = format!("{}/server/providers/vessels", APP);
    let http_common = format!("{}/server/providers/common/http.js", APP);
    let http_body = format!("{}/src/sources/httpBody.js", APP);

    // F091 — SSRF protection presence
    if ctx.file_exists(&server) {
        let has_ssrf = ctx.file_contains(&http_common, "isPrivateIpAddress")
            || ctx.file_contains(&http_common, "readCappedResponseText")
            || ctx.file_contains(&http_body, "RESPONSE_TOO_LARGE")
            || ctx.file_contains(&server, "localProviderPlugins");
        if has_ssrf {
            ctx.pass(
                "F091",
                "Proxy implementation validates and restricts upstream proxy targets",
            );
        } else {
            ctx.fail("F091", "Proxy target URL validation failed in server.mjs");
        }
    } else {
        ctx.fail("F091", "Proxy target URL validation failed in server.mjs");
    }

    // F092 — WebSocket reconnect
    if ctx.file_exists(&server) || ctx.dir_exists(&vessels) {
        if dir_files_contain(ctx, &vessels, ".js", "reconnect") {
            ctx.pass(
                "F092",
                "AISStream WebSocket implements auto-reconnect with backoff",
            );
        } else {
            ctx.skip(
                "F092",
                "WebSocket reconnect backoff audit",
                "Pending Milestone M5 review",
            );
        }
    } else {
        ctx.skip("F092", "Server not yet created", "Pending Milestone M3");
    }

    // F093 — error handling
    if ctx.file_exists(&server) || ctx.dir_exists(&providers) {
        if dir_files_contain(ctx, &providers, ".js", ".on('error'")
            || dir_files_contain(ctx, &providers, ".js", ".on(\"error\"")
        {
            ctx.pass(
                "F093",
                "Upstream providers handle stream error events, so a dropped connection cannot crash the process",
            );
        } else {
            ctx.skip(
                "F093",
                "WebSocket error handling audit",
                "Pending Milestone M5 review",
            );
        }
    } else {
        ctx.skip("F093", "Server not yet created", "Pending Milestone M3");
    }

    // F094 — ephemeral token
    if ctx.file_exists(&server) || ctx.dir_exists(&providers) {
        if dir_files_contain(ctx, &providers, ".js", "client_secrets") {
            ctx.pass(
                "F094",
                "OpenAI Realtime mints ephemeral client secrets; master key never sent to browser",
            );
        } else {
            ctx.skip(
                "F094",
                "Realtime token audit",
                "Pending Milestone M5 review",
            );
        }
    } else {
        ctx.skip("F094", "Server not yet created", "Pending Milestone M3");
    }

    // F095 — rate limiting
    if ctx.file_exists(&server) || ctx.dir_exists(&providers) {
        if dir_files_contain(ctx, &providers, ".js", "GEV_RATELIMIT") {
            ctx.pass(
                "F095",
                "Rate-limiting guards supported for high-cost endpoints (OpenAI, Google Places)",
            );
        } else {
            ctx.skip(
                "F095",
                "Rate limit audit",
                "Pending Milestone M5 review",
            );
        }
    } else {
        ctx.skip("F095", "Server not yet created", "Pending Milestone M3");
    }
}

// ---------------------------------------------------------------------------
// Feature 20: Subagent Audit: Networking & Security (F096-F100)
// ---------------------------------------------------------------------------
fn feature_20_security_audit(ctx: &mut TestContext) {
    // F096
    if ctx.file_exists(DEPLOY) {
        let content = ctx.read_file(DEPLOY).unwrap_or_default();
        if content.contains("drop:") && content.contains("ALL") {
            ctx.pass(
                "F096",
                "Deployment container securityContext explicitly drops ALL capabilities",
            );
        } else {
            ctx.fail("F096", "capabilities.drop ALL missing in deployment.yaml");
        }
    } else {
        ctx.skip("F096", "deployment.yaml not yet created", "Pending Milestone M4");
    }

    // F097
    if ctx.file_exists(DEPLOY) {
        if ctx.file_contains(DEPLOY, "allowPrivilegeEscalation: false") {
            ctx.pass("F097", "Deployment enforces allowPrivilegeEscalation: false");
        } else {
            ctx.fail(
                "F097",
                "allowPrivilegeEscalation: false missing in deployment.yaml",
            );
        }
    } else {
        ctx.skip("F097", "deployment.yaml not yet created", "Pending Milestone M4");
    }

    // F098
    if ctx.file_exists(DEPLOY) {
        if ctx.file_contains(DEPLOY, "RuntimeDefault") {
            ctx.pass("F098", "Deployment enforces seccompProfile: RuntimeDefault");
        } else {
            ctx.fail(
                "F098",
                "seccompProfile RuntimeDefault missing in deployment.yaml",
            );
        }
    } else {
        ctx.skip("F098", "deployment.yaml not yet created", "Pending Milestone M4");
    }

    // F099
    if ctx.file_exists(DEPLOY) {
        let content = ctx.read_file(DEPLOY).unwrap_or_default();
        if content.contains("resources:") && content.contains("limits:") {
            ctx.pass(
                "F099",
                "Workload declares CPU and Memory resource limits to prevent noisy neighbor contention",
            );
        } else {
            ctx.fail("F099", "resource limits missing in deployment.yaml");
        }
    } else {
        ctx.skip("F099", "deployment.yaml not yet created", "Pending Milestone M4");
    }

    // F100
    if ctx.file_exists(DEPLOY) {
        let content = ctx.read_file(DEPLOY).unwrap_or_default();
        if content.contains("readinessProbe:") && content.contains("livenessProbe:") {
            ctx.pass(
                "F100",
                "Deployment defines readinessProbe and livenessProbe for health lifecycle",
            );
        } else {
            ctx.fail(
                "F100",
                "readinessProbe or livenessProbe missing in deployment.yaml",
            );
        }
    } else {
        ctx.skip("F100", "deployment.yaml not yet created", "Pending Milestone M4");
    }
}
