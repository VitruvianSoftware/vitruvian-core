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

//! IaC, Pulumi, release-unit, and Copybara conformance checks.
//!
//! Ported from check.sh: check_zitadel_import, check_pulumi_project_names,
//! check_pulumi_project_renames, check_custom_domain_zone,
//! check_release_please_packages, check_release_infra_exclude,
//! check_copybara_infra_exclude, check_copybara_version_maps,
//! check_copybara_export_triggers, check_copybara_component_lists.

use crate::Context;
use std::collections::{BTreeMap, BTreeSet};
use std::fs;
use std::path::Path;
use std::process::Command;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Walk a directory recursively, collecting files matching a predicate.
fn walk_files(dir: &Path, pred: &dyn Fn(&str) -> bool, out: &mut Vec<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };
    let mut sorted: Vec<fs::DirEntry> = entries.filter_map(|e| e.ok()).collect();
    sorted.sort_by_key(|e| e.file_name());
    for entry in sorted {
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        let name = entry.file_name().to_string_lossy().to_string();
        if ft.is_dir() {
            walk_files(&entry.path(), pred, out);
        } else if ft.is_file() && pred(&name) {
            out.push(entry.path().to_string_lossy().to_string());
        }
    }
}

/// Find all Pulumi.yaml files under the LIVE deployed tree (infrastructure/pulumi,
/// apps, */infra) but NOT packages/pulumi/examples/**. Returns relative paths,
/// sorted.
fn find_live_pulumi_yamls(root: &str) -> Vec<String> {
    let mut results = Vec::new();
    let search_dirs = ["infrastructure/pulumi", "apps"];
    let pred = |name: &str| name == "Pulumi.yaml";

    for sd in &search_dirs {
        let dir = format!("{}/{}", root, sd);
        if Path::new(&dir).is_dir() {
            walk_files(Path::new(&dir), &pred, &mut results);
        }
    }

    // Also search */infra (top-level directories that have infra/ subdirs).
    if let Ok(entries) = fs::read_dir(root) {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') || name.starts_with("bazel-") {
                continue;
            }
            let infra_dir = format!("{}/{}/infra", root, name);
            if Path::new(&infra_dir).is_dir() {
                walk_files(Path::new(&infra_dir), &pred, &mut results);
            }
        }
    }

    // Filter out packages/pulumi/examples/**
    let exclude_prefix = format!("{}/packages/pulumi/examples/", root);
    results.retain(|p| !p.starts_with(&exclude_prefix));

    // Convert to relative paths and sort.
    let root_prefix = if root.ends_with('/') {
        root.to_string()
    } else {
        format!("{}/", root)
    };
    let mut rels: Vec<String> = results
        .iter()
        .map(|p| p.strip_prefix(&root_prefix).unwrap_or(p).to_string())
        .collect();
    rels.sort();
    rels
}

/// Extract the `name:` value from a Pulumi.yaml file.
fn pulumi_yaml_name(path: &str) -> Option<String> {
    let content = fs::read_to_string(path).ok()?;
    for line in content.lines() {
        let trimmed = line.trim_start();
        if trimmed.starts_with("name:") {
            let rest = trimmed["name:".len()..].trim();
            if !rest.is_empty() {
                return Some(rest.trim_end_matches('\r').to_string());
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// check_zitadel_import (group: iac)
// ---------------------------------------------------------------------------

pub fn check_zitadel_import(ctx: &Context) {
    let zdir = format!("{}/infrastructure/pulumi/platform/zitadel-apps", ctx.root);
    if !Path::new(&zdir).is_dir() {
        return;
    }

    let mut hits: Vec<(String, usize)> = Vec::new();
    let mut go_files = Vec::new();
    walk_files(
        Path::new(&zdir),
        &|name: &str| name.ends_with(".go"),
        &mut go_files,
    );

    for file in &go_files {
        if let Ok(content) = fs::read_to_string(file) {
            for (i, line) in content.lines().enumerate() {
                if line.contains("pulumi.Import(") {
                    hits.push((file.clone(), i + 1));
                }
            }
        }
    }

    if hits.is_empty() {
        ctx.emit_ok(
            "iac",
            "infrastructure/pulumi/platform/zitadel-apps",
            "no imports",
            "create-only",
            "zitadel-apps creates and owns its OIDC apps (no destructive adopt)",
        );
    } else {
        for (file, lineno) in &hits {
            let rel = ctx.rel(file);
            ctx.emit_fail(
                "iac",
                &format!("{}:{}", rel, lineno),
                "pulumi.Import",
                "create-only",
                "importing a zitadel ApplicationOidc force-replaces and DELETES the live OIDC client (PR #310 incident)",
                "remove the pulumi.Import option -- the zitadel-apps stack must CREATE and own its apps",
            );
        }
    }
}

// ---------------------------------------------------------------------------
// check_pulumi_project_names (group: pulumi)
// ---------------------------------------------------------------------------

pub fn check_pulumi_project_names(ctx: &Context) {
    let files = find_live_pulumi_yamls(&ctx.root);
    let mut names: Vec<String> = Vec::new();
    let mut name_to_files: BTreeMap<String, Vec<String>> = BTreeMap::new();

    for f in &files {
        let abs = format!("{}/{}", ctx.root, f);
        if let Some(name) = pulumi_yaml_name(&abs) {
            names.push(name.clone());
            name_to_files.entry(name).or_default().push(f.clone());
        }
    }

    // Find duplicates.
    names.sort();
    let mut dupes: Vec<String> = Vec::new();
    let mut i = 0;
    while i < names.len() {
        let mut j = i + 1;
        while j < names.len() && names[j] == names[i] {
            j += 1;
        }
        if j - i > 1 && !dupes.contains(&names[i]) {
            dupes.push(names[i].clone());
        }
        i = j;
    }

    if dupes.is_empty() {
        ctx.emit_ok_uncounted(
            "pulumi",
            "Pulumi.yaml",
            "unique",
            "unique",
            "every Pulumi project name is unique",
        );
        return;
    }

    for d in &dupes {
        let where_files = name_to_files
            .get(d)
            .map(|v| v.join(" "))
            .unwrap_or_default();
        ctx.emit_fail(
            "pulumi",
            "Pulumi.yaml",
            &format!("duplicate: {}", d),
            "unique",
            &format!(
                "Pulumi project name '{}' is declared by more than one program ({}) - they SHARE stack state, so one will adopt the other's resources and reconcile them against the wrong target",
                d, where_files
            ),
            "give each program a distinct name: in its Pulumi.yaml (renaming the directory is NOT enough - the name is independent of the path)",
        );
    }
}

// ---------------------------------------------------------------------------
// check_pulumi_project_renames (group: pulumi)
// ---------------------------------------------------------------------------

pub fn check_pulumi_project_renames(ctx: &Context) {
    let inv_path = format!("{}/tools/conformance/pulumi-project-names.tsv", ctx.root);
    let inv_rel = "tools/conformance/pulumi-project-names.tsv";

    let inv_content = match fs::read_to_string(&inv_path) {
        Ok(c) => c,
        Err(_) => {
            ctx.emit_fail(
                "pulumi",
                inv_rel,
                "missing",
                "inventory",
                "the Pulumi project-name inventory is gone, so a rename that orphans stack state would pass unnoticed",
                &format!("restore {} (one TAB-separated row per live Pulumi.yaml: path, project name)", inv_rel),
            );
            return;
        }
    };

    // Parse inventory: path\tname (skip comments).
    let mut inventory: BTreeMap<String, String> = BTreeMap::new();
    let mut inv_rows: Vec<(String, String)> = Vec::new();
    for line in inv_content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let parts: Vec<&str> = line.splitn(2, '\t').collect();
        if parts.len() == 2 {
            inventory.insert(parts[0].to_string(), parts[1].to_string());
            inv_rows.push((parts[0].to_string(), parts[1].to_string()));
        }
    }

    let files = find_live_pulumi_yamls(&ctx.root);
    let mut ok = true;
    let mut seen: BTreeSet<String> = BTreeSet::new();

    for f in &files {
        let abs = format!("{}/{}", ctx.root, f);
        let actual = match pulumi_yaml_name(&abs) {
            Some(n) => n,
            None => continue,
        };
        seen.insert(f.clone());

        if let Some(recorded) = inventory.get(f.as_str()) {
            if recorded != &actual {
                ctx.emit_fail(
                    "pulumi",
                    f,
                    &actual,
                    recorded,
                    &format!(
                        "Pulumi project RENAMED ('{}' -> '{}'). Pulumi keys stack state on this name, so on the next deploy the '{}' stack keeps every existing resource and '{}' starts EMPTY -- it will try to CREATE infrastructure that already exists",
                        recorded, actual, recorded, actual
                    ),
                    &format!(
                        "if the rename is intended, migrate the state first (pulumi stack export from '{}' -> rewrite the project name in every URN -> pulumi stack import into '{}', per env), verify the new stack's resource count matches, THEN update this row; otherwise restore the name to '{}'",
                        recorded, actual, recorded
                    ),
                );
                ok = false;
            }
        } else {
            ctx.emit_fail(
                "pulumi",
                f,
                "unrecorded",
                "in inventory",
                "this Pulumi program is not in the project-name inventory, so a later rename of it would go unnoticed",
                &format!("add a row to {}: {}\t{}", inv_rel, f, actual),
            );
            ok = false;
        }
    }

    // Stale rows.
    for (path, name) in &inv_rows {
        if !seen.contains(path.as_str()) {
            ctx.emit_fail(
                "pulumi",
                inv_rel,
                &format!("stale: {}", path),
                "removed",
                &format!(
                    "the inventory records '{}' at {} but no Pulumi.yaml exists there -- a stale row hides a real rename behind a name that matches nothing",
                    name, path
                ),
                &format!("drop the row for {} (and confirm its stack was intentionally retired)", path),
            );
            ok = false;
        }
    }

    if ok {
        let n = inv_rows.len();
        ctx.emit_ok(
            "pulumi",
            inv_rel,
            &format!("{} recorded", n),
            "unchanged",
            "every Pulumi project name matches its recorded value -- no rename can silently orphan stack state",
        );
    }
}

// ---------------------------------------------------------------------------
// check_custom_domain_zone (group: pulumi)
// ---------------------------------------------------------------------------

pub fn check_custom_domain_zone(ctx: &Context) {
    let mut ok = true;

    // Collect Pulumi.*.yaml (env config) files from */infra/* and apps/*/*/infra/*.
    let mut candidates: Vec<String> = Vec::new();

    // */infra/*/Pulumi.*.yaml
    if let Ok(entries) = fs::read_dir(&ctx.root) {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with('.') || name.starts_with("bazel-") {
                continue;
            }
            let infra_dir = format!("{}/{}/infra", ctx.root, name);
            if let Ok(subdirs) = fs::read_dir(&infra_dir) {
                for sd in subdirs.filter_map(|e| e.ok()) {
                    if sd.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                        collect_pulumi_env_yamls(
                            &sd.path().to_string_lossy(),
                            &ctx.root,
                            &mut candidates,
                        );
                    }
                }
            }
        }
    }

    // apps/*/*/infra/*/Pulumi.*.yaml
    let apps_dir = format!("{}/apps", ctx.root);
    if let Ok(cats) = fs::read_dir(&apps_dir) {
        for cat in cats.filter_map(|e| e.ok()) {
            if !cat.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                continue;
            }
            if let Ok(app_entries) = fs::read_dir(cat.path()) {
                for app in app_entries.filter_map(|e| e.ok()) {
                    if !app.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                        continue;
                    }
                    let infra_dir = format!("{}/infra", app.path().to_string_lossy());
                    if let Ok(subdirs) = fs::read_dir(&infra_dir) {
                        for sd in subdirs.filter_map(|e| e.ok()) {
                            if sd.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                                collect_pulumi_env_yamls(
                                    &sd.path().to_string_lossy(),
                                    &ctx.root,
                                    &mut candidates,
                                );
                            }
                        }
                    }
                }
            }
        }
    }

    candidates.sort();

    for f in &candidates {
        let abs = format!("{}/{}", ctx.root, f);
        let content = match fs::read_to_string(&abs) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let dom = extract_pulumi_config_value(&content, "customDomain");
        let dom = match dom {
            Some(d) if !d.is_empty() => d,
            _ => continue,
        };

        let zone = extract_pulumi_config_value(&content, "cloudflareZone");

        if zone.is_none() || zone.as_deref() == Some("") {
            let dom_parent = dom.splitn(2, '.').nth(1).unwrap_or("");
            ctx.emit_fail(
                "pulumi",
                f,
                "no cloudflareZone",
                "zone declared",
                &format!(
                    "{} sets customDomain={} but declares no cloudflareZone - the CNAME and the ownership-verification TXT would have no zone to be written into",
                    f, dom
                ),
                &format!("add the registrable parent zone, e.g. '<ns>:cloudflareZone: {}'", dom_parent),
            );
            ok = false;
            continue;
        }

        let zone = zone.unwrap();
        // Check domain is under zone: dom == zone || dom ends with .zone
        if dom != zone && !dom.ends_with(&format!(".{}", zone)) {
            ctx.emit_fail(
                "pulumi",
                f,
                &format!("{} not under {}", dom, zone),
                "domain under zone",
                &format!(
                    "{} maps customDomain={} into cloudflareZone={}, but {} is not {} or a subdomain of it - the grey-cloud CNAME and the google-site-verification TXT would both be written to the WRONG zone",
                    f, dom, zone, dom, zone
                ),
                &format!("set cloudflareZone (and its pinned cloudflareZoneId) to the zone that actually contains {}", dom),
            );
            ok = false;
        }
    }

    if ok {
        ctx.emit_ok_uncounted(
            "pulumi",
            "customDomain",
            "under its zone",
            "under its zone",
            "every customDomain is a subdomain of the cloudflareZone declared beside it",
        );
    }
}

/// Collect Pulumi.*.yaml files (but not plain Pulumi.yaml) from a directory.
fn collect_pulumi_env_yamls(dir: &str, root: &str, out: &mut Vec<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };
    let root_prefix = if root.ends_with('/') {
        root.to_string()
    } else {
        format!("{}/", root)
    };
    for entry in entries.filter_map(|e| e.ok()) {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with("Pulumi.") && name.ends_with(".yaml") && name != "Pulumi.yaml" {
            let abs = entry.path().to_string_lossy().to_string();
            let rel = abs.strip_prefix(&root_prefix).unwrap_or(&abs).to_string();
            out.push(rel);
        }
    }
}

/// Extract a namespaced Pulumi config value like `<ns>:customDomain: <value>`.
/// The namespace prefix is unknown, so match any `<word>:<key>:` pattern.
fn extract_pulumi_config_value(content: &str, key: &str) -> Option<String> {
    let suffix = format!(":{}:", key);
    for line in content.lines() {
        let trimmed = line.trim_start();
        // Match pattern: <namespace>:<key>: <value>
        if let Some(pos) = trimmed.find(&suffix) {
            // Verify the part before the colon is a valid namespace (alphanumeric, _, ., -)
            let ns_part = &trimmed[..pos];
            if !ns_part.is_empty()
                && ns_part
                    .chars()
                    .all(|c| c.is_alphanumeric() || c == '_' || c == '.' || c == '-')
            {
                let after = &trimmed[pos + suffix.len()..].trim();
                let value = after.trim_matches('"').trim_matches('\'').to_string();
                if !value.is_empty() {
                    return Some(value);
                }
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// check_release_please_packages (group: pulumi)
// ---------------------------------------------------------------------------

pub fn check_release_please_packages(ctx: &Context) {
    let mut ok = true;
    let glob_dir = format!("{}/packages/pulumi/library/go/pkg", ctx.root);

    if let Ok(entries) = fs::read_dir(&glob_dir) {
        let mut sorted: Vec<fs::DirEntry> = entries.filter_map(|e| e.ok()).collect();
        sorted.sort_by_key(|e| e.file_name());

        for entry in sorted {
            if !entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                continue;
            }
            let pkg = entry.file_name().to_string_lossy().to_string();
            let dir_path = format!("packages/pulumi/library/go/pkg/{}", pkg);
            let cfg_path = format!("{}/{}/release-please-config.json", ctx.root, dir_path);
            if !Path::new(&cfg_path).exists() {
                continue;
            }
            let rel = format!("{}/release-please-config.json", dir_path);

            // Check manifest exists.
            let manifest_path = format!("{}/{}/.release-please-manifest.json", ctx.root, dir_path);
            if !Path::new(&manifest_path).exists() {
                ctx.emit_fail(
                    "pulumi",
                    &rel,
                    "no manifest",
                    "manifest present",
                    &format!(
                        "{} has release-please-config.json but no .release-please-manifest.json - the release job fails with \"Missing required manifest versions\" and this package never publishes",
                        dir_path
                    ),
                    &format!(
                        "add {}/.release-please-manifest.json containing {{\"{}\": \"0.0.0\"}}",
                        dir_path, dir_path
                    ),
                );
                ok = false;
            }

            // Check component matches convention.
            let want = format!("go-{}", pkg.replace('_', "-"));
            if let Ok(content) = fs::read_to_string(&cfg_path) {
                let got = extract_json_string_value(&content, "component");
                if let Some(got) = got {
                    if got != want {
                        ctx.emit_fail(
                            "pulumi",
                            &rel,
                            &format!("component: {}", got),
                            &want,
                            &format!(
                                "{} declares component '{}' but lives in {} - the component is the release TAG PREFIX, so this package would publish under another package's tag namespace (the signature of a config copied from a sibling)",
                                rel, got, dir_path
                            ),
                            &format!("set \"component\": \"{}\"", want),
                        );
                        ok = false;
                    }
                }
            }
        }
    }

    if ok {
        ctx.emit_ok_uncounted(
            "pulumi",
            "release-please",
            "config+manifest",
            "config+manifest",
            "every pulumi-library package has both release-please files and a matching component",
        );
    }
}

/// Extract a simple string value from JSON-like text: `"key": "value"`.
fn extract_json_string_value(content: &str, key: &str) -> Option<String> {
    let pattern = format!("\"{}\"", key);
    for line in content.lines() {
        if let Some(pos) = line.find(&pattern) {
            let after = &line[pos + pattern.len()..];
            // Find : then the value in quotes.
            if let Some(colon_pos) = after.find(':') {
                let after_colon = &after[colon_pos + 1..];
                if let Some(q1) = after_colon.find('"') {
                    let rest = &after_colon[q1 + 1..];
                    if let Some(q2) = rest.find('"') {
                        return Some(rest[..q2].to_string());
                    }
                }
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// check_release_infra_exclude (group: release)
// ---------------------------------------------------------------------------

pub fn check_release_infra_exclude(ctx: &Context) {
    let mut ok = true;
    let mut seen = 0;

    // Glob: $ROOT/*/release-please-config.json and $ROOT/apps/*/*/release-please-config.json
    let mut configs: Vec<String> = Vec::new();

    // Top-level: $ROOT/*/release-please-config.json
    if let Ok(entries) = fs::read_dir(&ctx.root) {
        for entry in entries.filter_map(|e| e.ok()) {
            if !entry.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                continue;
            }
            let name = entry.file_name().to_string_lossy().to_string();
            let cfg = format!("{}/{}/release-please-config.json", ctx.root, name);
            if Path::new(&cfg).is_file() {
                configs.push(format!("{}/release-please-config.json", name));
            }
        }
    }

    // apps/*/*/release-please-config.json
    let apps_dir = format!("{}/apps", ctx.root);
    if let Ok(cats) = fs::read_dir(&apps_dir) {
        for cat in cats.filter_map(|e| e.ok()) {
            if !cat.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                continue;
            }
            if let Ok(app_entries) = fs::read_dir(cat.path()) {
                for app in app_entries.filter_map(|e| e.ok()) {
                    if !app.file_type().map(|ft| ft.is_dir()).unwrap_or(false) {
                        continue;
                    }
                    let rel = format!(
                        "apps/{}/{}/release-please-config.json",
                        cat.file_name().to_string_lossy(),
                        app.file_name().to_string_lossy()
                    );
                    let abs = format!("{}/{}", ctx.root, rel);
                    if Path::new(&abs).is_file() {
                        configs.push(rel);
                    }
                }
            }
        }
    }

    configs.sort();

    for rel in &configs {
        let abs = format!("{}/{}", ctx.root, rel);
        if !Path::new(&abs).is_file() {
            continue;
        }
        seen += 1;

        // app = dirname of rel
        let app = match rel.rfind('/') {
            Some(pos) => &rel[..pos],
            None => continue,
        };

        let infra_dir = format!("{}/{}/infra", ctx.root, app);
        if !Path::new(&infra_dir).is_dir() {
            continue; // only co-located apps are at risk
        }

        // Check if the config excludes app/infra in exclude-paths.
        let content = match fs::read_to_string(&abs) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let excluded = check_release_infra_excluded(&content, app);

        if excluded {
            ctx.emit_ok_uncounted(
                "release",
                rel,
                &format!("{}/infra excluded", app),
                "excluded",
                "co-located infra is outside the app's release unit",
            );
        } else {
            ctx.emit_fail(
                "release",
                rel,
                &format!("{}/infra NOT excluded", app),
                "excluded",
                &format!(
                    "{} co-locates infra at {}/infra, so an infrastructure-only commit bumps the APP's version and triggers a deploy of unchanged code",
                    app, app
                ),
                &format!(
                    "add \"exclude-paths\": [\"{}/infra\"] to packages[\"{}\"] in {} (paths are repo-root-relative)",
                    app, app, rel
                ),
            );
            ok = false;
        }
    }

    if seen == 0 {
        ctx.emit_fail(
            "release",
            "*/release-please-config.json",
            "none found",
            "at least 1",
            &format!(
                "the release-unit guard found no release-please configs to inspect - it is running blind, not passing"
            ),
            &format!("check the glob resolves from $ROOT ({})", ctx.root),
        );
        ok = false;
    }
    let _ = ok; // suppress unused warning; the function's return is implicit
}

/// Check if a release-please-config.json excludes `app/infra` from the package.
/// Port of the Python: json.load(...)["packages"][app].get("exclude-paths", [])
fn check_release_infra_excluded(content: &str, app: &str) -> bool {
    // Line-based parsing: find `"exclude-paths"` and check if `"app/infra"` appears nearby.
    let target = format!("{}/infra", app);
    let target_quoted = format!("\"{}\"", target);

    // Simple approach: find the packages block for the app, then look for exclude-paths.
    let app_key = format!("\"{}\"", app);
    let mut in_app_block = false;
    let mut brace_depth = 0;

    for line in content.lines() {
        let trimmed = line.trim();
        if !in_app_block {
            if trimmed.contains(&app_key) && trimmed.contains(':') {
                in_app_block = true;
                brace_depth = 0;
                // Count braces on this line.
                for c in trimmed.chars() {
                    if c == '{' {
                        brace_depth += 1;
                    }
                    if c == '}' {
                        brace_depth -= 1;
                    }
                }
            }
            continue;
        }

        // In app block.
        for c in trimmed.chars() {
            if c == '{' {
                brace_depth += 1;
            }
            if c == '}' {
                brace_depth -= 1;
            }
        }

        if trimmed.contains(&target_quoted) && trimmed.contains("exclude-paths")
            || (in_app_block && trimmed.contains(&target_quoted))
        {
            return true;
        }

        if brace_depth <= 0 {
            in_app_block = false;
        }
    }
    false
}

// ---------------------------------------------------------------------------
// check_copybara_infra_exclude (group: copybara)
// ---------------------------------------------------------------------------

pub fn check_copybara_infra_exclude(ctx: &Context) {
    let cb_path = format!("{}/tools/copybara/copy.bara.sky", ctx.root);
    let cb_rel = "tools/copybara/copy.bara.sky";

    let content = match fs::read_to_string(&cb_path) {
        Ok(c) => c,
        Err(_) => return,
    };

    let mut ok = true;

    // 1. _monorepo_only() body contains component + "/infra/**"
    let monorepo_body = extract_function_body(&content, "def _monorepo_only(");
    if !monorepo_body.contains("component + \"/infra/**\"") {
        ctx.emit_fail(
            "copybara",
            cb_rel,
            "no infra exclude",
            "component + \"/infra/**\"",
            "_monorepo_only() no longer lists <component>/infra/** \u{2014} a mirrored app's co-located Pulumi stacks (internal GCP details) would be EXPORTED to its public mirror",
            "add 'component + \"/infra/**\"' back to the _monorepo_only() list in tools/copybara/copy.bara.sky",
        );
        ok = false;
    }

    // 2. origin_files excludes _monorepo_only_files
    if !content.contains("origin_files = glob([_subtree + \"/**\"], exclude = _monorepo_only_files")
    {
        ctx.emit_fail(
            "copybara",
            cb_rel,
            "export not excluding",
            "origin_files excludes _monorepo_only_files",
            "the export workflow's origin_files no longer excludes _monorepo_only_files \u{2014} BUILD files and <app>/infra/** would be exported to the public mirrors",
            "restore 'exclude = _monorepo_only_files + _origin_exclude' on the export origin_files glob",
        );
        ok = false;
    }

    // 3. destination_files excludes _monorepo_only_files
    if !content
        .contains("destination_files = glob([_subtree + \"/**\"], exclude = _monorepo_only_files)")
    {
        ctx.emit_fail(
            "copybara",
            cb_rel,
            "import not excluding",
            "destination_files excludes _monorepo_only_files",
            "the import workflows' destination_files no longer exclude _monorepo_only_files \u{2014} an import could delete the monorepo's <app>/infra/** (and BUILD files)",
            "restore 'exclude = _monorepo_only_files' on the import destination_files globs",
        );
        ok = false;
    }

    if !ok {
        return;
    }

    // 4. Enumerate mirrored subtrees with infra/ dirs.
    let subtrees = extract_copybara_subtrees(&content);
    let mut covered: Vec<String> = Vec::new();
    for st in &subtrees {
        let infra_dir = format!("{}/{}/infra", ctx.root, st);
        if Path::new(&infra_dir).is_dir() {
            covered.push(format!("{}/infra", st));
        }
    }

    if !covered.is_empty() {
        for c in &covered {
            ctx.emit_ok(
                "copybara",
                c,
                "monorepo-only",
                "never exported",
                "co-located per-app Pulumi stacks are excluded from the public-mirror export (structural _monorepo_only guarantee)",
            );
        }
    } else {
        ctx.emit_ok(
            "copybara",
            cb_rel,
            "structural exclude",
            "never exported",
            "<component>/infra/** is monorepo-only for every mirrored component (none on disk yet)",
        );
    }
}

/// Extract the body of a function starting at a given marker, up to the closing `]`.
fn extract_function_body(content: &str, marker: &str) -> String {
    let mut in_func = false;
    let mut body = String::new();
    for line in content.lines() {
        if line.starts_with(marker) || line.contains(marker) {
            in_func = true;
        }
        if in_func {
            body.push_str(line);
            body.push('\n');
            if line.trim_start().starts_with(']') {
                break;
            }
        }
    }
    body
}

/// Extract copybara subtrees: name (or subtree override) for each component.
fn extract_copybara_subtrees(content: &str) -> Vec<String> {
    let mut subtrees = BTreeSet::new();
    let mut name = String::new();
    let mut sub = String::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.contains("\"name\":") {
            let val = extract_starlark_string_value(trimmed);
            if let Some(v) = val {
                name = v;
                sub.clear();
            }
        } else if trimmed.contains("\"subtree\":") {
            let val = extract_starlark_string_value(trimmed);
            if let Some(v) = val {
                sub = v;
            }
        } else if trimmed.contains("\"standalone_rev_id\":") {
            let st = if sub.is_empty() { &name } else { &sub };
            if !st.is_empty() {
                subtrees.insert(st.clone());
            }
        }
    }

    subtrees.into_iter().collect()
}

/// Extract a simple string value from a starlark/JSON-like line.
fn extract_starlark_string_value(line: &str) -> Option<String> {
    // Find the first quoted value after the colon.
    let after_colon = line.find(':').map(|i| &line[i + 1..])?;
    let trimmed = after_colon.trim().trim_matches(',').trim();
    if trimmed.starts_with('"') {
        let inner = &trimmed[1..];
        if let Some(end) = inner.find('"') {
            return Some(inner[..end].to_string());
        }
    }
    None
}

// ---------------------------------------------------------------------------
// check_copybara_version_maps (group: copybara)
// ---------------------------------------------------------------------------

pub fn check_copybara_version_maps(ctx: &Context) {
    let cb_path = format!("{}/tools/copybara/copy.bara.sky", ctx.root);
    if !Path::new(&cb_path).is_file() {
        return;
    }

    let checker = format!("{}/tools/copybara/check-version-maps.sh", ctx.root);
    if !Path::new(&checker).is_file() {
        ctx.emit_fail(
            "copybara",
            "tools/copybara/check-version-maps.sh",
            "missing",
            "present",
            "the version-map checker is gone, so nothing verifies that the export maps still match this repo -- and a rule that skips when its checker is absent reports a clean run either way",
            "restore tools/copybara/check-version-maps.sh (see //tools/copybara:check-version-maps)",
        );
        return;
    }

    let output = Command::new("bash")
        .arg(&checker)
        .env("BUILD_WORKSPACE_DIRECTORY", &ctx.root)
        .output();

    let output = match output {
        Ok(o) => o,
        Err(_) => {
            ctx.emit_fail(
                "copybara",
                "tools/copybara/copy.bara.sky",
                "check-version-maps exited non-zero with errors",
                "clean check",
                "failed to run check-version-maps.sh",
                "run: bash tools/copybara/check-version-maps.sh",
            );
            return;
        }
    };

    if output.status.success() {
        return; // Clean check.
    }

    let vm_out = String::from_utf8_lossy(&output.stdout).to_string()
        + &String::from_utf8_lossy(&output.stderr);

    let mut emitted = false;
    for line in vm_out.lines() {
        if line.contains("map=")
            || line.contains("ABSENT from the map")
            || line.contains("does not exist")
            || line.contains("no manifest")
        {
            ctx.emit_fail(
                "copybara",
                "tools/copybara/copy.bara.sky",
                line.trim_start(),
                "matches the version in this repo",
                "an export version map is stale -- the mirror would reference a version that does not exist on the registry, and its build fails with ETARGET/no matching version",
                "run: bazel run //tools/copybara:check-version-maps  (it prints map vs repo for every entry)",
            );
            emitted = true;
        }
    }

    if !emitted {
        ctx.emit_fail(
            "copybara",
            "tools/copybara/copy.bara.sky",
            "check-version-maps exited non-zero with errors",
            "clean check",
            &vm_out,
            "run: bash tools/copybara/check-version-maps.sh",
        );
    }
}

// ---------------------------------------------------------------------------
// check_copybara_export_triggers (group: copybara)
// ---------------------------------------------------------------------------

pub fn check_copybara_export_triggers(ctx: &Context) {
    let wf_dir = format!("{}/.github/workflows", ctx.root);
    let mut cb_callers = 0u32;
    let mut cb_forced = 0u32;

    let mut wf_files: Vec<String> = Vec::new();
    if let Ok(entries) = fs::read_dir(&wf_dir) {
        for entry in entries.filter_map(|e| e.ok()) {
            let name = entry.file_name().to_string_lossy().to_string();
            if name.starts_with("copybara-export-") && name.ends_with(".yaml") {
                wf_files.push(name);
            }
        }
    }
    wf_files.sort();

    for wf_name in &wf_files {
        let wf_path = format!("{}/{}", wf_dir, wf_name);
        let content = match fs::read_to_string(&wf_path) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let rel = format!(".github/workflows/{}", wf_name);

        // Check paths: line includes copy.bara.sky.
        let paths_line = content
            .lines()
            .find(|l| l.trim_start().starts_with("paths: ["));
        if let Some(pl) = paths_line {
            if !pl.contains("tools/copybara/copy.bara.sky") {
                ctx.emit_fail(
                    "copybara",
                    &rel,
                    pl.trim(),
                    "paths includes \"tools/copybara/copy.bara.sky\"",
                    "this export only triggers on its own subtree, so a change to the shared export config never reaches the mirror -- the fix looks applied here and is never delivered there",
                    &format!("add \"tools/copybara/copy.bara.sky\" to the paths list in {}", rel),
                );
            }
        }

        cb_callers += 1;

        // Parse the copybara-options: input under the with: of the job that uses _copybara-export.yaml.
        let opts_line = extract_copybara_options(&content);

        if opts_line.is_none() {
            ctx.emit_fail(
                "copybara",
                &rel,
                "no copybara-options input found",
                "a copybara-options: line under the with: of the job that uses _copybara-export.yaml",
                "nothing to inspect, so this caller's push default is unverified: the rule cannot say whether a config-only change would reach the mirror",
                &format!("pass copybara-options under with: in {}, falling back to '--force --ignore-noop' (copy a sibling copybara-export-*.yaml)", rel),
            );
            continue;
        }

        let opts_line = opts_line.unwrap();
        let opts_value = opts_line
            .trim_start()
            .strip_prefix("copybara-options:")
            .unwrap_or(&opts_line)
            .trim();

        // Extract push default.
        let opts_default = if opts_value.contains("${{") {
            // Expression: extract the fallback `|| '...'` literal.
            extract_expression_fallback(opts_value)
        } else {
            // Plain value: strip surrounding quotes.
            opts_value.trim_matches('"').trim_matches('\'').to_string()
        };

        if format!(" {} ", opts_default).contains(" --force ") {
            cb_forced += 1;
        } else {
            ctx.emit_fail(
                "copybara",
                &rel,
                &format!("push default: '{}'", opts_default),
                "push default includes --force",
                "without --force a config-only change migrates NOTHING: copybara sees no source-revision change, logs 'No changes match any origin_files', and the run goes green while the mirror stays stale",
                &format!("set the fallback of copybara-options under with: to '--force --ignore-noop' in {}", rel),
            );
        }
    }

    if cb_callers > 0 && cb_forced == cb_callers {
        ctx.emit_ok_uncounted(
            "copybara",
            ".github/workflows/copybara-export-*.yaml",
            &format!("{} export callers", cb_callers),
            "push default includes --force",
            "read from the copybara-options input each caller passes to _copybara-export.yaml",
        );
    }
}

/// Extract the copybara-options: line from under the `with:` of the job that
/// `uses: ./_copybara-export.yaml`. Port of the awk logic in check.sh.
fn extract_copybara_options(content: &str) -> Option<String> {
    let lines: Vec<&str> = content.lines().collect();
    let mut in_job = false;
    let mut in_with = false;
    let mut job_indent = 0usize;

    for line in &lines {
        let stripped = line.trim();
        if stripped.is_empty() || stripped.starts_with('#') {
            continue;
        }
        let indent = line.len() - line.trim_start().len();

        if in_job && indent < job_indent {
            in_job = false;
            in_with = false;
        }
        if in_with && indent <= job_indent {
            in_with = false;
        }

        if stripped.starts_with("uses:") && stripped.contains("/_copybara-export.yaml") {
            in_job = true;
            job_indent = indent;
            continue;
        }

        if in_job && indent == job_indent && stripped == "with:" {
            in_with = true;
            continue;
        }

        if in_with && stripped.starts_with("copybara-options:") {
            return Some(stripped.to_string());
        }
    }
    None
}

/// Extract the fallback literal from a GitHub Actions expression like:
/// `${{ inputs.copybara-options || '--force --ignore-noop' }}`
fn extract_expression_fallback(expr: &str) -> String {
    // Find the pattern: || '<value>'
    if let Some(pos) = expr.find("|| '") {
        let rest = &expr[pos + 4..];
        if let Some(end) = rest.find('\'') {
            return rest[..end].to_string();
        }
    }
    // No fallback found.
    String::new()
}

// ---------------------------------------------------------------------------
// check_copybara_component_lists (group: copybara)
// ---------------------------------------------------------------------------

pub fn check_copybara_component_lists(ctx: &Context) {
    let cb_path = format!("{}/tools/copybara/copy.bara.sky", ctx.root);
    let content = match fs::read_to_string(&cb_path) {
        Ok(c) => c,
        Err(_) => return,
    };

    let smoke_path = format!(
        "{}/.github/workflows/copybara-config-smoketest.yaml",
        ctx.root
    );
    let notify_path = format!("{}/.github/workflows/notify-ci-issues.yaml", ctx.root);
    let smoke_rel = ".github/workflows/copybara-config-smoketest.yaml";
    let notify_rel = ".github/workflows/notify-ci-issues.yaml";

    // Extract repos: name (or repo) per component.
    let repos = extract_copybara_repos(&content);

    if repos.is_empty() {
        ctx.emit_fail(
            "copybara",
            "tools/copybara/copy.bara.sky",
            "no components parsed",
            "at least 1",
            "the component-list guard found no COMPONENTS entries - it is running blind, not passing",
            "check the COMPONENTS list format in tools/copybara/copy.bara.sky",
        );
        return;
    }

    // Check both files exist.
    for (path, frel) in [
        (smoke_path.as_str(), smoke_rel),
        (notify_path.as_str(), notify_rel),
    ] {
        if !Path::new(path).is_file() {
            ctx.emit_fail(
                "copybara",
                frel,
                "missing",
                "present",
                "the file that must list every mirrored component is gone, so nothing verifies the list - and a rule that skips when its input is absent reports a clean run either way",
                &format!("restore {}", frel),
            );
            return;
        }
    }

    let smoke_content = fs::read_to_string(&smoke_path).unwrap_or_default();
    let notify_content = fs::read_to_string(&notify_path).unwrap_or_default();

    let mut total = 0u32;
    let mut bad = false;

    for repo in &repos {
        total += 1;
        let wf = format!("export_{}", repo.replace('-', "_"));

        // Check smoke test: grep for the wf name in a `for wf in ...` line.
        let in_smoke = smoke_content.lines().any(|l| {
            if !l.contains("for wf in ") {
                return false;
            }
            // Check that the wf name appears as a standalone token.
            l.split_whitespace().any(|token| {
                token == wf || token == format!("{};", wf) || token.starts_with(&format!("{} ", wf))
            })
        });

        if !in_smoke {
            ctx.emit_fail(
                "copybara",
                smoke_rel,
                &format!("{} not listed", wf),
                "listed in the smoke test's expected migrations",
                &format!(
                    "the smoke test would still pass if '{}' disappeared from copy.bara.sky, so a mirror's export could be dropped with nothing red",
                    wf
                ),
                &format!("add {} to the 'for wf in' list in {}", wf, smoke_rel),
            );
            bad = true;
        }

        // Check notify: VitruvianSoftware/<repo> on its own line.
        let notify_pattern = format!("VitruvianSoftware/{}", repo);
        let in_notify = notify_content.lines().any(|l| {
            let trimmed = l.trim();
            trimmed == notify_pattern
        });

        if !in_notify {
            ctx.emit_fail(
                "copybara",
                notify_rel,
                &format!("VitruvianSoftware/{} not watched", repo),
                "listed under MIRRORS",
                &format!(
                    "a failing run on the '{}' mirror's main raises no alert, so it breaks unseen (4 of 8 mirrors were broken for weeks this way before #1851)",
                    repo
                ),
                &format!("add VitruvianSoftware/{} to the MIRRORS list in {}", repo, notify_rel),
            );
            bad = true;
        }
    }

    if !bad {
        ctx.emit_ok(
            "copybara",
            "tools/copybara/copy.bara.sky",
            &format!("{} components", total),
            "all smoke-tested and watched",
            "every mirrored component is in the smoke test's expected list and in notify-ci-issues' MIRRORS",
        );
    }
}

/// Extract repo names from COMPONENTS in copy.bara.sky.
/// Uses `"repo":` if set, else `"name":`. Each component has a `"standalone_rev_id":` marker.
fn extract_copybara_repos(content: &str) -> Vec<String> {
    let mut repos = BTreeSet::new();
    let mut name = String::new();
    let mut repo = String::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.contains("\"name\":") {
            if let Some(v) = extract_starlark_string_value(trimmed) {
                name = v;
                repo.clear();
            }
        } else if trimmed.contains("\"repo\":") {
            if let Some(v) = extract_starlark_string_value(trimmed) {
                repo = v;
            }
        } else if trimmed.contains("\"standalone_rev_id\":") {
            let r = if repo.is_empty() { &name } else { &repo };
            if !r.is_empty() {
                repos.insert(r.clone());
            }
        }
    }

    repos.into_iter().collect()
}
