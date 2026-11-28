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

use crate::canonical::{
    canonical_go, canonical_node, canonical_node_exact, canonical_pnpm, canonical_rust, go_is_newer,
};
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
// CHECK: Node — every Dockerfile & workflow Node version vs .nvmrc
// ---------------------------------------------------------------------------

/// Return true when `s` is an exact `major.minor.patch` numeric triplet.
fn is_full_semver(s: &str) -> bool {
    let mut parts = s.split('.');
    matches!(
        (parts.next(), parts.next(), parts.next(), parts.next()),
        (Some(a), Some(b), Some(c), None)
            if !a.is_empty()
                && !b.is_empty()
                && !c.is_empty()
                && a.chars().all(|ch| ch.is_ascii_digit())
                && b.chars().all(|ch| ch.is_ascii_digit())
                && c.chars().all(|ch| ch.is_ascii_digit())
    )
}

/// Extract leading digits from a string, stopping at the first non-digit.
/// Mirrors awk's `split(tag, p, /[^0-9]/)` which puts leading digits in p[1].
fn extract_leading_digits(s: &str) -> String {
    s.chars().take_while(|c| c.is_ascii_digit()).collect()
}

/// Parse a Node version token (e.g. `"26.13.1"`, `"v26.13.1"`, `"26.13.1-slim"`,
/// `"26-bookworm-slim"`, `"26.x"`) into either an exact `X.Y.Z` semver string or
/// a major version string. Returns `None` if no leading numeric version exists.
fn parse_node_version_token(raw: &str) -> Option<String> {
    let s = raw.trim();
    let s = if let Some(rest) = s.strip_prefix('v') {
        if rest.starts_with(|c: char| c.is_ascii_digit()) {
            rest
        } else {
            s
        }
    } else {
        s
    };

    let numeric: String = s
        .chars()
        .take_while(|c| c.is_ascii_digit() || *c == '.')
        .collect();
    let numeric = numeric.trim_end_matches('.');
    if is_full_semver(numeric) {
        return Some(numeric.to_string());
    }

    let major = extract_leading_digits(numeric);
    if major.is_empty() {
        None
    } else {
        Some(major)
    }
}

fn strip_yaml_comment(s: &str) -> &str {
    let (mut single, mut double) = (false, false);
    let bytes = s.as_bytes();
    for (i, &b) in bytes.iter().enumerate() {
        match b {
            b'\'' if !double => single = !single,
            b'"' if !single => double = !double,
            b'#' if !single && !double && (i == 0 || bytes[i - 1] == b' ') => {
                return s[..i].trim_end();
            }
            _ => {}
        }
    }
    s.trim_end()
}

fn unquote_yaml(s: &str) -> &str {
    let s = s.trim();
    if s.len() >= 2
        && ((s.starts_with('"') && s.ends_with('"')) || (s.starts_with('\'') && s.ends_with('\'')))
    {
        &s[1..s.len() - 1]
    } else {
        s
    }
}

/// Extract the effective node version(s) a Dockerfile pins, in first-seen order.
///
/// Handles both hardcoded `FROM node:<tag>...` and parameterized
/// `FROM node:${NODE_VERSION}...` resolved through its `ARG NODE_VERSION=<default>`.
/// Preserves exact `X.Y.Z` versions when written, and otherwise returns the
/// major version. A parameterized FROM whose ARG has no default emits nothing.
fn df_node_versions(content: &str) -> Vec<String> {
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

        // FROM [--flag=...] node:<tag>
        if upper_first.eq_ignore_ascii_case("FROM") {
            let img = trimmed
                .split_whitespace()
                .skip(1)
                .find(|tok| !tok.starts_with("--"))
                .unwrap_or("");
            if let Some(tag) = img.strip_prefix("node:") {
                let raw = if tag.starts_with('$') {
                    // Parameterized: ${NAME}... or $NAME...
                    let mut name = tag.to_string();
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
                    arg_defaults.get(&name).map(|s| s.as_str()).unwrap_or("")
                } else {
                    tag
                };
                if let Some(ver) = parse_node_version_token(raw) {
                    if seen.insert(ver.clone()) {
                        result.push(ver);
                    }
                }
            }
        }
    }
    result
}

/// Extract `matrix.<key>` identifiers from an expression like `${{ matrix.node }}`.
fn extract_matrix_keys(expr: &str) -> Vec<String> {
    let mut keys = Vec::new();
    let mut rest = expr;
    while let Some(idx) = rest.find("matrix.") {
        let after = &rest[idx + "matrix.".len()..];
        let key: String = after
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric() || *c == '_' || *c == '-')
            .collect();
        if !key.is_empty() {
            keys.push(key);
        }
        rest = after;
    }
    keys
}

/// Extract pinned Node versions from a GitHub Actions workflow (`node-version:`
/// literals and `matrix.<key>` values referenced by `node-version:`).
fn wf_node_versions(content: &str) -> Vec<String> {
    let mut seen = HashSet::new();
    let mut result = Vec::new();
    let mut matrix_keys: HashSet<String> = HashSet::new();

    let push_ver = |raw: &str, seen: &mut HashSet<String>, result: &mut Vec<String>| {
        if let Some(ver) = parse_node_version_token(unquote_yaml(raw)) {
            if seen.insert(ver.clone()) {
                result.push(ver);
            }
        }
    };

    // Pass 1: find literal `node-version:` values and any `matrix.<key>` references.
    for raw_line in content.lines() {
        let line = strip_yaml_comment(raw_line.trim_end_matches('\r'));
        let trimmed = line.trim_start();
        if trimmed.is_empty() {
            continue;
        }
        let after_dash = trimmed.strip_prefix("- ").unwrap_or(trimmed).trim_start();
        if let Some(rest) = after_dash.strip_prefix("node-version:") {
            let val = unquote_yaml(rest);
            if val.contains("${{") {
                for key in extract_matrix_keys(val) {
                    matrix_keys.insert(key);
                }
            } else if !val.is_empty() {
                push_ver(val, &mut seen, &mut result);
            }
        }
    }

    // Pass 2: if any `node-version` references `matrix.<key>`, extract values from `matrix:`.
    if !matrix_keys.is_empty() {
        let mut matrix_indent: Option<usize> = None;
        let mut active_seq_indent: Option<usize> = None;

        for raw_line in content.lines() {
            let line = strip_yaml_comment(raw_line.trim_end_matches('\r'));
            let trimmed = line.trim_start();
            if trimmed.is_empty() {
                continue;
            }
            let ind = line.len() - trimmed.len();

            if let Some(mi) = matrix_indent {
                if ind <= mi {
                    matrix_indent = None;
                    active_seq_indent = None;
                }
            }

            if matrix_indent.is_none() {
                if trimmed == "matrix:" || trimmed.starts_with("matrix: ") {
                    matrix_indent = Some(ind);
                }
                continue;
            }

            if let Some(si) = active_seq_indent {
                if ind < si || (ind == si && !trimmed.starts_with("- ") && trimmed != "-") {
                    active_seq_indent = None;
                } else if let Some(item) = trimmed.strip_prefix("- ") {
                    let item = unquote_yaml(item);
                    if !item.is_empty() && !item.contains("${{") {
                        push_ver(item, &mut seen, &mut result);
                    }
                    continue;
                }
            }

            if let Some((key, rest)) = trimmed.split_once(':') {
                let key = key.trim();
                if matrix_keys.contains(key) {
                    let val = rest.trim();
                    if val.is_empty() {
                        active_seq_indent = Some(ind);
                    } else if val.starts_with('[') && val.ends_with(']') {
                        let inner = &val[1..val.len() - 1];
                        for elem in inner.split(',') {
                            let elem = unquote_yaml(elem);
                            if !elem.is_empty() && !elem.contains("${{") {
                                push_ver(elem, &mut seen, &mut result);
                            }
                        }
                    } else if !val.contains("${{") {
                        push_ver(val, &mut seen, &mut result);
                    }
                }
            }
        }
    }

    result
}

fn check_node_extracted(
    ctx: &Context,
    rel: &str,
    versions: &[String],
    canon_major: &str,
    canon_exact: Option<&str>,
) {
    for v in versions {
        let expected = if is_full_semver(v) {
            canon_exact.unwrap_or(canon_major)
        } else {
            canon_major
        };
        verdict(ctx, "node", rel, "node", v, expected, false);
    }
}

/// Port of `check_node()` (check.sh lines 574-594), extended to compare exact
/// `major.minor.patch` versions in Dockerfiles and `.github/workflows/` files
/// against `.nvmrc`.
pub fn check_node(ctx: &Context) {
    let canon_major = match canonical_node(&ctx.root) {
        Ok(v) => v,
        Err(_) => return,
    };
    let canon_exact = canonical_node_exact(&ctx.root).ok();

    let dockerfiles = ctx.files.discover(&ctx.root, "Dockerfile*");
    for dockerfile in &dockerfiles {
        if dockerfile.ends_with(".dockerignore") {
            continue;
        }
        let content = match fs::read_to_string(dockerfile) {
            Ok(c) => c,
            Err(_) => continue,
        };

        let versions = df_node_versions(&content);
        if versions.is_empty() {
            continue;
        }

        let df_rel = ctx.rel(dockerfile);
        check_node_extracted(
            ctx,
            &df_rel,
            &versions,
            &canon_major,
            canon_exact.as_deref(),
        );
    }

    let mut workflows = ctx.files.discover(&ctx.root, "*.yml");
    workflows.extend(ctx.files.discover(&ctx.root, "*.yaml"));
    workflows.sort();
    for wf in &workflows {
        let rel = ctx.rel(wf);
        if !(rel.starts_with(".github/workflows/") || rel.contains("/.github/workflows/")) {
            continue;
        }
        let content = match fs::read_to_string(wf) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let versions = wf_node_versions(&content);
        if versions.is_empty() {
            continue;
        }
        check_node_extracted(ctx, &rel, &versions, &canon_major, canon_exact.as_deref());
    }
}

// ---------------------------------------------------------------------------
// CHECK: Rust — every rust-toolchain(.toml) vs MODULE.bazel's rust.toolchain
// ---------------------------------------------------------------------------

/// Every `rust-toolchain` / `rust-toolchain.toml` in the tree must pin exactly
/// the Bazel toolchain's version (`rust.toolchain` in MODULE.bazel). rustup
/// reads such a file in its directory and every directory below, so one that
/// says `channel = "stable"` silently moves every rustup-driven cargo/rustc
/// run there to whatever stable is today (#4183). It cannot move Bazel's
/// hermetic toolchain, which is exactly why the two would drift apart. A
/// justified exception goes in version-pins.tsv (tool `rust`) like any pin.
pub fn check_rust_toolchain(ctx: &Context) {
    // Fail closed. Unlike go.work, whose absence means no Go to check, this
    // repo always has a Rust toolchain: not finding its version means this
    // reader no longer understands MODULE.bazel, and returning here would
    // report every rust-toolchain file as clean.
    let canon = match canonical_rust(&ctx.root) {
        Ok(v) => v,
        Err(e) => {
            ctx.emit_fail(
                "rust",
                "MODULE.bazel",
                "",
                "",
                &e,
                "keep a use_extension(\"@rules_rust//rust:extensions.bzl\", \"rust\") binding with a .toolchain(versions = [...]) call, or teach canonical_rust the new shape",
            );
            return;
        }
    };
    let mut files = ctx.files.discover(&ctx.root, "rust-toolchain");
    files.extend(ctx.files.discover(&ctx.root, "rust-toolchain.toml"));
    files.sort();
    for f in &files {
        let content = match fs::read_to_string(f) {
            Ok(c) => c,
            Err(_) => continue,
        };
        let found = rust_toolchain_channel(&content).unwrap_or_else(|| "(no channel)".to_string());
        verdict(ctx, "rust", &ctx.rel(f), "rust", &found, &canon, false);
    }
}

/// The toolchain a `rust-toolchain(.toml)` file selects: TOML's
/// `channel = "..."`, or the legacy one-line form (`1.75.0`, `nightly`).
fn rust_toolchain_channel(content: &str) -> Option<String> {
    let lines: Vec<&str> = content
        .lines()
        .map(|l| l.split('#').next().unwrap_or("").trim())
        .filter(|l| !l.is_empty())
        .collect();
    for l in &lines {
        if let Some(rest) = l.strip_prefix("channel") {
            let v = rest.trim_start().strip_prefix('=')?.trim();
            return Some(v.trim_matches(|c| c == '"' || c == '\'').to_string());
        }
    }
    // Legacy form: the whole file is one toolchain name, no TOML at all.
    match lines.as_slice() {
        [one] if !one.contains('=') && !one.starts_with('[') => Some(one.to_string()),
        _ => None,
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
    let c_node_exact = canonical_node_exact(&ctx.root).ok();
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
                let versions = if pin.file.ends_with(".yml") || pin.file.ends_with(".yaml") {
                    wf_node_versions(&content)
                } else {
                    df_node_versions(&content)
                };
                let cur = versions.into_iter().next();
                let canon = match cur.as_deref() {
                    Some(v) if is_full_semver(v) => {
                        c_node_exact.clone().unwrap_or_else(|| c_node.clone())
                    }
                    _ => c_node.clone(),
                };
                (canon, cur)
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
// reachable pin (npm install -g pnpm@..., packageManager, corepack prepare,
// or root package.json COPY)
// ---------------------------------------------------------------------------

/// Port of `check_pnpm_pin()` (check.sh lines 719-768).
pub fn check_pnpm_pin(ctx: &Context) {
    let canon_pnpm = canonical_pnpm(&ctx.root).ok();
    let dockerfiles = ctx.files.discover(&ctx.root, "Dockerfile*");

    for dockerfile in &dockerfiles {
        if dockerfile.ends_with(".dockerignore") {
            continue;
        }
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

        let npm_pins = extract_npm_install_pnpm_versions(&content);
        let corepack_pins = extract_corepack_prepare_pnpm_versions(&content);

        // Enforce parity with root package.json packageManager before any branch
        // short-circuiting so Dockerfiles with co-located/root package.json also
        // fail on pin drift.
        if let Some(ref canon) = canon_pnpm {
            if let Some(ver) = npm_pins
                .iter()
                .chain(corepack_pins.iter())
                .find(|v| v.as_str() != canon.as_str())
            {
                ctx.emit_fail(
                    "pnpm_pin",
                    &df_rel,
                    ver,
                    canon,
                    &format!(
                        "Dockerfile pins pnpm@{ver}, which disagrees with root package.json packageManager (pnpm@{canon})"
                    ),
                    &format!("align the Dockerfile pin to pnpm@{canon} to match root package.json"),
                );
                continue;
            }
        }

        // (1) The Dockerfile installs a pinned pnpm via npm.
        if !npm_pins.is_empty() {
            ctx.emit_ok(
                "pnpm_pin",
                &df_rel,
                "pinned",
                "pinned",
                "pnpm pinned via npm install -g pnpm@... in the Dockerfile",
            );
            continue;
        }

        // (2) Co-located manifest carries the pin.
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

        // (3) The Dockerfile pins corepack explicitly.
        // grep -qE 'corepack[[:space:]]+prepare[[:space:]]+["'"'"']?pnpm@'
        if !corepack_pins.is_empty() {
            ctx.emit_ok(
                "pnpm_pin",
                &df_rel,
                "pinned",
                "pinned",
                "pnpm pinned via corepack prepare in the Dockerfile",
            );
            continue;
        }

        // (4) The root package.json (repo-wide pin) is copied into the build
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
            "Dockerfile runs pnpm with no pin reachable: no npm install -g pnpm@..., no packageManager in its dir, no corepack prepare pnpm@..., no root package.json copied in",
            "pin it: run `npm install -g pnpm@<root version>` in the Dockerfile, or add \"packageManager\" to the co-located package.json",
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

/// Extract pinned versions from `npm install -g pnpm@<version>` (or `npm i` /
/// `--global`, optionally quoted).
fn extract_npm_install_pnpm_versions(content: &str) -> Vec<String> {
    let mut versions = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        for seg in trimmed
            .split("&&")
            .flat_map(|s| s.split("||"))
            .flat_map(|s| s.split(';'))
        {
            let mut tokens: Vec<&str> = seg.split_whitespace().collect();
            if tokens
                .first()
                .is_some_and(|t| t.eq_ignore_ascii_case("RUN"))
            {
                tokens.remove(0);
            }
            if tokens.first() != Some(&"npm") || !matches!(tokens.get(1), Some(&"install" | &"i")) {
                continue;
            }
            let rest = &tokens[2..];
            if !rest.iter().any(|t| *t == "-g" || *t == "--global") {
                continue;
            }
            for tok in rest {
                let stripped = tok.trim_matches(|c| c == '"' || c == '\'');
                if let Some(after) = stripped.strip_prefix("pnpm@") {
                    if after.starts_with(|c: char| c.is_ascii_digit()) {
                        let ver: String = after
                            .chars()
                            .take_while(|c| c.is_ascii_digit() || *c == '.')
                            .collect();
                        if !ver.is_empty() {
                            versions.push(ver);
                        }
                    }
                }
            }
        }
    }
    versions
}

/// Returns true if the content has an `npm install -g pnpm@<version>` pattern.
#[cfg_attr(not(test), allow(dead_code))]
fn has_npm_install_pnpm(content: &str) -> bool {
    !extract_npm_install_pnpm_versions(content).is_empty()
}

/// Extract pinned versions from `corepack prepare ... pnpm@<version>` patterns.
fn extract_corepack_prepare_pnpm_versions(content: &str) -> Vec<String> {
    let mut versions = Vec::new();
    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let mut search = trimmed;
        while let Some(pos) = search.find("corepack") {
            let after = search[pos + 8..].trim_start();
            if let Some(rest) = after.strip_prefix("prepare") {
                let rest = rest.trim_start();
                let rest = rest
                    .strip_prefix('"')
                    .or_else(|| rest.strip_prefix('\''))
                    .unwrap_or(rest);
                if let Some(after_at) = rest.strip_prefix("pnpm@") {
                    if after_at.starts_with(|c: char| c.is_ascii_digit()) {
                        let ver: String = after_at
                            .chars()
                            .take_while(|c| c.is_ascii_digit() || *c == '.')
                            .collect();
                        if !ver.is_empty() {
                            versions.push(ver);
                        }
                    }
                }
            }
            search = &search[pos + 1..];
        }
    }
    versions
}

/// Returns true if the content has a `corepack prepare ... pnpm@` pattern.
/// Matches: `corepack[[:space:]]+prepare[[:space:]]+["']?pnpm@`
#[cfg_attr(not(test), allow(dead_code))]
fn has_corepack_prepare_pnpm(content: &str) -> bool {
    !extract_corepack_prepare_pnpm_versions(content).is_empty()
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
// CHECK: release-please JSON extra-files — every non-package.json `"type": "json"`
// extra-file must be in release-please's 2-space expanded-array layout AND
// marked `rules-lint-ignored=true` in `.gitattributes` so `//:tidy` (Prettier)
// does not collapse short arrays back and fail `tidy-check` on release PRs.
// ---------------------------------------------------------------------------

#[derive(Debug)]
enum OrderedJson {
    Leaf(serde_json::Value),
    Arr(Vec<OrderedJson>),
    Obj(Vec<(String, OrderedJson)>),
}

struct JsonCursor<'a> {
    bytes: &'a [u8],
    src: &'a str,
    pos: usize,
}

impl<'a> JsonCursor<'a> {
    fn skip_ws(&mut self) {
        while self.pos < self.bytes.len() && self.bytes[self.pos].is_ascii_whitespace() {
            self.pos += 1;
        }
    }

    fn parse_value(&mut self) -> Result<OrderedJson, String> {
        self.skip_ws();
        let b = *self.bytes.get(self.pos).ok_or("unexpected EOF")?;
        match b {
            b'{' => self.parse_obj(),
            b'[' => self.parse_arr(),
            b'"' => {
                let s = self.parse_str()?;
                Ok(OrderedJson::Leaf(serde_json::Value::String(s)))
            }
            _ => {
                let start = self.pos;
                while self.pos < self.bytes.len() {
                    let c = self.bytes[self.pos];
                    if c.is_ascii_whitespace() || matches!(c, b',' | b']' | b'}') {
                        break;
                    }
                    self.pos += 1;
                }
                let tok = &self.src[start..self.pos];
                let val: serde_json::Value =
                    serde_json::from_str(tok).map_err(|e| format!("invalid token {tok:?}: {e}"))?;
                Ok(OrderedJson::Leaf(val))
            }
        }
    }

    fn parse_str(&mut self) -> Result<String, String> {
        let start = self.pos;
        self.pos += 1; // opening '"'
        let mut escaped = false;
        while self.pos < self.bytes.len() {
            let c = self.bytes[self.pos];
            self.pos += 1;
            if escaped {
                escaped = false;
            } else if c == b'\\' {
                escaped = true;
            } else if c == b'"' {
                let slice = &self.src[start..self.pos];
                return serde_json::from_str(slice)
                    .map_err(|e| format!("invalid string {slice}: {e}"));
            }
        }
        Err("unterminated JSON string".to_string())
    }

    fn parse_arr(&mut self) -> Result<OrderedJson, String> {
        self.pos += 1; // '['
        self.skip_ws();
        let mut items = Vec::new();
        if self.bytes.get(self.pos) == Some(&b']') {
            self.pos += 1;
            return Ok(OrderedJson::Arr(items));
        }
        loop {
            items.push(self.parse_value()?);
            self.skip_ws();
            match self.bytes.get(self.pos) {
                Some(b',') => {
                    self.pos += 1;
                }
                Some(b']') => {
                    self.pos += 1;
                    return Ok(OrderedJson::Arr(items));
                }
                other => return Err(format!("expected ',' or ']', found {other:?}")),
            }
        }
    }

    fn parse_obj(&mut self) -> Result<OrderedJson, String> {
        self.pos += 1; // '{'
        self.skip_ws();
        let mut entries: Vec<(String, OrderedJson)> = Vec::new();
        if self.bytes.get(self.pos) == Some(&b'}') {
            self.pos += 1;
            return Ok(OrderedJson::Obj(entries));
        }
        loop {
            self.skip_ws();
            if self.bytes.get(self.pos) != Some(&b'"') {
                return Err("expected string key in object".to_string());
            }
            let key = self.parse_str()?;
            self.skip_ws();
            if self.bytes.get(self.pos) != Some(&b':') {
                return Err("expected ':' after object key".to_string());
            }
            self.pos += 1;
            let val = self.parse_value()?;
            if let Some(existing) = entries.iter_mut().find(|(k, _)| k == &key) {
                existing.1 = val;
            } else {
                entries.push((key, val));
            }
            self.skip_ws();
            match self.bytes.get(self.pos) {
                Some(b',') => {
                    self.pos += 1;
                }
                Some(b'}') => {
                    self.pos += 1;
                    return Ok(OrderedJson::Obj(entries));
                }
                other => return Err(format!("expected ',' or '}}', found {other:?}")),
            }
        }
    }
}

fn format_ordered_json(val: &OrderedJson, indent: usize) -> String {
    match val {
        OrderedJson::Leaf(v) => serde_json::to_string(v).expect("serialize leaf"),
        OrderedJson::Arr(items) => {
            if items.is_empty() {
                return "[]".to_string();
            }
            let inner = " ".repeat(indent + 2);
            let outer = " ".repeat(indent);
            let parts: Vec<String> = items
                .iter()
                .map(|i| format!("{inner}{}", format_ordered_json(i, indent + 2)))
                .collect();
            format!("[\n{}\n{outer}]", parts.join(",\n"))
        }
        OrderedJson::Obj(entries) => {
            if entries.is_empty() {
                return "{}".to_string();
            }
            let inner = " ".repeat(indent + 2);
            let outer = " ".repeat(indent);
            let parts: Vec<String> = entries
                .iter()
                .map(|(k, v)| {
                    let k_str = serde_json::to_string(k).expect("serialize key");
                    format!("{inner}{k_str}: {}", format_ordered_json(v, indent + 2))
                })
                .collect();
            format!("{{\n{}\n{outer}}}", parts.join(",\n"))
        }
    }
}

fn release_please_json_layout(text: &str) -> Result<String, String> {
    let mut cur = JsonCursor {
        bytes: text.as_bytes(),
        src: text,
        pos: 0,
    };
    let parsed = cur.parse_value()?;
    cur.skip_ws();
    if cur.pos != cur.bytes.len() {
        return Err("trailing characters after JSON root".to_string());
    }
    let mut out = format_ordered_json(&parsed, 0);
    out.push('\n');
    Ok(out)
}

fn gitattr_glob_rec(pat: &[char], pi: usize, txt: &[char], ti: usize) -> bool {
    if pi == pat.len() {
        return ti == txt.len();
    }
    if pi + 1 < pat.len() && pat[pi] == '*' && pat[pi + 1] == '*' {
        // `/**/` or leading `**/`: zero or more directory segments.
        if pi + 2 < pat.len() && pat[pi + 2] == '/' && gitattr_glob_rec(pat, pi + 3, txt, ti) {
            return true;
        }
        for skip in 0..=(txt.len() - ti) {
            if gitattr_glob_rec(pat, pi + 2, txt, ti + skip) {
                return true;
            }
        }
        return false;
    }
    match pat[pi] {
        '*' => {
            let mut skip = 0;
            loop {
                if gitattr_glob_rec(pat, pi + 1, txt, ti + skip) {
                    return true;
                }
                if ti + skip >= txt.len() || txt[ti + skip] == '/' {
                    break;
                }
                skip += 1;
            }
            false
        }
        '?' => ti < txt.len() && txt[ti] != '/' && gitattr_glob_rec(pat, pi + 1, txt, ti + 1),
        c => ti < txt.len() && txt[ti] == c && gitattr_glob_rec(pat, pi + 1, txt, ti + 1),
    }
}

fn is_rules_lint_ignored(gitattributes: &str, rel_path: &str) -> bool {
    let basename = rel_path.rsplit('/').next().unwrap_or(rel_path);
    let mut ignored = false;
    for raw_line in gitattributes.lines() {
        let line = raw_line.trim();
        if line.is_empty() || line.starts_with('#') {
            continue;
        }
        let mut tokens = line.split_whitespace();
        let Some(pattern) = tokens.next() else {
            continue;
        };
        let pat_str = pattern.strip_prefix('/').unwrap_or(pattern);
        let pat_chars: Vec<char> = pat_str.chars().collect();
        let target = if pattern.contains('/') {
            rel_path
        } else {
            basename
        };
        let txt_chars: Vec<char> = target.chars().collect();
        if !gitattr_glob_rec(&pat_chars, 0, &txt_chars, 0) {
            continue;
        }
        for attr in tokens {
            if attr == "rules-lint-ignored" || attr == "rules-lint-ignored=true" {
                ignored = true;
            } else if attr == "-rules-lint-ignored" || attr == "rules-lint-ignored=false" {
                ignored = false;
            }
        }
    }
    ignored
}

fn normalize_rel_path(base: &str, rel: &str) -> String {
    let combined = if base.is_empty() || base == "." {
        rel.to_string()
    } else {
        format!("{}/{}", base.trim_matches('/'), rel)
    };
    let mut parts: Vec<&str> = Vec::new();
    for seg in combined.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            s => parts.push(s),
        }
    }
    parts.join("/")
}

/// Every non-`package.json` `"type": "json"` extra-file in any
/// `release-please-config.json` must be committed in `release-please`'s
/// 2-space expanded-array layout and marked `rules-lint-ignored=true` in
/// `.gitattributes`. Prettier's built-in `json-stringify` parser already
/// formats `package.json` identically to `release-please`, whereas Prettier's
/// default `json` parser collapses short arrays onto one line and breaks
/// `tidy-check` on release PRs (#3200, #3217, #4676).
pub fn check_release_json_extra_files(ctx: &Context) {
    let gitattr_path = format!("{}/.gitattributes", ctx.root);
    let gitattributes = fs::read_to_string(&gitattr_path).unwrap_or_default();

    let configs = ctx.files.discover(&ctx.root, "release-please-config.json");
    let mut checked = 0u32;
    let mut all_ok = true;

    for cfg_abs in &configs {
        let cfg_rel = ctx.rel(cfg_abs);
        let cfg_dir = cfg_rel.rfind('/').map(|i| &cfg_rel[..i]).unwrap_or("");
        let Ok(cfg_text) = fs::read_to_string(cfg_abs) else {
            continue;
        };
        let Ok(cfg_json) = serde_json::from_str::<serde_json::Value>(&cfg_text) else {
            continue;
        };
        let Some(packages) = cfg_json.get("packages").and_then(|p| p.as_object()) else {
            continue;
        };
        for (pkg_key, pkg_val) in packages {
            let pkg_base = if pkg_key == "." || pkg_key.is_empty() {
                cfg_dir
            } else {
                pkg_key.as_str()
            };
            let Some(extra_files) = pkg_val.get("extra-files").and_then(|e| e.as_array()) else {
                continue;
            };
            for entry in extra_files {
                let Some(obj) = entry.as_object() else {
                    continue;
                };
                if obj.get("type").and_then(|t| t.as_str()) != Some("json") {
                    continue;
                }
                let Some(rel_file) = obj.get("path").and_then(|p| p.as_str()) else {
                    continue;
                };
                let target_rel = normalize_rel_path(pkg_base, rel_file);
                let filename = target_rel.rsplit('/').next().unwrap_or(&target_rel);
                if filename == "package.json" {
                    continue;
                }
                checked += 1;
                let target_abs = format!("{}/{}", ctx.root, target_rel);
                let Ok(text) = fs::read_to_string(&target_abs) else {
                    ctx.emit_fail(
                        "release",
                        &target_rel,
                        "(missing)",
                        "present",
                        &format!("referenced by {cfg_rel} extra-files, but missing on disk"),
                        &format!("create {target_rel} or fix extra-files in {cfg_rel}"),
                    );
                    all_ok = false;
                    continue;
                };

                if !is_rules_lint_ignored(&gitattributes, &target_rel) {
                    ctx.emit_fail(
                        "release",
                        &target_rel,
                        "formatted by prettier",
                        "rules-lint-ignored=true",
                        &format!(
                            "{cfg_rel} updates {target_rel} with release-please's json updater (arrays one item a line), which Prettier collapses back on tidy-check"
                        ),
                        &format!(
                            "mark {target_rel} (or its pattern) rules-lint-ignored=true in .gitattributes"
                        ),
                    );
                    all_ok = false;
                }

                match release_please_json_layout(&text) {
                    Ok(expected) if expected == text => {}
                    Ok(_) => {
                        ctx.emit_fail(
                            "release",
                            &target_rel,
                            "collapsed arrays",
                            "release-please JSON layout",
                            &format!(
                                "{target_rel} is not in release-please's 2-space expanded-array layout; its next release PR will rewrite unrelated lines"
                            ),
                            &format!(
                                "format {target_rel} with JSON.stringify(..., null, 2) + \"\\n\" (every non-empty array one item a line)"
                            ),
                        );
                        all_ok = false;
                    }
                    Err(e) => {
                        ctx.emit_fail(
                            "release",
                            &target_rel,
                            "invalid JSON",
                            "valid JSON",
                            &format!("could not parse {target_rel}: {e}"),
                            &format!("fix JSON syntax in {target_rel}"),
                        );
                        all_ok = false;
                    }
                }
            }
        }
    }

    if checked > 0 && all_ok {
        ctx.emit_ok_uncounted(
            "release",
            "json extra-files",
            "release-please layout + lint-ignored",
            "release-please layout + lint-ignored",
            &format!(
                "all {checked} non-package.json release-please JSON extra-files keep release-please layout and are rules-lint-ignored"
            ),
        );
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    /// A temp repo root holding `files` (relative path, content).
    fn repo(files: &[(&str, &str)]) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static N: AtomicU64 = AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!(
            "conformance-rust-{}-{}",
            std::process::id(),
            N.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&dir);
        for (rel, body) in files {
            let p = dir.join(rel);
            fs::create_dir_all(p.parent().unwrap()).unwrap();
            fs::write(p, body).unwrap();
        }
        dir
    }

    fn run_rust_check(files: &[(&str, &str)]) -> (u32, u32, String) {
        let dir = repo(files);
        let ctx = Context::for_root(dir.to_str().unwrap());
        check_rust_toolchain(&ctx);
        let out = (
            ctx.ok_count.get(),
            ctx.fail_count.get(),
            ctx.rows.get("rust"),
        );
        let _ = fs::remove_dir_all(&dir);
        out
    }

    const MODULE: &str = "rust = use_extension(\"@rules_rust//rust:extensions.bzl\", \"rust\")\n\
rust.toolchain(\n    edition = \"2021\",\n    versions = [\"1.75.0\"],\n)\n";

    #[test]
    fn a_rust_toolchain_on_a_moving_channel_fails() {
        let (ok, fail, rows) = run_rust_check(&[
            ("MODULE.bazel", MODULE),
            (
                "apps/x/rust-toolchain.toml",
                "[toolchain]\nchannel = \"stable\"\n",
            ),
            ("rust-toolchain", "nightly\n"),
            (
                "tools/rust-toolchain.toml",
                "[toolchain]\nchannel = \"1.75.0\"\n",
            ),
        ]);
        assert_eq!((ok, fail), (1, 2), "{rows}");
        assert!(
            rows.contains("apps/x/rust-toolchain.toml") && rows.contains("DRIFT"),
            "{rows}"
        );
    }

    /// aegis's repro: with the extension variable renamed, the drifting
    /// files must still fail, not drop out of the report.
    #[test]
    fn a_renamed_extension_variable_still_checks_every_file() {
        let renamed = MODULE
            .replace("rust = use_extension", "rust_ext = use_extension")
            .replace("rust.toolchain(", "rust_ext.toolchain(");
        let (ok, fail, rows) = run_rust_check(&[
            ("MODULE.bazel", &renamed),
            (
                "apps/x/rust-toolchain.toml",
                "[toolchain]\nchannel = \"stable\"\n",
            ),
            ("rust-toolchain", "nightly\n"),
        ]);
        assert_eq!((ok, fail), (0, 2), "{rows}");
    }

    /// Fail closed: a MODULE.bazel whose Rust version cannot be read fails
    /// the run, even with no rust-toolchain file anywhere.
    #[test]
    fn an_unreadable_rust_version_fails_the_run() {
        for module in [
            "bazel_dep(name = \"rules_rust\", version = \"0.60.0\")\n",
            "rust = use_extension(\"@rules_rust//rust:extensions.bzl\", \"rust\")\nrust.toolchain(edition = \"2021\")\n",
        ] {
            let (ok, fail, rows) = run_rust_check(&[("MODULE.bazel", module)]);
            assert_eq!((ok, fail), (0, 1), "{module}: {rows}");
            assert!(rows.contains("could not read"), "{rows}");
        }
        let (_, fail, rows) = run_rust_check(&[]);
        assert_eq!(fail, 1, "no MODULE.bazel: {rows}");
    }

    #[test]
    fn rust_toolchain_channel_reads_toml() {
        assert_eq!(
            rust_toolchain_channel("[toolchain]\nchannel = \"1.75.0\"\nprofile = \"minimal\"\n")
                .as_deref(),
            Some("1.75.0")
        );
        assert_eq!(
            rust_toolchain_channel("[toolchain]\n# pinned\nchannel = 'stable'\n").as_deref(),
            Some("stable")
        );
        assert_eq!(
            rust_toolchain_channel("[toolchain]\nchannel=\"nightly-2024-01-01\"\n").as_deref(),
            Some("nightly-2024-01-01")
        );
    }

    #[test]
    fn rust_toolchain_channel_reads_the_legacy_form() {
        assert_eq!(
            rust_toolchain_channel("1.75.0\n").as_deref(),
            Some("1.75.0")
        );
        assert_eq!(
            rust_toolchain_channel("nightly\n").as_deref(),
            Some("nightly")
        );
    }

    #[test]
    fn rust_toolchain_channel_without_one() {
        assert_eq!(
            rust_toolchain_channel("[toolchain]\ncomponents = [\"clippy\"]\n"),
            None
        );
        assert_eq!(rust_toolchain_channel(""), None);
    }

    #[test]
    fn extract_leading_digits_works() {
        assert_eq!(extract_leading_digits("22-slim"), "22");
        assert_eq!(extract_leading_digits("22.1.0"), "22");
        assert_eq!(extract_leading_digits("22"), "22");
        assert_eq!(extract_leading_digits(""), "");
        assert_eq!(extract_leading_digits("slim"), "");
    }

    #[test]
    fn df_node_versions_hardcoded() {
        let content = "FROM node:22-slim AS build\nRUN npm install\n";
        assert_eq!(df_node_versions(content), vec!["22"]);
    }

    #[test]
    fn df_node_versions_exact_semver() {
        let content = "FROM node:26.13.1-bookworm-slim AS build\n";
        assert_eq!(df_node_versions(content), vec!["26.13.1"]);
    }

    #[test]
    fn df_node_versions_parameterized() {
        let content = "ARG NODE_VERSION=22\nFROM node:${NODE_VERSION}-slim AS build\n";
        assert_eq!(df_node_versions(content), vec!["22"]);
        let exact = "ARG NODE_VERSION=26.12.0\nFROM node:${NODE_VERSION}-slim AS build\n";
        assert_eq!(df_node_versions(exact), vec!["26.12.0"]);
    }

    #[test]
    fn df_node_versions_no_default() {
        // Parameterized FROM with no ARG default — emits nothing.
        let content = "ARG NODE_VERSION\nFROM node:${NODE_VERSION}-slim AS build\n";
        assert!(df_node_versions(content).is_empty());
    }

    #[test]
    fn df_node_versions_no_node() {
        let content = "FROM python:3.12-slim\nRUN pip install flask\n";
        assert!(df_node_versions(content).is_empty());
    }

    #[test]
    fn df_node_versions_multi_stage_dedup() {
        let content = "FROM node:22-slim AS deps\nFROM node:22-slim AS build\n";
        // Same version appears once.
        assert_eq!(df_node_versions(content), vec!["22"]);
    }

    #[test]
    fn df_node_versions_multi_stage_distinct() {
        let content = "FROM node:20-slim AS deps\nFROM node:22-slim AS build\n";
        assert_eq!(df_node_versions(content), vec!["20", "22"]);
    }

    #[test]
    fn df_node_versions_skips_platform_flag() {
        let content =
            "FROM --platform=$BUILDPLATFORM node:22-bookworm-slim AS build\nFROM node:22-bookworm-slim AS runtime\n";
        assert_eq!(df_node_versions(content), vec!["22"]);
    }

    #[test]
    fn wf_node_versions_extracts_literals_and_matrices() {
        let wf = r#"
jobs:
  a:
    strategy:
      matrix:
        node: [26.13.1, "26"]
    steps:
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ matrix.node }}
  b:
    steps:
      - uses: actions/setup-node@v7
        with:
          node-version: 'v26.12.0'
      - uses: actions/setup-node@v7
        with:
          node-version-file: .nvmrc
      # node-version: 18
  c:
    strategy:
      matrix:
        runtime:
          - 26.13.1
          - 24.22.2
    steps:
      - uses: actions/setup-node@v7
        with:
          node-version: ${{ matrix.runtime }}
"#;
        assert_eq!(
            wf_node_versions(wf),
            vec!["26.12.0", "26.13.1", "26", "24.22.2"]
        );
    }

    #[test]
    fn check_node_compares_exact_semver_in_dockerfiles_and_workflows() {
        let ok_dir = repo(&[
            (".nvmrc", "26.13.1\n"),
            (
                "app/Dockerfile",
                "ARG NODE_VERSION=26.13.1\nFROM node:${NODE_VERSION}-slim AS deps\nFROM node:26-bookworm-slim AS runtime\n",
            ),
            (
                "app/.github/workflows/ci.yml",
                "jobs:\n  test:\n    strategy:\n      matrix:\n        node: [26.13.1]\n    steps:\n      - uses: actions/setup-node@v7\n        with:\n          node-version: ${{ matrix.node }}\n      - uses: actions/setup-node@v7\n        with:\n          node-version: 26.13.1\n      - uses: actions/setup-node@v7\n        with:\n          node-version: \"26\"\n",
            ),
        ]);
        let ok_ctx = Context::for_root(ok_dir.to_str().unwrap());
        check_node(&ok_ctx);
        let ok_fail = ok_ctx.fail_count.get();
        let ok_rows = ok_ctx.rows.get("node");
        let _ = fs::remove_dir_all(&ok_dir);
        assert_eq!(ok_fail, 0, "{ok_rows}");

        let bad_dir = repo(&[
            (".nvmrc", "26.13.1\n"),
            ("app/Dockerfile", "FROM node:26.12.0-bookworm-slim AS build\n"),
            (
                "app/Dockerfile.param",
                "ARG NODE_VERSION=26.12.0\nFROM node:${NODE_VERSION}-slim\n",
            ),
            (
                ".github/workflows/ci.yml",
                "jobs:\n  test:\n    strategy:\n      matrix:\n        node: [26.11.0]\n    steps:\n      - uses: actions/setup-node@v7\n        with:\n          node-version: ${{ matrix.node }}\n      - uses: actions/setup-node@v7\n        with:\n          node-version: 26.12.0\n",
            ),
            (
                "other/.github/workflows/release.yml",
                "jobs:\n  rel:\n    steps:\n      - uses: actions/setup-node@v7\n        with:\n          node-version: 24\n",
            ),
        ]);
        let bad_ctx = Context::for_root(bad_dir.to_str().unwrap());
        check_node(&bad_ctx);
        let bad_fail = bad_ctx.fail_count.get();
        let bad_rows = bad_ctx.rows.get("node");
        let _ = fs::remove_dir_all(&bad_dir);
        assert_eq!(bad_fail, 5, "{bad_rows}");
        assert!(
            bad_rows.contains("26.11.0")
                && bad_rows.contains("26.12.0")
                && bad_rows.contains("26.13.1"),
            "{bad_rows}"
        );
    }

    #[test]
    fn dockerfile_dockerignore_is_ignored_by_node_and_pnpm_pin_checks() {
        let dir = repo(&[
            (".nvmrc", "22.21.1\n"),
            ("package.json", "{\"packageManager\":\"pnpm@10.20.0\"}\n"),
            (
                "app/Dockerfile",
                "FROM --platform=$BUILDPLATFORM node:22-bookworm-slim AS build\n",
            ),
            ("app/Dockerfile.dockerignore", "*\n!pnpm-lock.yaml\npnpm\n"),
        ]);
        let ctx = Context::for_root(dir.to_str().unwrap());
        check_node(&ctx);
        check_pnpm_pin(&ctx);
        let fail = ctx.fail_count.get();
        let _ = fs::remove_dir_all(&dir);
        assert_eq!(fail, 0, "expected 0 failures");
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
    fn has_npm_install_pnpm_works() {
        assert!(has_npm_install_pnpm("RUN npm install -g pnpm@10.20.0"));
        assert!(has_npm_install_pnpm(
            "RUN npm install --global \"pnpm@10.20.0\""
        ));
        assert!(has_npm_install_pnpm("RUN npm i -g pnpm@10.20.0"));
        assert!(has_npm_install_pnpm(
            "RUN echo ok && npm install -g pnpm@10.20.0"
        ));
        assert!(!has_npm_install_pnpm("RUN npm install -g pnpm"));
        assert!(!has_npm_install_pnpm("RUN npm install pnpm@10.20.0"));
        assert!(!has_npm_install_pnpm("# npm install -g pnpm@10.20.0"));
    }

    #[test]
    fn check_pnpm_pin_accepts_matching_npm_install_and_rejects_drift() {
        let ok_dir = repo(&[
            ("package.json", "{\"packageManager\":\"pnpm@10.20.0\"}\n"),
            (
                "app/Dockerfile",
                "FROM node:26-slim\nRUN npm install -g pnpm@10.20.0\nRUN pnpm install\n",
            ),
        ]);
        let ok_ctx = Context::for_root(ok_dir.to_str().unwrap());
        check_pnpm_pin(&ok_ctx);
        let ok_fail = ok_ctx.fail_count.get();
        let _ = fs::remove_dir_all(&ok_dir);
        assert_eq!(ok_fail, 0);

        for extra in [
            (
                "app/package.json",
                "{\"packageManager\":\"pnpm@10.20.0\"}\n",
            ),
            ("app/COPY_MARKER", "unused"),
        ] {
            let df = if extra.0 == "app/COPY_MARKER" {
                "FROM node:26-slim\nRUN npm install -g pnpm@9.15.4\nCOPY package.json ./\nRUN pnpm install\n"
            } else {
                "FROM node:26-slim\nRUN npm install -g pnpm@9.15.4\nRUN pnpm install\n"
            };
            let drift_dir = repo(&[
                ("package.json", "{\"packageManager\":\"pnpm@10.20.0\"}\n"),
                ("app/Dockerfile", df),
                extra,
            ]);
            let drift_ctx = Context::for_root(drift_dir.to_str().unwrap());
            check_pnpm_pin(&drift_ctx);
            let drift_fail = drift_ctx.fail_count.get();
            let rows = drift_ctx.rows.get("pnpm_pin");
            let _ = fs::remove_dir_all(&drift_dir);
            assert_eq!(drift_fail, 1, "{rows}");
            assert!(
                rows.contains("9.15.4") && rows.contains("10.20.0"),
                "{rows}"
            );
        }
    }

    #[test]
    fn copies_package_json_works() {
        assert!(copies_package_json("COPY package.json ./"));
        assert!(copies_package_json("COPY pnpm-lock.yaml package.json ./"));
        assert!(!copies_package_json("COPY requirements.txt ./"));
        assert!(!copies_package_json("RUN cat package.json"));
    }

    fn run_release_json_check(files: &[(&str, &str)]) -> (u32, String) {
        let dir = repo(files);
        let ctx = Context::for_root(dir.to_str().unwrap());
        check_release_json_extra_files(&ctx);
        let out = (ctx.fail_count.get(), ctx.rows.get("RELEASE"));
        let _ = fs::remove_dir_all(&dir);
        out
    }

    #[test]
    fn release_json_extra_file_fails_when_collapsed_or_not_lint_ignored() {
        let cfg = r#"{
  "packages": {
    "apps/desktop/demo": {
      "extra-files": [
        { "type": "json", "path": "vitruvian-tool.json", "jsonpath": "$.version" }
      ]
    }
  }
}
"#;
        let collapsed = "{\n  \"version\": \"0.1.0\",\n  \"uses\": [\"notify\"]\n}\n";
        let (fail, rows) = run_release_json_check(&[
            ("apps/desktop/demo/release-please-config.json", cfg),
            ("apps/desktop/demo/vitruvian-tool.json", collapsed),
            (".gitattributes", ""),
        ]);
        assert_eq!(fail, 2, "{rows}");
        assert!(rows.contains("rules-lint-ignored=true"), "{rows}");
        assert!(rows.contains("expanded-array layout"), "{rows}");
    }

    #[test]
    fn release_json_extra_file_passes_with_wildcard_gitattributes_and_expanded_arrays() {
        let cfg = r#"{
  "packages": {
    "apps/desktop/demo": {
      "extra-files": [
        { "type": "json", "path": "vitruvian-tool.json", "jsonpath": "$.version" },
        { "type": "json", "path": "package.json", "jsonpath": "$.version" }
      ]
    }
  }
}
"#;
        let expanded = "{\n  \"version\": \"0.1.0\",\n  \"uses\": [\n    \"notify\"\n  ]\n}\n";
        let (fail, rows) = run_release_json_check(&[
            ("apps/desktop/demo/release-please-config.json", cfg),
            ("apps/desktop/demo/vitruvian-tool.json", expanded),
            (
                "apps/desktop/demo/package.json",
                "{\"version\":\"0.1.0\"}\n",
            ),
            (
                ".gitattributes",
                "apps/**/vitruvian-tool.json rules-lint-ignored=true\n",
            ),
        ]);
        assert_eq!(fail, 0, "{rows}");
    }
}
