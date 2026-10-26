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

//! Version-conformance checks: Go, Node, pnpm, stale-pin sweep, doc-sync,
//! and pnpm build-pin.
//!
//! Port of `check_go()`, `check_node()`, `check_pnpm()`, `stale_sweep()`,
//! `doc_sync()`, and `check_pnpm_pin()` from `check.sh` (lines 549-768).

use std::collections::HashSet;
use std::fs;
use std::path::Path;

use crate::canonical::{canonical_go, canonical_node, canonical_pnpm, go_is_newer};
use crate::emit::GLYPH_PIN;
use crate::Context;

// ---------------------------------------------------------------------------
// verdict — shared decision logic for (file, tool, found, canonical)
// ---------------------------------------------------------------------------

/// Core verdict for a discovered `(file, tool, found, canonical)`. Records a
/// report row and updates counters. `group` is the report bucket (go|node|pnpm).
/// When `is_go` is true, the extra "never newer than the workspace" safety rule
/// applies.
fn verdict(
    ctx: &Context,
    group: &str,
    file: &str,
    tool: &str,
    found: &str,
    canon: &str,
    is_go: bool,
) {
    // GO SAFETY: a module requiring NEWER Go than the workspace is ALWAYS a
    // fail, even if a pin claims to bless it (the workspace can't build it).
    if is_go && go_is_newer(found, canon) {
        ctx.emit_fail(
            group,
            file,
            found,
            canon,
            "requires newer Go than the workspace",
            &format!(
                "lower this module's go directive to <= {}, or bump go.work first",
                canon
            ),
        );
        return;
    }

    if found == canon {
        ctx.emit_ok(group, file, found, canon, "");
        return;
    }

    // found != canonical -> consult the registry.
    if let Some(pin) = ctx.registry.lookup(file, tool) {
        if pin.value == found {
            // Sanctioned pin. Surface it, then check expiry.
            if ctx.today.as_str() > pin.review_by.as_str() {
                ctx.emit_fail(
                    group,
                    file,
                    found,
                    canon,
                    &format!(
                        "EXPIRED pin (review_by {}, owner {}) \u{2014} re-justify or remove",
                        pin.review_by, pin.owner
                    ),
                    &format!(
                        "retire the pin: align {} to canonical {} and delete its row from version-pins.tsv",
                        file, canon
                    ),
                );
            } else {
                // Valid, unexpired pin: emit with GLYPH_PIN and cyan (matching
                // bash's C_CYAN, not yellow).
                ctx.rows.emit(
                    group,
                    GLYPH_PIN,
                    &ctx.colors.cyan,
                    file,
                    found,
                    canon,
                    &format!(
                        "PINNED until {} ({}): {}",
                        pin.review_by, pin.owner, pin.reason
                    ),
                    "",
                );
                ctx.inc_pin();
            }
        } else {
            // Registry disagrees with reality.
            ctx.emit_fail(
                group,
                file,
                found,
                canon,
                &format!(
                    "registry is STALE: says pinned_value {} but file is {}",
                    pin.value, found
                ),
                &format!(
                    "update or remove this row in version-pins.tsv to match {}",
                    file
                ),
            );
        }
        return;
    }

    // No pin record at all -> undeclared drift.
    ctx.emit_fail(
        group,
        file,
        found,
        canon,
        &format!(
            "DRIFT: matches neither canonical {} nor a registered pin",
            canon
        ),
        &format!(
            "align {} to {}, or add a justified row to version-pins.tsv",
            file, canon
        ),
    );
}

// ---------------------------------------------------------------------------
// CHECK: Go — every go.mod's `go` directive vs go.work's
// ---------------------------------------------------------------------------

/// Port of `check_go()` (check.sh lines 549-564).
pub fn check_go(ctx: &Context) {
    let canon = match canonical_go(&ctx.root) {
        Ok(v) => v,
        Err(_) => return, // go.work missing or has no go directive — nothing to check
    };

    let go_mods = ctx.files.discover(&ctx.root, "go.mod");
    for gomod in &go_mods {
        let content = match fs::read_to_string(gomod) {
            Ok(c) => c,
            Err(_) => continue,
        };

        // awk '$1 == "go" { print $2; exit }'
        let found = content.lines().find_map(|line| {
            let mut tokens = line.split_whitespace();
            if tokens.next() == Some("go") {
                tokens.next().map(|s| s.to_string())
            } else {
                None
            }
        });

        let found = match found {
            Some(v) => v,
            None => continue, // go.mod with no go directive is not our concern
        };

        verdict(ctx, "go", &ctx.rel(gomod), "go", &found, &canon, true);
    }
}

// ---------------------------------------------------------------------------
// CHECK: Node — every Dockerfile's effective node major vs .nvmrc's
// ---------------------------------------------------------------------------

/// Extract the effective node major(s) a Dockerfile pins, in first-seen order.
///
/// Port of `df_node_majors()` (check.sh lines 361-394). Handles both hardcoded
/// `FROM node:<major>...` and parameterized `FROM node:${NODE_VERSION}...`
/// resolved through its `ARG NODE_VERSION=<default>`. A parameterized FROM
/// whose ARG has no default emits nothing.
fn df_node_majors(content: &str) -> Vec<String> {
    let mut arg_defaults: std::collections::HashMap<String, String> =
        std::collections::HashMap::new();
    let mut seen = HashSet::new();
    let mut result = Vec::new();

    for line in content.lines() {
        let trimmed = line.trim();
        let upper_first = trimmed.split_whitespace().next().unwrap_or("");

        // Collect ARG defaults: `ARG NAME=VALUE`
        if upper_first.eq_ignore_ascii_case("ARG") {
            // Strip the ARG keyword and leading whitespace.
            let rest = trimmed.strip_prefix(upper_first).unwrap_or("").trim_start();
            if let Some(eq_pos) = rest.find('=') {
                let name = rest[..eq_pos].trim().to_string();
                let value = rest[eq_pos + 1..]
                    .split_whitespace()
                    .next()
                    .unwrap_or("")
                    .to_string();
                if !name.is_empty() {
                    arg_defaults.insert(name, value);
                }
            }
        }

        // FROM node:<tag>
        if upper_first.eq_ignore_ascii_case("FROM") {
            let img = trimmed.split_whitespace().nth(1).unwrap_or("");
            if let Some(tag) = img.strip_prefix("node:") {
                if tag.starts_with('$') {
                    // Parameterized: ${NAME}... or $NAME...
                    let mut name = tag.to_string();
                    // Strip leading $ or ${
                    if name.starts_with("${") {
                        name = name[2..].to_string();
                    } else {
                        name = name[1..].to_string();
                    }
                    // NAME ends at - } : or end of string
                    let end = name
                        .find(|c: char| c == '-' || c == '}' || c == ':')
                        .unwrap_or(name.len());
                    name.truncate(end);

                    if let Some(val) = arg_defaults.get(&name) {
                        if !val.is_empty() {
                            // split on non-digit, take first part
                            let major = extract_leading_digits(val);
                            if !major.is_empty() && seen.insert(major.clone()) {
                                result.push(major);
                            }
                        }
                    }
                } else {
                    // Hardcoded major: split on non-digit, take first part
                    let major = extract_leading_digits(tag);
                    if !major.is_empty() && seen.insert(major.clone()) {
                        result.push(major);
                    }
                }
            }
        }
    }
    result
}

/// Extract leading digits from a string, stopping at the first non-digit.
/// Mirrors awk's `split(tag, p, /[^0-9]/)` which puts leading digits in p[1].
fn extract_leading_digits(s: &str) -> String {
    s.chars().take_while(|c| c.is_ascii_digit()).collect()
}

/// Port of `check_node()` (check.sh lines 574-594).
pub fn check_node(ctx: &Context) {
    let canon = match canonical_node(&ctx.root) {
        Ok(v) => v,
        Err(_) => return,
    };

    let dockerfiles = ctx.files.discover(&ctx.root, "Dockerfile*");
    for dockerfile in &dockerfiles {
        let content = match fs::read_to_string(dockerfile) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let majors = df_node_majors(&content);
        if majors.is_empty() {
            continue;
        }

        let df_rel = ctx.rel(dockerfile);
        for maj in &majors {
            verdict(ctx, "node", &df_rel, "node", maj, &canon, false);
        }
    }
}

// ---------------------------------------------------------------------------
// CHECK: pnpm — every package.json with packageManager vs root's
// ---------------------------------------------------------------------------

/// Port of `check_pnpm()` (check.sh lines 600-613).
pub fn check_pnpm(ctx: &Context) {
    let canon = match canonical_pnpm(&ctx.root) {
        Ok(v) => v,
        Err(_) => return,
    };

    let packages = ctx.files.discover(&ctx.root, "package.json");
    for pkg in &packages {
        let content = match fs::read_to_string(pkg) {
            Ok(c) => c,
            Err(_) => continue,
        };

        if !content.contains("\"packageManager\"") {
            continue;
        }

        // sed -n 's/.*pnpm@\([0-9][0-9.]*\).*/\1/p' | head -1
        let found = extract_pnpm_version(&content);
        let found = match found {
            Some(v) => v,
            None => continue, // declares packageManager but not pnpm (e.g. npm@)
        };

        verdict(ctx, "pnpm", &ctx.rel(pkg), "pnpm", &found, &canon, false);
    }
}

/// Extract the pnpm version from a string containing `pnpm@X.Y.Z`.
/// Returns the first match.
fn extract_pnpm_version(content: &str) -> Option<String> {
    for line in content.lines() {
        if let Some(idx) = line.find("pnpm@") {
            let after = &line[idx + 5..];
            // Must start with a digit.
            if after.starts_with(|c: char| c.is_ascii_digit()) {
                let version: String = after
                    .chars()
                    .take_while(|c| c.is_ascii_digit() || *c == '.')
                    .collect();
                if !version.is_empty() {
                    return Some(version);
                }
            }
        }
    }
    None
}

// ---------------------------------------------------------------------------
// STALE-PIN SWEEP — for every registry row, if the file now matches
// canonical, the pin is dead weight (STALE). Also flags missing files.
// ---------------------------------------------------------------------------

/// Port of `stale_sweep()` (check.sh lines 622-658).
pub fn stale_sweep(ctx: &Context) {
    if ctx.registry.rows.is_empty() {
        return;
    }

    let c_go = canonical_go(&ctx.root).unwrap_or_default();
    let c_node = canonical_node(&ctx.root).unwrap_or_default();
    let c_pnpm = canonical_pnpm(&ctx.root).unwrap_or_default();

    for pin in &ctx.registry.rows {
        let fpath = format!("{}/{}", ctx.root, pin.file);

        if !Path::new(&fpath).is_file() {
            ctx.emit_fail(
                &pin.tool,
                &pin.file,
                "(missing)",
                "",
                &format!(
                    "STALE pin: {} no longer exists \u{2014} delete this row from version-pins.tsv",
                    pin.file
                ),
                &format!(
                    "delete the row for {} ({}) from version-pins.tsv",
                    pin.file, pin.tool
                ),
            );
            continue;
        }

        let (canon, cur) = match pin.tool.as_str() {
            "go" => {
                let content = fs::read_to_string(&fpath).unwrap_or_default();
                let cur = content.lines().find_map(|line| {
                    let mut tokens = line.split_whitespace();
                    if tokens.next() == Some("go") {
                        tokens.next().map(|s| s.to_string())
                    } else {
                        None
                    }
                });
                (c_go.clone(), cur)
            }
            "node" => {
                let content = fs::read_to_string(&fpath).unwrap_or_default();
                let majors = df_node_majors(&content);
                (c_node.clone(), majors.into_iter().next())
            }
            "pnpm" => {
                let content = fs::read_to_string(&fpath).unwrap_or_default();
                (c_pnpm.clone(), extract_pnpm_version(&content))
            }
            _ => continue,
        };

        if let Some(ref cur) = cur {
            if cur == &canon {
                ctx.emit_fail(
                    &pin.tool,
                    &pin.file,
                    cur,
                    &canon,
                    &format!(
                        "STALE pin: {} now matches canonical \u{2014} pin no longer needed",
                        pin.file
                    ),
                    &format!(
                        "delete this row from version-pins.tsv ({} matches canonical {})",
                        pin.file, canon
                    ),
                );
            }
        }
    }
}

// ---------------------------------------------------------------------------
// DOC SYNC — every pin must be documented in the exceptions doc
// ---------------------------------------------------------------------------

/// Port of `doc_sync()` (check.sh lines 667-683).
pub fn doc_sync(ctx: &Context) {
    if ctx.registry.rows.is_empty() {
        return;
    }

    let exceptions_doc = format!("{}/docs/engineering/version-pin-exceptions.md", ctx.root);

    let doc_content = match fs::read_to_string(&exceptions_doc) {
        Ok(c) => c,
        Err(_) => {
            ctx.die("exceptions doc missing: docs/engineering/version-pin-exceptions.md (every pin must be documented there)");
            return;
        }
    };

    for pin in &ctx.registry.rows {
        if !doc_content.contains(&pin.file) {
            ctx.emit_fail(
                &pin.tool,
                &pin.file,
                "",
                "",
                "UNDOCUMENTED pin: not described in docs/engineering/version-pin-exceptions.md",
                "document this exception (why + removal plan) in version-pin-exceptions.md",
            );
        }
    }
}

// ---------------------------------------------------------------------------
// CHECK: pnpm build pin — every Dockerfile that runs pnpm must have a
// reachable pin (packageManager, corepack prepare, or root package.json COPY)
// ---------------------------------------------------------------------------

/// Port of `check_pnpm_pin()` (check.sh lines 719-768).
pub fn check_pnpm_pin(ctx: &Context) {
    let dockerfiles = ctx.files.discover(&ctx.root, "Dockerfile*");

    for dockerfile in &dockerfiles {
        let content = match fs::read_to_string(dockerfile) {
            Ok(c) => c,
            Err(_) => continue,
        };

        // Skip Dockerfiles that don't mention pnpm.
        // grep -qiE '(^|[[:space:]])pnpm([[:space:]]|$)'
        if !mentions_pnpm(&content) {
            continue;
        }

        let dir = Path::new(dockerfile)
            .parent()
            .map(|p| p.to_string_lossy().to_string())
            .unwrap_or_default();
        let pkg = format!("{}/package.json", dir);
        let df_rel = ctx.rel(dockerfile);

        // (1) Co-located manifest carries the pin.
        if Path::new(&pkg).is_file() {
            if let Ok(pkg_content) = fs::read_to_string(&pkg) {
                if pkg_content.contains("\"packageManager\"") {
                    ctx.emit_ok(
                        "pnpm_pin",
                        &df_rel,
                        "pinned",
                        "pinned",
                        &format!("pnpm pinned via {} packageManager", ctx.rel(&pkg)),
                    );
                    continue;
                }
            }
        }

        // (2) The Dockerfile pins corepack explicitly.
        // grep -qE 'corepack[[:space:]]+prepare[[:space:]]+["'"'"']?pnpm@'
        if has_corepack_prepare_pnpm(&content) {
            ctx.emit_ok(
                "pnpm_pin",
                &df_rel,
                "pinned",
                "pinned",
                "pnpm pinned via corepack prepare in the Dockerfile",
            );
            continue;
        }

        // (3) The root package.json (repo-wide pin) is copied into the build
        //     context. Check that the Dockerfile COPYs package.json AND the root
        //     package.json has packageManager.
        if copies_package_json(&content) {
            let root_pkg = format!("{}/package.json", ctx.root);
            if let Ok(root_content) = fs::read_to_string(&root_pkg) {
                if root_content.contains("\"packageManager\"") {
                    ctx.emit_ok(
                        "pnpm_pin",
                        &df_rel,
                        "pinned",
                        "pinned",
                        "pnpm pinned via the root package.json copied into the image",
                    );
                    continue;
                }
            }
        }

        // No pin reachable.
        ctx.emit_fail(
            "pnpm_pin",
            &df_rel,
            "unpinned",
            "pinned",
            "Dockerfile runs pnpm with no pin reachable: no packageManager in its dir, no corepack prepare pnpm@..., no root package.json copied in",
            "pin it: add \"packageManager\" to the co-located package.json, or `corepack prepare pnpm@<root version> --activate` in the Dockerfile",
        );
    }
}

// ---------------------------------------------------------------------------
// Helpers for check_pnpm_pin
// ---------------------------------------------------------------------------

/// Returns true if content mentions pnpm as a standalone word (not as part of
/// another word). Matches bash's:
/// `grep -qiE '(^|[[:space:]])pnpm([[:space:]]|$)'`
fn mentions_pnpm(content: &str) -> bool {
    for line in content.lines() {
        let lower = line.to_ascii_lowercase();
        // Find each occurrence of "pnpm" and check word boundaries.
        let mut start = 0;
        while let Some(pos) = lower[start..].find("pnpm") {
            let abs_pos = start + pos;
            let before_ok = abs_pos == 0 || lower.as_bytes()[abs_pos - 1].is_ascii_whitespace();
            let after_pos = abs_pos + 4;
            let after_ok =
                after_pos >= lower.len() || lower.as_bytes()[after_pos].is_ascii_whitespace();
            if before_ok && after_ok {
                return true;
            }
            start = abs_pos + 1;
        }
    }
    false
}

/// Returns true if the content has a `corepack prepare ... pnpm@` pattern.
/// Matches: `corepack[[:space:]]+prepare[[:space:]]+["']?pnpm@`
fn has_corepack_prepare_pnpm(content: &str) -> bool {
    for line in content.lines() {
        let trimmed = line.trim();
        let mut search = trimmed;
        while let Some(pos) = search.find("corepack") {
            let after = search[pos + 8..].trim_start();
            if let Some(rest) = after.strip_prefix("prepare") {
                let rest = rest.trim_start();
                let rest = rest
                    .strip_prefix('"')
                    .or_else(|| rest.strip_prefix('\''))
                    .unwrap_or(rest);
                if rest.starts_with("pnpm@") {
                    return true;
                }
            }
            search = &search[pos + 1..];
        }
    }
    false
}

/// Returns true if the Dockerfile COPYs `package.json`.
/// Matches: `^[[:space:]]*COPY[[:space:]]+([^[:space:]]+[[:space:]]+)*package\.json([[:space:]]|$)`
fn copies_package_json(content: &str) -> bool {
    for line in content.lines() {
        let trimmed = line.trim();
        let upper_first = trimmed.split_whitespace().next().unwrap_or("");
        if !upper_first.eq_ignore_ascii_case("COPY") {
            continue;
        }
        // Check if any token in the COPY instruction is "package.json".
        let tokens: Vec<&str> = trimmed.split_whitespace().collect();
        // Skip the COPY keyword itself (index 0) and look at the remaining
        // source tokens (all but the last, which is the destination).
        if tokens.len() >= 3 {
            // Source tokens are tokens[1..tokens.len()-1], dest is the last.
            for token in &tokens[1..] {
                if *token == "package.json" {
                    return true;
                }
            }
        }
    }
    false
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extract_leading_digits_works() {
        assert_eq!(extract_leading_digits("22-slim"), "22");
        assert_eq!(extract_leading_digits("22.1.0"), "22");
        assert_eq!(extract_leading_digits("22"), "22");
        assert_eq!(extract_leading_digits(""), "");
        assert_eq!(extract_leading_digits("slim"), "");
    }

    #[test]
    fn df_node_majors_hardcoded() {
        let content = "FROM node:22-slim AS build\nRUN npm install\n";
        assert_eq!(df_node_majors(content), vec!["22"]);
    }

    #[test]
    fn df_node_majors_parameterized() {
        let content = "ARG NODE_VERSION=22\nFROM node:${NODE_VERSION}-slim AS build\n";
        assert_eq!(df_node_majors(content), vec!["22"]);
    }

    #[test]
    fn df_node_majors_no_default() {
        // Parameterized FROM with no ARG default — emits nothing.
        let content = "ARG NODE_VERSION\nFROM node:${NODE_VERSION}-slim AS build\n";
        assert!(df_node_majors(content).is_empty());
    }

    #[test]
    fn df_node_majors_no_node() {
        let content = "FROM python:3.12-slim\nRUN pip install flask\n";
        assert!(df_node_majors(content).is_empty());
    }

    #[test]
    fn df_node_majors_multi_stage_dedup() {
        let content = "FROM node:22-slim AS deps\nFROM node:22-slim AS build\n";
        // Same major appears once.
        assert_eq!(df_node_majors(content), vec!["22"]);
    }

    #[test]
    fn df_node_majors_multi_stage_distinct() {
        let content = "FROM node:20-slim AS deps\nFROM node:22-slim AS build\n";
        assert_eq!(df_node_majors(content), vec!["20", "22"]);
    }

    #[test]
    fn extract_pnpm_version_works() {
        let content = r#"{ "packageManager": "pnpm@9.15.4+sha512.abc" }"#;
        assert_eq!(extract_pnpm_version(content), Some("9.15.4".to_string()));
    }

    #[test]
    fn extract_pnpm_version_no_pnpm() {
        let content = r#"{ "packageManager": "npm@10.0.0" }"#;
        assert_eq!(extract_pnpm_version(content), None);
    }

    #[test]
    fn mentions_pnpm_standalone() {
        assert!(mentions_pnpm("RUN pnpm install"));
        assert!(mentions_pnpm("pnpm build"));
        assert!(mentions_pnpm("RUN corepack enable && pnpm"));
        // Not standalone: part of another word.
        assert!(!mentions_pnpm("RUN pnpmx install"));
        // But at end of line is fine.
        assert!(mentions_pnpm("corepack enable pnpm"));
    }

    #[test]
    fn has_corepack_prepare_pnpm_works() {
        assert!(has_corepack_prepare_pnpm(
            "RUN corepack prepare pnpm@9.15.4 --activate"
        ));
        assert!(has_corepack_prepare_pnpm(
            "RUN corepack prepare \"pnpm@9.15.4\" --activate"
        ));
        assert!(!has_corepack_prepare_pnpm("RUN corepack enable"));
    }

    #[test]
    fn copies_package_json_works() {
        assert!(copies_package_json("COPY package.json ./"));
        assert!(copies_package_json("COPY pnpm-lock.yaml package.json ./"));
        assert!(!copies_package_json("COPY requirements.txt ./"));
        assert!(!copies_package_json("RUN cat package.json"));
    }
}
