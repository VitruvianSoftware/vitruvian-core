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

//! //tools/ci:pnpm_lock_gate — decide whether a commit actually changes any
//! non-lockfile workflow path or any target importer's transitive closure in
//! `pnpm-lock.yaml` v9.
//!
//! Only std + `shell_compat` so `./.github/actions/build-ci-tool` compiles it
//! in a second without setting up Bazel.
//!
//! Fail-open invariant: every unexpected state (workflow_dispatch, missing or
//! all-zero base SHA, unreadable commit, git failure, unknown lockfile section,
//! unsupported lockfileVersion, unsupported glob syntax, missing snapshot/package,
//! malformed YAML) emits `verdict=run` and exits 0.

use shell_compat::{capture, env, env_or_empty, err, os, out, path};
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fs;
use std::path::Path;
use std::process::Command;

const ALLOWED_TOP_KEYS: &[&str] = &[
    "lockfileVersion",
    "settings",
    "catalogs",
    "overrides",
    "packageExtensionsChecksum",
    "patchedDependencies",
    "ignoredOptionalDependencies",
    "importers",
    "packages",
    "snapshots",
    "time",
];

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Importer {
    pub raw_canonical: String,
    /// (package_name, specifier, version) across dependency groups.
    pub deps: Vec<(String, String, String)>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Snapshot {
    pub raw_canonical: String,
    /// (dep_package_name, dep_version) across dependencies & optionalDependencies.
    pub deps: Vec<(String, String)>,
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct Lockfile {
    pub lockfile_version: String,
    pub settings: String,
    pub catalogs: BTreeMap<String, BTreeMap<String, String>>,
    pub overrides: String,
    pub package_extensions_checksum: String,
    pub patched_dependencies: String,
    /// pnpm 10.20+ `ignoredOptionalDependencies`: optional packages pnpm never
    /// installs. Workspace-wide, so like `overrides` it is part of every closure.
    pub ignored_optional_dependencies: String,
    pub importers: BTreeMap<String, Importer>,
    pub packages: BTreeMap<String, String>,
    pub snapshots: BTreeMap<String, Snapshot>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LockClosure {
    pub settings: String,
    pub overrides: String,
    pub package_extensions_checksum: String,
    pub patched_dependencies: String,
    /// pnpm 10.20+ `ignoredOptionalDependencies`: optional packages pnpm never
    /// installs. Workspace-wide, so like `overrides` it is part of every closure.
    pub ignored_optional_dependencies: String,
    pub catalogs: BTreeMap<(String, String), String>,
    pub importers: BTreeMap<String, String>,
    pub snapshots: BTreeMap<String, String>,
    pub packages: BTreeMap<String, String>,
}

fn emit(run_build: bool, reason: &str) -> i32 {
    let val = if run_build { "run" } else { "skip" };
    let msg = format!("pnpm-lock-gate: verdict={val} ({reason})\n");
    out(msg.as_bytes());
    if let Some(gh_output) = env("GITHUB_OUTPUT") {
        if !gh_output.is_empty() {
            let line = format!("verdict={val}\nreason={reason}\n");
            let _ = fs::OpenOptions::new()
                .append(true)
                .create(true)
                .open(path(&gh_output))
                .and_then(|mut f| {
                    use std::io::Write;
                    f.write_all(line.as_bytes())
                });
        }
    }
    0
}

fn parse_yaml_key_colon(s: &str) -> Result<(String, &str), String> {
    let t = s.trim_start();
    if let Some(rest) = t.strip_prefix('\'') {
        let mut key = String::new();
        let bytes = rest.as_bytes();
        let mut i = 0;
        while i < bytes.len() {
            if bytes[i] == b'\'' {
                if i + 1 < bytes.len() && bytes[i + 1] == b'\'' {
                    key.push('\'');
                    i += 2;
                    continue;
                }
                let after = rest[i + 1..].trim_start();
                if let Some(val_part) = after.strip_prefix(':') {
                    return Ok((key, val_part.trim()));
                }
                return Err(format!("expected ':' after single-quoted key: {s}"));
            }
            let ch = rest[i..]
                .chars()
                .next()
                .ok_or_else(|| "utf8 boundary error".to_string())?;
            key.push(ch);
            i += ch.len_utf8();
        }
        Err(format!("unterminated single-quoted key: {s}"))
    } else if let Some(rest) = t.strip_prefix('"') {
        let mut key = String::new();
        let mut chars = rest.char_indices();
        while let Some((idx, ch)) = chars.next() {
            if ch == '\\' {
                let (_, esc) = chars
                    .next()
                    .ok_or_else(|| format!("unterminated escape in key: {s}"))?;
                key.push(esc);
            } else if ch == '"' {
                let after = rest[idx + 1..].trim_start();
                if let Some(val_part) = after.strip_prefix(':') {
                    return Ok((key, val_part.trim()));
                }
                return Err(format!("expected ':' after double-quoted key: {s}"));
            } else {
                key.push(ch);
            }
        }
        Err(format!("unterminated double-quoted key: {s}"))
    } else {
        if let Some((k, v)) = t.split_once(": ") {
            return Ok((k.trim_end().to_string(), v.trim()));
        }
        if let Some(k) = t.strip_suffix(':') {
            return Ok((k.trim_end().to_string(), ""));
        }
        Err(format!("missing ':' in YAML mapping line: {s}"))
    }
}

fn unquote_scalar(raw: &str) -> Result<String, String> {
    let t = raw.trim();
    if t.is_empty() {
        return Err("empty scalar value".to_string());
    }
    if t.starts_with('{')
        || t.starts_with('[')
        || t.starts_with('*')
        || t.starts_with('&')
        || t == "|"
        || t == ">"
        || t.starts_with("|+")
        || t.starts_with("|-")
        || t.starts_with(">+")
        || t.starts_with(">-")
    {
        return Err(format!("unsupported YAML scalar syntax: {t}"));
    }
    if let Some(inner) = t.strip_prefix('\'') {
        let inner = inner
            .strip_suffix('\'')
            .ok_or_else(|| format!("unterminated single-quoted scalar: {t}"))?;
        return Ok(inner.replace("''", "'"));
    }
    if let Some(inner) = t.strip_prefix('"') {
        let inner = inner
            .strip_suffix('"')
            .ok_or_else(|| format!("unterminated double-quoted scalar: {t}"))?;
        let mut out = String::with_capacity(inner.len());
        let mut chars = inner.chars();
        while let Some(c) = chars.next() {
            if c == '\\' {
                let n = chars
                    .next()
                    .ok_or_else(|| format!("dangling escape in scalar: {t}"))?;
                out.push(n);
            } else {
                out.push(c);
            }
        }
        return Ok(out);
    }
    Ok(t.to_string())
}

fn push_raw(buf: &mut String, line: &str) {
    if !buf.is_empty() {
        buf.push('\n');
    }
    buf.push_str(line.trim_end());
}

fn parse_raw_block(
    lines: &[&str],
    start: &mut usize,
    parent_indent: usize,
) -> Result<String, String> {
    let mut raw = String::new();
    while *start < lines.len() {
        let l = lines[*start];
        if l.trim().is_empty() || l.trim_start().starts_with('#') {
            *start += 1;
            continue;
        }
        if l.starts_with('\t') {
            return Err("tab indentation in YAML".to_string());
        }
        let indent = l.len() - l.trim_start_matches(' ').len();
        if indent <= parent_indent {
            break;
        }
        push_raw(&mut raw, l);
        *start += 1;
    }
    Ok(raw)
}

fn parse_map_of_blocks(
    lines: &[&str],
    i: &mut usize,
    section_indent: usize,
) -> Result<BTreeMap<String, String>, String> {
    let mut out = BTreeMap::new();
    while *i < lines.len() {
        let l = lines[*i];
        if l.trim().is_empty() || l.trim_start().starts_with('#') {
            *i += 1;
            continue;
        }
        if l.starts_with('\t') {
            return Err("tab indentation in YAML".to_string());
        }
        let indent = l.len() - l.trim_start_matches(' ').len();
        if indent <= section_indent {
            break;
        }
        if indent != section_indent + 2 {
            return Err(format!("unexpected indentation inside map: {l}"));
        }
        let (key, val) = parse_yaml_key_colon(l)?;
        *i += 1;
        let mut raw = String::new();
        if !val.is_empty() {
            if val != "{}" {
                return Err(format!("unexpected inline entry value for {key}: {val}"));
            }
            raw.push_str("{}");
        } else {
            raw = parse_raw_block(lines, i, indent)?;
        }
        if out.insert(key.clone(), raw).is_some() {
            return Err(format!("duplicate entry key {key}"));
        }
    }
    Ok(out)
}

fn parse_catalogs(
    lines: &[&str],
    i: &mut usize,
) -> Result<BTreeMap<String, BTreeMap<String, String>>, String> {
    let mut catalogs = BTreeMap::new();
    while *i < lines.len() {
        let l = lines[*i];
        if l.trim().is_empty() || l.trim_start().starts_with('#') {
            *i += 1;
            continue;
        }
        if l.starts_with('\t') {
            return Err("tab indentation in YAML".to_string());
        }
        let indent = l.len() - l.trim_start_matches(' ').len();
        if indent == 0 {
            break;
        }
        if indent != 2 {
            return Err(format!("unexpected indent in catalogs: {l}"));
        }
        let (cat_name, rest) = parse_yaml_key_colon(l)?;
        *i += 1;
        let entries = if !rest.is_empty() {
            if rest != "{}" {
                return Err(format!("unsupported inline catalog {cat_name}: {rest}"));
            }
            BTreeMap::new()
        } else {
            let mut m = BTreeMap::new();
            while *i < lines.len() {
                let cl = lines[*i];
                if cl.trim().is_empty() || cl.trim_start().starts_with('#') {
                    *i += 1;
                    continue;
                }
                let ci = cl.len() - cl.trim_start_matches(' ').len();
                if ci <= 2 {
                    break;
                }
                if ci != 4 {
                    return Err(format!("unexpected indent in catalog entry: {cl}"));
                }
                let (pkg_name, crest) = parse_yaml_key_colon(cl)?;
                *i += 1;
                let block = if !crest.is_empty() {
                    crest.to_string()
                } else {
                    parse_raw_block(lines, i, 4)?
                };
                if m.insert(pkg_name.clone(), block).is_some() {
                    return Err(format!("duplicate catalog pkg {cat_name}/{pkg_name}"));
                }
            }
            m
        };
        if catalogs.insert(cat_name.clone(), entries).is_some() {
            return Err(format!("duplicate catalog {cat_name}"));
        }
    }
    Ok(catalogs)
}

fn parse_importers(lines: &[&str], i: &mut usize) -> Result<BTreeMap<String, Importer>, String> {
    let mut importers = BTreeMap::new();
    while *i < lines.len() {
        let l = lines[*i];
        if l.trim().is_empty() || l.trim_start().starts_with('#') {
            *i += 1;
            continue;
        }
        if l.starts_with('\t') {
            return Err("tab indentation in YAML".to_string());
        }
        let indent = l.len() - l.trim_start_matches(' ').len();
        if indent == 0 {
            break;
        }
        if indent != 2 {
            return Err(format!("unexpected indent in importers: {l}"));
        }
        let (imp_name, rest) = parse_yaml_key_colon(l)?;
        *i += 1;
        let mut imp = Importer::default();
        if !rest.is_empty() {
            if rest != "{}" {
                return Err(format!("unexpected inline importer {imp_name}: {rest}"));
            }
            imp.raw_canonical = "{}".to_string();
            if importers.insert(imp_name.clone(), imp).is_some() {
                return Err(format!("duplicate importer {imp_name}"));
            }
            continue;
        }
        let block_start = *i;
        let raw = parse_raw_block(lines, i, 2)?;
        imp.raw_canonical = raw;

        // Walk the captured block lines for dependency groups.
        let mut j = block_start;
        let end = *i;
        let mut cur_group = String::new();
        while j < end {
            let il = lines[j];
            if il.trim().is_empty() || il.trim_start().starts_with('#') {
                j += 1;
                continue;
            }
            let ii = il.len() - il.trim_start_matches(' ').len();
            if ii == 4 {
                let (grp, grest) = parse_yaml_key_colon(il)?;
                cur_group = grp;
                j += 1;
                if !grest.is_empty() && grest != "{}" && cur_group != "dependenciesMeta" {
                    // dependenciesMeta or scalar fields still fail open only on dep groups
                    if is_dep_group(&cur_group) {
                        return Err(format!("unsupported inline dep group {cur_group}: {grest}"));
                    }
                }
                continue;
            }
            if ii == 6 && is_dep_group(&cur_group) {
                let (pkg_name, prest) = parse_yaml_key_colon(il)?;
                if !prest.is_empty() {
                    return Err(format!(
                        "unexpected inline importer dep {imp_name}/{pkg_name}: {prest}"
                    ));
                }
                j += 1;
                let mut specifier = String::new();
                let mut version = String::new();
                while j < end {
                    let fl = lines[j];
                    if fl.trim().is_empty() || fl.trim_start().starts_with('#') {
                        j += 1;
                        continue;
                    }
                    let fi = fl.len() - fl.trim_start_matches(' ').len();
                    if fi <= 6 {
                        break;
                    }
                    if fi != 8 {
                        return Err(format!("unexpected importer field indent: {fl}"));
                    }
                    let (fk, fv) = parse_yaml_key_colon(fl)?;
                    let val = unquote_scalar(fv)?;
                    if fk == "specifier" {
                        specifier = val;
                    } else if fk == "version" {
                        version = val;
                    }
                    j += 1;
                }
                if version.is_empty() {
                    return Err(format!("missing version for {imp_name}/{pkg_name}"));
                }
                imp.deps.push((pkg_name, specifier, version));
                continue;
            }
            j += 1;
        }

        if importers.insert(imp_name.clone(), imp).is_some() {
            return Err(format!("duplicate importer {imp_name}"));
        }
    }
    Ok(importers)
}

fn is_dep_group(name: &str) -> bool {
    matches!(
        name,
        "dependencies" | "devDependencies" | "optionalDependencies" | "peerDependencies"
    )
}

fn parse_snapshots(lines: &[&str], i: &mut usize) -> Result<BTreeMap<String, Snapshot>, String> {
    let mut snapshots = BTreeMap::new();
    while *i < lines.len() {
        let l = lines[*i];
        if l.trim().is_empty() || l.trim_start().starts_with('#') {
            *i += 1;
            continue;
        }
        if l.starts_with('\t') {
            return Err("tab indentation in YAML".to_string());
        }
        let indent = l.len() - l.trim_start_matches(' ').len();
        if indent == 0 {
            break;
        }
        if indent != 2 {
            return Err(format!("unexpected indent in snapshots: {l}"));
        }
        let (snap_key, rest) = parse_yaml_key_colon(l)?;
        *i += 1;
        let mut snap = Snapshot::default();
        if !rest.is_empty() {
            if rest != "{}" {
                return Err(format!("unexpected inline snapshot {snap_key}: {rest}"));
            }
            snap.raw_canonical = "{}".to_string();
            if snapshots.insert(snap_key.clone(), snap).is_some() {
                return Err(format!("duplicate snapshot {snap_key}"));
            }
            continue;
        }
        let block_start = *i;
        snap.raw_canonical = parse_raw_block(lines, i, 2)?;
        let end = *i;

        let mut j = block_start;
        let mut in_deps = false;
        while j < end {
            let sl = lines[j];
            if sl.trim().is_empty() || sl.trim_start().starts_with('#') {
                j += 1;
                continue;
            }
            let si = sl.len() - sl.trim_start_matches(' ').len();
            if si == 4 {
                let (sub, srest) = parse_yaml_key_colon(sl)?;
                in_deps = sub == "dependencies" || sub == "optionalDependencies";
                if in_deps && !srest.is_empty() {
                    if srest != "{}" {
                        return Err(format!("unexpected inline snapshot {sub}: {srest}"));
                    }
                    in_deps = false;
                }
                j += 1;
                continue;
            }
            if si == 6 && in_deps {
                let (dep_pkg, dep_ver_raw) = parse_yaml_key_colon(sl)?;
                let dep_ver = unquote_scalar(dep_ver_raw)?;
                snap.deps.push((dep_pkg, dep_ver));
            } else if si > 4 && in_deps {
                return Err(format!("unexpected snapshot dep structure: {sl}"));
            }
            j += 1;
        }

        if snapshots.insert(snap_key.clone(), snap).is_some() {
            return Err(format!("duplicate snapshot {snap_key}"));
        }
    }
    Ok(snapshots)
}

pub fn parse_lockfile(text: &str) -> Result<Lockfile, String> {
    let normalized = text.replace("\r\n", "\n");
    let lines: Vec<&str> = normalized.split('\n').collect();
    let mut lock = Lockfile::default();
    let mut seen_top = BTreeSet::new();
    let mut i = 0usize;

    while i < lines.len() {
        let l = lines[i];
        let trimmed = l.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            i += 1;
            continue;
        }
        if l.starts_with('\t') {
            return Err("tab indentation in YAML".to_string());
        }
        let indent = l.len() - l.trim_start_matches(' ').len();
        if indent != 0 {
            return Err(format!("unexpected top-level indent: {l}"));
        }
        if trimmed == "---"
            || trimmed == "..."
            || trimmed.starts_with('&')
            || trimmed.starts_with('*')
        {
            return Err(format!("unsupported YAML top-level token: {l}"));
        }
        let (key, val) = parse_yaml_key_colon(l)?;
        if !ALLOWED_TOP_KEYS.contains(&key.as_str()) {
            return Err(format!("unknown top-level lockfile section: {key}"));
        }
        if !seen_top.insert(key.clone()) {
            return Err(format!("duplicate top-level lockfile section: {key}"));
        }
        i += 1;

        match key.as_str() {
            "lockfileVersion" => {
                lock.lockfile_version = unquote_scalar(val)?;
            }
            "packageExtensionsChecksum" => {
                lock.package_extensions_checksum = unquote_scalar(val)?;
            }
            "settings" => {
                lock.settings = if !val.is_empty() {
                    val.to_string()
                } else {
                    parse_raw_block(&lines, &mut i, 0)?
                };
            }
            "overrides" => {
                lock.overrides = if !val.is_empty() {
                    val.to_string()
                } else {
                    parse_raw_block(&lines, &mut i, 0)?
                };
            }
            "patchedDependencies" => {
                lock.patched_dependencies = if !val.is_empty() {
                    val.to_string()
                } else {
                    parse_raw_block(&lines, &mut i, 0)?
                };
            }
            "ignoredOptionalDependencies" => {
                lock.ignored_optional_dependencies = if !val.is_empty() {
                    val.to_string()
                } else {
                    parse_raw_block(&lines, &mut i, 0)?
                };
            }
            "time" => {
                if val.is_empty() {
                    let _ = parse_raw_block(&lines, &mut i, 0)?;
                }
            }
            "catalogs" => {
                if !val.is_empty() {
                    if val != "{}" {
                        return Err(format!("unexpected catalogs value: {val}"));
                    }
                } else {
                    lock.catalogs = parse_catalogs(&lines, &mut i)?;
                }
            }
            "importers" => {
                if !val.is_empty() {
                    if val != "{}" {
                        return Err(format!("unexpected importers value: {val}"));
                    }
                } else {
                    lock.importers = parse_importers(&lines, &mut i)?;
                }
            }
            "packages" => {
                if !val.is_empty() {
                    if val != "{}" {
                        return Err(format!("unexpected packages value: {val}"));
                    }
                } else {
                    lock.packages = parse_map_of_blocks(&lines, &mut i, 0)?;
                }
            }
            "snapshots" => {
                if !val.is_empty() {
                    if val != "{}" {
                        return Err(format!("unexpected snapshots value: {val}"));
                    }
                } else {
                    lock.snapshots = parse_snapshots(&lines, &mut i)?;
                }
            }
            _ => return Err(format!("unhandled top-level key: {key}")),
        }
    }

    if lock.lockfile_version != "9.0" {
        return Err(format!(
            "unsupported lockfileVersion '{}'",
            lock.lockfile_version
        ));
    }
    Ok(lock)
}

fn normalize_rel_path(from_importer: &str, rel_link: &str) -> Result<String, String> {
    let mut parts: Vec<&str> = if from_importer == "." {
        Vec::new()
    } else {
        from_importer.split('/').filter(|s| !s.is_empty()).collect()
    };
    for seg in rel_link.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                if parts.pop().is_none() {
                    return Err(format!(
                        "workspace link '{rel_link}' escapes repo from '{from_importer}'"
                    ));
                }
            }
            other => parts.push(other),
        }
    }
    if parts.is_empty() {
        Ok(".".to_string())
    } else {
        Ok(parts.join("/"))
    }
}

pub fn resolve_snapshot_key(pkg: &str, ver: &str) -> Result<String, String> {
    if ver.starts_with("link:") || ver.starts_with("file:") {
        return Err(format!("unsupported snapshot ref for {pkg}: {ver}"));
    }
    let clean = ver.strip_prefix("npm:").unwrap_or(ver);
    let head = match clean.find('(') {
        Some(pos) => &clean[..pos],
        None => clean,
    };
    if (head.len() > 1 && head[1..].contains('@'))
        || head.starts_with("http://")
        || head.starts_with("https://")
        || head.starts_with("git+")
        || head.starts_with("github:")
    {
        Ok(clean.to_string())
    } else {
        Ok(format!("{pkg}@{clean}"))
    }
}

pub fn snapshot_to_package_key(snap_key: &str) -> Result<String, String> {
    if snap_key.is_empty() {
        return Err("empty snapshot key".to_string());
    }
    let idx = snap_key.find('(').unwrap_or(snap_key.len());
    let base = &snap_key[..idx];
    if base.is_empty() {
        return Err(format!("invalid snapshot key: {snap_key}"));
    }
    Ok(base.to_string())
}

pub fn extract_closure(lock: &Lockfile, seed_importers: &[&str]) -> Result<LockClosure, String> {
    if seed_importers.is_empty() {
        return Err("no seed importers provided".to_string());
    }

    let mut closure = LockClosure {
        settings: lock.settings.clone(),
        overrides: lock.overrides.clone(),
        package_extensions_checksum: lock.package_extensions_checksum.clone(),
        patched_dependencies: lock.patched_dependencies.clone(),
        ignored_optional_dependencies: lock.ignored_optional_dependencies.clone(),
        catalogs: BTreeMap::new(),
        importers: BTreeMap::new(),
        snapshots: BTreeMap::new(),
        packages: BTreeMap::new(),
    };

    let mut imp_queue: VecDeque<String> = VecDeque::new();
    let mut seen_imps: BTreeSet<String> = BTreeSet::new();
    for s in seed_importers {
        let key = (*s).to_string();
        if seen_imps.insert(key.clone()) {
            imp_queue.push_back(key);
        }
    }

    let mut snap_queue: VecDeque<String> = VecDeque::new();
    let mut seen_snaps: BTreeSet<String> = BTreeSet::new();

    while let Some(imp_key) = imp_queue.pop_front() {
        let imp = lock
            .importers
            .get(&imp_key)
            .ok_or_else(|| format!("missing importer '{imp_key}' in lockfile"))?;
        closure
            .importers
            .insert(imp_key.clone(), imp.raw_canonical.clone());

        for (pkg, spec, ver) in &imp.deps {
            if let Some(rest) = spec.strip_prefix("catalog:") {
                let cat_name = if rest.is_empty() { "default" } else { rest };
                let entry = lock
                    .catalogs
                    .get(cat_name)
                    .and_then(|c| c.get(pkg))
                    .ok_or_else(|| format!("missing catalog entry {cat_name}/{pkg}"))?;
                closure
                    .catalogs
                    .insert((cat_name.to_string(), pkg.clone()), entry.clone());
            }
            if let Some(rel) = ver.strip_prefix("link:") {
                let linked = normalize_rel_path(&imp_key, rel)?;
                if seen_imps.insert(linked.clone()) {
                    imp_queue.push_back(linked);
                }
            } else {
                let snap_key = resolve_snapshot_key(pkg, ver)?;
                if seen_snaps.insert(snap_key.clone()) {
                    snap_queue.push_back(snap_key);
                }
            }
        }
    }

    while let Some(snap_key) = snap_queue.pop_front() {
        let snap = lock
            .snapshots
            .get(&snap_key)
            .ok_or_else(|| format!("missing snapshot '{snap_key}' in lockfile"))?;
        let pkg_key = snapshot_to_package_key(&snap_key)?;
        let pkg_raw = lock
            .packages
            .get(&pkg_key)
            .ok_or_else(|| format!("missing package '{pkg_key}' for snapshot '{snap_key}'"))?;

        closure
            .snapshots
            .insert(snap_key.clone(), snap.raw_canonical.clone());
        closure.packages.insert(pkg_key, pkg_raw.clone());

        for (dep_pkg, dep_ver) in &snap.deps {
            // pnpm stores published package `patch:` deps inline as `link:patch:...`
            // without separate snapshot/package nodes; they stay inside `snap.raw_canonical`.
            if dep_ver.starts_with("link:patch:") {
                continue;
            }
            let next_snap = resolve_snapshot_key(dep_pkg, dep_ver)?;
            if seen_snaps.insert(next_snap.clone()) {
                snap_queue.push_back(next_snap);
            }
        }
    }

    Ok(closure)
}

fn strip_unquoted_comment(s: &str) -> &str {
    let mut in_sq = false;
    let mut in_dq = false;
    let bytes = s.as_bytes();
    for (i, &b) in bytes.iter().enumerate() {
        match b {
            b'\'' if !in_dq => in_sq = !in_sq,
            b'"' if !in_sq => in_dq = !in_dq,
            b'#' if !in_sq && !in_dq && (i == 0 || bytes[i - 1].is_ascii_whitespace()) => {
                return s[..i].trim_end();
            }
            _ => {}
        }
    }
    s.trim_end()
}

/// Extract the `paths:` list for `event_name` (`"push"` or `"pull_request"`) from a workflow YAML.
pub fn extract_workflow_paths(
    workflow_yaml: &str,
    event_name: &str,
) -> Result<Vec<String>, String> {
    let norm = workflow_yaml.replace("\r\n", "\n");
    let lines: Vec<&str> = norm.split('\n').collect();
    let mut in_on = false;
    let mut on_indent = 0usize;
    let mut in_event = false;
    let mut event_indent = 0usize;
    let mut in_paths = false;
    let mut paths_indent = 0usize;
    let mut out = Vec::new();

    for raw_line in lines {
        let line = strip_unquoted_comment(raw_line);
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        let indent = line.len() - line.trim_start_matches(' ').len();

        if !in_on {
            if indent == 0 && (trimmed == "on:" || trimmed.starts_with("on:")) {
                in_on = true;
                on_indent = indent;
            }
            continue;
        }
        if indent <= on_indent {
            break;
        }

        if in_paths {
            if indent <= paths_indent && !trimmed.starts_with('-') {
                break;
            }
            if let Some(rest) = trimmed.strip_prefix('-') {
                let item = unquote_scalar(rest.trim())?;
                out.push(item);
                continue;
            } else {
                return Err(format!("unexpected line inside workflow paths: {raw_line}"));
            }
        }

        if !in_event {
            if trimmed == format!("{event_name}:") || trimmed.starts_with(&format!("{event_name}:"))
            {
                in_event = true;
                event_indent = indent;
            }
            continue;
        }

        if indent <= event_indent {
            break;
        }

        if trimmed == "paths:" {
            in_paths = true;
            paths_indent = indent;
        }
    }

    if out.is_empty() {
        return Err(format!(
            "no paths filter found for event '{event_name}' in workflow"
        ));
    }
    Ok(out)
}

fn match_segment(pat: &[u8], txt: &[u8]) -> bool {
    let (m, n) = (pat.len(), txt.len());
    let mut dp = vec![vec![false; n + 1]; m + 1];
    dp[0][0] = true;
    for i in 1..=m {
        if pat[i - 1] == b'*' {
            dp[i][0] = dp[i - 1][0];
        }
        for j in 1..=n {
            dp[i][j] = match pat[i - 1] {
                b'*' => dp[i - 1][j] || dp[i][j - 1],
                b'?' => dp[i - 1][j - 1],
                c => dp[i - 1][j - 1] && c == txt[j - 1],
            };
        }
    }
    dp[m][n]
}

fn match_segments(p_segs: &[&str], t_segs: &[&str]) -> bool {
    let (m, n) = (p_segs.len(), t_segs.len());
    let mut dp = vec![vec![false; n + 1]; m + 1];
    dp[0][0] = true;
    for i in 1..=m {
        if p_segs[i - 1] == "**" {
            dp[i][0] = dp[i - 1][0];
        }
        for j in 1..=n {
            if p_segs[i - 1] == "**" {
                dp[i][j] = dp[i - 1][j] || dp[i][j - 1];
            } else {
                dp[i][j] = dp[i - 1][j - 1]
                    && match_segment(p_segs[i - 1].as_bytes(), t_segs[j - 1].as_bytes());
            }
        }
    }
    dp[m][n]
}

pub fn validate_glob_pattern(pattern: &str) -> Result<(), String> {
    let p_norm = pattern.trim_start_matches("./");
    for seg in p_norm.split('/') {
        if seg.contains("**") && seg != "**" {
            return Err(format!(
                "partial-segment '**' unsupported in glob '{pattern}'"
            ));
        }
    }
    if p_norm.contains('[')
        || p_norm.contains(']')
        || p_norm.contains('+')
        || p_norm.contains('{')
        || p_norm.contains('}')
        || p_norm.contains('\\')
    {
        return Err(format!("unsupported glob metacharacter in '{pattern}'"));
    }
    Ok(())
}

pub fn glob_match(pattern: &str, candidate: &str) -> bool {
    let p_norm = pattern.trim_start_matches("./");
    let c_norm = candidate.trim_start_matches("./");
    let p_segs: Vec<&str> = p_norm.split('/').filter(|s| !s.is_empty()).collect();
    let c_segs: Vec<&str> = c_norm.split('/').filter(|s| !s.is_empty()).collect();
    match_segments(&p_segs, &c_segs)
}

pub fn matches_workflow_paths(rules: &[String], file_path: &str) -> Result<bool, String> {
    let mut matched = false;
    for rule in rules {
        let (neg, pat) = match rule.strip_prefix('!') {
            Some(rest) => (true, rest),
            None => (false, rule.as_str()),
        };
        validate_glob_pattern(pat)?;
        if glob_match(pat, file_path) {
            matched = !neg;
        }
    }
    Ok(matched)
}

fn git_cmd(repo_dir: Option<&Path>, args: &[&str]) -> shell_compat::Ran {
    let mut cmd = Command::new("git");
    if let Some(dir) = repo_dir {
        cmd.arg("-C").arg(dir);
    }
    cmd.arg("-c").arg("core.quotepath=false");
    for a in args {
        cmd.arg(a);
    }
    capture(0, &mut cmd)
}

pub fn evaluate_repo(
    repo_dir: Option<&Path>,
    workflow_rel: &str,
    importers: &[&str],
    base_sha: &str,
    head_sha: &str,
    event_name: &str,
) -> (bool, String) {
    if event_name == "workflow_dispatch" {
        return (true, "workflow_dispatch runs unconditionally".to_string());
    }
    if event_name != "push" && event_name != "pull_request" {
        return (
            true,
            format!("event '{event_name}' unsupported by gate; fail-open"),
        );
    }
    if base_sha.is_empty() || base_sha.bytes().all(|b| b == b'0') {
        return (true, "missing or zero base SHA".to_string());
    }

    let base_rev = format!("{base_sha}^{{commit}}");
    let head_rev = format!("{head_sha}^{{commit}}");
    if !git_cmd(repo_dir, &["rev-parse", "--verify", &base_rev]).ok() {
        return (true, format!("unreadable base commit '{base_sha}'"));
    }
    if !git_cmd(repo_dir, &["rev-parse", "--verify", &head_rev]).ok() {
        return (true, format!("unreadable head commit '{head_sha}'"));
    }

    let range = format!("{base_sha}..{head_sha}");
    let diff = git_cmd(repo_dir, &["diff", "--name-only", "--no-renames", &range]);
    if !diff.ok() {
        return (true, format!("git diff failed (status {})", diff.status));
    }
    let diff_text = match String::from_utf8(diff.stdout) {
        Ok(s) => s,
        Err(_) => return (true, "non-UTF-8 git diff output".to_string()),
    };

    let changed: Vec<&str> = diff_text.lines().filter(|l| !l.trim().is_empty()).collect();
    if changed.is_empty() {
        return (
            false,
            format!("no changed files between {base_sha} and {head_sha}"),
        );
    }

    let wf_path = match repo_dir {
        Some(dir) => dir.join(workflow_rel),
        None => Path::new(workflow_rel).to_path_buf(),
    };
    let wf_yaml = match fs::read_to_string(&wf_path) {
        Ok(s) => s,
        Err(e) => {
            return (
                true,
                format!("cannot read workflow '{}': {e}", wf_path.display()),
            )
        }
    };
    let rules = match extract_workflow_paths(&wf_yaml, event_name) {
        Ok(r) => r,
        Err(e) => return (true, format!("cannot parse workflow paths: {e}")),
    };

    let non_lock_rules: Vec<String> = rules
        .into_iter()
        .filter(|r| r != "pnpm-lock.yaml")
        .collect();
    for r in &non_lock_rules {
        let pat = r.strip_prefix('!').unwrap_or(r.as_str());
        if let Err(e) = validate_glob_pattern(pat) {
            return (true, format!("workflow path glob fail-open: {e}"));
        }
    }

    let mut lockfile_changed = false;
    for file in &changed {
        if file.starts_with('"') {
            return (true, format!("quoted path in diff: {file}"));
        }
        if *file == "pnpm-lock.yaml" {
            lockfile_changed = true;
            continue;
        }
        match matches_workflow_paths(&non_lock_rules, file) {
            Ok(true) => return (true, format!("workflow path changed: {file}")),
            Ok(false) => {}
            Err(e) => return (true, format!("workflow path match fail-open: {e}")),
        }
    }

    if !lockfile_changed {
        return (
            false,
            "only excluded or unrelated files changed".to_string(),
        );
    }

    let base_spec = format!("{base_sha}:pnpm-lock.yaml");
    let head_spec = format!("{head_sha}:pnpm-lock.yaml");
    let base_lock_out = git_cmd(repo_dir, &["show", &base_spec]);
    if !base_lock_out.ok() {
        return (true, format!("git show {base_spec} failed"));
    }
    let head_lock_out = git_cmd(repo_dir, &["show", &head_spec]);
    if !head_lock_out.ok() {
        return (true, format!("git show {head_spec} failed"));
    }

    let base_yaml = match String::from_utf8(base_lock_out.stdout) {
        Ok(s) => s,
        Err(_) => return (true, "base pnpm-lock.yaml is not valid UTF-8".to_string()),
    };
    let head_yaml = match String::from_utf8(head_lock_out.stdout) {
        Ok(s) => s,
        Err(_) => return (true, "head pnpm-lock.yaml is not valid UTF-8".to_string()),
    };

    let base_lock = match parse_lockfile(&base_yaml) {
        Ok(l) => l,
        Err(e) => return (true, format!("base pnpm-lock.yaml parse fail-open: {e}")),
    };
    let head_lock = match parse_lockfile(&head_yaml) {
        Ok(l) => l,
        Err(e) => return (true, format!("head pnpm-lock.yaml parse fail-open: {e}")),
    };

    let base_closure = match extract_closure(&base_lock, importers) {
        Ok(c) => c,
        Err(e) => return (true, format!("base lockfile closure fail-open: {e}")),
    };
    let head_closure = match extract_closure(&head_lock, importers) {
        Ok(c) => c,
        Err(e) => return (true, format!("head lockfile closure fail-open: {e}")),
    };

    if base_closure == head_closure {
        (
            false,
            format!(
                "pnpm-lock.yaml changed outside importer closure [{}]",
                importers.join(", ")
            ),
        )
    } else {
        (
            true,
            format!(
                "pnpm-lock.yaml closure changed for [{}]",
                importers.join(", ")
            ),
        )
    }
}

pub fn run(args: &[Vec<u8>]) -> i32 {
    let mut workflow: Option<String> = None;
    let mut importers_csv: Option<String> = None;
    let mut base_sha: Option<String> = None;
    let mut head_sha: Option<String> = None;
    let mut event_name: Option<String> = None;
    let mut repo_dir: Option<String> = None;

    // shell_compat::args() already omits argv[0].
    let mut i = 0usize;
    while i < args.len() {
        let arg = String::from_utf8_lossy(&args[i]).into_owned();
        let next = |idx: &mut usize, flag: &str| -> Result<String, ()> {
            *idx += 1;
            if *idx >= args.len() {
                err(format!("pnpm-lock-gate: missing value for {flag}\n").as_bytes());
                return Err(());
            }
            Ok(String::from_utf8_lossy(&args[*idx]).into_owned())
        };
        match arg.as_str() {
            "--workflow" => match next(&mut i, "--workflow") {
                Ok(v) => workflow = Some(v),
                Err(()) => return 2,
            },
            "--importers" => match next(&mut i, "--importers") {
                Ok(v) => importers_csv = Some(v),
                Err(()) => return 2,
            },
            "--base" => match next(&mut i, "--base") {
                Ok(v) => base_sha = Some(v),
                Err(()) => return 2,
            },
            "--head" => match next(&mut i, "--head") {
                Ok(v) => head_sha = Some(v),
                Err(()) => return 2,
            },
            "--event" => match next(&mut i, "--event") {
                Ok(v) => event_name = Some(v),
                Err(()) => return 2,
            },
            "--repo" => match next(&mut i, "--repo") {
                Ok(v) => repo_dir = Some(v),
                Err(()) => return 2,
            },
            other => {
                err(format!("pnpm-lock-gate: unknown argument '{other}'\n").as_bytes());
                return 2;
            }
        }
        i += 1;
    }

    let workflow = match workflow {
        Some(w) if !w.trim().is_empty() => w,
        _ => {
            err(b"pnpm-lock-gate: --workflow is required\n");
            return 2;
        }
    };
    let importers_csv = match importers_csv {
        Some(c) if !c.trim().is_empty() => c,
        _ => {
            err(b"pnpm-lock-gate: --importers is required\n");
            return 2;
        }
    };
    let importers: Vec<&str> = importers_csv
        .split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .collect();
    if importers.is_empty() {
        err(b"pnpm-lock-gate: --importers must list at least one importer\n");
        return 2;
    }

    let base =
        base_sha.unwrap_or_else(|| String::from_utf8_lossy(&env_or_empty("BASE_SHA")).into_owned());
    let head = head_sha.unwrap_or_else(|| {
        let s = String::from_utf8_lossy(&env_or_empty("HEAD_SHA")).into_owned();
        if s.is_empty() {
            "HEAD".to_string()
        } else {
            s
        }
    });
    let event = event_name.unwrap_or_else(|| {
        String::from_utf8_lossy(&env_or_empty("GITHUB_EVENT_NAME")).into_owned()
    });
    let repo_pb = repo_dir.map(|r| path(r.as_bytes()));
    let _ = os; // suppress if unused on platforms

    let (should_run, reason) = evaluate_repo(
        repo_pb.as_deref(),
        &workflow,
        &importers,
        base.trim(),
        head.trim(),
        event.trim(),
    );
    emit(should_run, &reason)
}
