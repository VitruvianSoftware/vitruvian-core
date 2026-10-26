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

//! Canonical source-of-truth readers and Go version helpers.
//!
//! Port of `canonical_go()`, `canonical_node()`, `canonical_pnpm()`,
//! `catalog_names()`, and the `go_major`/`go_minor`/`go_patch`/`go_is_newer`
//! helpers from `check.sh` (lines 261-352).

use std::fs;
use std::path::Path;

// ---------------------------------------------------------------------------
// Canonical readers
// ---------------------------------------------------------------------------

/// Read the canonical Go version from `go.work`.
///
/// Finds the first line whose first whitespace-delimited token is `"go"` and
/// returns the second token (the version string, e.g. `"1.23.4"`).
///
/// Returns `Err` if `go.work` is missing or contains no `go` directive.
pub fn canonical_go(root: &str) -> Result<String, String> {
    let path = Path::new(root).join("go.work");
    let content =
        fs::read_to_string(&path).map_err(|_| format!("canonical source missing: go.work"))?;

    for line in content.lines() {
        let mut tokens = line.split_whitespace();
        if let Some(first) = tokens.next() {
            if first == "go" {
                if let Some(version) = tokens.next() {
                    return Ok(version.to_string());
                }
            }
        }
    }
    Err("go.work has no 'go' directive".to_string())
}

/// Read the canonical Node major version from `.nvmrc`.
///
/// Reads the first line, strips leading whitespace and a leading `v`, splits
/// on `"."`, and returns the first part (the major version, e.g. `"22"`).
///
/// Returns `Err` if `.nvmrc` is missing.
pub fn canonical_node(root: &str) -> Result<String, String> {
    let path = Path::new(root).join(".nvmrc");
    let content =
        fs::read_to_string(&path).map_err(|_| format!("canonical source missing: .nvmrc"))?;

    let first_line = content.lines().next().unwrap_or("");

    // Strip leading whitespace and a leading 'v', matching:
    //   gsub(/^[ \tv]+|[ \t\r]+$/, "")
    let trimmed = first_line
        .trim_start_matches(|c: char| c == ' ' || c == '\t' || c == 'v')
        .trim_end_matches(|c: char| c == ' ' || c == '\t' || c == '\r');

    // split on ".", take the first part (major version)
    let major = trimmed.split('.').next().unwrap_or(trimmed);
    Ok(major.to_string())
}

/// Read the canonical pnpm version from the root `package.json`.
///
/// Finds a line containing `"packageManager"`, then extracts the version
/// after `"pnpm@"` (digits and dots).
///
/// Returns `Err` if `package.json` is missing or has no packageManager field.
pub fn canonical_pnpm(root: &str) -> Result<String, String> {
    let path = Path::new(root).join("package.json");
    let content =
        fs::read_to_string(&path).map_err(|_| format!("canonical source missing: package.json"))?;

    for line in content.lines() {
        if !line.contains("\"packageManager\"") {
            continue;
        }
        // Extract version after "pnpm@": match digits and dots.
        // Equivalent to: sed -n 's/.*pnpm@\([0-9][0-9.]*\).*/\1/p'
        if let Some(idx) = line.find("pnpm@") {
            let after = &line[idx + 5..]; // skip "pnpm@"
            let version: String = after
                .chars()
                .take_while(|c| c.is_ascii_digit() || *c == '.')
                .collect();
            if !version.is_empty() {
                return Ok(version);
            }
        }
    }
    Err("package.json has no pnpm packageManager".to_string())
}

// ---------------------------------------------------------------------------
// catalog_names
// ---------------------------------------------------------------------------

/// Extract dependency names from the pnpm catalog in `pnpm-workspace.yaml`.
///
/// Reads the file and applies the same awk logic from check.sh:
///
/// - A column-0 key (no leading whitespace, not a comment) that is exactly
///   `catalog:` or `catalogs:` (followed by optional whitespace) starts a
///   catalog block. Any other column-0 key ends the block.
/// - Inside a catalog block, lines matching `<indent>key: <non-whitespace>`
///   are dependency entries. The key is the dependency name.
/// - Named-group headers (`  react18:` with no value) are skipped.
/// - Quotes around keys are stripped.
/// - The result is sorted (LC_ALL=C byte order) and deduplicated.
pub fn catalog_names(workspace_yaml: &str) -> Vec<String> {
    let content = match fs::read_to_string(workspace_yaml) {
        Ok(c) => c,
        Err(_) => return Vec::new(),
    };

    let mut names: Vec<String> = Vec::new();
    let mut in_catalog = false;

    for line in content.lines() {
        // Skip comment lines (leading whitespace + '#').
        let stripped = line.trim_start();
        if stripped.starts_with('#') {
            continue;
        }

        // Column-0 key detection: a line that starts with a non-whitespace,
        // non-'#' character.
        let first_char = line.chars().next();
        if let Some(c) = first_char {
            if !c.is_whitespace() && c != '#' {
                // Check if this is catalog: or catalogs:
                let trimmed_line = line.trim();
                in_catalog = trimmed_line == "catalog:" || trimmed_line == "catalogs:";
                continue;
            }
        }

        // Inside a catalog block: look for dependency entries.
        if !in_catalog {
            continue;
        }

        // A dependency entry has a colon followed by whitespace and then a
        // non-whitespace character (the version specifier). A named-group
        // header ends with `:` and has no value, so it is skipped.
        //
        // Matches: match($0, /:[[:space:]]*[^[:space:]]/)
        if let Some(colon_pos) = stripped.find(':') {
            let after_colon = &stripped[colon_pos + 1..];
            let after_ws = after_colon.trim_start();
            if !after_ws.is_empty() {
                // Extract the key: everything before the colon, leading
                // whitespace already stripped.
                let key = stripped[..colon_pos].trim();
                // Strip quotes from the key.
                let clean_key = key.trim_matches('"').trim_matches('\'');
                if !clean_key.is_empty() {
                    names.push(clean_key.to_string());
                }
            }
        }
    }

    // LC_ALL=C sort -u: byte-order sort and deduplicate.
    names.sort();
    names.dedup();
    names
}

// ---------------------------------------------------------------------------
// Go version helpers
// ---------------------------------------------------------------------------

/// Extract the major version from a dotted Go version string.
///
/// `"1.23.4"` -> `1`, `"1"` -> `1`, `""` -> `0`.
pub fn go_major(v: &str) -> u32 {
    v.split('.')
        .next()
        .and_then(|s| s.parse().ok())
        .unwrap_or(0)
}

/// Extract the minor version from a dotted Go version string.
///
/// `"1.23.4"` -> `23`, `"1"` -> `0`.
pub fn go_minor(v: &str) -> u32 {
    v.split('.')
        .nth(1)
        .and_then(|s| s.parse().ok())
        .unwrap_or(0)
}

/// Extract the patch version from a dotted Go version string.
///
/// `"1.23.4"` -> `4`, `"1.23"` -> `0`.
pub fn go_patch(v: &str) -> u32 {
    v.split('.')
        .nth(2)
        .and_then(|s| s.parse().ok())
        .unwrap_or(0)
}

/// Returns `true` if `found` is strictly greater than `canonical` as a Go
/// version (major.minor.patch comparison).
///
/// Used for the go-safety "never newer" rule: a module should not declare a
/// Go version newer than the workspace canonical.
pub fn go_is_newer(found: &str, canonical: &str) -> bool {
    let f_major = go_major(found);
    let c_major = go_major(canonical);
    if f_major != c_major {
        return f_major > c_major;
    }

    let f_minor = go_minor(found);
    let c_minor = go_minor(canonical);
    if f_minor != c_minor {
        return f_minor > c_minor;
    }

    let f_patch = go_patch(found);
    let c_patch = go_patch(canonical);
    f_patch > c_patch
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    /// Create a temporary directory with a file and return the directory path.
    fn temp_dir_with_file(name: &str, content: &str) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static COUNTER: AtomicU64 = AtomicU64::new(0);
        let id = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!(
            "conformance-test-{}-{}-{}",
            std::process::id(),
            id,
            std::time::SystemTime::now()
                .duration_since(std::time::UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&dir).unwrap();
        let mut f = fs::File::create(dir.join(name)).unwrap();
        f.write_all(content.as_bytes()).unwrap();
        dir
    }

    #[test]
    fn canonical_go_reads_version() {
        let dir = temp_dir_with_file("go.work", "go 1.23.4\n\nuse (\n\t.\n\tapps/cli/devx\n)\n");
        let result = canonical_go(dir.to_str().unwrap()).unwrap();
        assert_eq!(result, "1.23.4");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn canonical_go_skips_non_go_lines() {
        let dir = temp_dir_with_file("go.work", "// comment\nuse .\ngo 1.24.0\ngo 1.25.0\n");
        // Should return the first match.
        let result = canonical_go(dir.to_str().unwrap()).unwrap();
        assert_eq!(result, "1.24.0");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn canonical_go_missing_file() {
        let result = canonical_go("/nonexistent/path");
        assert!(result.is_err());
        assert!(result.unwrap_err().contains("go.work"));
    }

    #[test]
    fn canonical_node_strips_v_prefix() {
        let dir = temp_dir_with_file(".nvmrc", "v22.21.1\n");
        let result = canonical_node(dir.to_str().unwrap()).unwrap();
        assert_eq!(result, "22");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn canonical_node_plain_version() {
        let dir = temp_dir_with_file(".nvmrc", "22.21.1\n");
        let result = canonical_node(dir.to_str().unwrap()).unwrap();
        assert_eq!(result, "22");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn canonical_node_with_leading_whitespace() {
        let dir = temp_dir_with_file(".nvmrc", "  v20.10.0\n");
        let result = canonical_node(dir.to_str().unwrap()).unwrap();
        assert_eq!(result, "20");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn canonical_pnpm_extracts_version() {
        let dir = temp_dir_with_file(
            "package.json",
            r#"{
  "name": "vitruvian-core",
  "packageManager": "pnpm@9.15.4+sha512.abc123"
}
"#,
        );
        let result = canonical_pnpm(dir.to_str().unwrap()).unwrap();
        assert_eq!(result, "9.15.4");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn canonical_pnpm_missing_file() {
        let result = canonical_pnpm("/nonexistent/path");
        assert!(result.is_err());
    }

    #[test]
    fn catalog_names_default_catalog() {
        let dir = temp_dir_with_file(
            "pnpm-workspace.yaml",
            r#"packages:
  - 'apps/**'
  - 'packages/**'

catalog:
  react: ^19.0.0
  typescript: ^5.7.0
  "@types/node": ^22.0.0
  vitest: ^3.0.0

packageExtensions:
  some-pkg:
    dependencies:
      foo: '*'
"#,
        );
        let yaml_path = dir.join("pnpm-workspace.yaml");
        let names = catalog_names(yaml_path.to_str().unwrap());
        assert_eq!(names, vec!["@types/node", "react", "typescript", "vitest"]);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn catalog_names_named_catalogs() {
        let dir = temp_dir_with_file(
            "pnpm-workspace.yaml",
            r#"packages:
  - 'apps/**'

catalogs:
  react18:
    react: ^18.0.0
    react-dom: ^18.0.0
  react19:
    react: ^19.0.0
"#,
        );
        let yaml_path = dir.join("pnpm-workspace.yaml");
        let names = catalog_names(yaml_path.to_str().unwrap());
        assert_eq!(names, vec!["react", "react-dom"]);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn catalog_names_skips_comments() {
        let dir = temp_dir_with_file(
            "pnpm-workspace.yaml",
            r#"catalog:
  # NOTE: this is pinned
  react: ^19.0.0
  # typescript: ^5.6.0
  vitest: ^3.0.0
"#,
        );
        let yaml_path = dir.join("pnpm-workspace.yaml");
        let names = catalog_names(yaml_path.to_str().unwrap());
        assert_eq!(names, vec!["react", "vitest"]);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn catalog_names_strips_quotes() {
        let dir = temp_dir_with_file(
            "pnpm-workspace.yaml",
            "catalog:\n  \"@scope/pkg\": ^1.0.0\n  '@other/pkg': ^2.0.0\n",
        );
        let yaml_path = dir.join("pnpm-workspace.yaml");
        let names = catalog_names(yaml_path.to_str().unwrap());
        assert_eq!(names, vec!["@other/pkg", "@scope/pkg"]);
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn catalog_names_missing_file() {
        let names = catalog_names("/nonexistent/pnpm-workspace.yaml");
        assert!(names.is_empty());
    }

    #[test]
    fn go_version_components() {
        assert_eq!(go_major("1.23.4"), 1);
        assert_eq!(go_minor("1.23.4"), 23);
        assert_eq!(go_patch("1.23.4"), 4);

        assert_eq!(go_major("1.23"), 1);
        assert_eq!(go_minor("1.23"), 23);
        assert_eq!(go_patch("1.23"), 0);

        assert_eq!(go_major("1"), 1);
        assert_eq!(go_minor("1"), 0);
        assert_eq!(go_patch("1"), 0);

        assert_eq!(go_major(""), 0);
        assert_eq!(go_minor(""), 0);
        assert_eq!(go_patch(""), 0);
    }

    #[test]
    fn go_is_newer_compares_correctly() {
        // Same version.
        assert!(!go_is_newer("1.23.4", "1.23.4"));

        // Newer major.
        assert!(go_is_newer("2.0.0", "1.23.4"));
        assert!(!go_is_newer("1.23.4", "2.0.0"));

        // Newer minor.
        assert!(go_is_newer("1.24.0", "1.23.4"));
        assert!(!go_is_newer("1.22.0", "1.23.4"));

        // Newer patch.
        assert!(go_is_newer("1.23.5", "1.23.4"));
        assert!(!go_is_newer("1.23.3", "1.23.4"));

        // Missing patch treated as 0.
        assert!(go_is_newer("1.24", "1.23.4"));
        assert!(!go_is_newer("1.23", "1.23.4"));
    }
}
