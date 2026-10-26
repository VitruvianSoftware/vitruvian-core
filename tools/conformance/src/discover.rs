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

//! One-shot file discovery cache for the conformance checker.
//!
//! The bash `discover()` function runs `find … | LC_ALL=C sort` on every call.
//! This module walks the tree once at startup, stores every regular file as a
//! relative path (relative to the repo root), and filters on demand. The walk
//! prunes the same directories bash does.

use std::fs;
use std::path::Path;

/// Directories (path components) that are pruned during the walk. A directory
/// is pruned when its name matches one of these values or when the full
/// relative path contains one of the pruned path segments.
///
/// Mirrors the bash find:
/// ```bash
/// \( -path '*/node_modules/*' -o -path '*/bazel-*' -o -name 'bazel-*'
///    -o -path '*/.claude/*' -o -path '*/.worktrees/*' -o -path '*/.agents/*'
///    -o -path '*/internal/scaffold/templates/*' \) -prune
/// ```
const PRUNE_NAMES: &[&str] = &["node_modules", ".claude", ".worktrees", ".agents"];

/// A directory name starting with `bazel-` is always pruned (covers both
/// `-path '*/bazel-*'` and `-name 'bazel-*'`).
fn is_bazel_dir(name: &str) -> bool {
    name.starts_with("bazel-")
}

/// Path segment sequence that triggers pruning: `internal/scaffold/templates`.
const PRUNE_PATH_SEGMENTS: &[&[&str]] = &[&["internal", "scaffold", "templates"]];

/// Returns true when a relative path (split into its components) ends with a
/// sequence that should be pruned.
fn matches_prune_path(components: &[String]) -> bool {
    for seg in PRUNE_PATH_SEGMENTS {
        if components.len() >= seg.len() {
            let start = components.len() - seg.len();
            if components[start..]
                .iter()
                .zip(seg.iter())
                .all(|(a, b)| a == b)
            {
                return true;
            }
        }
    }
    false
}

/// Whether a directory entry name means the directory should be pruned.
fn should_prune_dir(name: &str, components: &[String]) -> bool {
    if PRUNE_NAMES.contains(&name) {
        return true;
    }
    if is_bazel_dir(name) {
        return true;
    }
    // Check if appending this name completes a pruned path segment.
    let mut extended = components.to_vec();
    extended.push(name.to_string());
    matches_prune_path(&extended)
}

/// Cache of every regular file under the repo root, stored as workspace-relative
/// paths and sorted by raw bytes (LC_ALL=C).
pub struct FileCache {
    /// Relative paths (e.g. `"apps/cli/devx/main.go"`), byte-sorted.
    files: Vec<String>,
}

impl FileCache {
    /// Walk `root` once, collecting every regular file while pruning the same
    /// directories bash's `discover()` does. Entries at each directory level
    /// are sorted by filename before recursion for determinism.
    pub fn new(root: &str) -> Self {
        let mut files = Vec::new();
        let root_path = Path::new(root);
        let mut components: Vec<String> = Vec::new();
        Self::walk(root_path, root_path, &mut components, &mut files);
        // LC_ALL=C sort: byte-order on the relative path strings.
        files.sort_unstable();
        FileCache { files }
    }

    fn walk(base: &Path, dir: &Path, components: &mut Vec<String>, out: &mut Vec<String>) {
        let entries = match fs::read_dir(dir) {
            Ok(rd) => rd,
            Err(_) => return,
        };

        // Collect and sort by filename for determinism within each level.
        let mut sorted: Vec<fs::DirEntry> = entries.filter_map(|e| e.ok()).collect();
        sorted.sort_by(|a, b| a.file_name().cmp(&b.file_name()));

        for entry in sorted {
            let name = match entry.file_name().into_string() {
                Ok(s) => s,
                // Non-UTF-8 filenames: skip silently (bash find would emit
                // them but they never match any glob we care about).
                Err(_) => continue,
            };

            let ft = match entry.file_type() {
                Ok(ft) => ft,
                Err(_) => continue,
            };

            if ft.is_dir() {
                if should_prune_dir(&name, components) {
                    continue;
                }
                components.push(name);
                Self::walk(base, &entry.path(), components, out);
                components.pop();
            } else if ft.is_file() {
                // Build relative path from components + name.
                let rel = if components.is_empty() {
                    name
                } else {
                    let mut s = String::with_capacity(
                        components.iter().map(|c| c.len() + 1).sum::<usize>() + name.len(),
                    );
                    for (i, c) in components.iter().enumerate() {
                        if i > 0 {
                            s.push('/');
                        }
                        s.push_str(c);
                    }
                    s.push('/');
                    s.push_str(&name);
                    s
                };
                out.push(rel);
            }
            // Symlinks are not followed, matching `find -type f` which skips them.
        }
    }

    /// Filter cached files by a filename glob and return absolute paths,
    /// byte-sorted (LC_ALL=C). The glob applies to the filename part only,
    /// matching bash's `find … -name "$1"`.
    ///
    /// Supported glob forms (enough for every pattern check.sh uses):
    /// - `"*"` — matches every file
    /// - `"*.yaml"` — suffix match
    /// - `"Dockerfile*"` — prefix match
    /// - `"go.mod"` — exact match
    pub fn discover(&self, root: &str, glob: &str) -> Vec<String> {
        let matcher = GlobMatcher::new(glob);
        let root_slash = if root.ends_with('/') {
            root.to_string()
        } else {
            format!("{}/", root)
        };

        self.files
            .iter()
            .filter(|rel| {
                let filename = rel.rsplit('/').next().unwrap_or(rel);
                matcher.matches(filename)
            })
            .map(|rel| format!("{}{}", root_slash, rel))
            .collect()
    }

    /// Number of cached files (useful for diagnostics).
    #[allow(dead_code)]
    pub fn len(&self) -> usize {
        self.files.len()
    }

    /// Whether the cache is empty.
    #[allow(dead_code)]
    pub fn is_empty(&self) -> bool {
        self.files.is_empty()
    }
}

/// Strip `root/` from `path`, returning the workspace-relative remainder.
/// If `path` does not start with `root/`, it is returned unchanged.
pub fn rel(root: &str, path: &str) -> String {
    let prefix = if root.ends_with('/') {
        root.to_string()
    } else {
        format!("{}/", root)
    };
    if let Some(rest) = path.strip_prefix(&prefix) {
        rest.to_string()
    } else {
        path.to_string()
    }
}

// ---------------------------------------------------------------------------
// Simple glob matcher
// ---------------------------------------------------------------------------

enum GlobMatcher {
    /// `"*"` — match everything.
    Any,
    /// `"*.yaml"` — match files ending with the suffix.
    Suffix(String),
    /// `"Dockerfile*"` — match files starting with the prefix.
    Prefix(String),
    /// `"go.mod"` — exact filename match.
    Exact(String),
}

impl GlobMatcher {
    fn new(pattern: &str) -> Self {
        if pattern == "*" {
            return GlobMatcher::Any;
        }
        // Count stars: we only support a single `*`.
        let star_count = pattern.chars().filter(|&c| c == '*').count();
        if star_count == 0 {
            return GlobMatcher::Exact(pattern.to_string());
        }
        if star_count == 1 {
            if let Some(suffix) = pattern.strip_prefix('*') {
                return GlobMatcher::Suffix(suffix.to_string());
            }
            if let Some(prefix) = pattern.strip_suffix('*') {
                return GlobMatcher::Prefix(prefix.to_string());
            }
        }
        // Fallback: treat as exact (shouldn't happen with check.sh patterns).
        GlobMatcher::Exact(pattern.to_string())
    }

    fn matches(&self, filename: &str) -> bool {
        match self {
            GlobMatcher::Any => true,
            GlobMatcher::Suffix(s) => filename.ends_with(s.as_str()),
            GlobMatcher::Prefix(p) => filename.starts_with(p.as_str()),
            GlobMatcher::Exact(e) => filename == e.as_str(),
        }
    }
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn glob_matcher_exact() {
        let m = GlobMatcher::new("go.mod");
        assert!(m.matches("go.mod"));
        assert!(!m.matches("go.mod.bak"));
        assert!(!m.matches("xgo.mod"));
    }

    #[test]
    fn glob_matcher_suffix() {
        let m = GlobMatcher::new("*.yaml");
        assert!(m.matches("config.yaml"));
        assert!(m.matches(".yaml"));
        assert!(!m.matches("config.yml"));
    }

    #[test]
    fn glob_matcher_prefix() {
        let m = GlobMatcher::new("Dockerfile*");
        assert!(m.matches("Dockerfile"));
        assert!(m.matches("Dockerfile.dev"));
        assert!(!m.matches("xDockerfile"));
    }

    #[test]
    fn glob_matcher_any() {
        let m = GlobMatcher::new("*");
        assert!(m.matches("anything"));
        assert!(m.matches(""));
    }

    #[test]
    fn rel_strips_prefix() {
        assert_eq!(rel("/repo", "/repo/a/b.go"), "a/b.go");
        assert_eq!(rel("/repo/", "/repo/a/b.go"), "a/b.go");
        // When path does not start with root, return as-is.
        assert_eq!(rel("/repo", "/other/a.go"), "/other/a.go");
    }

    #[test]
    fn should_prune_dir_prunes_expected() {
        let empty: Vec<String> = vec![];
        assert!(should_prune_dir("node_modules", &empty));
        assert!(should_prune_dir(".claude", &empty));
        assert!(should_prune_dir(".worktrees", &empty));
        assert!(should_prune_dir(".agents", &empty));
        assert!(should_prune_dir("bazel-out", &empty));
        assert!(should_prune_dir("bazel-bin", &empty));
        assert!(!should_prune_dir("src", &empty));
        assert!(!should_prune_dir("bazel", &empty));
    }

    #[test]
    fn should_prune_scaffold_templates() {
        let components = vec!["internal".to_string(), "scaffold".to_string()];
        assert!(should_prune_dir("templates", &components));
        // But not if the parent path differs.
        let other = vec!["other".to_string(), "scaffold".to_string()];
        assert!(!should_prune_dir("templates", &other));
    }

    #[test]
    fn file_cache_discover_sorts_bytewise() {
        // Create a temp directory with a few files and confirm sorting.
        let tmp = std::env::temp_dir().join(format!("fc_test_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("b")).unwrap();
        fs::create_dir_all(tmp.join("a")).unwrap();
        fs::write(tmp.join("b/z.yaml"), "").unwrap();
        fs::write(tmp.join("a/a.yaml"), "").unwrap();
        fs::write(tmp.join("b/A.yaml"), "").unwrap();

        let root = tmp.to_str().unwrap();
        let cache = FileCache::new(root);
        let found = cache.discover(root, "*.yaml");

        // LC_ALL=C: uppercase before lowercase, so A < a < z.
        let names: Vec<String> = found.iter().map(|p| rel(root, p)).collect();
        assert_eq!(names, vec!["a/a.yaml", "b/A.yaml", "b/z.yaml"]);

        let _ = fs::remove_dir_all(&tmp);
    }

    #[test]
    fn file_cache_prunes_node_modules() {
        let tmp = std::env::temp_dir().join(format!("fc_prune_{}", std::process::id()));
        let _ = fs::remove_dir_all(&tmp);
        fs::create_dir_all(tmp.join("node_modules/pkg")).unwrap();
        fs::create_dir_all(tmp.join("src")).unwrap();
        fs::write(tmp.join("node_modules/pkg/index.js"), "").unwrap();
        fs::write(tmp.join("src/main.rs"), "").unwrap();

        let root = tmp.to_str().unwrap();
        let cache = FileCache::new(root);
        let all = cache.discover(root, "*");
        let names: Vec<String> = all.iter().map(|p| rel(root, p)).collect();
        assert_eq!(names, vec!["src/main.rs"]);

        let _ = fs::remove_dir_all(&tmp);
    }
}
