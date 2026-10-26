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

//! App-level conformance checks: visibility firewall, metadata catalog, and
//! TechDocs documentation parity.
//!
//! Ports `get_app_dirs()`, `check_app_visibility()`, `check_app_metadata()`,
//! and `check_techdocs()` from check.sh.

use std::collections::{BTreeSet, HashMap};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::Context;

// ---------------------------------------------------------------------------
// Helper: get_app_dirs (lines 1410-1429)
// ---------------------------------------------------------------------------

/// Discover all application directories containing a Backstage Component
/// catalog-info.yaml, excluding platform infrastructure, tools, and shared
/// libraries. Returns repo-relative paths, LC_ALL=C sorted.
pub fn get_app_dirs(root: &str) -> Vec<String> {
    let root_path = Path::new(root);
    let mut candidates: Vec<PathBuf> = Vec::new();

    // Pattern 1: $ROOT/*/catalog-info.yaml (top-level dirs)
    if let Ok(entries) = fs::read_dir(root_path) {
        for entry in entries.flatten() {
            let ci = entry.path().join("catalog-info.yaml");
            if ci.is_file() {
                candidates.push(entry.path());
            }
        }
    }

    // Pattern 2: $ROOT/apps/*/*/catalog-info.yaml
    let apps_dir = root_path.join("apps");
    if apps_dir.is_dir() {
        if let Ok(categories) = fs::read_dir(&apps_dir) {
            for cat in categories.flatten() {
                if !cat.path().is_dir() {
                    continue;
                }
                if let Ok(apps) = fs::read_dir(cat.path()) {
                    for app in apps.flatten() {
                        let ci = app.path().join("catalog-info.yaml");
                        if ci.is_file() {
                            candidates.push(app.path());
                        }
                    }
                }
            }
        }
    }

    // Pattern 3: $ROOT/mobile/*/*/catalog-info.yaml
    let mobile_dir = root_path.join("mobile");
    if mobile_dir.is_dir() {
        if let Ok(platforms) = fs::read_dir(&mobile_dir) {
            for plat in platforms.flatten() {
                if !plat.path().is_dir() {
                    continue;
                }
                if let Ok(apps) = fs::read_dir(plat.path()) {
                    for app in apps.flatten() {
                        let ci = app.path().join("catalog-info.yaml");
                        if ci.is_file() {
                            candidates.push(app.path());
                        }
                    }
                }
            }
        }
    }

    let mut dirs = BTreeSet::new();
    for parent in candidates {
        // Skip symlinks.
        if parent
            .symlink_metadata()
            .map(|m| m.file_type().is_symlink())
            .unwrap_or(false)
        {
            continue;
        }

        let rel = match parent.strip_prefix(root_path) {
            Ok(r) => r.to_string_lossy().to_string(),
            Err(_) => continue,
        };

        // Exclusions match on the FIRST path segment.
        let first_seg = rel.split('/').next().unwrap_or("");
        match first_seg {
            "tools" | "infrastructure" | "pulumi" | "gitops" | "architecture" | "packages"
            | "docs" => continue,
            s if s.starts_with("bazel-") || s.starts_with('.') => continue,
            _ => {}
        }

        // Must contain "kind: Component".
        let ci_path = parent.join("catalog-info.yaml");
        if let Ok(content) = fs::read_to_string(&ci_path) {
            if content
                .lines()
                .any(|l| l.trim().starts_with("kind:") && l.contains("Component"))
            {
                dirs.insert(rel);
            }
        }
    }

    // BTreeSet is already sorted (Rust default: byte-order on String).
    dirs.into_iter().collect()
}

// ---------------------------------------------------------------------------
// check_app_visibility (lines 1431-1516, group "vis")
// ---------------------------------------------------------------------------

/// Find all BUILD/BUILD.bazel files under `dir`, excluding node_modules and
/// bazel-* directories. Returns absolute paths, sorted.
fn find_build_files(dir: &Path) -> Vec<PathBuf> {
    let mut results = Vec::new();
    find_build_files_recurse(dir, &mut results);
    results.sort();
    results
}

fn find_build_files_recurse(dir: &Path, out: &mut Vec<PathBuf>) {
    let entries = match fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };
    let mut sorted: Vec<fs::DirEntry> = entries.flatten().collect();
    sorted.sort_by_key(|e| e.file_name());

    for entry in sorted {
        let name = entry.file_name();
        let name_str = name.to_string_lossy();
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if ft.is_dir() {
            if name_str == "node_modules" || name_str.starts_with("bazel-") {
                continue;
            }
            find_build_files_recurse(&entry.path(), out);
        } else if ft.is_file() && (name_str == "BUILD" || name_str == "BUILD.bazel") {
            out.push(entry.path());
        }
    }
}

/// Parse a BUILD file for `"//visibility:public"` targets. Returns a list of
/// (file_rel, target_name) pairs using the same AWK-equivalent logic as bash.
fn parse_public_targets(build_path: &Path, file_rel: &str) -> Vec<(String, String)> {
    let content = match fs::read_to_string(build_path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    let mut results = Vec::new();
    let mut current_name = String::new();

    for line in content.lines() {
        if line.starts_with("package(") {
            current_name = "(package default)".to_string();
        }
        if line.contains("name = \"") {
            if let Some(rest) = line.split("name = \"").nth(1) {
                if let Some(name) = rest.split('"').next() {
                    current_name = name.to_string();
                }
            }
        }
        if line.contains("\"//visibility:public\"") {
            results.push((file_rel.to_string(), current_name.clone()));
        }
    }

    results
}

/// Load the public-targets.tsv allowlist. Returns file:target -> justification.
fn load_allowlist(path: &Path) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let content = match fs::read_to_string(path) {
        Ok(c) => c,
        Err(_) => return map,
    };
    for line in content.lines() {
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let fields: Vec<&str> = line.splitn(3, '\t').collect();
        if fields.len() >= 3 {
            let key = format!("{}:{}", fields[0], fields[1]);
            map.insert(key, fields[2].to_string());
        }
    }
    map
}

pub fn check_app_visibility(ctx: &Context) {
    let app_dirs = get_app_dirs(&ctx.root);
    let allowlist_path = PathBuf::from(&ctx.root).join("tools/conformance/public-targets.tsv");

    // --- 1. root boundary declaration per app. --------------------------------
    for app in &app_dirs {
        let mut rootbuild = String::new();
        for cand in &["BUILD", "BUILD.bazel"] {
            let p = format!("{}/{}/{}", ctx.root, app, cand);
            if Path::new(&p).is_file() {
                rootbuild = p;
                break;
            }
        }

        let expected = format!(
            "package(default_visibility = [\"//{}:__subpackages__\"])",
            app
        );

        if rootbuild.is_empty()
            || fs::read_to_string(&rootbuild)
                .map(|c| !c.contains(&expected))
                .unwrap_or(true)
        {
            ctx.emit_fail(
                "vis",
                &format!("{}/BUILD", app),
                "no boundary",
                "app-scoped default",
                "app root BUILD does not declare the inter-app boundary (#82)",
                &format!(
                    "add package(default_visibility = [\"//{}:__subpackages__\"]) to {}/BUILD",
                    app, app
                ),
            );
        } else {
            ctx.emit_ok(
                "vis",
                &format!("{}/BUILD", app),
                "boundary",
                "app-scoped default",
                &format!(
                    "package default_visibility scopes to //{}:__subpackages__",
                    app
                ),
            );
        }
    }

    // --- 2. public targets inside apps must be allowlisted. -------------------
    let allowlist = if allowlist_path.is_file() {
        load_allowlist(&allowlist_path)
    } else {
        HashMap::new()
    };

    let mut seen_keys: BTreeSet<String> = BTreeSet::new();

    for app in &app_dirs {
        let app_path = PathBuf::from(&ctx.root).join(app);
        let build_files = find_build_files(&app_path);

        for bf in &build_files {
            let bf_rel = match bf.strip_prefix(&ctx.root) {
                Ok(r) => r.to_string_lossy().to_string(),
                Err(_) => continue,
            };
            // Remove leading slash if present.
            let bf_rel = bf_rel.trim_start_matches('/').to_string();

            let public_targets = parse_public_targets(bf, &bf_rel);
            for (pfile, ptarget) in public_targets {
                let key = format!("{}:{}", pfile, ptarget);
                seen_keys.insert(key.clone());

                if let Some(justification) = allowlist.get(&key) {
                    ctx.emit_pin(
                        "vis",
                        &pfile,
                        &format!(":{}", ptarget),
                        "allowlisted public",
                        justification,
                    );
                } else {
                    ctx.emit_fail(
                        "vis",
                        &pfile,
                        &format!(":{}", ptarget),
                        "app-internal",
                        "//visibility:public inside an app without an allowlist entry -- the inter-app firewall (#82) has a hole",
                        "narrow to //<app>:__subpackages__ (CLI/workflow 'bazel run|build <label>' needs no visibility), or add a justified row to tools/conformance/public-targets.tsv",
                    );
                }
            }
        }
    }

    // --- 3. stale allowlist rows (listed but no longer public) are failures. --
    if allowlist_path.is_file() {
        if let Ok(content) = fs::read_to_string(&allowlist_path) {
            for line in content.lines() {
                if line.is_empty() || line.starts_with('#') {
                    continue;
                }
                let fields: Vec<&str> = line.splitn(3, '\t').collect();
                if fields.len() < 2 {
                    continue;
                }
                let afile = fields[0];
                let atarget = fields[1];
                let key = format!("{}:{}", afile, atarget);
                if !seen_keys.contains(&key) {
                    ctx.emit_fail(
                        "vis",
                        afile,
                        &format!(":{}", atarget),
                        "allowlist row",
                        "allowlisted target is no longer //visibility:public (or moved) -- stale exception",
                        "remove the row from tools/conformance/public-targets.tsv",
                    );
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// check_app_metadata (lines 2869-2913, group "meta")
// ---------------------------------------------------------------------------

/// Extract the first value for a given YAML key from file content.
/// Matches lines where the first whitespace-delimited token is `key:`.
fn yaml_first_value(content: &str, key: &str) -> Option<String> {
    let prefix = format!("{}:", key);
    for line in content.lines() {
        let trimmed = line.trim();
        let mut parts = trimmed.split_whitespace();
        if let Some(first) = parts.next() {
            if first == prefix {
                return parts.next().map(|v| v.to_string());
            }
        }
    }
    None
}

/// Parse CODEOWNERS for a given app path. Returns the team name (stripped of
/// org prefix) for the line whose first field is `/$app/`.
fn codeowners_team(codeowners_path: &Path, app: &str) -> Option<String> {
    let content = fs::read_to_string(codeowners_path).ok()?;
    let pattern = format!("/{}/", app);
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let mut parts = trimmed.split_whitespace();
        if let Some(first) = parts.next() {
            if first == pattern {
                if let Some(second) = parts.next() {
                    // Strip everything up to and including the last '/'.
                    let team = second.rsplit('/').next().unwrap_or(second);
                    return Some(team.to_string());
                }
            }
        }
    }
    None
}

pub fn check_app_metadata(ctx: &Context) {
    let app_dirs = get_app_dirs(&ctx.root);
    let codeowners_path = PathBuf::from(&ctx.root).join(".github/CODEOWNERS");
    let root_catalog = PathBuf::from(&ctx.root).join("catalog-info.yaml");
    let root_catalog_content = fs::read_to_string(&root_catalog).unwrap_or_default();

    for app in &app_dirs {
        let mf = format!("{}/{}/catalog-info.yaml", ctx.root, app);

        if !Path::new(&mf).is_file() {
            ctx.emit_fail(
                "meta",
                &format!("{}/catalog-info.yaml", app),
                "missing",
                "app metadata",
                "app has no machine-readable metadata (#500)",
                &format!(
                    "add {}/catalog-info.yaml (Component with owner = the CODEOWNERS team)",
                    app
                ),
            );
            continue;
        }

        let content = match fs::read_to_string(&mf) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let mname = yaml_first_value(&content, "name").unwrap_or_default();
        let mowner = yaml_first_value(&content, "owner").unwrap_or_default();
        let coteam = codeowners_team(&codeowners_path, app).unwrap_or_default();

        // The component NAME is the app dir's basename, not its path.
        let app_name = app.rsplit('/').next().unwrap_or(app);

        if mname != app_name {
            ctx.emit_fail(
                "meta",
                &format!("{}/catalog-info.yaml", app),
                &format!("name:{}", mname),
                &format!("name:{}", app_name),
                "metadata.name must equal the app directory name",
                &format!("set metadata.name: {}", app_name),
            );
        } else if coteam.is_empty() {
            ctx.emit_warn(
                "meta",
                &format!("{}/catalog-info.yaml", app),
                &format!("owner:{}", mowner),
                "(no CODEOWNERS row)",
                &format!(
                    "no /{}/ line in .github/CODEOWNERS to validate the owner against",
                    app
                ),
            );
        } else if mowner != coteam {
            ctx.emit_fail(
                "meta",
                &format!("{}/catalog-info.yaml", app),
                &format!("owner:{}", mowner),
                &format!("owner:{}", coteam),
                &format!(
                    "spec.owner disagrees with the CODEOWNERS team for /{}/ -- ownership is declared once, in CODEOWNERS",
                    app
                ),
                &format!("set spec.owner: {}", coteam),
            );
        } else if !root_catalog_content.contains(&format!("./{}/catalog-info.yaml", app)) {
            ctx.emit_fail(
                "meta",
                "catalog-info.yaml",
                "missing target",
                &format!("./{}/catalog-info.yaml", app),
                "the root Location does not list this app's catalog file -- consumers can't discover it",
                &format!(
                    "add ./{}/catalog-info.yaml to the root catalog-info.yaml Location targets",
                    app
                ),
            );
        } else {
            ctx.emit_ok(
                "meta",
                &format!("{}/catalog-info.yaml", app),
                &format!("owner:{}", mowner),
                &format!("owner:{}", coteam),
                "name + owner match CODEOWNERS; listed in the root Location",
            );
        }
    }
}

// ---------------------------------------------------------------------------
// check_techdocs (lines 2920-2981, group "techdocs")
// ---------------------------------------------------------------------------

/// Discover all catalog-info.yaml files using git ls-files (tracked + untracked),
/// falling back to the file cache if git is unavailable.
fn discover_catalog_files(root: &str) -> Vec<String> {
    let mut files = BTreeSet::new();

    // git ls-files: tracked
    if let Ok(output) = Command::new("git")
        .args([
            "-C",
            root,
            "ls-files",
            "*catalog-info.yaml",
            "**/catalog-info.yaml",
        ])
        .output()
    {
        if output.status.success() {
            for line in String::from_utf8_lossy(&output.stdout).lines() {
                if !line.is_empty() {
                    files.insert(line.to_string());
                }
            }
        }
    }

    // git ls-files: untracked but not ignored
    if let Ok(output) = Command::new("git")
        .args([
            "-C",
            root,
            "ls-files",
            "--others",
            "--exclude-standard",
            "*catalog-info.yaml",
            "**/catalog-info.yaml",
        ])
        .output()
    {
        if output.status.success() {
            for line in String::from_utf8_lossy(&output.stdout).lines() {
                if !line.is_empty() {
                    files.insert(line.to_string());
                }
            }
        }
    }

    files.into_iter().collect()
}

pub fn check_techdocs(ctx: &Context) {
    let catalog_files = discover_catalog_files(&ctx.root);

    for cf in &catalog_files {
        let full_cf = format!("{}/{}", ctx.root, cf);
        if !Path::new(&full_cf).is_file() {
            continue;
        }
        let cf_dir = Path::new(&full_cf)
            .parent()
            .map(|p| p.to_path_buf())
            .unwrap_or_else(|| PathBuf::from(&ctx.root));

        let content = match fs::read_to_string(&full_cf) {
            Ok(c) => c,
            Err(_) => continue,
        };

        for line in content.lines() {
            if !line.contains("backstage.io/techdocs-ref:") || !line.contains("dir:") {
                continue;
            }

            // Extract the dir:<path> reference.
            let trimmed = line.trim();
            let ref_value = if let Some(pos) = trimmed.find("backstage.io/techdocs-ref:") {
                let after_key = &trimmed[pos + "backstage.io/techdocs-ref:".len()..];
                let after_key = after_key.trim();
                // Extract the dir:... token (stops at whitespace).
                if let Some(dir_pos) = after_key.find("dir:") {
                    let from_dir = &after_key[dir_pos..];
                    from_dir.split_whitespace().next().unwrap_or("").to_string()
                } else {
                    continue;
                }
            } else {
                continue;
            };

            if ref_value.is_empty() {
                continue;
            }

            let rel_path = ref_value.strip_prefix("dir:").unwrap_or(&ref_value);
            let target_dir = cf_dir.join(rel_path);

            // Canonicalize (resolve symlinks/..): returns None if does not exist.
            let target_dir_clean = target_dir.canonicalize().ok();
            let rel_target = target_dir_clean
                .as_ref()
                .map(|p| match p.strip_prefix(&ctx.root) {
                    Ok(r) if !r.as_os_str().is_empty() => r.to_string_lossy().to_string(),
                    _ => p.to_string_lossy().to_string(),
                });

            if target_dir_clean.is_none() || !target_dir_clean.as_ref().unwrap().is_dir() {
                ctx.emit_fail(
                    "techdocs",
                    cf,
                    &ref_value,
                    "dir exists",
                    &format!(
                        "backstage.io/techdocs-ref points to nonexistent directory {}",
                        rel_path
                    ),
                    "point backstage.io/techdocs-ref to an existing directory containing mkdocs.yml",
                );
                continue;
            }

            let rel_target = rel_target.unwrap();
            let mkdocs_file = target_dir_clean.as_ref().unwrap().join("mkdocs.yml");

            if !mkdocs_file.is_file() {
                ctx.emit_fail(
                    "techdocs",
                    cf,
                    "mkdocs:missing",
                    "mkdocs.yml",
                    &format!(
                        "target directory {} has no mkdocs.yml \u{2014} Backstage TechDocs cannot build",
                        rel_target
                    ),
                    &format!(
                        "add mkdocs.yml with site_name and techdocs-core plugin to {}",
                        rel_target
                    ),
                );
                continue;
            }

            let mkdocs_content = match fs::read_to_string(&mkdocs_file) {
                Ok(c) => c,
                Err(_) => continue,
            };

            if !mkdocs_content.lines().any(|l| l.starts_with("site_name:")) {
                ctx.emit_fail(
                    "techdocs",
                    &format!("{}/mkdocs.yml", rel_target),
                    "site_name:missing",
                    "site_name",
                    "mkdocs.yml missing required site_name property",
                    &format!("add site_name to {}/mkdocs.yml", rel_target),
                );
                continue;
            }

            if !mkdocs_content.contains("techdocs-core") {
                ctx.emit_fail(
                    "techdocs",
                    &format!("{}/mkdocs.yml", rel_target),
                    "plugins:no-techdocs",
                    "techdocs-core",
                    "mkdocs.yml missing required techdocs-core plugin for Backstage",
                    &format!(
                        "add 'plugins: [techdocs-core]' to {}/mkdocs.yml",
                        rel_target
                    ),
                );
                continue;
            }

            ctx.emit_ok(
                "techdocs",
                cf,
                &ref_value,
                &format!("{}/mkdocs.yml", rel_target),
                "techdocs-ref resolves to valid mkdocs.yml with techdocs-core",
            );
        }
    }
}
