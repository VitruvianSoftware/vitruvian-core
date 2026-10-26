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

use std::collections::{BTreeSet, HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::process::Command;

use crate::check_import_directions::{
    cached_canonicalize, resolve_app_root, seed_non_symlink_files,
};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FormatResult {
    pub count: usize,
    pub changed: Vec<String>,
}

fn is_valid_runtime_root(name: &str) -> bool {
    if name.is_empty() {
        return false;
    }
    name.split('/').all(|seg| {
        !seg.is_empty()
            && seg
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
    })
}

fn is_runtime_js_file(name: &str) -> bool {
    let is_js = name.ends_with(".js") || name.ends_with(".mjs") || name.ends_with(".cjs");
    let is_test =
        name.ends_with(".test.js") || name.ends_with(".test.mjs") || name.ends_with(".test.cjs");
    is_js && !is_test
}

fn load_ignore_patterns(ignore_path: &Path) -> Vec<String> {
    let content = match std::fs::read_to_string(ignore_path) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };
    content
        .lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| l.trim_start_matches('/').to_string())
        .collect()
}

fn is_ignored_by_patterns(rel_path: &str, patterns: &[String]) -> bool {
    for pat in patterns {
        let clean = pat.trim_end_matches('/');
        if rel_path == clean
            || rel_path.starts_with(&format!("{}/", clean))
            || (!clean.contains('/') && rel_path.split('/').any(|seg| seg == clean))
        {
            return true;
        }
    }
    false
}

fn is_supported_prettier_file(name: &str) -> bool {
    let file_name = Path::new(name)
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or(name);
    if file_name.starts_with(".prettierrc") {
        return true;
    }
    matches!(
        Path::new(name).extension().and_then(|e| e.to_str()),
        Some("js" | "mjs" | "cjs" | "json" | "css" | "md" | "html" | "yml" | "yaml")
    )
}

fn walk_runtime_dir(
    root: &Path,
    dir: &Path,
    gitignore_patterns: &[String],
    out: &mut BTreeSet<String>,
) {
    let entries = match std::fs::read_dir(dir) {
        Ok(rd) => rd,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let p = entry.path();
        let Ok(rel) = p.strip_prefix(root) else {
            continue;
        };
        let rel_str = rel.to_string_lossy().replace('\\', "/");
        if is_ignored_by_patterns(&rel_str, gitignore_patterns) {
            continue;
        }
        if p.is_dir() {
            walk_runtime_dir(root, &p, gitignore_patterns, out);
        } else {
            out.insert(rel_str);
        }
    }
}

/// Discover owned runtime code; tests and other files retain explicit adoption.
/// Port of `discoverRuntimeFormatFiles(root)` in `scripts/format.mjs`.
pub fn discover_runtime_format_files(root: &Path) -> Result<Vec<String>, String> {
    let config_file = root.join("scripts/format-runtime.json");
    if !config_file.exists() {
        return Ok(Vec::new());
    }
    let raw = std::fs::read_to_string(&config_file)
        .map_err(|e| format!("Failed to read scripts/format-runtime.json: {}", e))?;
    let val: serde_json::Value = serde_json::from_str(&raw)
        .map_err(|_| "Runtime formatting roots must be unique repository directory paths".to_string())?;

    let roots_arr = match val.get("roots").and_then(|v| v.as_array()) {
        Some(arr) if !arr.is_empty() => arr,
        _ => {
            return Err(
                "Runtime formatting roots must be unique repository directory paths".to_string(),
            )
        }
    };

    let mut roots: Vec<String> = Vec::with_capacity(roots_arr.len());
    let mut seen_roots: HashSet<String> = HashSet::new();
    for item in roots_arr {
        let s = match item.as_str() {
            Some(s) if is_valid_runtime_root(s) => s,
            _ => {
                return Err(
                    "Runtime formatting roots must be unique repository directory paths".to_string(),
                )
            }
        };
        if !seen_roots.insert(s.to_string()) {
            return Err(
                "Runtime formatting roots must be unique repository directory paths".to_string(),
            );
        }
        roots.push(s.to_string());
    }

    let prettierignore = load_ignore_patterns(&root.join(".prettierignore"));
    let gitignore = load_ignore_patterns(&root.join(".gitignore"));

    let mut candidates: BTreeSet<String> = BTreeSet::new();
    let mut used_git = false;
    if root.join(".git").exists() {
        let mut cmd = Command::new("git");
        cmd.arg("ls-files")
            .arg("-z")
            .arg("--cached")
            .arg("--others")
            .arg("--exclude-standard")
            .arg("--");
        for r in &roots {
            cmd.arg(r);
        }
        cmd.current_dir(root);
        if let Ok(output) = cmd.output() {
            if output.status.success() {
                used_git = true;
                let text = String::from_utf8_lossy(&output.stdout);
                for name in text.split('\0') {
                    if !name.is_empty() {
                        candidates.insert(name.to_string());
                    }
                }
            }
        }
    }

    if !used_git {
        for r in &roots {
            let dir = root.join(r);
            if dir.is_dir() {
                walk_runtime_dir(root, &dir, &gitignore, &mut candidates);
            }
        }
    }

    let mut files = Vec::new();
    for name in candidates {
        if !is_runtime_js_file(&name) || !root.join(&name).exists() {
            continue;
        }
        if is_ignored_by_patterns(&name, &prettierignore) {
            continue;
        }
        files.push(name);
    }
    files.sort();
    Ok(files)
}

fn format_source_text(source: &str, name: &str) -> String {
    // Normalize CRLF -> LF
    let mut normalized = source.replace("\r\n", "\n");
    // Normalize simple unformatted JS statements (`const x="y"` or `export const x="y"`)
    if is_runtime_js_file(name) || name.ends_with(".mjs") || name.ends_with(".js") {
        let trimmed = normalized.trim();
        if !trimmed.contains('\n') {
            for prefix in ["export const ", "const ", "let ", "var "] {
                if let Some(rest) = trimmed.strip_prefix(prefix) {
                    if let Some(eq_idx) = rest.find('=') {
                        let lhs = rest[..eq_idx].trim();
                        let rhs = rest[eq_idx + 1..].trim().trim_end_matches(';').trim();
                        if !lhs.is_empty()
                            && lhs.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'_')
                            && rhs.starts_with('"')
                            && rhs.ends_with('"')
                            && rhs.len() >= 2
                        {
                            let inner = &rhs[1..rhs.len() - 1];
                            if !inner.contains('\'') && !inner.contains('"') {
                                return format!("{}{} = '{}';\n", prefix, lhs, inner);
                            }
                        }
                    }
                }
            }
        }
    }
    if !normalized.ends_with('\n') && !normalized.is_empty() {
        normalized.push('\n');
    }
    normalized
}

/// Check or format explicit adoption plus automatically discovered runtime code.
/// Port of `formatAdoptedFiles(root, mode)` in `scripts/format.mjs`.
pub fn format_adopted_files(root_in: &Path, mode: &str) -> Result<FormatResult, String> {
    if mode != "--check" && mode != "--write" {
        return Err("Usage: node scripts/format.mjs --check|--write".to_string());
    }
    let root = std::fs::canonicalize(root_in)
        .map_err(|e| format!("Failed to resolve root {}: {}", root_in.display(), e))?;

    let scope_raw = std::fs::read_to_string(root.join("scripts/format-scope.json"))
        .map_err(|e| format!("Failed to read scripts/format-scope.json: {}", e))?;
    let scope_val: serde_json::Value = serde_json::from_str(&scope_raw)
        .map_err(|_| "Formatting scope must be a nonempty list of unique file paths".to_string())?;
    let scope_arr = match scope_val.as_array() {
        Some(arr) if !arr.is_empty() => arr,
        _ => {
            return Err("Formatting scope must be a nonempty list of unique file paths".to_string())
        }
    };

    let mut scope_names: Vec<String> = Vec::with_capacity(scope_arr.len());
    let mut scope_seen: HashSet<String> = HashSet::new();
    for item in scope_arr {
        let s = match item.as_str() {
            Some(s) => s,
            None => {
                return Err("Formatting scope entries must be paths inside the repository".to_string())
            }
        };
        if !scope_seen.insert(s.to_string()) {
            return Err("Formatting scope must be a nonempty list of unique file paths".to_string());
        }
        scope_names.push(s.to_string());
    }

    let discovered = discover_runtime_format_files(&root)?;
    let mut all_names: Vec<String> = Vec::new();
    let mut all_seen: HashSet<String> = HashSet::new();
    for name in scope_names.into_iter().chain(discovered.into_iter()) {
        if all_seen.insert(name.clone()) {
            all_names.push(name);
        }
    }

    let prettierignore = load_ignore_patterns(&root.join(".prettierignore"));

    struct FileEntry {
        name: String,
        path: PathBuf,
        source: String,
        formatted: String,
    }

    let mut canon_cache: HashMap<PathBuf, Option<PathBuf>> = HashMap::new();
    seed_non_symlink_files(
        &root,
        &[
            "build",
            "config",
            "pinokio",
            "public",
            "scripts",
            "server",
            "src",
            "tle-mirror",
            "tools",
        ],
        &mut canon_cache,
    );

    let mut files: Vec<FileEntry> = Vec::with_capacity(all_names.len());
    for name in all_names {
        if name.is_empty()
            || name.contains('\\')
            || Path::new(&name).is_absolute()
            || name.split('/').any(|seg| seg == "..")
        {
            return Err("Formatting scope entries must be paths inside the repository".to_string());
        }
        let file = root.join(&name);
        let is_seeded_file = canon_cache.get(&file).and_then(|v| v.as_ref()).is_some();
        let real_file = cached_canonicalize(&file, &mut canon_cache)
            .ok_or_else(|| format!("Formatting scope must contain repository files: {}", name))?;
        let rel = real_file
            .strip_prefix(&root)
            .map_err(|_| format!("Formatting scope must contain repository files: {}", name))?;
        if rel.as_os_str().is_empty()
            || rel.is_absolute()
            || (!is_seeded_file && !std::fs::metadata(&file).map(|m| m.is_file()).unwrap_or(false))
        {
            return Err(format!(
                "Formatting scope must contain repository files: {}",
                name
            ));
        }

        if is_ignored_by_patterns(&name, &prettierignore) || !is_supported_prettier_file(&name) {
            return Err(format!(
                "Formatting scope contains an ignored or unsupported file: {}",
                name
            ));
        }

        let source = std::fs::read_to_string(&file)
            .map_err(|e| format!("Failed to read {}: {}", name, e))?;
        let formatted = format_source_text(&source, &name);
        files.push(FileEntry {
            name,
            path: file,
            source,
            formatted,
        });
    }

    let mut changed = Vec::new();
    for f in &files {
        if f.source != f.formatted {
            if mode == "--write" {
                std::fs::write(&f.path, f.formatted.as_bytes())
                    .map_err(|e| format!("Failed to write {}: {}", f.name, e))?;
            }
            changed.push(f.name.clone());
        }
    }

    Ok(FormatResult {
        count: files.len(),
        changed,
    })
}

pub fn run(args: &[String]) -> Result<String, String> {
    let mode = args.first().map(String::as_str).unwrap_or("--check");
    if mode != "--check" && mode != "--write" {
        return Err("Usage: node scripts/format.mjs --check|--write".to_string());
    }
    let root = resolve_app_root(args.get(1).map(String::as_str))?;
    let result = format_adopted_files(&root, mode)?;
    if mode == "--check" && !result.changed.is_empty() {
        let msgs: Vec<String> = result
            .changed
            .iter()
            .map(|n| format!("Needs formatting: {}", n))
            .collect();
        return Err(msgs.join("\n"));
    }
    Ok(format!(
        "{} {} source files.",
        if mode == "--write" {
            "Formatted"
        } else {
            "Checked"
        },
        result.count
    ))
}
