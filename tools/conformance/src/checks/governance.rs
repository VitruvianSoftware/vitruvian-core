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

//! Governance conformance checks, ported from check.sh.

use std::collections::{HashMap, HashSet};
use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

use crate::Context;

// ---------------------------------------------------------------------------
// check_renovate_schedule (group "renovate", lines 3345-3384)
// ---------------------------------------------------------------------------

pub fn check_renovate_schedule(ctx: &Context) {
    let cfg = format!("{}/renovate.json5", ctx.root);
    let cfg_rel = "renovate.json5";

    if !Path::new(&cfg).is_file() {
        ctx.emit_fail(
            "renovate",
            cfg_rel,
            "missing",
            "present",
            "renovate.json5 is gone but .github/workflows/renovate.yaml still runs with RENOVATE_REQUIRE_CONFIG=required",
            "restore renovate.json5, or delete the renovate workflow with it",
        );
        return;
    }

    let text = match fs::read_to_string(&cfg) {
        Ok(t) => t,
        Err(_) => return,
    };

    // Strip // line comments, then find schedule keys.
    let mut sched_lines: Vec<String> = Vec::new();
    for line in text.lines() {
        let stripped = if let Some(pos) = line.find("//") {
            &line[..pos]
        } else {
            line
        };
        let trimmed = stripped.trim();
        if trimmed.starts_with("schedule") && trimmed.contains(':') {
            sched_lines.push(stripped.to_string());
        }
    }

    // Filter: allowed = nested (3+ leading spaces) whole-day cron: * * <nws> <nws> <nws>
    let mut sched_bad: Vec<&String> = Vec::new();
    for sl in &sched_lines {
        let leading_spaces = sl.len() - sl.trim_start().len();
        if leading_spaces >= 3 {
            // Check if it matches the allowed pattern: schedule : ["* * <day> <day> <day>"],?
            let content = sl.trim();
            // After "schedule" and ":" find the value part
            if let Some(colon_pos) = content.find(':') {
                let value = content[colon_pos + 1..].trim();
                if is_whole_day_cron(value) {
                    continue;
                }
            }
        }
        sched_bad.push(sl);
    }

    if !sched_lines.is_empty() && sched_bad.is_empty() {
        ctx.emit_ok(
            "renovate",
            cfg_rel,
            "whole-day only",
            "no schedule window",
            "the only schedule is a per-package whole-day cron \u{2014} too wide for a late-delivered run to miss",
        );
    } else if !sched_bad.is_empty() {
        ctx.emit_fail(
            "renovate",
            cfg_rel,
            "schedule:",
            "no schedule",
            "a config-side time window silently no-ops every run GitHub delivers late (30-180min drift is normal) \u{2014} the lane stays green and opens nothing",
            "delete the schedule/timezone keys (a packageRule may keep a whole-day cron like [\"* * * * 1\"]); .github/workflows/renovate.yaml's cron is the only cadence control",
        );
    } else {
        ctx.emit_ok(
            "renovate",
            cfg_rel,
            "no schedule",
            "no schedule",
            "cadence lives only in the workflow cron \u{2014} a late-delivered run still does its work",
        );
    }
}

/// Check if a schedule value matches the allowed whole-day cron pattern:
/// `["* * <nws> <nws> <nws>"],?`
fn is_whole_day_cron(value: &str) -> bool {
    let v = value.trim().trim_end_matches(',').trim();
    // Must be [...] containing a single "* * X X X" entry
    if !v.starts_with('[') || !v.ends_with(']') {
        return false;
    }
    let inner = v[1..v.len() - 1].trim();
    // Must be a single double-quoted string
    if !inner.starts_with('"') || !inner.ends_with('"') {
        return false;
    }
    let cron = &inner[1..inner.len() - 1];
    let parts: Vec<&str> = cron.split_whitespace().collect();
    // Must be 5 fields: * * <non-empty> <non-empty> <non-empty>
    parts.len() == 5 && parts[0] == "*" && parts[1] == "*"
}

// ---------------------------------------------------------------------------
// check_chart_owned_crds (group "crdown", lines 3153-3227)
// ---------------------------------------------------------------------------

pub fn check_chart_owned_crds(ctx: &Context) {
    let rules: &[(&str, &str, &str, &str)] = &[
        (
            "gitops/argocd/platform/external-secrets/applicationset.yaml",
            "-",
            "installCRDs",
            "true",
        ),
        (
            "gitops/argocd/platform/cert-manager/applicationset.yaml",
            "crds",
            "enabled",
            "true",
        ),
        (
            "gitops/argocd/platform/cnpg/applicationset-operator.yaml",
            "crds",
            "create",
            "true",
        ),
        (
            "gitops/argocd/platform/cnpg/applicationset-plugin-barman-cloud.yaml",
            "crds",
            "create",
            "true",
        ),
    ];

    for &(rel, parent, key, want) in rules {
        let path = format!("{}/{}", ctx.root, rel);
        let label = if parent == "-" {
            key.to_string()
        } else {
            format!("{}.{}", parent, key)
        };

        if !Path::new(&path).is_file() {
            ctx.emit_fail(
                "crdown",
                rel,
                "missing",
                &format!("{}: {}", key, want),
                "CRD install switched off: Argo CD could prune the CRDs, deleting every object of their kinds",
                &format!("set {}: {} again; to retire a CRD, remove its objects first, deliberately", key, want),
            );
            continue;
        }

        let text = match fs::read_to_string(&path) {
            Ok(t) => t,
            Err(_) => continue,
        };

        // Strip comments from lines.
        let lines: Vec<String> = text
            .lines()
            .map(|l| l.split('#').next().unwrap_or("").trim_end().to_string())
            .collect();

        let found = find_yaml_value(&lines, parent, key);

        let got_str = format!("{}: {}", label, found.as_deref().unwrap_or("absent"));
        let want_str = format!("{}: {}", label, want);

        if found.as_deref() == Some(want) {
            ctx.emit_ok(
                "crdown",
                rel,
                &got_str,
                &want_str,
                "chart installs and upgrades its own CRDs",
            );
        } else {
            ctx.emit_fail(
                "crdown",
                rel,
                &got_str,
                &want_str,
                "CRD install switched off: Argo CD could prune the CRDs, deleting every object of their kinds",
                &format!("set {} again; to retire a CRD, remove its objects first, deliberately", want_str),
            );
        }
    }
}

/// Find a YAML key's value, optionally under a parent key. Line-based parsing.
fn find_yaml_value(lines: &[String], parent: &str, key: &str) -> Option<String> {
    let key_prefix = format!("{}:", key);
    if parent == "-" {
        // Top-level: find key at any indentation.
        for l in lines {
            let trimmed = l.trim();
            if trimmed.is_empty() {
                continue;
            }
            if trimmed.starts_with(&key_prefix) {
                return Some(trimmed.split_once(':')?.1.trim().to_string());
            }
        }
        return None;
    }

    // Find parent key, then look for child key underneath.
    let parent_str = format!("{}:", parent);
    for (i, l) in lines.iter().enumerate() {
        let trimmed = l.trim();
        if trimmed.is_empty() {
            continue;
        }
        if trimmed == parent_str {
            let ind = l.len() - l.trim_start().len();
            for m in &lines[i + 1..] {
                let mt = m.trim();
                if mt.is_empty() {
                    continue;
                }
                let mind = m.len() - m.trim_start().len();
                if mind <= ind {
                    break;
                }
                if mt.starts_with(&key_prefix) {
                    return Some(mt.split_once(':')?.1.trim().to_string());
                }
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// check_project_kind_allowlist (group "projkind", lines 3229-3343)
// ---------------------------------------------------------------------------

pub fn check_project_kind_allowlist(ctx: &Context) {
    let proj_dir = format!("{}/gitops/argocd/projects", ctx.root);
    let app_dir = format!("{}/gitops/argocd/applications", ctx.root);

    if !Path::new(&proj_dir).is_dir() || !Path::new(&app_dir).is_dir() {
        return;
    }

    // Parse scoped projects: name -> set of (group, kind). ("*","*") means allow all.
    let mut projects: HashMap<String, HashSet<(String, String)>> = HashMap::new();

    if let Ok(entries) = fs::read_dir(&proj_dir) {
        let mut files: Vec<_> = entries.filter_map(|e| e.ok()).collect();
        files.sort_by_key(|e| e.file_name());
        for entry in files {
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            let text = match fs::read_to_string(&path) {
                Ok(t) => t,
                Err(_) => continue,
            };
            let lines: Vec<&str> = text.lines().collect();
            let mut name: Option<String> = None;
            let mut allowed: Option<HashSet<(String, String)>> = None;
            let mut in_list = false;
            let mut list_ind: usize = 0;
            let mut group = String::new();

            for l in &lines {
                let s = l.trim();
                if s.is_empty() {
                    continue;
                }
                let ind = l.len() - l.trim_start().len();
                if s.starts_with("name:") && name.is_none() && ind == 2 {
                    name = Some(s[5..].trim().to_string());
                }
                if s == "namespaceResourceWhitelist:" {
                    in_list = true;
                    allowed = Some(HashSet::new());
                    list_ind = ind;
                    continue;
                }
                if in_list {
                    if ind <= list_ind && !s.starts_with('-') {
                        in_list = false;
                        continue;
                    }
                    // group: line
                    let st = s.trim_start_matches('-').trim();
                    if st.starts_with("group:") {
                        let v = st[6..].trim().trim_matches(|c| c == '\'' || c == '"');
                        group = v.to_string();
                        continue;
                    }
                    if st.starts_with("kind:") {
                        let kind = st[5..].trim().to_string();
                        if let Some(ref mut set) = allowed {
                            set.insert((group.clone(), kind));
                        }
                    }
                }
            }

            if let (Some(n), Some(a)) = (name, allowed) {
                if !a.contains(&("*".to_string(), "*".to_string())) {
                    projects.insert(n, a);
                }
            }
        }
    }

    // Parse application files.
    let app_entries = match fs::read_dir(&app_dir) {
        Ok(e) => {
            let mut v: Vec<_> = e.filter_map(|e| e.ok()).collect();
            v.sort_by_key(|e| e.file_name());
            v
        }
        Err(_) => return,
    };

    for entry in app_entries {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let text = match fs::read_to_string(&path) {
            Ok(t) => t,
            Err(_) => continue,
        };

        let lines: Vec<&str> = text
            .lines()
            .map(|l| l.split('#').next().unwrap_or("").trim_end())
            .collect();

        let proj = lines.iter().find_map(|l| {
            let s = l.trim();
            if s.starts_with("project:") {
                Some(s[8..].trim().to_string())
            } else {
                None
            }
        });

        let proj = match proj {
            Some(p) if projects.contains_key(&p) => p,
            _ => continue,
        };

        let paths: Vec<String> = lines
            .iter()
            .filter_map(|l| {
                let s = l.trim();
                if s.starts_with("path:") {
                    Some(s[5..].trim().to_string())
                } else {
                    None
                }
            })
            .collect();

        // Collect exclude patterns.
        let excludes: Vec<String> = lines
            .iter()
            .filter_map(|l| {
                let s = l.trim();
                if s.starts_with("exclude:") {
                    let val = s[8..].trim().trim_matches(|c| c == '\'' || c == '"');
                    Some(expand_braces(val))
                } else {
                    None
                }
            })
            .flatten()
            .collect();

        for p in &paths {
            let d = format!("{}/{}", ctx.root, p);
            if !Path::new(&d).is_dir() {
                continue;
            }
            // Skip chart directories.
            if Path::new(&format!("{}/Chart.yaml", d)).is_file() {
                continue;
            }

            let manifest_files =
                kustomize_resources(&d).unwrap_or_else(|| walk_yaml_files(&d, &excludes));

            for file_path in &manifest_files {
                let rel = strip_prefix(file_path, &ctx.root);
                let file_text = match fs::read_to_string(file_path) {
                    Ok(t) => t,
                    Err(_) => continue,
                };

                let mut api: Option<String> = None;
                for line in file_text.lines() {
                    let l = line.split('#').next().unwrap_or("").trim_end();
                    if l.starts_with("---") {
                        api = None;
                    } else if l.starts_with("apiVersion:") {
                        api = Some(l[11..].trim().to_string());
                    } else if l.starts_with("kind:") {
                        if let Some(ref a) = api {
                            let kind = l[5..].trim().to_string();
                            let g = if a.contains('/') {
                                a.split('/').next().unwrap_or("").to_string()
                            } else {
                                String::new()
                            };
                            let allowed = projects.get(&proj).unwrap();
                            let ok = allowed.contains(&(g.clone(), kind.clone()))
                                || allowed.contains(&(g.clone(), "*".to_string()));
                            if ok {
                                ctx.inc_ok();
                            } else {
                                let group_display =
                                    if g.is_empty() { "core".to_string() } else { g };
                                ctx.emit_fail(
                                    "projkind",
                                    &rel,
                                    &format!("{}/{}", group_display, kind),
                                    &format!("listed in {}", proj),
                                    "kind not allowed by the app's AppProject: the whole sync fails",
                                    &format!(
                                        "add it to namespaceResourceWhitelist in gitops/argocd/projects/{}.yaml",
                                        proj
                                    ),
                                );
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Expand a simple brace pattern like `{a,b}` into alternatives.
fn expand_braces(pat: &str) -> Vec<String> {
    if let Some(open) = pat.find('{') {
        if let Some(close) = pat[open..].find('}') {
            let prefix = &pat[..open];
            let suffix = &pat[open + close + 1..];
            let inner = &pat[open + 1..open + close];
            return inner
                .split(',')
                .map(|p| format!("{}{}{}", prefix, p, suffix))
                .collect();
        }
    }
    vec![pat.to_string()]
}

/// Read kustomization resources from a directory, returning file paths.
fn kustomize_resources(dir: &str) -> Option<Vec<String>> {
    for name in &["kustomization.yaml", "kustomization.yml", "Kustomization"] {
        let kpath = format!("{}/{}", dir, name);
        if !Path::new(&kpath).is_file() {
            continue;
        }
        let text = match fs::read_to_string(&kpath) {
            Ok(t) => t,
            Err(_) => continue,
        };

        let mut listed = Vec::new();
        let mut in_resources = false;
        for line in text.lines() {
            let l = line.split('#').next().unwrap_or("").trim_end();
            let trimmed = l.trim();
            if trimmed.is_empty() {
                continue;
            }
            // A top-level key (no leading space, no leading dash).
            if !l.starts_with(char::is_whitespace) && !l.starts_with('-') {
                in_resources = trimmed == "resources:";
                continue;
            }
            if in_resources {
                if let Some(rest) = trimmed.strip_prefix('-') {
                    let val = rest.trim().trim_matches(|c| c == '\'' || c == '"');
                    let full = format!("{}/{}", dir, val);
                    if Path::new(&full).is_file() {
                        listed.push(full);
                    }
                }
            }
        }
        return Some(listed);
    }
    None
}

/// Walk a directory for .yaml/.yml files, excluding matches.
fn walk_yaml_files(dir: &str, excludes: &[String]) -> Vec<String> {
    let mut result = Vec::new();
    walk_yaml_recursive(Path::new(dir), excludes, &mut result);
    result.sort();
    result
}

fn walk_yaml_recursive(dir: &Path, excludes: &[String], out: &mut Vec<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    let mut sorted: Vec<_> = entries.filter_map(|e| e.ok()).collect();
    sorted.sort_by_key(|e| e.file_name());
    for entry in sorted {
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if ft.is_dir() {
            walk_yaml_recursive(&entry.path(), excludes, out);
        } else if ft.is_file() {
            let name = entry.file_name().to_string_lossy().to_string();
            if (name.ends_with(".yaml") || name.ends_with(".yml"))
                && !excludes.iter().any(|e| fnmatch_simple(e, &name))
            {
                out.push(entry.path().to_string_lossy().to_string());
            }
        }
    }
}

/// Simple fnmatch: only supports `*` wildcard.
fn fnmatch_simple(pattern: &str, name: &str) -> bool {
    if pattern == "*" {
        return true;
    }
    if let Some(suffix) = pattern.strip_prefix('*') {
        return name.ends_with(suffix);
    }
    if let Some(prefix) = pattern.strip_suffix('*') {
        return name.starts_with(prefix);
    }
    pattern == name
}

fn strip_prefix(path: &str, root: &str) -> String {
    let prefix = if root.ends_with('/') {
        root.to_string()
    } else {
        format!("{}/", root)
    };
    path.strip_prefix(&prefix).unwrap_or(path).to_string()
}

// ---------------------------------------------------------------------------
// check_oci_base_registry (group "ocibase", lines 4197-4247)
// ---------------------------------------------------------------------------

pub fn check_oci_base_registry(ctx: &Context) {
    let module_path = format!("{}/MODULE.bazel", ctx.root);
    if !Path::new(&module_path).is_file() {
        return;
    }
    let text = match fs::read_to_string(&module_path) {
        Ok(t) => t,
        Err(_) => return,
    };

    // Strip comment lines.
    let live: String = text
        .lines()
        .filter(|l| !l.trim_start().starts_with('#'))
        .collect::<Vec<&str>>()
        .join("\n");

    let mut total: u32 = 0;
    let mut has_failures = false;

    // Find all oci.pull(...) blocks. Scan for "oci.pull(" and find matching ")".
    let bytes = live.as_bytes();
    let needle = b"oci.pull(";
    let mut pos = 0;
    while pos < bytes.len() {
        if let Some(start) = find_bytes(&bytes[pos..], needle) {
            let block_start = pos + start + needle.len();
            // Find the closing ")" that starts at column 0 on a new line.
            let block_end = find_closing_paren(&live, block_start);
            let block = &live[block_start..block_end];

            let image = extract_attr(block, "image");
            let name = extract_attr(block, "name");

            if let Some(ref img) = image {
                total += 1;
                if is_docker_hub(img) {
                    has_failures = true;
                    let name_str = name.as_deref().unwrap_or("?");
                    ctx.emit_fail(
                        "ocibase",
                        "MODULE.bazel",
                        img,
                        "not Docker Hub",
                        &format!("oci.pull {} is pulled from Docker Hub", name_str),
                        "pull the same digest from mirror.gcr.io/library/<image> or another registry that carries it",
                    );
                }
            }

            pos = block_end;
        } else {
            break;
        }
    }

    if !has_failures {
        ctx.emit_ok(
            "ocibase",
            "MODULE.bazel",
            &format!("{} image(s)", total),
            "not Docker Hub",
            "no base image is pulled from Docker Hub",
        );
    }
}

fn find_bytes(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn find_closing_paren(text: &str, from: usize) -> usize {
    // Find a ")" preceded by a newline (at start of a line).
    let bytes = text.as_bytes();
    for i in from..bytes.len() {
        if bytes[i] == b')' && (i == 0 || bytes[i - 1] == b'\n') {
            return i;
        }
    }
    text.len()
}

fn extract_attr(block: &str, attr: &str) -> Option<String> {
    let prefix = format!("{} = \"", attr);
    let prefix2 = format!("{}= \"", attr);
    for line in block.lines() {
        let trimmed = line.trim();
        for p in &[prefix.as_str(), prefix2.as_str()] {
            if let Some(rest) = trimmed.strip_prefix(p) {
                if let Some(end) = rest.find('"') {
                    return Some(rest[..end].to_string());
                }
            }
        }
    }
    None
}

fn is_docker_hub(image: &str) -> bool {
    if !image.contains('/') {
        // No slash: bare name like "ubuntu" -> Docker Hub.
        return true;
    }
    let first = image.split('/').next().unwrap_or("");
    let has_host = first.contains('.') || first.contains(':') || first == "localhost";
    if !has_host {
        return true;
    }
    matches!(
        first,
        "docker.io" | "index.docker.io" | "registry-1.docker.io"
    )
}

// ---------------------------------------------------------------------------
// check_backstage_prometheus_graphs (group "promgraph", lines 4267-4327)
// ---------------------------------------------------------------------------

pub fn check_backstage_prometheus_graphs(ctx: &Context) {
    let rules_path = format!(
        "{}/gitops/argocd/platform/prometheus/applicationset.yaml",
        ctx.root
    );

    let mut recorded: HashSet<String> = HashSet::new();
    if let Ok(text) = fs::read_to_string(&rules_path) {
        for line in text.lines() {
            let trimmed = line.trim();
            // Match: record: <name> or - record: <name>
            let rest = if let Some(r) = trimmed.strip_prefix("- record:") {
                Some(r)
            } else if let Some(r) = trimmed.strip_prefix("record:") {
                Some(r)
            } else {
                None
            };
            if let Some(r) = rest {
                let name = r.trim().trim_matches(|c| c == '\'' || c == '"');
                if !name.is_empty() && !name.starts_with('#') {
                    let name = name.split_whitespace().next().unwrap_or("");
                    let name = name.split('#').next().unwrap_or("").trim();
                    if !name.is_empty() {
                        recorded.insert(name.to_string());
                    }
                }
            }
        }
    }

    let skip = ["node_modules", ".git", "vendor", "dist", ".claude"];
    let mut total: u32 = 0;
    let mut has_failures = false;

    walk_catalog_files(&ctx.root, &skip, |path, rel| {
        let text = match fs::read_to_string(path) {
            Ok(t) => t,
            Err(_) => return,
        };
        for line in text.lines() {
            let trimmed = line.trim();
            if !trimmed.starts_with("prometheus.io/rule:") {
                continue;
            }
            let value = trimmed["prometheus.io/rule:".len()..]
                .trim()
                .trim_matches(|c| c == '\'' || c == '"');
            // Strip trailing comments.
            let value = value.split('#').next().unwrap_or("").trim();
            for entry in value.split(',') {
                let query = entry.split('|').next().unwrap_or("").trim();
                total += 1;
                if !is_valid_metric_name(query) {
                    has_failures = true;
                    let display = if query.is_empty() { "(empty)" } else { query };
                    ctx.emit_fail(
                        "promgraph",
                        rel,
                        display,
                        "a recording rule",
                        &format!("prometheus.io/rule: not a bare metric name"),
                        "name a rule from the backstage-graphs group in gitops/argocd/platform/prometheus/applicationset.yaml, or add one there",
                    );
                } else if !recorded.contains(query) {
                    has_failures = true;
                    ctx.emit_fail(
                        "promgraph",
                        rel,
                        query,
                        "a recording rule",
                        "prometheus.io/rule: no recording rule with this name",
                        "name a rule from the backstage-graphs group in gitops/argocd/platform/prometheus/applicationset.yaml, or add one there",
                    );
                }
            }
        }
    });

    if total == 0 {
        return;
    }
    if !has_failures {
        ctx.emit_ok(
            "promgraph",
            "catalog-info.yaml",
            &format!("{} graph(s)", total),
            "a recording rule",
            "every graph names a metric Prometheus records",
        );
    }
}

fn is_valid_metric_name(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let mut chars = s.chars();
    let first = chars.next().unwrap();
    if !first.is_ascii_alphabetic() && first != '_' && first != ':' {
        return false;
    }
    chars.all(|c| c.is_ascii_alphanumeric() || c == '_' || c == ':')
}

/// Walk tree for catalog-info.yaml, pruning skip dirs.
fn walk_catalog_files(root: &str, skip: &[&str], mut callback: impl FnMut(&str, &str)) {
    walk_catalog_recursive(Path::new(root), root, skip, &mut callback);
}

fn walk_catalog_recursive(
    dir: &Path,
    root: &str,
    skip: &[&str],
    callback: &mut impl FnMut(&str, &str),
) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    let mut sorted: Vec<_> = entries.filter_map(|e| e.ok()).collect();
    sorted.sort_by_key(|e| e.file_name());

    let mut has_catalog = false;
    for entry in &sorted {
        if entry.file_name() == "catalog-info.yaml" {
            has_catalog = true;
            break;
        }
    }

    if has_catalog {
        let path = dir.join("catalog-info.yaml");
        let path_str = path.to_string_lossy().to_string();
        let rel = strip_prefix(&path_str, root);
        callback(&path_str, &rel);
    }

    for entry in sorted {
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if ft.is_dir() {
            let name = entry.file_name().to_string_lossy().to_string();
            if skip.contains(&name.as_str()) || name.starts_with("bazel-") {
                continue;
            }
            walk_catalog_recursive(&entry.path(), root, skip, callback);
        }
    }
}

// ---------------------------------------------------------------------------
// check_backstage_prometheus_alerts (group "promalert", lines 4349-4448)
// ---------------------------------------------------------------------------

pub fn check_backstage_prometheus_alerts(ctx: &Context) {
    let rules_path = format!(
        "{}/gitops/argocd/platform/prometheus/applicationset.yaml",
        ctx.root
    );

    let mut alerts: HashSet<String> = HashSet::new();
    if let Ok(text) = fs::read_to_string(&rules_path) {
        for line in text.lines() {
            let trimmed = line.trim();
            let rest = if let Some(r) = trimmed.strip_prefix("- alert:") {
                Some(r)
            } else if let Some(r) = trimmed.strip_prefix("alert:") {
                Some(r)
            } else {
                None
            };
            if let Some(r) = rest {
                let name = r
                    .trim()
                    .trim_matches(|c| c == '\'' || c == '"')
                    .split_whitespace()
                    .next()
                    .unwrap_or("")
                    .split('#')
                    .next()
                    .unwrap_or("")
                    .trim();
                if !name.is_empty() {
                    alerts.insert(name.to_string());
                }
            }
        }
    }

    let skip = ["node_modules", ".git", "vendor", "dist", ".claude"];
    let mut total: u32 = 0;
    let mut has_failures = false;

    walk_catalog_files(&ctx.root, &skip, |path, rel| {
        let text = match fs::read_to_string(path) {
            Ok(t) => t,
            Err(_) => return,
        };

        // Split on --- for multi-document.
        let mut docs: Vec<Vec<&str>> = Vec::new();
        let mut cur: Vec<&str> = Vec::new();
        for line in text.lines() {
            if line.trim() == "---" {
                docs.push(cur);
                cur = Vec::new();
            } else {
                cur.push(line);
            }
        }
        docs.push(cur);

        for doc in &docs {
            let alert_val = annotation(doc, "prometheus.io/alert");
            let labels_val = annotation(doc, "prometheus.io/labels");
            let ns_val = annotation(doc, "backstage.io/kubernetes-namespace");
            let name = entity_name(doc);

            if alert_val.is_none() {
                if labels_val.is_some() {
                    has_failures = true;
                    let lv = labels_val.as_deref().unwrap_or("(empty)");
                    ctx.emit_fail(
                        "promalert",
                        rel,
                        &format!("{}: {}", name, lv),
                        "namespace=<own namespace>",
                        "prometheus.io/labels without prometheus.io/alert, so nothing reads it",
                        "set prometheus.io/labels: namespace=<the entity's backstage.io/kubernetes-namespace> beside prometheus.io/alert, name only alert rules from gitops/argocd/platform/prometheus/applicationset.yaml, or remove both annotations",
                    );
                }
                continue;
            }

            total += 1;
            let alert = alert_val.as_deref().unwrap_or("");

            if ns_val.is_none() {
                has_failures = true;
                let lbl_display = labels_val.as_deref().unwrap_or("(no labels)");
                ctx.emit_fail(
                    "promalert",
                    rel,
                    &format!("{}: {}", name, lbl_display),
                    "namespace=<own namespace>",
                    "prometheus.io/alert on an entity with no backstage.io/kubernetes-namespace to scope it to",
                    "set prometheus.io/labels: namespace=<the entity's backstage.io/kubernetes-namespace> beside prometheus.io/alert, name only alert rules from gitops/argocd/platform/prometheus/applicationset.yaml, or remove both annotations",
                );
            } else if labels_val.is_none() {
                has_failures = true;
                let ns = ns_val.as_deref().unwrap_or("");
                ctx.emit_fail(
                    "promalert",
                    rel,
                    &format!("{}: (no labels)", name),
                    "namespace=<own namespace>",
                    &format!("prometheus.io/alert without prometheus.io/labels lists every alert in the cluster; want namespace={}", ns),
                    "set prometheus.io/labels: namespace=<the entity's backstage.io/kubernetes-namespace> beside prometheus.io/alert, name only alert rules from gitops/argocd/platform/prometheus/applicationset.yaml, or remove both annotations",
                );
            } else {
                let ns = ns_val.as_deref().unwrap_or("");
                let lbl = labels_val.as_deref().unwrap_or("");
                let expected = format!("namespace={}", ns);
                if lbl != expected {
                    has_failures = true;
                    let display = if lbl.is_empty() { "(empty)" } else { lbl };
                    ctx.emit_fail(
                        "promalert",
                        rel,
                        &format!("{}: {}", name, display),
                        "namespace=<own namespace>",
                        &format!(
                            "prometheus.io/labels is not exactly namespace={}, this entity's own namespace",
                            ns
                        ),
                        "set prometheus.io/labels: namespace=<the entity's backstage.io/kubernetes-namespace> beside prometheus.io/alert, name only alert rules from gitops/argocd/platform/prometheus/applicationset.yaml, or remove both annotations",
                    );
                }
            }

            // Check named alerts exist.
            if alert != "all" {
                for wanted in alert.split(',') {
                    let wanted = wanted.trim();
                    if !wanted.is_empty() && !alerts.contains(wanted) {
                        has_failures = true;
                        let display = if wanted.is_empty() {
                            "(empty)".to_string()
                        } else {
                            wanted.to_string()
                        };
                        ctx.emit_fail(
                            "promalert",
                            rel,
                            &format!("{}: {}", name, display),
                            "namespace=<own namespace>",
                            "prometheus.io/alert names an alert that is no alert rule",
                            "set prometheus.io/labels: namespace=<the entity's backstage.io/kubernetes-namespace> beside prometheus.io/alert, name only alert rules from gitops/argocd/platform/prometheus/applicationset.yaml, or remove both annotations",
                        );
                    }
                }
            }
        }
    });

    if total == 0 {
        return;
    }
    if !has_failures {
        ctx.emit_ok(
            "promalert",
            "catalog-info.yaml",
            &format!("{} alert table(s)", total),
            "namespace=<own namespace>",
            "every alerts table is scoped to its component's namespace",
        );
    }
}

fn annotation(doc: &[&str], key: &str) -> Option<String> {
    let prefix = format!("{}:", key);
    for line in doc {
        let trimmed = line.trim();
        if trimmed.starts_with(&prefix) {
            let val = trimmed[prefix.len()..].trim();
            // Strip trailing comment.
            let val = val.split('#').next().unwrap_or("").trim();
            let val = val.trim_matches(|c| c == '\'' || c == '"');
            return Some(val.to_string());
        }
    }
    None
}

fn entity_name(doc: &[&str]) -> String {
    for line in doc {
        let trimmed = line.trim();
        // Match "  name: <value>" at 2 spaces of indentation.
        if line.starts_with("  name:") && !line.starts_with("   ") {
            let val = trimmed
                .strip_prefix("name:")
                .unwrap_or("")
                .trim()
                .trim_matches(|c| c == '\'' || c == '"')
                .split_whitespace()
                .next()
                .unwrap_or("")
                .split('#')
                .next()
                .unwrap_or("")
                .trim();
            if !val.is_empty() {
                return val.to_string();
            }
        }
    }
    "(unnamed)".to_string()
}

// ---------------------------------------------------------------------------
// check_naming_conventions (group "naming", lines 3391-3407)
// ---------------------------------------------------------------------------

pub fn check_naming_conventions(ctx: &Context) {
    let runner = format!("{}/tools/lint-naming/test_runner.py", ctx.root);
    if !Path::new(&runner).is_file() {
        return;
    }

    let output = Command::new("python3").arg(&runner).output();

    match output {
        Ok(out) if out.status.success() => {
            ctx.emit_ok(
                "naming",
                "monorepo",
                "153/153",
                "153/153",
                "all naming rules, boundary constraints, and pairwise interactions conform to standard",
            );
        }
        _ => {
            ctx.emit_fail(
                "naming",
                "monorepo",
                "failed",
                "153/153",
                "naming convention verification failed",
                "run 'python3 tools/lint-naming/test_runner.py --verbose' to inspect",
            );
        }
    }
}

// ---------------------------------------------------------------------------
// check_owners (group "owners", lines 3020-3089)
// ---------------------------------------------------------------------------

const OWNERS_BIN_REL: &str = "tools/owners/owners";

pub fn check_owners(ctx: &Context) {
    let mut has_root_owners = false;
    for name in &["OWNERS", "OWNERS.yaml", "OWNERS.yml"] {
        if Path::new(&format!("{}/{}", ctx.root, name)).is_file() {
            has_root_owners = true;
            break;
        }
    }

    let codeowners = format!("{}/.github/CODEOWNERS", ctx.root);
    let generated = if let Ok(text) = fs::read_to_string(&codeowners) {
        text.contains("generated by //tools/owners")
    } else {
        false
    };

    // Check required subtrees.
    let required = [
        "apps",
        "apps/suites/tabula",
        "packages/design-system",
        "infrastructure",
        "gitops",
        "tools",
    ];
    let mut missing = Vec::new();
    for req in &required {
        let dir = format!("{}/{}", ctx.root, req);
        if Path::new(&dir).is_dir() {
            let has_owners = ["OWNERS", "OWNERS.yaml", "OWNERS.yml"]
                .iter()
                .any(|n| Path::new(&format!("{}/{}", dir, n)).is_file());
            if !has_owners {
                missing.push(req.to_string());
            }
        }
    }

    if !missing.is_empty() {
        ctx.emit_fail(
            "owners",
            "OWNERS",
            "missing coverage",
            &format!(" {}", missing.join(" ")),
            "missing OWNERS declarations in required subtree(s)",
            "add OWNERS file in each missing subtree",
        );
    } else {
        ctx.emit_ok(
            "owners",
            "OWNERS",
            "coverage",
            "100%",
            "all required subtrees have declared OWNERS",
        );
    }

    if !has_root_owners && !generated {
        return;
    }

    // Find owners binary.
    let bin = find_owners_bin(&ctx.start_pwd);
    let bin = match bin {
        Some(b) => b,
        None => {
            ctx.emit_fail(
                "owners",
                ".github/CODEOWNERS",
                "not checked",
                "compiled",
                "the //tools/owners generator was not found, so CODEOWNERS could not be compared with the OWNERS files",
                "run this check as 'bazel run //tools/conformance:check' (the generator ships in its runfiles)",
            );
            return;
        }
    };

    let output = Command::new(&bin)
        .arg("--root")
        .arg(&ctx.root)
        .arg("--check")
        .output();

    match output {
        Ok(out) => {
            let stdout = String::from_utf8_lossy(&out.stdout);
            let stderr = String::from_utf8_lossy(&out.stderr);
            let combined = format!("{}{}", stdout, stderr);
            if out.status.success() {
                ctx.emit_ok(
                    "owners",
                    "OWNERS",
                    "syntax",
                    "valid",
                    "all declared OWNERS files have valid schema and handles",
                );
                ctx.emit_ok(
                    "owners",
                    ".github/CODEOWNERS",
                    "compiled",
                    "up to date",
                    "CODEOWNERS matches compiled output from //tools/owners",
                );
            } else if combined.contains("drift detected") {
                ctx.emit_ok(
                    "owners",
                    "OWNERS",
                    "syntax",
                    "valid",
                    "all declared OWNERS files have valid schema and handles",
                );
                // Get the expected output for diff.
                let want_output = Command::new(&bin).arg("--root").arg(&ctx.root).output();
                let mut diffrows = String::new();
                if let Ok(want_out) = want_output {
                    let want = String::from_utf8_lossy(&want_out.stdout).to_string();
                    let actual = fs::read_to_string(&codeowners).unwrap_or_default();
                    // Simple diff: lines only in actual vs only in want.
                    let actual_set: HashSet<&str> = actual.lines().collect();
                    let want_set: HashSet<&str> = want.lines().collect();
                    let mut parts = Vec::new();
                    for l in actual.lines() {
                        if !want_set.contains(l) {
                            parts.push(format!("only in CODEOWNERS: {}", l));
                        }
                    }
                    for l in want.lines() {
                        if !actual_set.contains(l) {
                            parts.push(format!("only from OWNERS: {}", l));
                        }
                    }
                    diffrows = parts.join("; ");
                }
                let note = if diffrows.is_empty() {
                    "CODEOWNERS is not what the OWNERS files compile to -- rows differ".to_string()
                } else {
                    format!(
                        "CODEOWNERS is not what the OWNERS files compile to -- {}",
                        diffrows
                    )
                };
                ctx.emit_fail(
                    "owners",
                    ".github/CODEOWNERS",
                    "drifted",
                    "compiled",
                    &note,
                    "ownership is declared in per-directory OWNERS files: add or fix the OWNERS file, then run 'bazel run //tools/owners -- --out .github/CODEOWNERS' (never edit CODEOWNERS by hand)",
                );
            } else {
                let msg = combined.trim().replace('\n', " ");
                ctx.emit_fail(
                    "owners",
                    "OWNERS",
                    "invalid",
                    "valid",
                    &msg,
                    "fix the OWNERS file named above, then run 'bazel run //tools/owners -- --out .github/CODEOWNERS'",
                );
            }
        }
        Err(_) => {
            ctx.emit_fail(
                "owners",
                ".github/CODEOWNERS",
                "not checked",
                "compiled",
                "the //tools/owners generator was not found, so CODEOWNERS could not be compared with the OWNERS files",
                "run this check as 'bazel run //tools/conformance:check' (the generator ships in its runfiles)",
            );
        }
    }
}

fn find_owners_bin(start_pwd: &str) -> Option<String> {
    if let Ok(val) = std::env::var("CONFORMANCE_OWNERS_BIN") {
        if !val.is_empty() {
            return Some(val);
        }
    }
    let mut candidates: Vec<String> = Vec::new();
    if let Ok(d) = std::env::var("RUNFILES_DIR") {
        candidates.push(format!("{}/_main/{}", d, OWNERS_BIN_REL));
    }
    if let Ok(exe) = std::env::current_exe() {
        let exe_str = exe.to_string_lossy();
        candidates.push(format!("{}.runfiles/_main/{}", exe_str, OWNERS_BIN_REL));
    }
    candidates.push(format!("{}/{}", start_pwd, OWNERS_BIN_REL));

    for c in &candidates {
        if is_executable(c) {
            return Some(c.clone());
        }
    }
    None
}

fn is_executable(path: &str) -> bool {
    if let Ok(meta) = fs::metadata(path) {
        meta.permissions().mode() & 0o111 != 0
    } else {
        false
    }
}

// ---------------------------------------------------------------------------
// check_root_directories (group "root", lines 3091-3119)
// ---------------------------------------------------------------------------

pub fn check_root_directories(ctx: &Context) {
    let allowed = [
        "apps",
        "packages",
        "infrastructure",
        "gitops",
        "tools",
        "docs",
        "requirements",
        "node_modules",
        "ds-bundle",
        "scratchpad",
        "catalog",
    ];

    let mut violations = Vec::new();
    let entries = match fs::read_dir(&ctx.root) {
        Ok(e) => e,
        Err(_) => return,
    };

    for entry in entries.flatten() {
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if !ft.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.') || name.starts_with("bazel-") {
            continue;
        }
        if !allowed.contains(&name.as_str()) {
            violations.push(name);
        }
    }

    if !violations.is_empty() {
        let viol_str = violations.join(" ");
        ctx.emit_fail(
            "root",
            "root",
            &format!("disallowed: {}", viol_str),
            "canonical taxonomy",
            "disallowed root directory detected. All applications must live under apps/<category>/<app>, libraries under packages/, infra under infrastructure/.",
            &format!(
                "move '{}' into the 4-layer taxonomy: apps/, packages/, infrastructure/, gitops/, tools/",
                viol_str
            ),
        );
    } else {
        ctx.emit_ok(
            "root",
            "root",
            "4-layer taxonomy",
            "conforming",
            "all root directories conform to the 4-layer taxonomy (apps, packages, infrastructure, gitops, tools)",
        );
    }
}

// ---------------------------------------------------------------------------
// check_preview_governance (group "preview", lines 3421-3500)
// ---------------------------------------------------------------------------

pub fn check_preview_governance(ctx: &Context) {
    let workflow = format!("{}/preview-teardown.yaml", ctx.workflows_dir);
    let workflow_rel = ".github/workflows/preview-teardown.yaml";
    let reaper = format!("{}/tools/ci/src/preview_reaper/main.rs", ctx.root);
    let reaper_rel = "tools/ci/src/preview_reaper/main.rs";

    if !Path::new(&workflow).is_file() {
        ctx.emit_fail(
            "preview",
            workflow_rel,
            "missing",
            "present",
            "preview teardown workflow is required for ephemeral resource lifecycle governance",
            "create .github/workflows/preview-teardown.yaml",
        );
        return;
    }

    let text = match fs::read_to_string(&workflow) {
        Ok(t) => t,
        Err(_) => return,
    };

    // Active text: strip comments.
    let active: String = text
        .lines()
        .map(|l| {
            // Strip inline comments (preceded by whitespace or at start).
            if let Some(pos) = l.find('#') {
                if pos == 0
                    || l.as_bytes()
                        .get(pos.saturating_sub(1))
                        .map_or(false, |&b| b == b' ' || b == b'\t')
                {
                    &l[..pos]
                } else {
                    l
                }
            } else {
                l
            }
        })
        .collect::<Vec<&str>>()
        .join("\n");

    // Check if previews are live.
    let mut previews_live = false;
    if let Ok(wf_entries) = fs::read_dir(&ctx.workflows_dir) {
        for entry in wf_entries.flatten() {
            let name = entry.file_name().to_string_lossy().to_string();
            if !name.ends_with(".yaml") && !name.ends_with(".yml") {
                continue;
            }
            let wf_text = match fs::read_to_string(entry.path()) {
                Ok(t) => t,
                Err(_) => continue,
            };
            // Strip comments before checking.
            for line in wf_text.lines() {
                let stripped = strip_inline_comment(line);
                if stripped.contains("provision-preview") {
                    previews_live = true;
                    break;
                }
            }
            if previews_live {
                break;
            }
        }
    }

    if !previews_live {
        ctx.emit_ok(
            "preview",
            workflow_rel,
            "paused",
            "paused",
            "no workflow provisions previews, so teardown triggers are not required",
        );
    } else {
        // 1. PR closed trigger.
        if active.contains("closed") && active.contains("types:") {
            ctx.emit_ok(
                "preview",
                workflow_rel,
                "pr: closed",
                "pr: closed",
                "triggers teardown automatically upon PR closure",
            );
        } else {
            ctx.emit_fail(
                "preview",
                workflow_rel,
                "missing closed",
                "pr: closed",
                "preview teardown workflow must trigger on pull_request: types: [closed]",
                "add 'types: [closed]' to pull_request trigger",
            );
        }

        // 2. Schedule cron.
        let has_cron = active.lines().any(|l| {
            let t = l.trim();
            t.contains("cron:") && t.contains('"')
        });
        if has_cron {
            ctx.emit_ok(
                "preview",
                workflow_rel,
                "schedule: cron",
                "schedule: cron",
                "runs hourly ghost reaper sweep to reclaim abandoned resources",
            );
        } else {
            ctx.emit_fail(
                "preview",
                workflow_rel,
                "missing cron",
                "schedule: cron",
                "preview teardown workflow must specify a cron schedule for periodic reaper sweeps",
                "add schedule: - cron: '17 * * * *'",
            );
        }
    }

    // 3. cancel-in-progress: false (always checked).
    if active.contains("cancel-in-progress:") && active.contains("false") {
        // More precise check.
        let has_cancel_false = active.lines().any(|l| {
            let t = l.trim();
            t.starts_with("cancel-in-progress:") && t.contains("false")
        });
        if has_cancel_false {
            ctx.emit_ok(
                "preview",
                workflow_rel,
                "cancel: false",
                "cancel: false",
                "teardown operations are non-cancellable to prevent partial resource leaks",
            );
        } else {
            ctx.emit_fail(
                "preview",
                workflow_rel,
                "cancel: true",
                "cancel: false",
                "preview teardown concurrency group must set 'cancel-in-progress: false'",
                "set concurrency.cancel-in-progress: false",
            );
        }
    } else {
        ctx.emit_fail(
            "preview",
            workflow_rel,
            "cancel: true",
            "cancel: false",
            "preview teardown concurrency group must set 'cancel-in-progress: false'",
            "set concurrency.cancel-in-progress: false",
        );
    }

    // 4. The workflow runs the reaper (the //tools/ci:preview_reaper binary) and
    // its source is there to build.
    if Path::new(&reaper).is_file() && active.contains("//tools/ci:preview_reaper") {
        ctx.emit_ok(
            "preview",
            reaper_rel,
            "wired",
            "wired",
            "preview teardown runs the //tools/ci:preview_reaper binary",
        );
    } else {
        ctx.emit_fail(
            "preview",
            reaper_rel,
            "missing/unwired",
            "wired",
            "preview teardown must run the //tools/ci:preview_reaper binary, whose source must exist",
            "keep tools/ci/src/preview_reaper and run `bazel run //tools/ci:preview_reaper` from preview-teardown.yaml",
        );
    }
}

fn strip_inline_comment(line: &str) -> &str {
    // Strip # comments that are preceded by whitespace or at start.
    if let Some(pos) = line.find('#') {
        if pos == 0 {
            return &line[..pos];
        }
        if line
            .as_bytes()
            .get(pos - 1)
            .map_or(false, |&b| b == b' ' || b == b'\t')
        {
            return &line[..pos];
        }
    }
    line
}

// ---------------------------------------------------------------------------
// check_lab_hostnames_served (group "labhost", lines 3511-3553)
// ---------------------------------------------------------------------------

pub fn check_lab_hostnames_served(ctx: &Context) {
    let gateway = format!(
        "{}/gitops/argocd/platform/envoy-gateway/gateway/gateway.yaml",
        ctx.root
    );
    let gateway_rel = "gitops/argocd/platform/envoy-gateway/gateway/gateway.yaml";
    let lab_dns = format!(
        "{}/gitops/argocd/platform/platform-config/lab-internal-dnsendpoints.yaml",
        ctx.root
    );

    if !Path::new(&gateway).is_file() {
        return;
    }

    let gateway_text = match fs::read_to_string(&gateway) {
        Ok(t) => t,
        Err(_) => return,
    };

    // Collect listeners: hostnames matching *.lab.ipv1337.dev.
    let mut listeners: HashSet<String> = HashSet::new();
    for line in gateway_text.lines() {
        let trimmed = line.trim();
        if trimmed.starts_with("hostname:") {
            if let Some(host) = extract_lab_hostname(trimmed) {
                listeners.insert(host);
            }
        }
    }

    // Collect published hostnames: (file, host) pairs.
    let mut published: Vec<(String, String)> = Vec::new();

    // From lab DNS endpoints.
    if Path::new(&lab_dns).is_file() {
        if let Ok(text) = fs::read_to_string(&lab_dns) {
            let rel = strip_prefix(&lab_dns, &ctx.root);
            for line in text.lines() {
                let trimmed = line.trim();
                if trimmed.starts_with("- dnsName:") || trimmed.starts_with("-  dnsName:") {
                    if let Some(host) = extract_lab_hostname(trimmed) {
                        published.push((rel.clone(), host));
                    }
                }
            }
        }
    }

    // From gitops routes: lines matching `- "?<host>.lab.ipv1337.dev"?` pattern.
    let gitops_dir = format!("{}/gitops", ctx.root);
    if Path::new(&gitops_dir).is_dir() {
        walk_yaml_for_lab_hosts(&gitops_dir, &ctx.root, &mut published);
    }

    if published.is_empty() {
        return;
    }

    for (file, host) in &published {
        if listeners.contains(host) {
            ctx.emit_ok(
                "labhost",
                file,
                host,
                "listener",
                "served by an HTTPS listener on the platform Gateway",
            );
        } else {
            ctx.emit_fail(
                "labhost",
                file,
                host,
                "listener",
                "no HTTPS listener for this lab name on the platform Gateway, so TLS resets",
                &format!("add a listener in {}, or drop the name", gateway_rel),
            );
        }
    }
}

fn extract_lab_hostname(text: &str) -> Option<String> {
    // Find a hostname matching [a-z0-9-]+\.lab\.ipv1337\.dev.
    let suffix = ".lab.ipv1337.dev";
    for word in text.split_whitespace() {
        let word = word.trim_matches(|c| c == '"' || c == '\'' || c == ',' || c == '-');
        if word.ends_with(suffix) {
            let prefix = &word[..word.len() - suffix.len()];
            if !prefix.is_empty()
                && prefix
                    .chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-')
            {
                return Some(word.to_string());
            }
        }
    }
    None
}

fn walk_yaml_for_lab_hosts(dir: &str, root: &str, published: &mut Vec<(String, String)>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let ft = match entry.file_type() {
            Ok(ft) => ft,
            Err(_) => continue,
        };
        if ft.is_dir() {
            walk_yaml_for_lab_hosts(&entry.path().to_string_lossy().to_string(), root, published);
        } else if ft.is_file() {
            let name = entry.file_name().to_string_lossy().to_string();
            if !name.ends_with(".yaml") && !name.ends_with(".yml") {
                continue;
            }
            let path_str = entry.path().to_string_lossy().to_string();
            let rel = strip_prefix(&path_str, root);
            let text = match fs::read_to_string(&path_str) {
                Ok(t) => t,
                Err(_) => continue,
            };
            for line in text.lines() {
                let trimmed = line.trim();
                // Match lines like `- "host.lab.ipv1337.dev"` or `- host.lab.ipv1337.dev`.
                if trimmed.starts_with('-') {
                    let after_dash = trimmed[1..].trim();
                    let cleaned = after_dash.trim_matches(|c| c == '"' || c == '\'');
                    if cleaned.ends_with(".lab.ipv1337.dev")
                        && cleaned.chars().all(|c| {
                            c.is_ascii_lowercase() || c.is_ascii_digit() || c == '-' || c == '.'
                        })
                    {
                        // Verify it's a bare hostname on a line by itself.
                        if !cleaned.contains(' ') && cleaned.matches('.').count() >= 3 {
                            published.push((rel.clone(), cleaned.to_string()));
                        }
                    }
                }
            }
        }
    }
}
