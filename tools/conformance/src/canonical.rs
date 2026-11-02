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

/// Read the canonical Rust version from `MODULE.bazel`: the first entry of
/// `versions = [...]` in the `<ext>.toolchain(...)` call, where `<ext>` is
/// whatever variable `use_extension("@rules_rust//rust:extensions.bzl",
/// "rust")` is bound to (`rust` today). That is the hermetic toolchain every
/// Rust target builds with (`1.75.0` today).
///
/// `<ext>.repository_set(...)` calls (the libsignal 1.98.1 toolchain,
/// selected only by its own flag) are not the canonical version and are
/// ignored.
///
/// Returns `Err` if `MODULE.bazel` is missing or the version cannot be found.
/// The caller must treat that as a failure: this repo always has a Rust
/// toolchain, so not finding one means this reader is broken.
pub fn canonical_rust(root: &str) -> Result<String, String> {
    let path = Path::new(root).join("MODULE.bazel");
    let content = fs::read_to_string(&path)
        .map_err(|_| "canonical source missing: MODULE.bazel".to_string())?;
    rust_version_from_module(&content).ok_or_else(|| {
        "could not read rules_rust's <ext>.toolchain(versions = [...]) from MODULE.bazel"
            .to_string()
    })
}

/// The variable `use_extension("@rules_rust//rust:extensions.bzl", "rust")`
/// is bound to, in either quote style and with any spacing.
fn rules_rust_extension_var(content: &str) -> Option<String> {
    for line in content.lines() {
        let l = line.split('#').next().unwrap_or("");
        let Some((lhs, rhs)) = l.split_once('=') else {
            continue;
        };
        let rhs: String = rhs
            .chars()
            .filter(|c| !c.is_whitespace())
            .collect::<String>()
            .replace('\'', "\"");
        if rhs.starts_with("use_extension(\"@rules_rust//rust:extensions.bzl\",\"rust\"") {
            let var = lhs.trim();
            if !var.is_empty() && var.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
                return Some(var.to_string());
            }
        }
    }
    None
}

/// `text` with its Starlark `#` comments removed, line breaks kept. String
/// literals (`"..."`, `'...'` and the triple-quoted forms) are copied as
/// they are, so a `#` inside one is not a comment. Without this, a
/// commented-out `# rust.toolchain(versions = [...])` above the real call
/// was read as the version.
fn strip_starlark_comments(text: &str) -> String {
    let b = text.as_bytes();
    let mut out = String::with_capacity(text.len());
    let mut i = 0;
    while i < b.len() {
        let c = b[i];
        if c == b'#' {
            while i < b.len() && b[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        if c == b'"' || c == b'\'' {
            let triple = i + 2 < b.len() && b[i + 1] == c && b[i + 2] == c;
            let q = if triple { 3 } else { 1 };
            let start = i;
            i += q;
            while i < b.len() {
                if b[i] == b'\\' {
                    i += 2;
                    continue;
                }
                if b[i] == c && (!triple || (i + 2 < b.len() && b[i + 1] == c && b[i + 2] == c)) {
                    i += q;
                    break;
                }
                if !triple && b[i] == b'\n' {
                    break;
                }
                i += 1;
            }
            out.push_str(&text[start..i.min(b.len())]);
            continue;
        }
        let len = text[i..].chars().next().map_or(1, char::len_utf8);
        out.push_str(&text[i..i + len]);
        i += len;
    }
    out
}

/// The parser behind [`canonical_rust`], on `MODULE.bazel`'s text. Comments
/// are stripped first, so nothing commented out is read.
pub fn rust_version_from_module(content: &str) -> Option<String> {
    let stripped = strip_starlark_comments(content);
    let content = stripped.as_str();
    let var = rules_rust_extension_var(content)?;
    let call = format!("{var}.toolchain(");
    // The call must start a statement: `xrust.toolchain(` is a different
    // variable.
    let start = content.match_indices(&call).map(|(i, _)| i).find(|&i| {
        i == 0 || content[..i].ends_with(|c: char| c == '\n' || c == ' ' || c == '\t')
    })?;
    let body = &content[start + call.len()..];
    // The call's own parentheses, so a later call's versions are not read.
    let mut depth = 1;
    let mut end = body.len();
    for (i, c) in body.char_indices() {
        match c {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if depth == 0 {
                    end = i;
                    break;
                }
            }
            _ => {}
        }
    }
    let body = &body[..end];
    // `versions = [ ... ]`, as a keyword argument: not `versions` inside
    // another argument's value.
    let list = body.match_indices("versions").find_map(|(i, m)| {
        let before_ok =
            i == 0 || body[..i].ends_with(|c: char| c.is_whitespace() || c == '(' || c == ',');
        let rest = body[i + m.len()..]
            .trim_start()
            .strip_prefix('=')?
            .trim_start();
        if !before_ok {
            return None;
        }
        let inner = rest.strip_prefix('[')?;
        Some(&inner[..inner.find(']')?])
    })?;
    let first = list.split(',').map(str::trim).find(|s| !s.is_empty())?;
    let version = if let Some(lit) = string_literal(first) {
        lit.to_string()
    } else {
        // A bare name (`versions = [RUST_VERSION]`): its top-level assignment.
        top_level_string(content, first)?
    };
    // Anything but one exact release means this reader misread the file.
    is_exact_release(&version).then_some(version)
}

/// The contents of `"x"` or `'x'`.
fn string_literal(s: &str) -> Option<&str> {
    let s = s.trim();
    for q in ['"', '\''] {
        if let Some(inner) = s.strip_prefix(q).and_then(|r| r.strip_suffix(q)) {
            return Some(inner);
        }
    }
    None
}

/// The string a top-level `name = "..."` statement assigns, if any.
fn top_level_string(content: &str, name: &str) -> Option<String> {
    if name.is_empty() || !name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
        return None;
    }
    content.lines().find_map(|l| {
        let (lhs, rhs) = l.split('#').next()?.split_once('=')?;
        if l.starts_with(char::is_whitespace) || lhs.trim() != name {
            return None;
        }
        string_literal(rhs).map(str::to_string)
    })
}

/// `1.75.0`: three dot-separated numbers.
fn is_exact_release(v: &str) -> bool {
    let parts: Vec<&str> = v.split('.').collect();
    parts.len() == 3
        && parts
            .iter()
            .all(|p| !p.is_empty() && p.bytes().all(|b| b.is_ascii_digit()))
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

    const EXT: &str = "rust = use_extension(\"@rules_rust//rust:extensions.bzl\", \"rust\")\n";

    #[test]
    fn rust_version_reads_the_toolchain_call() {
        let module = format!(
            "bazel_dep(name = \"rules_rust\", version = \"0.60.0\")\n{EXT}\
rust.toolchain(\n    edition = \"2021\",\n    versions = [\"1.75.0\"],\n)\n\
rust.repository_set(\n    name = \"rust_libsignal\",\n    versions = [\"1.98.1\"],\n)\n"
        );
        assert_eq!(rust_version_from_module(&module).as_deref(), Some("1.75.0"));
    }

    #[test]
    fn rust_version_ignores_a_commented_out_toolchain_call() {
        // aegis on #4183: the commented line above the real call was read.
        let module = "rust = use_extension(\"@rules_rust//rust:extensions.bzl\", \"rust\")\n\
# rust.toolchain(versions = [\"1.80.0\"])\n\
#rust.toolchain(\n#    versions = [\"1.81.0\"],\n#)\n\
rust.toolchain(\n    edition = \"2021\",  # versions = [\"1.82.0\"]\n    versions = [\"1.75.0\"],\n)\n";
        assert_eq!(rust_version_from_module(module).as_deref(), Some("1.75.0"));
    }

    #[test]
    fn rust_version_ignores_a_commented_out_extension_binding() {
        let module = "# old = use_extension(\"@rules_rust//rust:extensions.bzl\", \"rust\")\n\
# old.toolchain(versions = [\"1.80.0\"])\n\
rust = use_extension(\"@rules_rust//rust:extensions.bzl\", \"rust\")\n\
rust.toolchain(versions = [\"1.75.0\"])\n";
        assert_eq!(rust_version_from_module(module).as_deref(), Some("1.75.0"));
    }

    #[test]
    fn rust_version_finds_nothing_when_the_only_call_is_commented_out() {
        let module = "rust = use_extension(\"@rules_rust//rust:extensions.bzl\", \"rust\")\n\
# rust.toolchain(versions = [\"1.75.0\"])\n";
        assert_eq!(rust_version_from_module(module), None);
    }

    #[test]
    fn a_hash_inside_a_string_is_kept() {
        assert_eq!(
            strip_starlark_comments("x = \"a#b\"  # c\ny = '''#\n'''\n"),
            "x = \"a#b\"  \ny = '''#\n'''\n"
        );
    }

    #[test]
    fn rust_version_ignores_a_repository_set_before_the_toolchain() {
        let module = format!(
            "{EXT}rust.repository_set(\n    versions = [\"1.98.1\"],\n)\n\
rust.toolchain(\n    versions = [\"1.80.1\", \"1.75.0\"],\n)\n"
        );
        assert_eq!(rust_version_from_module(&module).as_deref(), Some("1.80.1"));
    }

    /// aegis's repro: the extension bound to another name is still read.
    #[test]
    fn rust_version_follows_a_renamed_extension_variable() {
        let module = "rust_ext = use_extension('@rules_rust//rust:extensions.bzl', 'rust')\n\
rust_ext.toolchain(\n    edition = \"2021\",\n    versions = [\"1.75.0\"],\n)\n\
use_repo(rust_ext, \"rust_toolchains\")\n";
        assert_eq!(rust_version_from_module(module).as_deref(), Some("1.75.0"));
    }

    /// A `rust.toolchain(` belonging to another extension is not the one.
    #[test]
    fn rust_version_reads_only_the_rules_rust_binding() {
        let module = "rust = use_extension(\"@other//x:ext.bzl\", \"rust\")\n\
rust.toolchain(versions = [\"9.9.9\"])\n";
        assert_eq!(rust_version_from_module(module), None);
        let module = format!("{EXT}xrust.toolchain(versions = [\"9.9.9\"])\nrust.toolchain(versions = [\"1.75.0\"])\n");
        assert_eq!(rust_version_from_module(&module).as_deref(), Some("1.75.0"));
    }

    /// The version moved into a variable (valid, builds the same) is read
    /// through it; a name that resolves to nothing, or to no exact release,
    /// is a failed read, never the name taken as a version.
    #[test]
    fn rust_version_through_a_variable() {
        let module = format!(
            "RUST_VERSION = \"1.75.0\"\n{EXT}rust.toolchain(\n    versions = [RUST_VERSION],\n)\n"
        );
        assert_eq!(rust_version_from_module(&module).as_deref(), Some("1.75.0"));
        let module = format!("{EXT}rust.toolchain(\n    versions = [RUST_VERSION],\n)\n");
        assert_eq!(rust_version_from_module(&module), None);
        let module = format!("RUST_VERSIONS = [\"1.75.0\"]\n{EXT}rust.toolchain(\n    versions = RUST_VERSIONS,\n)\n");
        assert_eq!(rust_version_from_module(&module), None);
        let module = format!("{EXT}rust.toolchain(versions = [\"stable\"])\n");
        assert_eq!(rust_version_from_module(&module), None);
    }

    /// `versions` is read as the call's own keyword argument only.
    #[test]
    fn rust_version_reads_the_versions_argument_only() {
        let module = format!(
            "{EXT}rust.toolchain(\n    extra_target_triples = [\"x\"],\n    versions = [\"1.75.0\"],\n)\n"
        );
        assert_eq!(rust_version_from_module(&module).as_deref(), Some("1.75.0"));
        let module = format!("{EXT}rust.toolchain(\n    extra_versions = [\"9.9.9\"],\n)\n");
        assert_eq!(rust_version_from_module(&module), None);
    }

    #[test]
    fn rust_version_missing() {
        assert_eq!(rust_version_from_module("bazel_dep(name = \"x\")\n"), None);
        // The extension is bound but its toolchain call names no version.
        let module = format!("{EXT}rust.toolchain(edition = \"2021\")\n");
        assert_eq!(rust_version_from_module(&module), None);
        // The toolchain call is there but under a name nothing binds.
        assert_eq!(
            rust_version_from_module("rust.toolchain(versions = [\"1.75.0\"])\n"),
            None
        );
        assert!(canonical_rust("/nonexistent/path")
            .unwrap_err()
            .contains("MODULE.bazel"));
    }

    #[test]
    fn canonical_rust_reads_module_bazel() {
        let dir = temp_dir_with_file(
            "MODULE.bazel",
            &format!(
                "{EXT}rust.toolchain(\n    edition = \"2021\",\n    versions = [\"1.75.0\"],\n)\n"
            ),
        );
        assert_eq!(canonical_rust(dir.to_str().unwrap()).unwrap(), "1.75.0");
        let _ = fs::remove_dir_all(&dir);
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
