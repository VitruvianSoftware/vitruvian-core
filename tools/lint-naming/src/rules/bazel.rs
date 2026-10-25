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

//! rules/bazel.py: Bazel target, rule, macro and Starlark naming rules.
//!
//! validate_build_file_content reads a BUILD file the way the Python does:
//! with `ast.parse` (src/pyast holds a Python 3.12 parser for that), and, when
//! Python would reject the file, with the same regular-expression fallback.

use crate::pyast::{self, SyntaxWarning};
use crate::pystr::{basename, dollar, is_lower_alnum, is_space, separated, strip};
use crate::violation::{Severity, Violation};

/// Rule kinds treated as binaries (BINARY_RULE_TYPES).
pub const BINARY_RULE_TYPES: &[&str] = &[
    "sh_binary",
    "py_binary",
    "go_binary",
    "js_binary",
    "ts_binary",
    "rust_binary",
    "cc_binary",
    "java_binary",
    "swift_binary",
    "oci_image",
    "container_image",
    "macos_command_line_application",
];

const SKIPPED_CALLS: &[&str] = &["load", "glob", "select", "package", "licenses"];

/// `^[a-z0-9]+(-[a-z0-9]+)*(\.[a-z0-9]+)*$`
pub fn is_kebab_target(s: &str) -> bool {
    dollar(s, |t| {
        let mut parts = t.split('.');
        let head = parts.next().unwrap_or("");
        separated(head, '-', is_lower_alnum)
            && parts.all(|p| !p.is_empty() && p.chars().all(is_lower_alnum))
    })
}

/// `^[a-z0-9]+(_[a-z0-9]+)*$`
pub fn is_snake_target(s: &str) -> bool {
    dollar(s, |t| separated(t, '_', is_lower_alnum))
}

/// `^[a-z0-9]+(-[a-z0-9]+)*_test$`
pub fn is_shell_test_target(s: &str) -> bool {
    dollar(s, |t| {
        t.strip_suffix("_test")
            .map_or(false, |b| separated(b, '-', is_lower_alnum))
    })
}

/// `^[a-z0-9]+(_[a-z0-9]+)*\.bzl$`
pub fn is_starlark_file(s: &str) -> bool {
    dollar(s, |t| {
        t.strip_suffix(".bzl")
            .map_or(false, |b| separated(b, '_', is_lower_alnum))
    })
}

/// validate_starlark_file_name.
pub fn validate_starlark_file_name(file_path: &str) -> Vec<Violation> {
    let mut violations = Vec::new();
    let file_name = basename(file_path);
    if file_name.ends_with(".bzl") && !is_starlark_file(file_name) {
        violations.push(Violation::new(
            "BZL004",
            file_path,
            None,
            format!("Starlark file '{}' must use snake_case.", file_name),
            Severity::Error,
            Some(file_name.replace('-', "_")),
        ));
    }
    violations
}

/// validate_bazel_target_name.
pub fn validate_bazel_target_name(
    file_path: &str,
    target_name: &str,
    rule_type: &str,
    line_number: Option<i64>,
) -> Vec<Violation> {
    let mut violations = Vec::new();

    if rule_type == "sh_test" {
        if !is_shell_test_target(target_name) && !is_snake_target(target_name) {
            violations.push(Violation::new(
                "BZL003",
                file_path,
                line_number,
                format!(
                    "Shell test target '{}' should follow the '<binary>_test' convention.",
                    target_name
                ),
                Severity::Warning,
                if target_name.ends_with("_test") {
                    None
                } else {
                    Some(format!("{}_test", target_name))
                },
            ));
        }
        return violations;
    }

    if ["go_library", "go_test", "go_proto_library"].contains(&rule_type) {
        if !is_snake_target(target_name) {
            violations.push(Violation::new(
                "BZL002",
                file_path,
                line_number,
                format!(
                    "Go build target '{}' must use snake_case per Gazelle standard.",
                    target_name
                ),
                Severity::Error,
                Some(target_name.replace('-', "_")),
            ));
        }
        return violations;
    }

    if BINARY_RULE_TYPES.contains(&rule_type)
        || rule_type.ends_with("_binary")
        || rule_type.ends_with("_image")
    {
        if !is_kebab_target(target_name) {
            violations.push(Violation::new(
                "BZL001",
                file_path,
                line_number,
                format!(
                    "CLI binary target '{}' ({}) must use kebab-case.",
                    target_name, rule_type
                ),
                Severity::Error,
                Some(target_name.replace('_', "-")),
            ));
        }
        return violations;
    }
    violations
}

/// What validate_build_file_content found, and what `ast.parse` would have
/// printed as SyntaxWarnings on the way.
pub struct BuildFileResult {
    pub violations: Vec<Violation>,
    pub warnings: Vec<SyntaxWarning>,
}

/// validate_build_file_content.
pub fn validate_build_file_content(file_path: &str, content: &str) -> BuildFileResult {
    let mut result = BuildFileResult {
        violations: Vec::new(),
        warnings: Vec::new(),
    };
    if strip(content).is_empty() {
        return result;
    }

    let parsed = pyast::parse(content);
    result.warnings = parsed.warnings;
    match parsed.calls {
        Some(calls) => {
            for call in calls {
                let Some(rule_type) = call.rule_type else {
                    continue;
                };
                if SKIPPED_CALLS.contains(&rule_type.as_str()) {
                    continue;
                }
                for kw in call.keywords {
                    if kw.arg.as_deref() != Some("name") {
                        continue;
                    }
                    if let Some(target_name) = kw.str_value {
                        if !target_name.is_empty() {
                            result.violations.extend(validate_bazel_target_name(
                                file_path,
                                &target_name,
                                &rule_type,
                                Some(kw.line as i64),
                            ));
                        }
                    }
                }
            }
        }
        None => {
            result.violations = fallback_scan(file_path, content);
        }
    }
    result
}

fn is_ident_char(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_'
}

/// `re.search(r'name\s*=\s*["\']([^"\']+)["\']', body)`: the offset of the
/// match in `body` and the captured name.
fn search_name(body: &[char]) -> Option<(usize, String)> {
    let is_quote = |c: char| c == '"' || c == '\'';
    for start in 0..body.len() {
        if body.len() - start < 4 || body[start..start + 4] != ['n', 'a', 'm', 'e'] {
            continue;
        }
        let mut i = start + 4;
        while i < body.len() && is_space(body[i]) {
            i += 1;
        }
        if i >= body.len() || body[i] != '=' {
            continue;
        }
        i += 1;
        while i < body.len() && is_space(body[i]) {
            i += 1;
        }
        if i >= body.len() || !is_quote(body[i]) {
            continue;
        }
        i += 1;
        let value_start = i;
        while i < body.len() && !is_quote(body[i]) {
            i += 1;
        }
        if i == value_start || i >= body.len() {
            continue;
        }
        return Some((start, body[value_start..i].iter().collect()));
    }
    None
}

/// The fallback for files `ast.parse` rejects:
/// `re.compile(r"([a-zA-Z0-9_]+)\s*\(([^)]*)\)", re.DOTALL).finditer(content)`.
pub fn fallback_scan(file_path: &str, content: &str) -> Vec<Violation> {
    let chars: Vec<char> = content.chars().collect();
    let mut violations = Vec::new();
    let mut pos = 0;
    while pos < chars.len() {
        // Find the leftmost match starting at or after pos.
        let mut found = None;
        let mut start = pos;
        while start < chars.len() {
            if is_ident_char(chars[start]) {
                let mut j = start;
                while j < chars.len() && is_ident_char(chars[j]) {
                    j += 1;
                }
                let mut k = j;
                while k < chars.len() && is_space(chars[k]) {
                    k += 1;
                }
                if k < chars.len() && chars[k] == '(' {
                    if let Some(close) = chars[k + 1..].iter().position(|&c| c == ')') {
                        found = Some((start, j, k + 1, k + 1 + close));
                        break;
                    } else {
                        // No ')' anywhere after: nothing later can match either.
                        return violations;
                    }
                }
            }
            start += 1;
        }
        let Some((m_start, ident_end, body_start, body_end)) = found else {
            break;
        };
        let rule_type: String = chars[m_start..ident_end].iter().collect();
        pos = body_end + 1;
        if SKIPPED_CALLS.contains(&rule_type.as_str()) {
            continue;
        }
        let body = &chars[body_start..body_end];
        if let Some((offset, target_name)) = search_name(body) {
            let upto = (m_start + offset).min(chars.len());
            let line_no = chars[..upto].iter().filter(|&&c| c == '\n').count() + 1;
            violations.extend(validate_bazel_target_name(
                file_path,
                &target_name,
                &rule_type,
                Some(line_no as i64),
            ));
        }
    }
    violations
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(v: &[Violation]) -> Vec<(&str, Option<i64>)> {
        v.iter()
            .map(|x| (x.rule_id.as_str(), x.line_number))
            .collect()
    }

    #[test]
    fn target_names() {
        assert_eq!(
            ids(&validate_bazel_target_name(
                "B",
                "bad_bin",
                "sh_binary",
                Some(10)
            )),
            [("BZL001", Some(10))]
        );
        assert_eq!(
            ids(&validate_bazel_target_name(
                "B",
                "bad-lib",
                "go_library",
                None
            )),
            [("BZL002", None)]
        );
        assert!(validate_bazel_target_name("B", "agent-app_test", "sh_test", None).is_empty());
        assert!(validate_bazel_target_name("B", "app.min", "js_binary", None).is_empty());
        assert!(
            validate_bazel_target_name("B", "NexusAgent", "macos_application", None).is_empty()
        );
        let v = validate_bazel_target_name("B", "Bad", "sh_test", None);
        assert_eq!(v[0].suggested_fix.as_deref(), Some("Bad_test"));
        assert!(validate_bazel_target_name("B", "x", "foo_image", None).is_empty());
        assert_eq!(
            validate_bazel_target_name("B", "x_y", "foo_image", None)[0].rule_id,
            "BZL001"
        );
    }

    #[test]
    fn starlark_files() {
        assert!(validate_starlark_file_name("tools/defs.bzl").is_empty());
        assert_eq!(
            validate_starlark_file_name("tools/my-defs.bzl")[0].rule_id,
            "BZL004"
        );
    }

    #[test]
    fn build_content_through_the_parser() {
        let r = validate_build_file_content(
            "BUILD.bazel",
            "sh_binary(name = \"bad_name\", srcs = [\"a.sh\"])\n",
        );
        assert_eq!(ids(&r.violations), [("BZL001", Some(1))]);
        let content = "sh_binary(\n    srcs = [\"script.sh\"],\n    # c\n    name = \"bad_binary_name\",\n)\n";
        assert_eq!(
            ids(&validate_build_file_content("B", content).violations),
            [("BZL001", Some(4))]
        );
        assert!(validate_build_file_content("B", "# only\n# comments\n")
            .violations
            .is_empty());
        assert!(validate_build_file_content("B", "").violations.is_empty());
        let nested = "native.go_library(name = \"a-b\")\nx = [go_test(name = \"c-d\")]\n";
        assert_eq!(
            ids(&validate_build_file_content("B", nested).violations),
            [("BZL002", Some(1)), ("BZL002", Some(2))]
        );
    }

    #[test]
    fn build_content_fallback() {
        // `$` is not Python, so the regular expressions take over.
        let content = "$\nsh_binary(\n  name = 'bad_one')\n";
        assert_eq!(
            ids(&validate_build_file_content("B", content).violations),
            [("BZL001", Some(2))]
        );
        assert!(fallback_scan("B", "load(name = 'a_b')").is_empty());
        assert_eq!(
            ids(&fallback_scan("B", "x sh_binary (target_name = \"q_r\")")),
            [("BZL001", Some(1))]
        );
    }
}
