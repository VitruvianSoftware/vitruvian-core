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

//! rules/source_files.py: source and asset file naming rules.

use crate::pystr::{
    basename, dollar, is_decimal, is_lower_alnum, is_upper_alnum, lower, pascal_body, separated,
    splitext_ext, strip_chars,
};
use crate::violation::{Severity, Violation};

/// Next.js App Router special files (NEXTJS_APP_ROUTER_FILES).
pub const NEXTJS_APP_ROUTER_FILES: &[&str] = &[
    "page.tsx",
    "layout.tsx",
    "loading.tsx",
    "error.tsx",
    "not-found.tsx",
    "route.ts",
    "template.tsx",
    "default.tsx",
    "global-error.tsx",
    "middleware.ts",
    "instrumentation.ts",
    "opengraph-image.tsx",
    "twitter-image.tsx",
    "sitemap.ts",
    "robots.ts",
    "icon.tsx",
    "apple-icon.tsx",
];

/// Files whose names are fixed by convention (CANONICAL_UPPER_DOCS).
pub const CANONICAL_UPPER_DOCS: &[&str] = &[
    "README.md",
    "AGENTS.md",
    "PROJECT.md",
    "SCOPE.md",
    "DISPATCH.md",
    "BRIEFING.md",
    "TEST_INFRA.md",
    "TEST_READY.md",
    "CONTRIBUTING.md",
    "LICENSE.md",
    "CHANGELOG.md",
    "SECURITY.md",
    "MAINTAINERS.md",
    "BUILD.bazel",
    "WORKSPACE.bazel",
    "MODULE.bazel",
    "BUILD",
    "WORKSPACE",
];

/// `^[a-z0-9]+(_[a-z0-9]+)*(_test)?\.go$`
pub fn is_go_file(s: &str) -> bool {
    dollar(s, |t| {
        t.strip_suffix(".go")
            .map_or(false, |stem| separated(stem, '_', is_lower_alnum))
    })
}

/// `^[a-z0-9]+(_[a-z0-9]+)*\.py$`
pub fn is_py_file(s: &str) -> bool {
    dollar(s, |t| {
        t.strip_suffix(".py")
            .map_or(false, |stem| separated(stem, '_', is_lower_alnum))
    })
}

/// `^[a-z0-9]+(-[a-z0-9]+)*(_test)?\.sh$`
pub fn is_shell_file(s: &str) -> bool {
    dollar(s, |t| {
        t.strip_suffix(".sh").map_or(false, |stem| {
            separated(stem, '-', is_lower_alnum)
                || stem
                    .strip_suffix("_test")
                    .map_or(false, |base| separated(base, '-', is_lower_alnum))
        })
    })
}

/// `^[A-Z][a-zA-Z0-9]*(\.[A-Z][a-zA-Z0-9]*)*(\.test|\.spec|\.d)?\.(tsx|jsx|swift|ts|js)$`
pub fn is_pascal_case_file(s: &str) -> bool {
    dollar(s, |t| {
        let segs: Vec<&str> = t.split('.').collect();
        if segs.len() < 2 || !["tsx", "jsx", "swift", "ts", "js"].contains(segs.last().unwrap()) {
            return false;
        }
        let mut mid = &segs[..segs.len() - 1];
        if ["test", "spec", "d"].contains(mid.last().unwrap()) {
            mid = &mid[..mid.len() - 1];
        }
        !mid.is_empty() && mid.iter().all(|seg| pascal_body(seg))
    })
}

/// One `TS_SEGMENT_RE`: kebab-case, camelCase or PascalCase.
fn ts_segment(seg: &str) -> bool {
    if seg.contains('-') {
        separated(seg, '-', is_lower_alnum)
    } else {
        !seg.is_empty() && seg.chars().all(|c| c.is_ascii_alphanumeric())
    }
}

/// `TS_LIB_RE`.
pub fn is_ts_lib(s: &str) -> bool {
    dollar(s, |t| {
        let segs: Vec<&str> = t.split('.').collect();
        if segs.len() < 2
            || !["ts", "tsx", "js", "jsx", "mjs", "cjs"].contains(segs.last().unwrap())
        {
            return false;
        }
        segs[..segs.len() - 1].iter().all(|seg| ts_segment(seg))
    })
}

/// `^[A-Z0-9_-]+\.md$`
pub fn is_upper_doc(s: &str) -> bool {
    dollar(s, |t| {
        t.strip_suffix(".md").map_or(false, |stem| {
            !stem.is_empty()
                && stem
                    .chars()
                    .all(|c| is_upper_alnum(c) || c == '_' || c == '-')
        })
    })
}

/// `^[a-z0-9.]+(-[a-z0-9.]+)*\.md$`
pub fn is_kebab_doc(s: &str) -> bool {
    dollar(s, |t| {
        t.strip_suffix(".md").map_or(false, |stem| {
            separated(stem, '-', |c| is_lower_alnum(c) || c == '.')
        })
    })
}

/// `^\d{4}-\d{2}-\d{2}-[a-z0-9-.]+(\.md|\.yaml|\.json)$`
pub fn is_dated_doc(s: &str) -> bool {
    dollar(s, |t| {
        let Some(stem) = t
            .strip_suffix(".md")
            .or_else(|| t.strip_suffix(".yaml"))
            .or_else(|| t.strip_suffix(".json"))
        else {
            return false;
        };
        let chars: Vec<char> = stem.chars().collect();
        if chars.len() < 12 {
            return false;
        }
        let digits = |r: std::ops::Range<usize>| chars[r].iter().all(|&c| is_decimal(c));
        digits(0..4)
            && chars[4] == '-'
            && digits(5..7)
            && chars[7] == '-'
            && digits(8..10)
            && chars[10] == '-'
            && chars[11..]
                .iter()
                .all(|&c| is_lower_alnum(c) || c == '-' || c == '.')
    })
}

/// validate_file_name.
pub fn validate_file_name(file_path: &str) -> Vec<Violation> {
    let mut violations = Vec::new();
    let normalized = strip_chars(file_path, "/").replace('\\', "/");
    let file_name = basename(&normalized);

    if file_name.starts_with(".DS_Store") || CANONICAL_UPPER_DOCS.contains(&file_name) {
        return violations;
    }

    let ext = lower(splitext_ext(file_name));
    let mut push = |rule: &str, message: String, severity: Severity, fix: Option<String>| {
        violations.push(Violation::new(
            rule,
            &normalized,
            None,
            message,
            severity,
            fix,
        ));
    };

    match ext.as_str() {
        ".go" => {
            if !is_go_file(file_name) {
                push(
                    "GO001",
                    format!(
                        "Go source file '{}' must use snake_case. Hyphens are forbidden in Go source files.",
                        file_name
                    ),
                    Severity::Error,
                    Some(file_name.replace('-', "_")),
                );
            }
        }
        ".py" => {
            if file_name.starts_with("__") && file_name.ends_with("__.py") {
                return violations;
            }
            if !is_py_file(file_name) {
                push(
                    "PY001",
                    format!(
                        "Python module '{}' must use snake_case. Hyphens break Python import statements.",
                        file_name
                    ),
                    Severity::Error,
                    Some(file_name.replace('-', "_")),
                );
            }
        }
        ".sh" | ".bash" | ".zsh" => {
            if !is_shell_file(file_name) {
                push(
                    "SH001",
                    format!(
                        "Shell script '{}' must use kebab-case (with optional _test.sh suffix).",
                        file_name
                    ),
                    Severity::Error,
                    Some(
                        file_name
                            .replace("_test.sh", "@@TEST@@")
                            .replace('_', "-")
                            .replace("@@TEST@@", "_test.sh"),
                    ),
                );
            }
        }
        ".tsx" | ".jsx" => {
            if NEXTJS_APP_ROUTER_FILES.contains(&file_name) || file_name.starts_with("__") {
                return violations;
            }
            if !is_pascal_case_file(file_name) && !is_ts_lib(file_name) {
                push(
                    "TSX001",
                    format!(
                        "React component/view '{}' must use PascalCase (or kebab-case for pages/layouts).",
                        file_name
                    ),
                    Severity::Warning,
                    Some(file_name.replace('_', "-")),
                );
            }
        }
        ".ts" | ".js" | ".mjs" | ".cjs" => {
            if file_name.starts_with("__")
                || file_name.ends_with(".d.ts")
                || NEXTJS_APP_ROUTER_FILES.contains(&file_name)
            {
                return violations;
            }
            if !is_ts_lib(file_name) {
                push(
                    "TS001",
                    format!(
                        "TypeScript/JavaScript file '{}' should use kebab-case or camelCase.",
                        file_name
                    ),
                    Severity::Error,
                    Some(file_name.replace('_', "-")),
                );
            }
        }
        ".swift" => {
            if !is_pascal_case_file(file_name) {
                push(
                    "SWIFT001",
                    format!("Swift file '{}' must use PascalCase.", file_name),
                    Severity::Error,
                    None,
                );
            }
        }
        ".md" => {
            if !is_kebab_doc(file_name) && !is_upper_doc(file_name) && !is_dated_doc(file_name) {
                push(
                    "DOC001",
                    format!(
                        "Documentation file '{}' must use kebab-case or UPPERCASE.",
                        file_name
                    ),
                    Severity::Error,
                    Some(lower(file_name).replace('_', "-")),
                );
            }
        }
        _ => {}
    }
    violations
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(p: &str) -> Vec<String> {
        validate_file_name(p)
            .into_iter()
            .map(|v| v.rule_id)
            .collect()
    }

    #[test]
    fn go_and_python() {
        assert!(ids("pkg/net/cloud_dns.go").is_empty());
        assert!(ids("pkg/cloud_dns_test.go").is_empty());
        assert_eq!(ids("pkg/net/net-hubs.go"), ["GO001"]);
        assert_eq!(ids("pkg/net__hubs.go"), ["GO001"]);
        assert_eq!(ids("pkg/A.GO"), ["GO001"]);
        assert!(ids("pkg/__init__.py").is_empty());
        assert_eq!(ids("hooks/stream-hook.py"), ["PY001"]);
    }

    #[test]
    fn shell_scripts() {
        assert!(ids("tools/ci/affected-targets.sh").is_empty());
        assert!(ids("tools/ci/affected-targets_test.sh").is_empty());
        let v = validate_file_name("tools/copybara/check_version_maps_test.sh");
        assert_eq!(
            v[0].suggested_fix.as_deref(),
            Some("check-version-maps_test.sh")
        );
        assert_eq!(ids("run_me.zsh"), ["SH001"]);
    }

    #[test]
    fn typescript_and_react() {
        for ok in [
            "web/components/App.tsx",
            "web/A.tsx",
            "src/routes/user.routes.ts",
            "src/apiEndpoints.server.ts",
            "src/runtime-config.server.test.ts",
            "postcss.config.mjs",
            "tabula/web/__tests__/RelayLanding.test.tsx",
            "app/page.tsx",
            "types/x_y.d.ts",
        ] {
            assert!(ids(ok).is_empty(), "{}", ok);
        }
        assert_eq!(ids("web/bad_component.tsx"), ["TSX001"]);
        assert_eq!(
            validate_file_name("web/bad_component.tsx")[0].severity,
            Severity::Warning
        );
        assert_eq!(ids("src/bad_name.ts"), ["TS001"]);
    }

    #[test]
    fn swift_and_docs() {
        assert!(ids("macos/Sources/Core2D.swift").is_empty());
        assert_eq!(ids("macos/core.swift"), ["SWIFT001"]);
        assert!(ids("docs/v1.0.0-release.md").is_empty());
        assert!(ids("docs/2026-01-02-plan.md").is_empty());
        assert!(ids("TODO_LIST.md").is_empty());
        let v = validate_file_name("docs/My_Doc.md");
        assert_eq!(v[0].suggested_fix.as_deref(), Some("my-doc.md"));
    }

    #[test]
    fn untouched_files() {
        assert!(ids("tools/binary_executable").is_empty());
        assert!(ids("README.md").is_empty());
        assert!(ids(".DS_Store_x").is_empty());
        assert!(ids("tools/copybara/copy.bara.sky").is_empty());
    }
}
