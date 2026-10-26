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

//! Catalog conformance checks, ported from `check.sh` lines 782-978.
//!
//! Validates that:
//!  - Cataloged deps use `"catalog:"` (or a concrete range in exempt workspaces).
//!  - Exempt (standalone-built) workspaces never use `"workspace:"`.
//!  - Every catalog entry is referenced by at least one workspace.
//!  - Deps appearing in 2+ files with 2+ distinct ranges are flagged as drift
//!    candidates (advisory only).

use std::collections::{HashMap, HashSet};
use std::fs;

use crate::emit;
use crate::Context;

// ---------------------------------------------------------------------------
// Helpers: lightweight JSON line parsing (no serde)
// ---------------------------------------------------------------------------

/// Extract `"key": "value"` pairs from a JSON file's text, line by line.
/// Matches the same regex the bash awk uses:
///   `^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*"[^"]*"`
/// Returns (key, value) tuples.
fn extract_string_pairs(text: &str) -> Vec<(String, String)> {
    let mut pairs = Vec::new();
    for line in text.lines() {
        if let Some(pair) = parse_kv_line(line) {
            pairs.push(pair);
        }
    }
    pairs
}

/// Try to parse a single JSON line as `"key": "value"`, returning the
/// unquoted key and value.  Returns `None` for lines that are not simple
/// string-to-string mappings (arrays, objects, non-string values, comments).
fn parse_kv_line(line: &str) -> Option<(String, String)> {
    let trimmed = line.trim_start();
    // Must start with `"`
    if !trimmed.starts_with('"') {
        return None;
    }
    // Find the closing quote of the key.
    let after_open = &trimmed[1..];
    let key_end = after_open.find('"')?;
    let key = &after_open[..key_end];
    if key.is_empty() {
        return None;
    }

    // After the key's closing quote we expect optional whitespace, then `:`,
    // then optional whitespace, then `"`.
    let rest = &after_open[key_end + 1..];
    let rest = rest.trim_start();
    let rest = rest.strip_prefix(':')?;
    let rest = rest.trim_start();
    let rest = rest.strip_prefix('"')?;

    // Value runs up to the next unescaped `"`.
    let val_end = rest.find('"')?;
    let val = &rest[..val_end];

    Some((key.to_string(), val.to_string()))
}

// ---------------------------------------------------------------------------
// Helpers: exempt-workspace matching
// ---------------------------------------------------------------------------

/// Determine whether a workspace-relative package.json path falls under one of
/// the catalog-exempt prefixes.  Returns `Some(ws)` with the matched exempt
/// prefix, or `None` if the path is not exempt.
///
/// Mirrors the shell logic:
/// ```bash
/// _ws="${_rel%%/*}"
/// case " $CATALOG_EXEMPT " in *" $_ws "*) _exempt=1 ;; esac
/// for _ex in $CATALOG_EXEMPT; do
///   case "$_rel" in "$_ex"/*) _exempt=1; _ws="$_ex" ;; esac
/// done
/// ```
fn exempt_workspace<'a>(rel_path: &str, exempt: &'a [String]) -> Option<&'a str> {
    let first_seg = rel_path.split('/').next().unwrap_or(rel_path);
    let mut matched: Option<&str> = None;
    // First: match on the top-level directory name.
    for ex in exempt {
        if ex == first_seg {
            matched = Some(ex.as_str());
        }
    }
    // Second: match on a deeper path-prefix (overrides the first-segment match
    // so that the diagnostic message names the deeper prefix).
    for ex in exempt {
        if rel_path.starts_with(ex.as_str()) && rel_path[ex.len()..].starts_with('/') {
            matched = Some(ex.as_str());
        }
    }
    matched
}

// ---------------------------------------------------------------------------
// CHECK: catalog (check.sh lines 782-843)
// ---------------------------------------------------------------------------

/// For every `package.json`, check that deps listed in the pnpm catalog use
/// `"catalog:"` as their version — unless the workspace is catalog-exempt, in
/// which case a concrete range is required and `"catalog:"` is a failure.
pub fn check_catalog(ctx: &Context) {
    if ctx.catalog_names.is_empty() {
        return;
    }
    let catalog_set: HashSet<&str> = ctx.catalog_names.iter().map(|s| s.as_str()).collect();

    let pkgs = ctx.files.discover(&ctx.root, "package.json");
    for pkg in &pkgs {
        let text = match fs::read_to_string(pkg) {
            Ok(t) => t,
            Err(_) => continue,
        };
        let rel = ctx.rel(pkg);
        let pairs = extract_string_pairs(&text);

        // Collect only the deps that are in the catalog.
        let catalog_decls: Vec<(&str, &str)> = pairs
            .iter()
            .filter(|(name, _)| catalog_set.contains(name.as_str()))
            .map(|(n, v)| (n.as_str(), v.as_str()))
            .collect();

        if catalog_decls.is_empty() {
            continue;
        }

        let exempt = exempt_workspace(&rel, &ctx.catalog_exempt);

        for (dep, val) in catalog_decls {
            if let Some(ws) = exempt {
                // Exempt workspaces: concrete range is correct; catalog: breaks
                // standalone/Docker build.
                if val.starts_with("catalog:") {
                    ctx.emit_fail(
                        "CATALOG",
                        &rel,
                        val,
                        "concrete",
                        &format!(
                            "'{dep}' uses catalog: but {ws} builds standalone \
                             (no workspace catalog at build time)"
                        ),
                        &format!(
                            "pin a concrete version of \"{dep}\" in {rel} \
                             — catalog: cannot resolve in the standalone/Docker build"
                        ),
                    );
                } else {
                    // Correct: concrete version in an exempt workspace → PIN (cyan).
                    ctx.rows.emit(
                        "CATALOG",
                        emit::GLYPH_PIN,
                        &ctx.colors.cyan,
                        &rel,
                        val,
                        "concrete",
                        &format!(
                            "exempt: {ws} builds standalone, so a concrete version \
                             is required (catalog: would break it)"
                        ),
                        "",
                    );
                    ctx.inc_pin();
                }
            } else {
                // Non-exempt: must use catalog:.
                if val.starts_with("catalog:") {
                    ctx.emit_ok("CATALOG", &rel, val, "catalog:", dep);
                } else {
                    ctx.emit_fail(
                        "CATALOG",
                        &rel,
                        val,
                        "catalog:",
                        &format!("'{dep}' is in the catalog but declared as a literal range here"),
                        &format!(
                            "set \"{dep}\": \"catalog:\" in {rel} \
                             (or a named \"catalog:<group>\" for intentional divergence)"
                        ),
                    );
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// CHECK: standalone workspace deps (check.sh lines 854-896)
// ---------------------------------------------------------------------------

/// Catalog-exempt packages that ship a Dockerfile build in an isolated Docker
/// context where monorepo workspace packages (`packages/*`) are not present.
/// Any `"workspace:*"` or `"workspace:^..."` dependency in such a package.json
/// breaks `docker build` → FAIL.
pub fn check_standalone_workspace_deps(ctx: &Context) {
    let pkgs = ctx.files.discover(&ctx.root, "package.json");
    for pkg in &pkgs {
        let rel = ctx.rel(pkg);
        let exempt = match exempt_workspace(&rel, &ctx.catalog_exempt) {
            Some(ws) => ws.to_string(),
            None => continue,
        };

        // Only flag packages that actually build in Docker.
        let ws_root = format!("{}/{}", ctx.root, exempt);
        let dockerfile = format!("{}/Dockerfile", ws_root);
        if !std::path::Path::new(&dockerfile).is_file() {
            continue;
        }

        let text = match fs::read_to_string(pkg) {
            Ok(t) => t,
            Err(_) => continue,
        };
        let pairs = extract_string_pairs(&text);

        // Find deps using the workspace: protocol.
        let ws_decls: Vec<(&str, &str)> = pairs
            .iter()
            .filter(|(_, v)| v.starts_with("workspace:"))
            .map(|(n, v)| (n.as_str(), v.as_str()))
            .collect();

        for (dep, val) in ws_decls {
            ctx.emit_fail(
                "STANDALONE_DEPS",
                &rel,
                val,
                "non-workspace",
                &format!(
                    "'{dep}' uses workspace: but {exempt} builds standalone \
                     (no monorepo workspace packages in Docker context)"
                ),
                &format!(
                    "vendor or inline \"{dep}\" in {rel} \
                     — workspace: cannot resolve in standalone Docker build"
                ),
            );
        }
    }
}

// ---------------------------------------------------------------------------
// CHECK: catalog orphan sweep (check.sh lines 903-923)
// ---------------------------------------------------------------------------

/// Every entry in the pnpm-workspace.yaml catalog must be declared by at least
/// one workspace's package.json.  An orphan entry is dead config.
pub fn catalog_orphan_sweep(ctx: &Context) {
    if ctx.catalog_names.is_empty() {
        return;
    }

    // Collect every dep name declared by any package.json (regardless of value
    // or exempt status).
    let pkgs = ctx.files.discover(&ctx.root, "package.json");
    let mut declared: HashSet<String> = HashSet::new();
    for pkg in &pkgs {
        let text = match fs::read_to_string(pkg) {
            Ok(t) => t,
            Err(_) => continue,
        };
        for (name, _) in extract_string_pairs(&text) {
            declared.insert(name);
        }
    }

    for dep in &ctx.catalog_names {
        if !declared.contains(dep.as_str()) {
            ctx.emit_fail(
                "CATALOG",
                "pnpm-workspace.yaml",
                "(unused)",
                "",
                &format!("catalog entry '{dep}' is declared by no workspace"),
                &format!("remove '{dep}' from the catalog in pnpm-workspace.yaml"),
            );
        }
    }
}

// ---------------------------------------------------------------------------
// ADVISORY: shared deps not in the catalog (check.sh lines 947-978)
// ---------------------------------------------------------------------------

/// Find deps that appear in 2+ package.json files with 2+ distinct version
/// ranges but are NOT in the catalog.  These are drift candidates — advisory
/// only, never a failure.
///
/// Only considers declarations inside `dependencies`, `devDependencies`,
/// `optionalDependencies`, or `peerDependencies` blocks (matching the shell
/// awk's `indeps` gating), and skips `workspace:` / `catalog:` values.
pub fn advisory_catalog(ctx: &Context) {
    let catalog_set: HashSet<&str> = ctx.catalog_names.iter().map(|s| s.as_str()).collect();
    let pkgs = ctx.files.discover(&ctx.root, "package.json");

    // For each dep name: track the set of distinct ranges and the set of
    // distinct files it appears in.
    struct DepInfo {
        ranges: Vec<String>,
        seen_pairs: HashSet<String>,
        file_count: usize,
        seen_files: HashSet<String>,
    }
    let mut deps: HashMap<String, DepInfo> = HashMap::new();

    for pkg in &pkgs {
        let text = match fs::read_to_string(pkg) {
            Ok(t) => t,
            Err(_) => continue,
        };

        // Track whether we're inside a dependency block.
        let mut in_deps = false;
        for line in text.lines() {
            let trimmed = line.trim();
            // Enter a dependency block.
            if !in_deps {
                if (trimmed.contains("\"dependencies\"")
                    || trimmed.contains("\"devDependencies\"")
                    || trimmed.contains("\"optionalDependencies\"")
                    || trimmed.contains("\"peerDependencies\""))
                    && trimmed.contains('{')
                {
                    in_deps = true;
                    continue;
                }
            }
            if in_deps {
                // Exit when we hit a closing brace.
                if trimmed.starts_with('}') {
                    in_deps = false;
                    continue;
                }
                if let Some((name, val)) = parse_kv_line(line) {
                    // Skip catalog entries and workspace:/catalog: protocols.
                    if catalog_set.contains(name.as_str()) {
                        continue;
                    }
                    if val.starts_with("workspace:") || val.starts_with("catalog:") {
                        continue;
                    }

                    let info = deps.entry(name.clone()).or_insert_with(|| DepInfo {
                        ranges: Vec::new(),
                        seen_pairs: HashSet::new(),
                        file_count: 0,
                        seen_files: HashSet::new(),
                    });

                    // Track distinct (name, val) pairs.
                    let pair_key = format!("{}\x1C{}", name, val);
                    if info.seen_pairs.insert(pair_key) {
                        info.ranges.push(val.clone());
                    }

                    // Track distinct files.
                    if info.seen_files.insert(pkg.clone()) {
                        info.file_count += 1;
                    }
                }
            }
        }
    }

    // Collect candidates: 2+ distinct ranges AND 2+ distinct files.
    let mut candidates: Vec<(&str, &[String])> = deps
        .iter()
        .filter(|(_, info)| info.ranges.len() >= 2 && info.file_count >= 2)
        .map(|(name, info)| (name.as_str(), info.ranges.as_slice()))
        .collect();

    // LC_ALL=C sort by dep name.
    candidates.sort_by(|a, b| a.0.as_bytes().cmp(b.0.as_bytes()));

    for (dep, ranges) in candidates {
        let ranges_str = ranges.join(", ");
        ctx.rows.emit(
            "CAT_ADVISORY",
            emit::GLYPH_WARN,
            &ctx.colors.yellow,
            dep,
            "",
            "",
            &format!("declared in 2+ workspaces with differing ranges: {ranges_str}"),
            &format!(
                "converge and add '{dep}' to the catalog \
                 (or a named catalog if the split is intentional)"
            ),
        );
        ctx.inc_warn();
    }
}
