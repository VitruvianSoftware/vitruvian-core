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

//! rules/directories.py: directory naming rules.

use crate::pystr::{
    dollar, is_decimal, is_kebab, is_lower_alnum, is_pascal, is_snake, lower, strip_chars,
};
use crate::violation::{Severity, Violation};

/// Permitted hidden directories (ALLOWED_DOT_DIRS).
pub const ALLOWED_DOT_DIRS: &[&str] = &[
    ".aspect",
    ".claude",
    ".devcontainer",
    ".github",
    ".vscode",
    ".husky",
    ".remember",
    ".agents",
    ".agent",
    ".gemini",
    ".changeset",
    ".next",
    ".turbo",
    ".astro",
    ".superpowers",
    ".worktrees",
    ".claude-worktrees",
    ".ruff_cache",
    ".storybook",
    ".vitepress",
    ".swc",
];

/// Subtrees whose Go packages may be snake_case (GO_PACKAGE_DIR_ROOTS).
pub const GO_PACKAGE_DIR_ROOTS: &[&str] = &[
    "infrastructure/pulumi",
    "packages/pulumi/library/go",
    "packages/pulumi/examples",
    "pulumi/library/go",
    "pulumi/examples",
    "apps/cli/devx",
    "apps/cli/homelab",
    "apps/web/oauth-user-inspector/infra",
    "devx",
    "homelab",
    "pkg",
];

/// Subtrees whose Swift directories may be PascalCase (SWIFT_DIR_ROOTS).
pub const SWIFT_DIR_ROOTS: &[&str] = &[
    "apps/desktop/nexus-agent/macos",
    "macos",
    "Sources",
    "Tests",
];

const SYSTEM_DIRS: &[&str] = &[
    ".git",
    ".hg",
    ".svn",
    "node_modules",
    "bazel-out",
    "bazel-bin",
    "bazel-testlogs",
];

fn route_class(c: char) -> bool {
    c.is_ascii_alphanumeric() || c == '_' || c == '-'
}

fn all_route(s: &str) -> bool {
    !s.is_empty() && s.chars().all(route_class)
}

/// `^(\[[a-zA-Z0-9_-]+\]|\[\.\.\.[a-zA-Z0-9_-]+\]|\([a-zA-Z0-9_-]+\))$`
pub fn is_dynamic_route(s: &str) -> bool {
    dollar(s, |t| {
        if let Some(inner) = t.strip_prefix('[').and_then(|r| r.strip_suffix(']')) {
            all_route(inner) || inner.strip_prefix("...").map_or(false, all_route)
        } else if let Some(inner) = t.strip_prefix('(').and_then(|r| r.strip_suffix(')')) {
            all_route(inner)
        } else {
            false
        }
    })
}

/// `^__[a-zA-Z0-9_-]+__$`
pub fn is_dunder_dir(s: &str) -> bool {
    dollar(s, |t| {
        t.len() >= 5 && t.starts_with("__") && t.ends_with("__") && t.chars().all(route_class)
    })
}

/// `^\d{14}_[a-z0-9_]+$`
pub fn is_prisma_migration(s: &str) -> bool {
    dollar(s, |t| {
        let chars: Vec<char> = t.chars().collect();
        chars.len() >= 16
            && chars[..14].iter().all(|&c| is_decimal(c))
            && chars[14] == '_'
            && chars[15..].iter().all(|&c| is_lower_alnum(c) || c == '_')
    })
}

fn fix(dir_name: &str) -> Option<String> {
    Some(lower(dir_name).replace('_', "-"))
}

/// validate_directory_name.
pub fn validate_directory_name(dir_path: &str, is_root: bool) -> Vec<Violation> {
    let mut violations = Vec::new();
    let normalized = strip_chars(dir_path, "/").replace('\\', "/");
    if normalized.is_empty() || normalized == "." {
        return violations;
    }
    let parts: Vec<&str> = normalized.split('/').collect();
    let dir_name = *parts.last().unwrap();

    if SYSTEM_DIRS.contains(&dir_name) {
        return violations;
    }

    if dir_name.starts_with('.') {
        if ALLOWED_DOT_DIRS.contains(&dir_name) || dir_name.starts_with(".git") {
            return violations;
        }
        violations.push(Violation::new(
            "DIR001",
            &normalized,
            None,
            format!("Disallowed dot-prefixed directory '{}'.", dir_name),
            Severity::Error,
            None,
        ));
        return violations;
    }

    if is_dynamic_route(dir_name) || is_dunder_dir(dir_name) {
        return violations;
    }

    if is_prisma_migration(dir_name) {
        return violations;
    }

    let under = |root: &str| normalized == root || normalized.starts_with(&format!("{}/", root));

    if SWIFT_DIR_ROOTS
        .iter()
        .any(|sr| under(sr) || dir_name == *sr)
        && (is_pascal(dir_name) || is_kebab(dir_name) || is_snake(dir_name))
    {
        return violations;
    }

    if GO_PACKAGE_DIR_ROOTS.iter().any(|gr| under(gr)) && (is_snake(dir_name) || is_kebab(dir_name))
    {
        return violations;
    }

    if is_root || parts.len() == 1 {
        if !is_kebab(dir_name) {
            violations.push(Violation::new(
                "DIR002",
                &normalized,
                None,
                format!(
                    "Root directory '{}' must be kebab-case (lowercase alphanumeric with hyphens).",
                    dir_name
                ),
                Severity::Error,
                fix(dir_name),
            ));
        }
        return violations;
    }

    if !is_kebab(dir_name) {
        violations.push(Violation::new(
            "DIR003",
            &normalized,
            None,
            format!(
                "Directory '{}' has invalid casing. Expected kebab-case.",
                dir_name
            ),
            Severity::Error,
            fix(dir_name),
        ));
    }
    violations
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ids(v: Vec<Violation>) -> Vec<String> {
        v.into_iter().map(|x| x.rule_id).collect()
    }

    #[test]
    fn kebab_and_roots() {
        assert!(validate_directory_name("tools/ci-preflight", false).is_empty());
        assert_eq!(
            ids(validate_directory_name("tools/ci_preflight", false)),
            ["DIR003"]
        );
        assert_eq!(ids(validate_directory_name("mcp_slack", true)), ["DIR002"]);
        assert_eq!(ids(validate_directory_name("-mcp-slack", true)), ["DIR002"]);
        assert!(validate_directory_name("a", true).is_empty());
        assert!(validate_directory_name("", false).is_empty());
        assert!(validate_directory_name(".", false).is_empty());
        assert!(validate_directory_name("tools\\ci-preflight\\scripts", false).is_empty());
        assert!(validate_directory_name("tools/ci-preflight/", false).is_empty());
    }

    #[test]
    fn ecosystem_overrides() {
        assert!(validate_directory_name(
            "infrastructure/pulumi/network_hubs/modules/cloud_dns",
            false
        )
        .is_empty());
        assert!(validate_directory_name(
            "tabula/web/prisma/migrations/20260524120000_init_schema",
            false
        )
        .is_empty());
        assert!(validate_directory_name("macos/Sources/NexusAgent", false).is_empty());
        assert!(validate_directory_name("app/[id]", false).is_empty());
        assert!(validate_directory_name("app/[...slug]", false).is_empty());
        assert!(validate_directory_name("app/(group)", false).is_empty());
        assert!(validate_directory_name("web/__tests__", false).is_empty());
        assert_eq!(
            ids(validate_directory_name("pkg_invalid/cloud_dns", false)),
            ["DIR003"]
        );
        assert_eq!(
            ids(validate_directory_name("devx_tools/my_module", false)),
            ["DIR003"]
        );
    }

    #[test]
    fn dot_directories() {
        assert!(validate_directory_name(".github/workflows", false).is_empty());
        assert!(validate_directory_name(".gitlab", false).is_empty());
        let v = validate_directory_name("a/.hidden", false);
        assert_eq!(v[0].rule_id, "DIR001");
        assert_eq!(v[0].file_path, "a/.hidden");
    }

    #[test]
    fn suggested_fix_lowercases() {
        let v = validate_directory_name("tools/CI_Preflight", false);
        assert_eq!(v[0].suggested_fix.as_deref(), Some("ci-preflight"));
    }

    #[test]
    fn prisma_needs_fourteen_digits() {
        assert!(is_prisma_migration("20260524120000_x"));
        assert!(!is_prisma_migration("2026052412000_x"));
        assert!(is_prisma_migration("٢٠٢٦٠٥٢٤١٢٠٠٠٠_x"));
    }
}
