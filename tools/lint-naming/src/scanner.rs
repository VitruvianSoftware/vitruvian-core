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

//! scanner.py: walks the tree like `os.walk` and runs every rule.

use crate::pystr::{cmp_str, strip};
use crate::rules::bazel::{validate_build_file_content, validate_starlark_file_name};
use crate::rules::configs::{validate_config_file_name, validate_workflow_yaml_content};
use crate::rules::directories::validate_directory_name;
use crate::rules::source_files::validate_file_name;
use crate::textio::{os_to_str, read_text_ignore, str_to_os};
use crate::violation::{Severity, Violation};
use std::collections::HashMap;
use std::ffi::OsString;
use std::path::{Path, PathBuf};

/// Names never scanned (DEFAULT_IGNORES).
pub const DEFAULT_IGNORES: &[&str] = &[
    ".git",
    ".hg",
    ".svn",
    ".venv",
    "node_modules",
    "bazel-out",
    "bazel-bin",
    "bazel-testlogs",
    "bazel-vitruvian-core",
    ".remember",
    ".cache",
    "dist",
    "build",
    "coverage",
    "__pycache__",
    ".agents",
    ".next",
    ".turbo",
    ".astro",
    ".output",
    "out",
    ".ruff_cache",
    ".storybook",
    ".vitepress",
    ".worktrees",
    ".claude-worktrees",
    ".superpowers",
    ".swc",
    ".aspect",
    "sdk",
    "examples",
    "testdata",
];

/// `os.path.normpath` on POSIX.
pub fn normpath(path: &str) -> String {
    if path.is_empty() {
        return ".".to_string();
    }
    let mut initial = if path.starts_with('/') { 1 } else { 0 };
    if path.starts_with("//") && !path.starts_with("///") {
        initial = 2;
    }
    let mut comps: Vec<&str> = Vec::new();
    for comp in path.split('/') {
        if comp.is_empty() || comp == "." {
            continue;
        }
        if comp != ".." || (initial == 0 && comps.is_empty()) || comps.last() == Some(&"..") {
            comps.push(comp);
        } else if !comps.is_empty() {
            comps.pop();
        }
    }
    let joined = comps.join("/");
    let out = format!("{}{}", "/".repeat(initial), joined);
    if out.is_empty() {
        ".".to_string()
    } else {
        out
    }
}

/// `os.path.abspath`.
pub fn abspath(path: &str) -> String {
    if path.starts_with('/') {
        return normpath(path);
    }
    let cwd = std::env::current_dir()
        .map(|p| os_to_str(p.as_os_str()))
        .unwrap_or_else(|_| "/".into());
    let joined = if cwd.ends_with('/') {
        format!("{}{}", cwd, path)
    } else {
        format!("{}/{}", cwd, path)
    };
    normpath(&joined)
}

fn join(rel_root: &str, name: &str) -> String {
    if rel_root.is_empty() {
        name.to_string()
    } else {
        format!("{}/{}", rel_root, name)
    }
}

/// RepositoryNamingScanner.
pub struct Scanner {
    pub root_dir: String,
    pub ignores: Vec<String>,
    pub ignore_violation_fixtures: bool,
}

/// Python's `linecache`, as far as warnings use it: a file name relative to
/// the working directory, else to each entry of `sys.path` (for the port:
/// the directory of the executable, which stands where the script would).
#[derive(Default)]
pub struct LineCache {
    cache: HashMap<String, Vec<String>>,
    search: Vec<PathBuf>,
}

impl LineCache {
    pub fn new(search: Vec<PathBuf>) -> LineCache {
        LineCache {
            cache: HashMap::new(),
            search,
        }
    }

    fn load(&self, filename: &str) -> Option<Vec<String>> {
        let rel = PathBuf::from(str_to_os(filename));
        let mut candidates = vec![rel.clone()];
        if !rel.is_absolute() {
            candidates.extend(self.search.iter().map(|d| d.join(&rel)));
        }
        let path = candidates
            .into_iter()
            .find(|p| std::fs::metadata(p).is_ok())?;
        let bytes = std::fs::read(path).ok()?;
        let text = decode_source(&bytes)?;
        let text = crate::textio::translate_newlines(&text);
        Some(text.split_inclusive('\n').map(String::from).collect())
    }

    /// `linecache.getline(filename, lineno)`.
    pub fn getline(&mut self, filename: &str, lineno: usize) -> String {
        if filename.is_empty() || (filename.starts_with('<') && filename.ends_with('>')) {
            return String::new();
        }
        if !self.cache.contains_key(filename) {
            match self.load(filename) {
                Some(lines) => {
                    self.cache.insert(filename.to_string(), lines);
                }
                None => return String::new(),
            }
        }
        let lines = &self.cache[filename];
        if lineno >= 1 && lineno <= lines.len() {
            lines[lineno - 1].clone()
        } else {
            String::new()
        }
    }
}

/// `tokenize.open`: a UTF-8 BOM or a coding cookie, else UTF-8.
fn decode_source(bytes: &[u8]) -> Option<String> {
    let (bom, body) = match bytes.strip_prefix(b"\xef\xbb\xbf") {
        Some(rest) => (true, rest),
        None => (false, bytes),
    };
    let cookie = coding_cookie(body);
    match cookie.as_deref() {
        None | Some("utf-8") => std::str::from_utf8(body).ok().map(String::from),
        Some("latin-1") if !bom => Some(body.iter().map(|&b| b as char).collect()),
        Some("ascii") if !bom => {
            if body.is_ascii() {
                Some(String::from_utf8(body.to_vec()).ok()?)
            } else {
                None
            }
        }
        _ => None,
    }
}

fn normalize_encoding(name: &str) -> String {
    let lower = name.to_ascii_lowercase().replace('_', "-");
    if lower == "utf-8" || lower.starts_with("utf-8-") {
        "utf-8".into()
    } else if ["latin-1", "iso-8859-1", "iso-latin-1"]
        .iter()
        .any(|p| lower == *p || lower.starts_with(&format!("{}-", p)))
    {
        "latin-1".into()
    } else if lower == "ascii" || lower == "us-ascii" {
        "ascii".into()
    } else {
        lower
    }
}

/// `^[ \t\f]*#.*?coding[:=][ \t]*([-\w.]+)` on the first line, or the
/// second when the first is blank or a comment.
fn coding_cookie(body: &[u8]) -> Option<String> {
    let mut lines = body.split_inclusive(|&b| b == b'\n');
    for (i, line) in (&mut lines).take(2).enumerate() {
        let text = String::from_utf8_lossy(line);
        let t = text.trim_start_matches([' ', '\t', '\x0c']);
        if t.starts_with('#') {
            if let Some(at) = t.find("coding") {
                let rest = &t[at + 6..];
                if let Some(r) = rest.strip_prefix(':').or_else(|| rest.strip_prefix('=')) {
                    let r = r.trim_start_matches([' ', '\t']);
                    let name: String = r
                        .chars()
                        .take_while(|c| c.is_alphanumeric() || *c == '_' || *c == '-' || *c == '.')
                        .collect();
                    if !name.is_empty() {
                        return Some(normalize_encoding(&name));
                    }
                }
            }
        }
        let blank = t.trim_end_matches(['\r', '\n']).is_empty() || t.starts_with('#');
        if i == 0 && !blank {
            break;
        }
    }
    None
}

/// The text `warnings` prints for a SyntaxWarning from `ast.parse`.
pub fn format_warning(
    cache: &mut LineCache,
    filename: &str,
    lineno: usize,
    message: &str,
) -> String {
    let mut s = format!("{}:{}: SyntaxWarning: {}\n", filename, lineno, message);
    let line = cache.getline(filename, lineno);
    let line = strip(&line);
    if !line.is_empty() {
        s.push_str(&format!("  {}\n", line));
    }
    s
}

impl Scanner {
    pub fn new(
        root_dir: &str,
        ignores: Option<Vec<String>>,
        ignore_violation_fixtures: bool,
    ) -> Scanner {
        Scanner {
            root_dir: abspath(root_dir),
            ignores: ignores
                .unwrap_or_else(|| DEFAULT_IGNORES.iter().map(|s| s.to_string()).collect()),
            ignore_violation_fixtures,
        }
    }

    /// should_ignore.
    pub fn should_ignore(&self, rel_path: &str) -> bool {
        let normalized = rel_path.replace('\\', "/");
        if normalized
            .split('/')
            .any(|part| self.ignores.iter().any(|i| i == part))
        {
            return true;
        }
        self.ignore_violation_fixtures && normalized.contains("testdata/violations")
    }

    /// scan(): the violations, in the order the walk finds them. Each
    /// SyntaxWarning `ast.parse` would print goes to `warn` as it happens.
    pub fn scan(&self, cache: &mut LineCache, warn: &mut dyn FnMut(String)) -> Vec<Violation> {
        let mut violations = Vec::new();
        let root = PathBuf::from(str_to_os(&self.root_dir));
        let mut stack: Vec<(PathBuf, String)> = vec![(root, String::new())];
        while let Some((dir, rel_root)) = stack.pop() {
            let Ok(entries) = std::fs::read_dir(&dir) else {
                continue;
            };
            let mut dirs: Vec<(String, OsString)> = Vec::new();
            let mut files: Vec<(String, OsString)> = Vec::new();
            let mut failed = false;
            for entry in entries {
                let Ok(entry) = entry else {
                    failed = true;
                    break;
                };
                let raw = entry.file_name();
                let name = os_to_str(&raw);
                let is_dir = match entry.file_type() {
                    Ok(ft) if ft.is_symlink() => std::fs::metadata(entry.path())
                        .map(|m| m.is_dir())
                        .unwrap_or(false),
                    Ok(ft) => ft.is_dir(),
                    Err(_) => false,
                };
                if is_dir {
                    dirs.push((name, raw));
                } else {
                    files.push((name, raw));
                }
            }
            if failed {
                continue;
            }

            dirs.retain(|(d, _)| !self.should_ignore(&join(&rel_root, d)));

            if !rel_root.is_empty() {
                let is_root = !rel_root.replace('\\', "/").contains('/');
                violations.extend(validate_directory_name(&rel_root, is_root));
            }

            for (file_name, raw) in &files {
                let rel_file = join(&rel_root, file_name).replace('\\', "/");
                if self.should_ignore(&rel_file) {
                    continue;
                }
                let abs_file = dir.join(raw);
                violations.extend(validate_file_name(&rel_file));
                if file_name.ends_with(".bzl") {
                    violations.extend(validate_starlark_file_name(&rel_file));
                }
                if file_name.ends_with(".yaml") || file_name.ends_with(".yml") {
                    violations.extend(validate_config_file_name(&rel_file));
                    if rel_file.contains(".github/workflows") {
                        if let Ok(content) = read_text_ignore(&abs_file) {
                            violations.extend(validate_workflow_yaml_content(&rel_file, &content));
                        }
                    }
                }
                if file_name == "BUILD" || file_name == "BUILD.bazel" {
                    if let Ok(content) = read_text_ignore(&abs_file) {
                        let result = validate_build_file_content(&rel_file, &content);
                        for w in &result.warnings {
                            warn(format_warning(cache, &rel_file, w.line, &w.message));
                        }
                        violations.extend(result.violations);
                    }
                }
            }

            for (_, raw) in dirs.iter().rev() {
                let path = dir.join(raw);
                let is_link = std::fs::symlink_metadata(&path)
                    .map(|m| m.file_type().is_symlink())
                    .unwrap_or(false);
                if !is_link {
                    let name = os_to_str(raw);
                    stack.push((path, join(&rel_root, &name)));
                }
            }
        }
        violations
    }
}

/// format_report.
pub fn format_report(violations: &[Violation], output_format: &str) -> String {
    let errors = violations
        .iter()
        .filter(|v| v.severity == Severity::Error)
        .count();
    let warnings = violations
        .iter()
        .filter(|v| v.severity == Severity::Warning)
        .count();
    if output_format == "json" {
        let list = if violations.is_empty() {
            "[]".to_string()
        } else {
            let items: Vec<String> = violations
                .iter()
                .map(|v| format!("    {}", v.to_json("    ")))
                .collect();
            format!("[\n{}\n  ]", items.join(",\n"))
        };
        return format!(
            "{{\n  \"total_violations\": {},\n  \"error_count\": {},\n  \"warning_count\": {},\n  \"violations\": {}\n}}",
            violations.len(),
            errors,
            warnings,
            list
        );
    }
    let mut sorted: Vec<&Violation> = violations.iter().collect();
    sorted.sort_by(|a, b| {
        cmp_str(&a.file_path, &b.file_path)
            .then_with(|| a.line_number.unwrap_or(0).cmp(&b.line_number.unwrap_or(0)))
    });
    let mut lines: Vec<String> = sorted.iter().map(|v| v.format_line()).collect();
    lines.push(format!(
        "\nNaming Audit Complete: {} issues found ({} errors, {} warnings).",
        violations.len(),
        errors,
        warnings
    ));
    lines.join("\n")
}

/// The directory a script would be imported from: where the executable is.
pub fn exe_dir() -> Vec<PathBuf> {
    std::env::args_os()
        .next()
        .map(|a| {
            let p = PathBuf::from(a);
            let parent = p.parent().map(Path::to_path_buf).unwrap_or_default();
            if parent.as_os_str().is_empty() {
                PathBuf::from(".")
            } else {
                parent
            }
        })
        .into_iter()
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normpath_matches_python() {
        assert_eq!(normpath("/a/./b/../c"), "/a/c");
        assert_eq!(normpath("//a//b"), "//a/b");
        assert_eq!(normpath("///a"), "/a");
        assert_eq!(normpath("a/../.."), "..");
        assert_eq!(normpath("/.."), "/");
        assert_eq!(normpath(""), ".");
    }

    #[test]
    fn ignores() {
        let s = Scanner::new(".", None, true);
        assert!(s.should_ignore("node_modules/pkg/bad_file.go"));
        assert!(s.should_ignore(".git/hooks/pre-commit"));
        assert!(s.should_ignore("a\\testdata\\x"));
        assert!(!s.should_ignore("src/main.go"));
        let c = Scanner::new(".", Some(vec!["custom_vendor".into()]), true);
        assert!(c.should_ignore("custom_vendor/bad_name.go"));
        assert!(c.should_ignore("x/testdata/violations/y"));
        assert!(!Scanner::new(".", Some(vec![]), false).should_ignore("x/testdata/violations/y"));
        assert!(Path::new(&s.root_dir).is_absolute());
    }

    #[test]
    fn report_formats() {
        assert_eq!(
            format_report(&[], "text"),
            "\nNaming Audit Complete: 0 issues found (0 errors, 0 warnings)."
        );
        assert_eq!(
            format_report(&[], "json"),
            "{\n  \"total_violations\": 0,\n  \"error_count\": 0,\n  \"warning_count\": 0,\n  \"violations\": []\n}"
        );
        let v = |p: &str, l: Option<i64>| {
            Violation::new("X1", p, l, "m".into(), Severity::Warning, None)
        };
        let text = format_report(&[v("b", None), v("a", Some(2)), v("a", None)], "text");
        assert_eq!(
            text,
            "a: [X1] WARNING: m\na:2: [X1] WARNING: m\nb: [X1] WARNING: m\n\nNaming Audit Complete: 3 issues found (0 errors, 3 warnings)."
        );
    }

    #[test]
    fn scans_a_tree() {
        let dir = std::env::temp_dir().join(format!("lint-naming-rs-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(dir.join("pkg/auth_service")).unwrap();
        std::fs::write(dir.join("pkg/auth_service/auth-handler.go"), "package x\n").unwrap();
        std::fs::create_dir_all(dir.join("node_modules/x")).unwrap();
        std::fs::write(dir.join("node_modules/x/bad-name.go"), "").unwrap();
        std::fs::write(dir.join("BUILD"), "sh_binary(name = \"a_b\")\n").unwrap();
        let s = Scanner::new(dir.to_str().unwrap(), None, true);
        let mut cache = LineCache::default();
        let found = s.scan(&mut cache, &mut |_| {});
        let mut ids: Vec<&str> = found.iter().map(|v| v.rule_id.as_str()).collect();
        ids.sort();
        assert_eq!(ids, ["BZL001", "GO001"]);
        std::fs::remove_dir_all(&dir).unwrap();
    }

    #[test]
    fn testdata_fixtures() {
        let clean = Path::new("tools/lint-naming/testdata/clean_repo");
        if clean.is_dir() {
            let s = Scanner::new(clean.to_str().unwrap(), Some(vec![]), false);
            let mut cache = LineCache::default();
            let found = s.scan(&mut cache, &mut |_| {});
            let errors: Vec<_> = found
                .iter()
                .filter(|v| v.severity == Severity::Error)
                .collect();
            assert!(
                errors.is_empty(),
                "expected 0 errors on clean_repo, got {:?}",
                errors
            );
        }
        let violations = Path::new("tools/lint-naming/testdata/violations");
        if violations.is_dir() {
            let s = Scanner::new(violations.to_str().unwrap(), Some(vec![]), false);
            let mut cache = LineCache::default();
            let found = s.scan(&mut cache, &mut |_| {});
            assert!(
                !found.is_empty(),
                "expected violations on testdata/violations"
            );
        }
    }
}
