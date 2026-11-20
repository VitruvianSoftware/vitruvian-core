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

//! Catalog completeness and package contract conformance check.
//!
//! Enforces Decisions 3 and 5 of
//! `docs/superpowers/specs/2026-11-20-shared-packages-convention.md`:
//! - Every top-level folder under `packages/` (and every folder directly inside
//!   transitional `packages/rust/` and `packages/swift/`) has a
//!   `catalog-info.yaml` declaring a `Component` with `spec.type: library`,
//!   `spec.owner`, `spec.lifecycle`, `metadata.description`, at least one
//!   `metadata.tags` value, and `vitruvian.dev/bazel-target` whose Bazel labels
//!   resolve to declared targets in their package BUILD files.
//! - Every product folder `apps/<category>/<name>` (or plugin/extension
//!   subfolders under `apps/*/plugins/<name>` and `apps/extensions/<host>/<name>`)
//!   has a `catalog-info.yaml` with `kind: Component`, unless explicitly
//!   allow-listed as a non-product folder.
//! - If `tools/initializer/package` exists, rendering its new-package template
//!   produces the six required README sections and a `catalog-info.yaml` +
//!   `BUILD` pair that pass this check.

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use crate::Context;

const GROUP: &str = "CATALOG_ENTRIES";
const PACKAGE_LANGUAGE_CONTAINERS: &[&str] = &["rust", "swift"];

/// Explicit allowlist of non-product folders under `apps/` (scripts or fixtures
/// only) that do not require a `catalog-info.yaml`. Format: `(repo_rel_path, reason)`.
/// Never add a real product here.
pub const NON_PRODUCT_APP_ALLOWLIST: &[(&str, &str)] = &[];

const REQUIRED_PACKAGE_README_SECTIONS: &[&str] = &[
    "## What it gives you",
    "## When to use it",
    "## When not to use it",
    "## Example",
    "## Depend on it",
    "## Constraints",
];

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub(crate) struct CatalogDoc {
    pub kind: String,
    pub name: String,
    pub description: String,
    pub tags: Vec<String>,
    pub annotations: BTreeMap<String, String>,
    pub spec_type: String,
    pub owner: String,
    pub lifecycle: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct CheckError {
    file: String,
    found: String,
    canon: String,
    note: String,
    fix: String,
}

pub fn check_catalog_entries(ctx: &Context) {
    check_catalog_entries_with_allowlist(ctx, NON_PRODUCT_APP_ALLOWLIST);
}

pub(crate) fn check_catalog_entries_with_allowlist(ctx: &Context, allowlist: &[(&str, &str)]) {
    check_packages(ctx);
    check_apps(ctx, allowlist);
    check_initializer_package_template(ctx);
}

fn list_child_dirs(dir: &Path) -> Vec<String> {
    let Ok(entries) = fs::read_dir(dir) else {
        return Vec::new();
    };
    let mut names = Vec::new();
    for entry in entries.flatten() {
        let Ok(ft) = entry.file_type() else {
            continue;
        };
        if !ft.is_dir() {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        if name.starts_with('.')
            || name.starts_with("bazel-")
            || name == "node_modules"
            || name == "target"
        {
            continue;
        }
        names.push(name);
    }
    names.sort();
    names
}

fn unquote_yaml_value(raw: &str) -> String {
    let trimmed = raw.trim();
    if trimmed.len() >= 2
        && ((trimmed.starts_with('"') && trimmed.ends_with('"'))
            || (trimmed.starts_with('\'') && trimmed.ends_with('\'')))
    {
        return trimmed[1..trimmed.len() - 1].to_string();
    }
    // Strip trailing YAML inline comment (` # ...`).
    let bytes = trimmed.as_bytes();
    for i in 1..bytes.len() {
        if bytes[i] == b'#' && (bytes[i - 1] == b' ' || bytes[i - 1] == b'\t') {
            return trimmed[..i].trim().to_string();
        }
    }
    trimmed.to_string()
}

fn is_block_scalar_indicator(val: &str) -> bool {
    matches!(val.trim(), "|" | "|-" | "|+" | ">" | ">-" | ">+")
}

fn parse_flow_list(raw: &str) -> Option<Vec<String>> {
    let t = raw.trim();
    if !t.starts_with('[') || !t.ends_with(']') {
        return None;
    }
    let inner = t[1..t.len() - 1].trim();
    if inner.is_empty() {
        return Some(Vec::new());
    }
    Some(
        inner
            .split(',')
            .map(unquote_yaml_value)
            .filter(|s| !s.is_empty())
            .collect(),
    )
}

pub(crate) fn parse_catalog_docs(content: &str) -> Vec<CatalogDoc> {
    let mut docs = Vec::new();
    let lines: Vec<&str> = content.lines().collect();
    let mut start = 0usize;
    for i in 0..=lines.len() {
        let is_sep = i == lines.len() || lines[i].trim() == "---";
        if is_sep {
            let chunk = lines[start..i].join("\n");
            if let Some(doc) = parse_single_catalog_doc(&chunk) {
                docs.push(doc);
            }
            start = i + 1;
        }
    }
    docs
}

fn parse_single_catalog_doc(content: &str) -> Option<CatalogDoc> {
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum Section {
        Top,
        Metadata,
        Spec,
        OtherTop,
    }
    #[derive(Clone, Copy, PartialEq, Eq)]
    enum MetaSub {
        None,
        Tags,
        Annotations,
        Other,
    }
    #[derive(Clone)]
    struct ScalarFold {
        base_indent: usize,
        target: ScalarTarget,
    }
    #[derive(Clone)]
    enum ScalarTarget {
        Description,
        Annotation(String),
    }

    let mut doc = CatalogDoc::default();
    let mut section = Section::Top;
    let mut meta_indent: Option<usize> = None;
    let mut meta_sub = MetaSub::None;
    let mut meta_sub_indent: usize = 0;
    let mut spec_indent: Option<usize> = None;
    let mut scalar_fold: Option<ScalarFold> = None;

    for raw in content.lines() {
        let line = raw.trim_end_matches('\r');
        let trimmed = line.trim();
        let indent = line.len() - line.trim_start().len();

        if let Some(ref fold) = scalar_fold {
            if trimmed.is_empty() {
                continue;
            }
            if indent > fold.base_indent {
                let piece = trimmed;
                match &fold.target {
                    ScalarTarget::Description => {
                        if !doc.description.is_empty() {
                            doc.description.push(' ');
                        }
                        doc.description.push_str(piece);
                    }
                    ScalarTarget::Annotation(k) => {
                        let entry = doc.annotations.entry(k.clone()).or_default();
                        if !entry.is_empty() {
                            entry.push(' ');
                        }
                        entry.push_str(piece);
                    }
                }
                continue;
            }
            scalar_fold = None;
        }

        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }

        if indent == 0 {
            meta_sub = MetaSub::None;
            if let Some((key, val)) = trimmed.split_once(':') {
                let key = unquote_yaml_value(key);
                let val_trimmed = val.trim();
                match key.as_str() {
                    "kind" => {
                        doc.kind = unquote_yaml_value(val_trimmed);
                        section = Section::Top;
                    }
                    "metadata" => section = Section::Metadata,
                    "spec" => section = Section::Spec,
                    _ => section = Section::OtherTop,
                }
            } else {
                section = Section::OtherTop;
            }
            continue;
        }

        match section {
            Section::Metadata => {
                let mf_indent = *meta_indent.get_or_insert(indent);
                if indent < mf_indent {
                    // Unlikely malformed indent, treat as same level.
                    meta_indent = Some(indent);
                }
                if indent == mf_indent {
                    meta_sub = MetaSub::None;
                    if let Some((key, val)) = trimmed.split_once(':') {
                        let key = unquote_yaml_value(key);
                        let val_trimmed = val.trim();
                        match key.as_str() {
                            "name" => doc.name = unquote_yaml_value(val_trimmed),
                            "description" => {
                                if is_block_scalar_indicator(val_trimmed) || val_trimmed.is_empty()
                                {
                                    scalar_fold = Some(ScalarFold {
                                        base_indent: indent,
                                        target: ScalarTarget::Description,
                                    });
                                } else {
                                    doc.description = unquote_yaml_value(val_trimmed);
                                }
                            }
                            "tags" => {
                                if let Some(flow) = parse_flow_list(val_trimmed) {
                                    doc.tags = flow;
                                } else {
                                    meta_sub = MetaSub::Tags;
                                    meta_sub_indent = indent;
                                }
                            }
                            "annotations" => {
                                meta_sub = MetaSub::Annotations;
                                meta_sub_indent = indent;
                            }
                            _ => {
                                meta_sub = MetaSub::Other;
                                meta_sub_indent = indent;
                            }
                        }
                    }
                    continue;
                }

                if indent > meta_sub_indent {
                    match meta_sub {
                        MetaSub::Tags => {
                            if let Some(rest) = trimmed.strip_prefix('-') {
                                let tag = unquote_yaml_value(rest);
                                if !tag.is_empty() {
                                    doc.tags.push(tag);
                                }
                            }
                        }
                        MetaSub::Annotations => {
                            if let Some((key, val)) = trimmed.split_once(':') {
                                let k = unquote_yaml_value(key);
                                let val_trimmed = val.trim();
                                if !k.is_empty() {
                                    if is_block_scalar_indicator(val_trimmed)
                                        || val_trimmed.is_empty()
                                    {
                                        scalar_fold = Some(ScalarFold {
                                            base_indent: indent,
                                            target: ScalarTarget::Annotation(k),
                                        });
                                    } else {
                                        doc.annotations.insert(k, unquote_yaml_value(val_trimmed));
                                    }
                                }
                            }
                        }
                        MetaSub::None | MetaSub::Other => {}
                    }
                }
            }
            Section::Spec => {
                let sf_indent = *spec_indent.get_or_insert(indent);
                if indent == sf_indent {
                    if let Some((key, val)) = trimmed.split_once(':') {
                        let key = unquote_yaml_value(key);
                        let val_trimmed = val.trim();
                        match key.as_str() {
                            "type" => doc.spec_type = unquote_yaml_value(val_trimmed),
                            "owner" => doc.owner = unquote_yaml_value(val_trimmed),
                            "lifecycle" => doc.lifecycle = unquote_yaml_value(val_trimmed),
                            _ => {}
                        }
                    }
                }
            }
            Section::Top | Section::OtherTop => {}
        }
    }

    if doc.kind.is_empty() && doc.name.is_empty() && doc.spec_type.is_empty() {
        None
    } else {
        Some(doc)
    }
}

/// Parse a first-party Bazel label (`//pkg:target` or `//pkg`) into `(pkg, target)`.
pub(crate) fn parse_bazel_label(raw: &str) -> Result<(String, String), String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return Err("empty Bazel target label".to_string());
    }
    if trimmed.chars().any(char::is_whitespace) {
        return Err(format!("label '{trimmed}' contains whitespace"));
    }
    let Some(body) = trimmed.strip_prefix("//") else {
        return Err(format!("label '{trimmed}' must start with '//'"));
    };
    if body.ends_with("...") {
        return Err(format!(
            "label '{trimmed}' uses a wildcard; name a concrete target"
        ));
    }

    let (pkg, target) = match body.split_once(':') {
        Some((p, t)) => {
            if t.is_empty() {
                return Err(format!("label '{trimmed}' has an empty target name"));
            }
            if t.contains(':') {
                return Err(format!("label '{trimmed}' contains multiple ':'"));
            }
            if matches!(t, "all" | "*" | "all-targets") {
                return Err(format!("label '{trimmed}' names a wildcard, not a target"));
            }
            (p.to_string(), t.to_string())
        }
        None => {
            if body.is_empty() {
                return Err(format!("label '{trimmed}' has no package path"));
            }
            let target = body.rsplit('/').next().unwrap_or(body).to_string();
            (body.to_string(), target)
        }
    };

    if pkg.starts_with('/') || pkg.ends_with('/') || pkg.split('/').any(|seg| seg == "..") {
        return Err(format!("label '{trimmed}' has an invalid package path"));
    }

    Ok((pkg, target))
}

fn strip_starlark_comment(line: &str) -> &str {
    let mut in_quote: Option<char> = None;
    let mut escaped = false;
    for (idx, ch) in line.char_indices() {
        if escaped {
            escaped = false;
            continue;
        }
        if in_quote.is_some() && ch == '\\' {
            escaped = true;
            continue;
        }
        match in_quote {
            Some(q) if ch == q => in_quote = None,
            Some(_) => {}
            None if ch == '"' || ch == '\'' => in_quote = Some(ch),
            None if ch == '#' => return &line[..idx],
            None => {}
        }
    }
    line
}

/// Check whether Starlark source declares `name = "<target>"` (or single-quoted),
/// ignoring comments and attribute names like `crate_name` or `module_name`.
pub(crate) fn build_declares_target(build_text: &str, target: &str) -> bool {
    let stripped: String = build_text
        .lines()
        .map(strip_starlark_comment)
        .collect::<Vec<_>>()
        .join("\n");

    let mut from = 0usize;
    while let Some(rel_pos) = stripped[from..].find("name") {
        let pos = from + rel_pos;
        let boundary_ok = pos == 0
            || stripped[..pos]
                .chars()
                .next_back()
                .is_some_and(|c| !c.is_ascii_alphanumeric() && c != '_');
        let after = &stripped[pos + 4..];
        if boundary_ok {
            let trimmed = after.trim_start();
            if let Some(after_eq) = trimmed.strip_prefix('=') {
                let val = after_eq.trim_start();
                for quote in ['"', '\''] {
                    if let Some(rest) = val.strip_prefix(quote) {
                        if let Some(after_name) = rest.strip_prefix(target) {
                            if after_name.starts_with(quote) {
                                return true;
                            }
                        }
                    }
                }
            }
        }
        from = pos + 4;
    }
    false
}

pub(crate) fn verify_bazel_label(root: &str, raw_label: &str) -> Result<(), String> {
    let (pkg, target) = parse_bazel_label(raw_label)?;
    let pkg_dir = if pkg.is_empty() {
        PathBuf::from(root)
    } else {
        Path::new(root).join(&pkg)
    };
    if !pkg_dir.is_dir() {
        return Err(format!("package directory '{pkg}' does not exist"));
    }

    let build_file = ["BUILD", "BUILD.bazel"]
        .iter()
        .map(|name| pkg_dir.join(name))
        .find(|p| p.is_file());
    let Some(build_path) = build_file else {
        return Err(format!("package '{pkg}' has no BUILD or BUILD.bazel file"));
    };

    let build_text = fs::read_to_string(&build_path)
        .map_err(|e| format!("failed to read {}: {e}", build_path.display()))?;
    if !build_declares_target(&build_text, &target) {
        return Err(format!(
            "target '{target}' not declared in {}/{}",
            pkg,
            build_path
                .file_name()
                .map(|n| n.to_string_lossy().to_string())
                .unwrap_or_else(|| "BUILD".to_string())
        ));
    }
    Ok(())
}

fn collect_package_dirs(root: &str) -> Vec<String> {
    let packages_dir = Path::new(root).join("packages");
    let mut out = Vec::new();
    for entry in list_child_dirs(&packages_dir) {
        if PACKAGE_LANGUAGE_CONTAINERS.contains(&entry.as_str()) {
            let container = packages_dir.join(&entry);
            for child in list_child_dirs(&container) {
                out.push(format!("packages/{entry}/{child}"));
            }
        } else {
            out.push(format!("packages/{entry}"));
        }
    }
    out.sort();
    out
}

fn validate_package_dir(root: &str, pkg_rel: &str) -> Result<usize, Vec<CheckError>> {
    let rel_catalog = format!("{pkg_rel}/catalog-info.yaml");
    let abs_catalog = Path::new(root).join(&rel_catalog);
    if !abs_catalog.is_file() {
        return Err(vec![CheckError {
            file: rel_catalog.clone(),
            found: "missing".to_string(),
            canon: "catalog-info.yaml".to_string(),
            note: format!("package '{pkg_rel}' has no catalog-info.yaml"),
            fix: format!("add {rel_catalog} (or run `aspect render-package`)"),
        }]);
    }

    let content = match fs::read_to_string(&abs_catalog) {
        Ok(c) => c,
        Err(e) => {
            return Err(vec![CheckError {
                file: rel_catalog,
                found: "unreadable".to_string(),
                canon: "readable YAML".to_string(),
                note: format!("failed to read catalog-info.yaml: {e}"),
                fix: "ensure catalog-info.yaml is valid UTF-8 and readable".to_string(),
            }]);
        }
    };

    let docs = parse_catalog_docs(&content);
    let components: Vec<&CatalogDoc> = docs.iter().filter(|d| d.kind == "Component").collect();
    if components.is_empty() {
        return Err(vec![CheckError {
            file: rel_catalog,
            found: "no Component".to_string(),
            canon: "kind: Component".to_string(),
            note: "package catalog-info.yaml must declare at least one kind: Component".to_string(),
            fix: "declare apiVersion: backstage.io/v1alpha1 and kind: Component".to_string(),
        }]);
    }

    let libraries: Vec<&CatalogDoc> = components
        .iter()
        .copied()
        .filter(|d| d.spec_type == "library")
        .collect();
    if libraries.is_empty() {
        let found_type = components
            .first()
            .map(|d| d.spec_type.as_str())
            .filter(|t| !t.is_empty())
            .unwrap_or("missing");
        return Err(vec![CheckError {
            file: rel_catalog,
            found: format!("spec.type:{found_type}"),
            canon: "spec.type:library".to_string(),
            note: "package Component must declare spec.type: library".to_string(),
            fix: "set spec.type: library".to_string(),
        }]);
    }

    let multi = libraries.len() > 1;
    let mut errors = Vec::new();
    let mut total_targets = 0usize;

    for doc in libraries {
        let entry_file = if multi && !doc.name.is_empty() {
            format!("{rel_catalog} ({})", doc.name)
        } else {
            rel_catalog.clone()
        };

        if doc.owner.trim().is_empty() {
            errors.push(CheckError {
                file: entry_file.clone(),
                found: "spec.owner:missing".to_string(),
                canon: "spec.owner".to_string(),
                note: "package catalog-info.yaml is missing spec.owner".to_string(),
                fix: "set spec.owner (e.g. platform-team)".to_string(),
            });
        }
        if doc.lifecycle.trim().is_empty() {
            errors.push(CheckError {
                file: entry_file.clone(),
                found: "spec.lifecycle:missing".to_string(),
                canon: "spec.lifecycle".to_string(),
                note: "package catalog-info.yaml is missing spec.lifecycle".to_string(),
                fix: "set spec.lifecycle (e.g. experimental or production)".to_string(),
            });
        }
        if doc.description.trim().is_empty() {
            errors.push(CheckError {
                file: entry_file.clone(),
                found: "metadata.description:missing".to_string(),
                canon: "metadata.description".to_string(),
                note: "package catalog-info.yaml is missing metadata.description".to_string(),
                fix: "add a one-sentence metadata.description".to_string(),
            });
        }
        if doc.tags.is_empty() {
            errors.push(CheckError {
                file: entry_file.clone(),
                found: "metadata.tags:empty".to_string(),
                canon: ">= 1 tag".to_string(),
                note: "package catalog-info.yaml must list at least one tag under metadata.tags"
                    .to_string(),
                fix: "add language and capability tags under metadata.tags".to_string(),
            });
        }

        let raw_targets = doc
            .annotations
            .get("vitruvian.dev/bazel-target")
            .map(String::as_str)
            .unwrap_or("")
            .trim();
        if raw_targets.is_empty() {
            errors.push(CheckError {
                file: entry_file,
                found: "vitruvian.dev/bazel-target:missing".to_string(),
                canon: "vitruvian.dev/bazel-target".to_string(),
                note: "package catalog-info.yaml is missing annotation vitruvian.dev/bazel-target"
                    .to_string(),
                fix: "add metadata.annotations.\"vitruvian.dev/bazel-target\"".to_string(),
            });
            continue;
        }

        let labels: Vec<&str> = raw_targets
            .split(',')
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .collect();
        if labels.is_empty() {
            errors.push(CheckError {
                file: entry_file,
                found: "vitruvian.dev/bazel-target:empty".to_string(),
                canon: "valid Bazel label".to_string(),
                note: "vitruvian.dev/bazel-target annotation contains no labels".to_string(),
                fix: "set vitruvian.dev/bazel-target to one or more comma-separated Bazel labels"
                    .to_string(),
            });
            continue;
        }

        for label in labels {
            match verify_bazel_label(root, label) {
                Ok(()) => total_targets += 1,
                Err(why) => {
                    errors.push(CheckError {
                        file: entry_file.clone(),
                        found: label.to_string(),
                        canon: "existing Bazel target".to_string(),
                        note: format!("vitruvian.dev/bazel-target label does not exist ({why})"),
                        fix: "point vitruvian.dev/bazel-target at a declared target in its BUILD file"
                            .to_string(),
                    });
                }
            }
        }
    }

    if errors.is_empty() {
        Ok(total_targets)
    } else {
        Err(errors)
    }
}

fn check_packages(ctx: &Context) {
    for pkg_rel in collect_package_dirs(&ctx.root) {
        let rel_catalog = format!("{pkg_rel}/catalog-info.yaml");
        match validate_package_dir(&ctx.root, &pkg_rel) {
            Ok(target_count) => {
                ctx.emit_ok(
                    GROUP,
                    &rel_catalog,
                    "valid",
                    "library + bazel targets",
                    &format!("{target_count} target(s) verified"),
                );
            }
            Err(errs) => {
                for err in errs {
                    ctx.emit_fail(
                        GROUP, &err.file, &err.found, &err.canon, &err.note, &err.fix,
                    );
                }
            }
        }
    }
}

fn allowlist_reason<'a>(allowlist: &[(&'a str, &'a str)], rel: &str) -> Option<&'a str> {
    allowlist
        .iter()
        .find(|(path, _)| *path == rel)
        .map(|(_, reason)| *reason)
}

fn validate_app_product(ctx: &Context, rel: &str, allowlist: &[(&str, &str)]) {
    if let Some(reason) = allowlist_reason(allowlist, rel) {
        ctx.emit_ok(GROUP, rel, "allowlisted", "non-product", reason);
        return;
    }

    let rel_catalog = format!("{rel}/catalog-info.yaml");
    let abs_catalog = Path::new(&ctx.root).join(&rel_catalog);
    if !abs_catalog.is_file() {
        ctx.emit_fail(
            GROUP,
            &rel_catalog,
            "missing",
            "catalog-info.yaml",
            &format!("product folder '{rel}' has no catalog-info.yaml"),
            &format!("add {rel_catalog} (Component), or allow-list non-product folders in tools/conformance/src/checks/catalog_entries.rs"),
        );
        return;
    }

    let content = match fs::read_to_string(&abs_catalog) {
        Ok(c) => c,
        Err(e) => {
            ctx.emit_fail(
                GROUP,
                &rel_catalog,
                "unreadable",
                "readable YAML",
                &format!("failed to read {rel_catalog}: {e}"),
                "ensure catalog-info.yaml is readable UTF-8",
            );
            return;
        }
    };

    let docs = parse_catalog_docs(&content);
    if !docs.iter().any(|d| d.kind == "Component") {
        ctx.emit_fail(
            GROUP,
            &rel_catalog,
            "no Component",
            "kind: Component",
            &format!("{rel_catalog} does not declare a Backstage Component"),
            "set kind: Component in catalog-info.yaml",
        );
        return;
    }

    ctx.emit_ok(
        GROUP,
        &rel_catalog,
        "Component",
        "catalog-info.yaml",
        "product registered in catalog",
    );
}

fn check_apps(ctx: &Context, allowlist: &[(&str, &str)]) {
    let apps_dir = Path::new(&ctx.root).join("apps");
    for category in list_child_dirs(&apps_dir) {
        let cat_dir = apps_dir.join(&category);
        for name in list_child_dirs(&cat_dir) {
            let rel = format!("apps/{category}/{name}");
            if let Some(reason) = allowlist_reason(allowlist, &rel) {
                ctx.emit_ok(GROUP, &rel, "allowlisted", "non-product", reason);
                continue;
            }
            if name == "plugins" {
                let plugins_dir = cat_dir.join(&name);
                let plugins = list_child_dirs(&plugins_dir);
                if plugins.is_empty() {
                    ctx.emit_fail(
                        GROUP,
                        &rel,
                        "empty plugins dir",
                        ">= 1 plugin with catalog-info.yaml",
                        "plugins container has no plugin subfolders",
                        "remove empty plugins folder or add plugin folders with catalog-info.yaml",
                    );
                } else {
                    for plugin in plugins {
                        validate_app_product(ctx, &format!("{rel}/{plugin}"), allowlist);
                    }
                }
                continue;
            }
            if category == "extensions"
                && !Path::new(&ctx.root)
                    .join(&rel)
                    .join("catalog-info.yaml")
                    .is_file()
            {
                let host_dir = cat_dir.join(&name);
                let exts = list_child_dirs(&host_dir);
                if !exts.is_empty() {
                    for ext in exts {
                        validate_app_product(ctx, &format!("{rel}/{ext}"), allowlist);
                    }
                    continue;
                }
            }
            validate_app_product(ctx, &rel, allowlist);
        }
    }
}

struct TempDirGuard(PathBuf);

impl Drop for TempDirGuard {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn render_package_template_value(template: &str) -> String {
    let pairs = [
        ("{{ project_kebab }}", "smoke-pkg"),
        ("{{ project_snake }}", "smoke_pkg"),
        ("{{ project_pascal }}", "SmokePkg"),
        ("{{ project_name }}", "smoke_pkg"),
        ("{{ description }}", "Shared smoke-pkg library package."),
        ("{{ language }}", "rust"),
        ("{{ tags_yaml }}", "    - rust"),
        ("{{ owner }}", "platform-team"),
        ("{{ lifecycle }}", "experimental"),
        ("{{ target_name }}", "smoke-pkg"),
        ("{{ bazel_target }}", "//packages/smoke-pkg:smoke-pkg"),
    ];
    let mut out = template.to_string();
    for (k, v) in pairs {
        out = out.replace(k, v);
    }
    out
}

fn check_initializer_package_template(ctx: &Context) {
    let tmpl_rel = "tools/initializer/package";
    let tmpl_dir = Path::new(&ctx.root).join(tmpl_rel);
    if !tmpl_dir.is_dir() {
        return;
    }

    let required_templates = [
        ("README.md.tmpl", "README.md"),
        ("catalog-info.yaml.tmpl", "catalog-info.yaml"),
        ("BUILD.tmpl", "BUILD"),
    ];

    let mut rendered_files: Vec<(&str, String)> = Vec::new();
    for (tmpl_name, out_name) in required_templates {
        let path = tmpl_dir.join(tmpl_name);
        if !path.is_file() {
            ctx.emit_fail(
                GROUP,
                &format!("{tmpl_rel}/{tmpl_name}"),
                "missing",
                tmpl_name,
                "new-package initializer template is missing a required template file",
                &format!("add {tmpl_rel}/{tmpl_name}"),
            );
            return;
        }
        let raw = match fs::read_to_string(&path) {
            Ok(c) => c,
            Err(e) => {
                ctx.emit_fail(
                    GROUP,
                    &format!("{tmpl_rel}/{tmpl_name}"),
                    "unreadable",
                    "readable template",
                    &format!("failed to read template: {e}"),
                    "ensure template is valid UTF-8",
                );
                return;
            }
        };
        let rendered = render_package_template_value(&raw);
        if rendered.contains("{{") || rendered.contains("{%") {
            ctx.emit_fail(
                GROUP,
                &format!("{tmpl_rel}/{tmpl_name}"),
                "unrendered placeholders",
                "only supported package template variables",
                "template still contains unrendered Jinja tokens after substitution",
                "restrict placeholders to supported variables (project_kebab, description, language, tags_yaml, owner, lifecycle, target_name, bazel_target)",
            );
            return;
        }
        rendered_files.push((out_name, rendered));
    }

    use std::sync::atomic::{AtomicU64, Ordering};
    static SEQ: AtomicU64 = AtomicU64::new(0);
    let tmp_root = std::env::temp_dir().join(format!(
        "conformance-pkg-tmpl-{}-{}",
        std::process::id(),
        SEQ.fetch_add(1, Ordering::Relaxed)
    ));
    let _guard = TempDirGuard(tmp_root.clone());
    let pkg_dir = tmp_root.join("packages/smoke-pkg");
    if let Err(e) = fs::create_dir_all(&pkg_dir) {
        ctx.emit_fail(
            GROUP,
            tmpl_rel,
            "temp dir failed",
            "writable temp dir",
            &format!("could not create staging dir: {e}"),
            "check TMPDIR permissions",
        );
        return;
    }

    let mut readme_content = String::new();
    for (out_name, content) in &rendered_files {
        if *out_name == "README.md" {
            readme_content = content.clone();
        }
        if let Err(e) = fs::write(pkg_dir.join(out_name), content) {
            ctx.emit_fail(
                GROUP,
                tmpl_rel,
                "write failed",
                "rendered file",
                &format!("could not write rendered {out_name}: {e}"),
                "check TMPDIR permissions",
            );
            return;
        }
    }

    let mut failed = false;
    for section in REQUIRED_PACKAGE_README_SECTIONS {
        if !readme_content.contains(section) {
            failed = true;
            ctx.emit_fail(
                GROUP,
                &format!("{tmpl_rel}/README.md.tmpl"),
                "missing section",
                section,
                &format!("rendered README.md is missing required section '{section}'"),
                &format!("add '{section}' heading to {tmpl_rel}/README.md.tmpl"),
            );
        }
    }

    if let Err(errs) = validate_package_dir(tmp_root.to_str().unwrap(), "packages/smoke-pkg") {
        failed = true;
        for err in errs {
            ctx.emit_fail(
                GROUP,
                &format!("{tmpl_rel} -> {}", err.file),
                &err.found,
                &err.canon,
                &err.note,
                &err.fix,
            );
        }
    }

    if !failed {
        ctx.emit_ok(
            GROUP,
            tmpl_rel,
            "valid",
            "README sections + catalog_entries",
            "rendered package template passes catalog_entries and README contract",
        );
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_repo(files: &[(&str, &str)]) -> TempDirGuard {
        use std::sync::atomic::{AtomicU64, Ordering};
        static N: AtomicU64 = AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!(
            "conformance-catalog-entries-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        for (rel, body) in files {
            let p = dir.join(rel);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, body).unwrap();
        }
        TempDirGuard(dir)
    }

    fn run_with_allowlist(
        files: &[(&str, &str)],
        allowlist: &[(&str, &str)],
    ) -> (u32, u32, String) {
        let dir = temp_repo(files);
        let ctx = Context::for_root(dir.0.to_str().unwrap());
        check_catalog_entries_with_allowlist(&ctx, allowlist);
        (
            ctx.ok_count.get(),
            ctx.fail_count.get(),
            ctx.rows.get(GROUP),
        )
    }

    const VALID_PKG_CATALOG: &str = "\
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: foo
  description: Shared foo library.
  tags:
    - rust
    - cli
  annotations:
    vitruvian.dev/bazel-target: //packages/foo:foo_lib
spec:
  type: library
  lifecycle: production
  owner: platform-team
";

    const VALID_PKG_BUILD: &str = "\
rust_library(
    name = \"foo_lib\",
    srcs = [\"src/lib.rs\"],
)
";

    const VALID_APP_CATALOG: &str = "\
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: my-app
  description: Example application.
spec:
  type: service
  lifecycle: production
  owner: platform-team
";

    #[test]
    fn valid_packages_and_apps_pass() {
        let rust_catalog = VALID_PKG_CATALOG
            .replace("name: foo", "name: rust-foo")
            .replace(
                "//packages/foo:foo_lib",
                "//packages/rust/rust-foo:rust_foo",
            );
        let rust_build = "rust_library(name = \"rust_foo\")\n";
        let swift_catalog = VALID_PKG_CATALOG
            .replace("name: foo", "name: swift-bar")
            .replace("    - rust", "    - swift")
            .replace(
                "//packages/foo:foo_lib",
                "//packages/swift/SwiftBar:SwiftBar",
            );
        let swift_build = "swift_library(name = \"SwiftBar\")\n";
        let multi_doc_catalog = "\
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: pulumi-lib
  description: Pulumi Go library.
  tags: [go, iac]
  annotations:
    vitruvian.dev/bazel-target: //packages/pulumi/sub
spec:
  type: library
  lifecycle: production
  owner: platform-team
---
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: pulumi-example
  description: Example reference architecture.
  tags: [go]
spec:
  type: reference-architecture
  lifecycle: production
  owner: platform-team
";
        let pulumi_sub_build = "go_library(name = \"sub\")\n";

        let (ok, fail, rows) = run_with_allowlist(
            &[
                ("packages/foo/catalog-info.yaml", VALID_PKG_CATALOG),
                ("packages/foo/BUILD", VALID_PKG_BUILD),
                ("packages/rust/rust-foo/catalog-info.yaml", &rust_catalog),
                ("packages/rust/rust-foo/BUILD", rust_build),
                ("packages/swift/SwiftBar/catalog-info.yaml", &swift_catalog),
                ("packages/swift/SwiftBar/BUILD.bazel", swift_build),
                ("packages/pulumi/catalog-info.yaml", multi_doc_catalog),
                ("packages/pulumi/sub/BUILD", pulumi_sub_build),
                ("apps/cli/my-app/catalog-info.yaml", VALID_APP_CATALOG),
                (
                    "apps/antigravity/plugins/my-plugin/catalog-info.yaml",
                    VALID_APP_CATALOG,
                ),
                (
                    "apps/extensions/atrium/my-ext/catalog-info.yaml",
                    VALID_APP_CATALOG,
                ),
            ],
            &[],
        );
        assert_eq!((ok, fail), (7, 0), "{rows}");
    }

    #[test]
    fn missing_package_catalog_fails() {
        let (_, fail, rows) = run_with_allowlist(
            &[
                ("packages/no-catalog/BUILD", "filegroup(name = \"x\")\n"),
                (
                    "packages/rust/missing-rs/BUILD",
                    "filegroup(name = \"x\")\n",
                ),
                (
                    "packages/swift/MissingSwift/BUILD",
                    "filegroup(name = \"x\")\n",
                ),
            ],
            &[],
        );
        assert_eq!(fail, 3, "{rows}");
        assert!(
            rows.contains("packages/no-catalog/catalog-info.yaml"),
            "{rows}"
        );
        assert!(
            rows.contains("packages/rust/missing-rs/catalog-info.yaml"),
            "{rows}"
        );
        assert!(
            rows.contains("packages/swift/MissingSwift/catalog-info.yaml"),
            "{rows}"
        );
    }

    #[test]
    fn missing_package_fields_fail() {
        let bad_type = VALID_PKG_CATALOG.replace("type: library", "type: service");
        let missing_owner = VALID_PKG_CATALOG.replace("  owner: platform-team\n", "");
        let missing_lifecycle = VALID_PKG_CATALOG.replace("  lifecycle: production\n", "");
        let missing_desc = VALID_PKG_CATALOG.replace("  description: Shared foo library.\n", "");
        let missing_tags = VALID_PKG_CATALOG.replace("  tags:\n    - rust\n    - cli\n", "");
        let missing_anno = VALID_PKG_CATALOG.replace(
            "  annotations:\n    vitruvian.dev/bazel-target: //packages/foo:foo_lib\n",
            "",
        );

        for (case_name, yaml, expected_needle) in [
            ("wrong type", bad_type.as_str(), "spec.type:service"),
            (
                "missing owner",
                missing_owner.as_str(),
                "spec.owner:missing",
            ),
            (
                "missing lifecycle",
                missing_lifecycle.as_str(),
                "spec.lifecycle:missing",
            ),
            (
                "missing description",
                missing_desc.as_str(),
                "metadata.description:missing",
            ),
            ("missing tags", missing_tags.as_str(), "metadata.tags:empty"),
            (
                "missing annotation",
                missing_anno.as_str(),
                "vitruvian.dev/bazel-target:missing",
            ),
        ] {
            let (_, fail, rows) = run_with_allowlist(
                &[
                    ("packages/foo/catalog-info.yaml", yaml),
                    ("packages/foo/BUILD", VALID_PKG_BUILD),
                ],
                &[],
            );
            assert_eq!(fail, 1, "{case_name}: {rows}");
            assert!(rows.contains(expected_needle), "{case_name}: {rows}");
        }
    }

    #[test]
    fn unknown_bazel_label_fails() {
        // 1. Missing BUILD file in target package directory
        let (_, fail, rows) = run_with_allowlist(
            &[("packages/foo/catalog-info.yaml", VALID_PKG_CATALOG)],
            &[],
        );
        assert_eq!(fail, 1, "{rows}");
        assert!(rows.contains("no BUILD or BUILD.bazel file"), "{rows}");

        // 2. Target not declared in BUILD (crate_name = "foo_lib" must NOT match)
        let (_, fail, rows) = run_with_allowlist(
            &[
                ("packages/foo/catalog-info.yaml", VALID_PKG_CATALOG),
                (
                    "packages/foo/BUILD",
                    "rust_library(\n    name = \"other_name\",\n    crate_name = \"foo_lib\",\n)\n",
                ),
            ],
            &[],
        );
        assert_eq!(fail, 1, "{rows}");
        assert!(rows.contains("target 'foo_lib' not declared"), "{rows}");

        // 3. Malformed label without leading //
        let bad_label = VALID_PKG_CATALOG.replace("//packages/foo:foo_lib", "packages/foo:foo_lib");
        let (_, fail, rows) = run_with_allowlist(
            &[
                ("packages/foo/catalog-info.yaml", &bad_label),
                ("packages/foo/BUILD", VALID_PKG_BUILD),
            ],
            &[],
        );
        assert_eq!(fail, 1, "{rows}");
        assert!(rows.contains("must start with '//'"), "{rows}");
    }

    #[test]
    fn product_without_catalog_fails() {
        let (_, fail, rows) = run_with_allowlist(
            &[
                ("apps/cli/no-cat/main.go", "package main\n"),
                ("apps/antigravity/plugins/no-cat-plugin/plugin.json", "{}\n"),
                (
                    "apps/extensions/atrium/no-cat-ext/Package.swift",
                    "// swift\n",
                ),
            ],
            &[],
        );
        assert_eq!(fail, 3, "{rows}");
        assert!(rows.contains("apps/cli/no-cat/catalog-info.yaml"), "{rows}");
        assert!(
            rows.contains("apps/antigravity/plugins/no-cat-plugin/catalog-info.yaml"),
            "{rows}"
        );
        assert!(
            rows.contains("apps/extensions/atrium/no-cat-ext/catalog-info.yaml"),
            "{rows}"
        );
    }

    #[test]
    fn allowlisted_non_product_folder_passes() {
        let (ok, fail, rows) = run_with_allowlist(
            &[
                ("apps/cli/fixtures/sample.json", "{}\n"),
                ("apps/cli/real-app/catalog-info.yaml", VALID_APP_CATALOG),
            ],
            &[("apps/cli/fixtures", "test fixtures only, not a product")],
        );
        assert_eq!((ok, fail), (2, 0), "{rows}");
        assert!(rows.contains("allowlisted"), "{rows}");

        // Without allowlist, the non-catalog folder fails.
        let (_, fail_no_allow, rows_no_allow) = run_with_allowlist(
            &[
                ("apps/cli/fixtures/sample.json", "{}\n"),
                ("apps/cli/real-app/catalog-info.yaml", VALID_APP_CATALOG),
            ],
            &[],
        );
        assert_eq!(fail_no_allow, 1, "{rows_no_allow}");
        assert!(
            rows_no_allow.contains("apps/cli/fixtures/catalog-info.yaml"),
            "{rows_no_allow}"
        );
    }

    #[test]
    fn initializer_package_template_passes_and_broken_template_fails() {
        let readme_tmpl = "\
# {{ project_kebab }}

## What it gives you

{{ description }}

## When to use it

When shared.

## When not to use it

When single-product.

## Example

```{{ language }}
// example
```

## Depend on it

`{{ bazel_target }}`

## Constraints

None.
";
        let catalog_tmpl = "\
apiVersion: backstage.io/v1alpha1
kind: Component
metadata:
  name: {{ project_kebab }}
  description: {{ description }}
  tags:
{{ tags_yaml }}
  annotations:
    vitruvian.dev/bazel-target: {{ bazel_target }}
spec:
  type: library
  lifecycle: {{ lifecycle }}
  owner: {{ owner }}
";
        let build_tmpl = "\
filegroup(
    name = \"{{ target_name }}\",
    srcs = [\"README.md\"],
    visibility = [\"//visibility:public\"],
)
";

        let (ok, fail, rows) = run_with_allowlist(
            &[
                ("tools/initializer/package/README.md.tmpl", readme_tmpl),
                (
                    "tools/initializer/package/catalog-info.yaml.tmpl",
                    catalog_tmpl,
                ),
                ("tools/initializer/package/BUILD.tmpl", build_tmpl),
            ],
            &[],
        );
        assert_eq!((ok, fail), (1, 0), "{rows}");

        // Missing vitruvian.dev/bazel-target fails.
        let bad_catalog_tmpl =
            catalog_tmpl.replace("    vitruvian.dev/bazel-target: {{ bazel_target }}\n", "");
        let (_, fail, rows) = run_with_allowlist(
            &[
                ("tools/initializer/package/README.md.tmpl", readme_tmpl),
                (
                    "tools/initializer/package/catalog-info.yaml.tmpl",
                    &bad_catalog_tmpl,
                ),
                ("tools/initializer/package/BUILD.tmpl", build_tmpl),
            ],
            &[],
        );
        assert_eq!(fail, 1, "{rows}");
        assert!(
            rows.contains("vitruvian.dev/bazel-target:missing"),
            "{rows}"
        );

        // Mismatched target name in BUILD.tmpl fails.
        let bad_build_tmpl = build_tmpl.replace("{{ target_name }}", "wrong_target");
        let (_, fail, rows) = run_with_allowlist(
            &[
                ("tools/initializer/package/README.md.tmpl", readme_tmpl),
                (
                    "tools/initializer/package/catalog-info.yaml.tmpl",
                    catalog_tmpl,
                ),
                ("tools/initializer/package/BUILD.tmpl", &bad_build_tmpl),
            ],
            &[],
        );
        assert_eq!(fail, 1, "{rows}");
        assert!(rows.contains("target 'smoke-pkg' not declared"), "{rows}");

        // Missing README section fails.
        let bad_readme_tmpl = readme_tmpl.replace("## Constraints\n\nNone.\n", "");
        let (_, fail, rows) = run_with_allowlist(
            &[
                ("tools/initializer/package/README.md.tmpl", &bad_readme_tmpl),
                (
                    "tools/initializer/package/catalog-info.yaml.tmpl",
                    catalog_tmpl,
                ),
                ("tools/initializer/package/BUILD.tmpl", build_tmpl),
            ],
            &[],
        );
        assert_eq!(fail, 1, "{rows}");
        assert!(rows.contains("## Constraints"), "{rows}");
    }
}
