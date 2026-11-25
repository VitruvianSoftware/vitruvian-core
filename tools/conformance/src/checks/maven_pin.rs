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

//! Every `maven.install(...)` call in the root `MODULE.bazel` must set
//! `lock_file` so Bazel fetches jars through its downloader and repository
//! cache instead of running Coursier live at fetch time.

use std::fs;
use std::path::Path;

use crate::Context;

const GROUP: &str = "MAVENPIN";

/// Scan `MODULE.bazel` text and return `(total_calls, unpinned_calls)` where
/// `unpinned_calls` holds `(1_based_line, repo_name)` for each `maven.install`
/// call missing a non-empty `lock_file`.
pub fn scan_maven_installs(text: &str) -> (usize, Vec<(usize, String)>) {
    let live = strip_starlark_comments(text);
    let bytes = live.as_bytes();
    let needle = b"maven.install(";

    let mut total = 0usize;
    let mut unpinned = Vec::new();
    let mut pos = 0usize;

    while let Some(rel_idx) = find_bytes(&bytes[pos..], needle) {
        let start = pos + rel_idx;
        let prev_is_ident = start > 0 && is_ident_char(bytes[start - 1]);
        if prev_is_ident {
            pos = start + needle.len();
            continue;
        }

        total += 1;
        let start_line = 1 + live[..start].bytes().filter(|&b| b == b'\n').count();
        let args_start = start + needle.len();
        let args_end = find_matching_paren(&live, args_start);
        let body = &live[args_start..args_end];

        let (name, has_lock_file) = parse_maven_install_args(body);
        if !has_lock_file {
            unpinned.push((start_line, name));
        }

        pos = if args_end < live.len() {
            args_end + 1
        } else {
            live.len()
        };
    }

    (total, unpinned)
}

pub fn check_maven_lock_files(ctx: &Context) {
    let module_path = format!("{}/MODULE.bazel", ctx.root);
    if !Path::new(&module_path).is_file() {
        ctx.emit_fail(
            GROUP,
            "MODULE.bazel",
            "missing",
            "present",
            "MODULE.bazel could not be read",
            "restore MODULE.bazel",
        );
        return;
    }
    let Ok(text) = fs::read_to_string(&module_path) else {
        ctx.emit_fail(
            GROUP,
            "MODULE.bazel",
            "unreadable",
            "readable",
            "MODULE.bazel could not be read",
            "check permissions on MODULE.bazel",
        );
        return;
    };

    let (total, unpinned) = scan_maven_installs(&text);
    if unpinned.is_empty() {
        ctx.emit_ok(
            GROUP,
            "MODULE.bazel",
            &format!("{total} maven.install call(s)"),
            "all pinned with lock_file",
            "every maven.install in MODULE.bazel pins a lock_file",
        );
        return;
    }

    for (line, name) in unpinned {
        ctx.emit_fail(
            GROUP,
            &format!("MODULE.bazel:{line}"),
            &format!("maven.install(name = \"{name}\")"),
            &format!("lock_file = \"//:{name}_install.json\""),
            "unpinned maven.install runs Coursier at fetch time outside Bazel's downloader and repository cache",
            &format!("add lock_file = \"//:{name}_install.json\" and run REPIN=1 bazel run @{name}//:pin"),
        );
    }
}

/// Strip `# ...` comments outside string literals while preserving newlines so
/// 1-based line numbers remain exact.
fn strip_starlark_comments(text: &str) -> String {
    let mut out = String::with_capacity(text.len());
    for line in text.split_inclusive('\n') {
        let has_nl = line.ends_with('\n');
        let content = if has_nl {
            &line[..line.len() - 1]
        } else {
            line
        };
        let bytes = content.as_bytes();
        let mut i = 0;
        let mut quote: Option<u8> = None;
        let mut escaped = false;
        let mut comment_at = None;

        while i < bytes.len() {
            let b = bytes[i];
            if let Some(q) = quote {
                if escaped {
                    escaped = false;
                } else if b == b'\\' {
                    escaped = true;
                } else if b == q {
                    quote = None;
                }
            } else if b == b'"' || b == b'\'' {
                quote = Some(b);
            } else if b == b'#' {
                comment_at = Some(i);
                break;
            }
            i += 1;
        }

        let live_slice = match comment_at {
            Some(idx) => &content[..idx],
            None => content,
        };
        out.push_str(live_slice);
        if has_nl {
            out.push('\n');
        }
    }
    out
}

fn find_bytes(haystack: &[u8], needle: &[u8]) -> Option<usize> {
    haystack.windows(needle.len()).position(|w| w == needle)
}

fn is_ident_char(b: u8) -> bool {
    b.is_ascii_alphanumeric() || b == b'_'
}

/// Starting right after the opening `(` of `maven.install(`, find the index of
/// the matching `)`.
fn find_matching_paren(text: &str, from: usize) -> usize {
    let bytes = text.as_bytes();
    let mut depth = 1usize;
    let mut i = from;
    let mut quote: Option<u8> = None;
    let mut escaped = false;

    while i < bytes.len() {
        let b = bytes[i];
        if let Some(q) = quote {
            if escaped {
                escaped = false;
            } else if b == b'\\' {
                escaped = true;
            } else if b == q {
                quote = None;
            }
        } else {
            match b {
                b'"' | b'\'' => quote = Some(b),
                b'(' => depth += 1,
                b')' => {
                    depth -= 1;
                    if depth == 0 {
                        return i;
                    }
                }
                _ => {}
            }
        }
        i += 1;
    }
    text.len()
}

/// Parse top-level keyword arguments inside a `maven.install(...)` body,
/// returning `(name, has_non_empty_lock_file)`.
fn parse_maven_install_args(body: &str) -> (String, bool) {
    let mut name: Option<String> = None;
    let mut has_lock_file = false;

    for arg in split_top_level_args(body) {
        let Some((lhs, rhs)) = arg.split_once('=') else {
            continue;
        };
        let key = lhs.trim();
        let val = rhs.trim();
        if key == "name" {
            if let Some(s) = parse_non_empty_string_literal(val) {
                name = Some(s);
            }
        } else if key == "lock_file" && parse_non_empty_string_literal(val).is_some() {
            has_lock_file = true;
        }
    }

    (name.unwrap_or_else(|| "maven".to_string()), has_lock_file)
}

/// Split top-level comma-separated arguments, respecting nested `()`, `[]`,
/// `{}` and string literals.
fn split_top_level_args(body: &str) -> Vec<&str> {
    let bytes = body.as_bytes();
    let mut args = Vec::new();
    let mut start = 0usize;
    let mut depth = 0usize;
    let mut quote: Option<u8> = None;
    let mut escaped = false;

    let mut i = 0;
    while i < bytes.len() {
        let b = bytes[i];
        if let Some(q) = quote {
            if escaped {
                escaped = false;
            } else if b == b'\\' {
                escaped = true;
            } else if b == q {
                quote = None;
            }
        } else {
            match b {
                b'"' | b'\'' => quote = Some(b),
                b'(' | b'[' | b'{' => depth += 1,
                b')' | b']' | b'}' => depth = depth.saturating_sub(1),
                b',' if depth == 0 => {
                    args.push(&body[start..i]);
                    start = i + 1;
                }
                _ => {}
            }
        }
        i += 1;
    }
    if start < body.len() {
        args.push(&body[start..]);
    }
    args
}

fn parse_non_empty_string_literal(val: &str) -> Option<String> {
    let trimmed = val.trim();
    let inner = trimmed
        .strip_prefix('"')
        .and_then(|s| s.strip_suffix('"'))
        .or_else(|| {
            trimmed
                .strip_prefix('\'')
                .and_then(|s| s.strip_suffix('\''))
        })?;
    if inner.is_empty() {
        None
    } else {
        Some(inner.to_string())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_repo(label: &str, module_bazel: &str) -> std::path::PathBuf {
        use std::sync::atomic::{AtomicU64, Ordering};
        static SEQ: AtomicU64 = AtomicU64::new(0);
        let dir = std::env::temp_dir().join(format!(
            "conformance-mavenpin-{label}-{}-{}",
            std::process::id(),
            SEQ.fetch_add(1, Ordering::Relaxed)
        ));
        let _ = fs::remove_dir_all(&dir);
        fs::create_dir_all(&dir).unwrap();
        fs::write(dir.join("MODULE.bazel"), module_bazel).unwrap();
        dir
    }

    #[test]
    fn pinned_maven_installs_pass() {
        let module = r#"
maven = use_extension("@rules_jvm_external//:extensions.bzl", "maven")

maven.install(
    artifacts = ["androidx.annotation:annotation:1.9.1"],
    lock_file = "//:maven_install.json",
    repositories = ["https://maven.google.com"],
)

maven.install(
    name = "extra_maven",
    artifacts = ["junit:junit:4.13.2"],
    lock_file = "//:extra_maven_install.json",
    repositories = ["https://maven.google.com"],
)
"#;
        let (total, unpinned) = scan_maven_installs(module);
        assert_eq!(total, 2);
        assert!(unpinned.is_empty(), "{unpinned:?}");
    }

    #[test]
    fn unpinned_maven_install_fails() {
        let module = r#"
maven.install(
    lock_file = "//:maven_install.json",
)

maven.install(
    name = "extra_maven",
    artifacts = ["junit:junit:4.13.2"],
    repositories = [
        "https://maven.google.com",
        "https://repo1.maven.org/maven2",
    ],
)
"#;
        let (total, unpinned) = scan_maven_installs(module);
        assert_eq!(total, 2);
        assert_eq!(unpinned, vec![(6, "extra_maven".to_string())]);
    }

    #[test]
    fn commented_out_lock_file_fails() {
        let module = r#"
maven.install(
    name = "extra_maven",
    # lock_file = "//:extra_maven_install.json",
    repositories = ["https://maven.google.com"],
)
"#;
        assert_eq!(
            scan_maven_installs(module).1,
            vec![(2, "extra_maven".to_string())]
        );
    }

    #[test]
    fn commented_out_maven_install_is_ignored() {
        let module = r#"
# maven.install(
#     name = "dormant_maven",
# )
"#;
        let (total, unpinned) = scan_maven_installs(module);
        assert_eq!(total, 0);
        assert!(unpinned.is_empty(), "{unpinned:?}");
    }

    #[test]
    fn empty_or_none_lock_file_fails() {
        let module = r#"
maven.install(
    name = "empty_lock",
    lock_file = "",
)
maven.install(
    name = "none_lock",
    lock_file = None,
)
"#;
        assert_eq!(
            scan_maven_installs(module).1,
            vec![(2, "empty_lock".to_string()), (6, "none_lock".to_string()),]
        );
    }

    #[test]
    fn context_check_reports_pass_and_fail() {
        let good_dir = temp_repo(
            "good",
            "maven.install(\n    name = \"extra_maven\",\n    lock_file = \"//:extra_maven_install.json\",\n)\n",
        );
        let good_ctx = Context::for_root(good_dir.to_str().unwrap());
        check_maven_lock_files(&good_ctx);
        assert_eq!(good_ctx.ok_count.get(), 1);
        assert_eq!(good_ctx.fail_count.get(), 0);
        assert!(!good_ctx.overall_fail.get());
        let _ = fs::remove_dir_all(&good_dir);

        let bad_dir = temp_repo(
            "bad",
            "maven.install(\n    name = \"extra_maven\",\n    repositories = [\"https://repo1.maven.org/maven2\"],\n)\n",
        );
        let bad_ctx = Context::for_root(bad_dir.to_str().unwrap());
        check_maven_lock_files(&bad_ctx);
        assert_eq!(bad_ctx.fail_count.get(), 1);
        assert!(bad_ctx.overall_fail.get());
        let rows = bad_ctx.rows.get(GROUP);
        assert!(rows.contains("MODULE.bazel:1"), "{rows}");
        assert!(rows.contains("extra_maven"), "{rows}");
        let _ = fs::remove_dir_all(&bad_dir);
    }
}
