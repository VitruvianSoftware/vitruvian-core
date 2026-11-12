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

//! Retired product names (`RET001`) enforced across paths and file contents,
//! with an explicit allowlist for historical records and external infra keys.
//!
//! Retired token literals use `concat!` so this source file itself does not
//! match raw `git grep` sweeps for the retired product name.

use crate::pystr::basename;
use crate::textio::{decode_ignore, translate_newlines};
use crate::violation::{Severity, Violation};

/// Rule identifier for retired product-name violations.
pub const RULE_ID: &str = "RET001";

const SUGGESTED_REPLACEMENT: &str = "Vitruvian Code / vitruvian-code / VitruvianCode";

const RETIRED_PATTERNS: &[&str] = &[
    concat!("nexus", " agent"),
    concat!("nexus", "-agent"),
    concat!("nexus", "_agent"),
    concat!("nexus", "agent"),
];

const BINARY_EXTENSIONS: &[&str] = &[
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".icns", ".pdf", ".zip", ".tar", ".gz",
    ".tgz", ".xz", ".zst", ".woff", ".woff2", ".ttf", ".otf", ".eot", ".mp3", ".mp4", ".mov",
    ".wav", ".ogg", ".wasm", ".bin", ".der", ".p12", ".sqlite", ".db",
];

fn normalize_rel_path(rel_path: &str) -> String {
    let norm = rel_path.replace('\\', "/");
    norm.trim_start_matches("./").to_string()
}

/// Returns true when the entire path is allowlisted (historical changelogs,
/// dated design archives, the brand rename table itself, `infrastructure/`,
/// the Copybara export workflow, the Stripe Payment Link donate pages, and the
/// publish-signed website catalog copy).
pub fn is_allowlisted_path(rel_path: &str) -> bool {
    let norm = normalize_rel_path(rel_path);
    let base = basename(&norm);

    if base == "CHANGELOG.md" || norm == "apps/desktop/vitruvian-atrium/UPSTREAM.md" {
        return true;
    }
    if norm.starts_with("docs/superpowers/") || norm.starts_with("docs/archive/") {
        return true;
    }
    if norm == "docs/standards/brand.md" {
        return true;
    }
    if norm == "infrastructure" || norm.starts_with("infrastructure/") {
        return true;
    }
    if norm == concat!(".github/workflows/copybara-export-", "nexus", "-agent.yaml") {
        return true;
    }
    if norm == "apps/web/vitruviansoftware-dev/tools/catalog/tools.json" {
        return true;
    }
    matches!(
        norm.as_str(),
        "apps/web/vitruviansoftware-dev/_data/donations.yml"
            | "apps/web/vitruviansoftware-dev/donate/vitruvian-code/index.html"
            | "apps/desktop/vitruvian-code/.github/FUNDING.yml"
    ) || norm
        == concat!(
            "apps/web/vitruviansoftware-dev/donate/",
            "nexus",
            "-agent.html"
        )
}

/// Exact substrings allowed within specific files where an external/infra-owned
/// identifier remains load-bearing; any other retired mention in the same file
/// still triggers `RET001`.
fn allowed_line_tokens(norm: &str) -> &'static [&'static str] {
    match norm {
        ".github/CODEOWNERS"
        | "apps/desktop/vitruvian-code/OWNERS"
        | "apps/desktop/vitruvian-code/catalog-info.yaml"
        | "catalog-info.yaml"
        | "docs/engineering/service-maturity-scorecards.md" => &[concat!("nexus", "-agent-team")],
        "apps/desktop/vitruvian-code/.github/workflows/release.yml" => &[
            concat!("Casks/", "nexus", "-agent.rb"),
            concat!("cask \"", "nexus", "-agent\""),
            concat!("nexus", "-agent Cask"),
        ],
        "apps/web/vitruviansoftware-dev/_data/downloads.yml" => {
            &[concat!("vitruviansoftware/tap/", "nexus", "-agent")]
        }
        "tools/conformance/src/checks/brew.rs" => &[concat!("\"", "nexus", "-agent\"")],
        "docs/admin/copybara-sync.md" => &[
            concat!("NEXUS", "_AGENT_SYNC_SSH_KEY"),
            concat!("NEXUS", "_AGENT_*"),
            concat!("`", "nexus", "-agent`"),
            concat!("\"", "nexus", "-agent\""),
        ],
        "docs/operations/key-rotation.md" => &[concat!("NEXUS", "_AGENT_SYNC_SSH_KEY")],
        "gitops/argocd/platform/cicd-telemetry/src/lib.rs" => &[
            concat!("copybara-export-", "nexus", "-agent.yaml"),
            concat!("Copybara Export (", "nexus", "-agent)"),
        ],
        "tools/copybara/copy.bara.sky"
        | "tools/copybara/conflict-precheck/src/lib.rs"
        | "tools/copybara/conflict-precheck/src/lib_test.rs" => {
            &[concat!("NEXUS", "_AGENT_REV_ID")]
        }
        _ => &[],
    }
}

fn find_retired_pattern(text: &str) -> Option<&'static str> {
    let lower = text.to_ascii_lowercase();
    RETIRED_PATTERNS
        .iter()
        .copied()
        .find(|pat| lower.contains(pat))
}

/// Fast ASCII case-insensitive check for `"nexus"` before decoding UTF-8.
pub fn contains_nexus_ascii_ci(bytes: &[u8]) -> bool {
    bytes.windows(5).any(|w| w.eq_ignore_ascii_case(b"nexus"))
}

/// Returns true when `rel_path` has a binary file extension that should not be
/// scanned line-by-line as text.
pub fn has_binary_extension(rel_path: &str) -> bool {
    let lower = basename(rel_path).to_ascii_lowercase();
    BINARY_EXTENSIONS.iter().any(|ext| lower.ends_with(ext))
}

/// Validates a directory or file path's final component against retired names.
pub fn validate_retired_path(rel_path: &str) -> Vec<Violation> {
    if is_allowlisted_path(rel_path) {
        return Vec::new();
    }
    let norm = normalize_rel_path(rel_path);
    let name = basename(&norm);
    if let Some(matched) = find_retired_pattern(name) {
        return vec![Violation::new(
            RULE_ID,
            rel_path,
            None,
            format!(
                "Path '{}' uses retired product name '{}'; rename to {}.",
                rel_path, matched, SUGGESTED_REPLACEMENT
            ),
            Severity::Error,
            Some("vitruvian-code".into()),
        )];
    }
    Vec::new()
}

/// Validates decoded UTF-8 file contents line-by-line against retired names.
pub fn validate_retired_content(rel_path: &str, content: &str) -> Vec<Violation> {
    if is_allowlisted_path(rel_path) {
        return Vec::new();
    }
    let norm = normalize_rel_path(rel_path);
    let tokens = allowed_line_tokens(&norm);
    let mut violations = Vec::new();

    for (idx, line) in content.lines().enumerate() {
        let mut scrubbed = line.to_string();
        for tok in tokens {
            if scrubbed.contains(tok) {
                scrubbed = scrubbed.replace(tok, "");
            }
        }
        if let Some(matched) = find_retired_pattern(&scrubbed) {
            violations.push(Violation::new(
                RULE_ID,
                rel_path,
                Some((idx + 1) as i64),
                format!(
                    "Line references retired product name '{}'; use {}.",
                    matched, SUGGESTED_REPLACEMENT
                ),
                Severity::Error,
                Some(SUGGESTED_REPLACEMENT.into()),
            ));
        }
    }
    violations
}

/// Reads raw file bytes and checks text contents when applicable.
pub fn validate_retired_file_bytes(rel_path: &str, bytes: &[u8]) -> Vec<Violation> {
    if is_allowlisted_path(rel_path) || bytes.contains(&0) || !contains_nexus_ascii_ci(bytes) {
        return Vec::new();
    }
    let content = translate_newlines(&decode_ignore(bytes));
    validate_retired_content(rel_path, &content)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flags_stray_retired_names_in_paths_and_contents() {
        let prose = concat!("Install ", "Nexus", " Agent from the catalog.\n");
        let v_prose = validate_retired_content("docs/guides/getting-started.md", prose);
        assert_eq!(v_prose.len(), 1);
        assert_eq!(v_prose[0].rule_id, RULE_ID);
        assert_eq!(v_prose[0].severity, Severity::Error);
        assert_eq!(v_prose[0].line_number, Some(1));

        let kebab = concat!("id = \"dev.vitruvian.", "nexus", "-agent\"\n");
        let v_kebab = validate_retired_content("catalog/sources.json", kebab);
        assert_eq!(v_kebab.len(), 1);
        assert_eq!(v_kebab[0].rule_id, RULE_ID);

        let pascal = concat!("struct ", "Nexus", "AgentView {}\n");
        let v_pascal = validate_retired_content("apps/desktop/vitruvian/App.swift", pascal);
        assert_eq!(v_pascal.len(), 1);
        assert_eq!(v_pascal[0].rule_id, RULE_ID);

        let snake = concat!("export ", "NEXUS", "_AGENT_HOME=/tmp\n");
        let v_snake = validate_retired_content("tools/dev.sh", snake);
        assert_eq!(v_snake.len(), 1);
        assert_eq!(v_snake[0].rule_id, RULE_ID);

        let bad_file = concat!(".github/workflows/", "nexus", "-agent-ci.yaml");
        let v_path = validate_retired_path(bad_file);
        assert_eq!(v_path.len(), 1);
        assert_eq!(v_path[0].rule_id, RULE_ID);
    }

    #[test]
    fn permits_allowlisted_paths_and_scoped_tokens_only() {
        let prose = concat!("Migrated from ", "Nexus", " Agent in v1.34.0.\n");
        assert!(validate_retired_content("CHANGELOG.md", prose).is_empty());
        assert!(
            validate_retired_content("apps/desktop/vitruvian-code/CHANGELOG.md", prose).is_empty()
        );
        assert!(validate_retired_content("apps/desktop/vitruvian/UPSTREAM.md", prose).is_empty());
        assert!(validate_retired_content("docs/superpowers/specs/2026-05-01.md", prose).is_empty());
        assert!(validate_retired_content("docs/archive/planning/old.md", prose).is_empty());
        assert!(validate_retired_content("docs/standards/brand.md", prose).is_empty());
        assert!(validate_retired_content(
            "infrastructure/pulumi/platform/repo-config/main.go",
            prose
        )
        .is_empty());
        assert!(validate_retired_path(concat!(
            ".github/workflows/copybara-export-",
            "nexus",
            "-agent.yaml"
        ))
        .is_empty());

        // Scoped token passes on its designated line, but a stray mention on another line fails.
        let copybara_ok = concat!("standalone_rev_id = \"", "NEXUS", "_AGENT_REV_ID\"\n");
        assert!(validate_retired_content("tools/copybara/copy.bara.sky", copybara_ok).is_empty());

        let copybara_stray = concat!(
            "standalone_rev_id = \"",
            "NEXUS",
            "_AGENT_REV_ID\"\n# ",
            "Nexus",
            " Agent mirror\n"
        );
        let v = validate_retired_content("tools/copybara/copy.bara.sky", copybara_stray);
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].line_number, Some(2));
    }

    #[test]
    fn ignores_unrelated_nexus_terms() {
        let unrelated = "wear/nexus-wrist/.nexus.yaml uses NexusSparkleMotion\n";
        assert!(validate_retired_path("apps/wear/nexus-wrist").is_empty());
        assert!(validate_retired_path(".nexus.yaml").is_empty());
        assert!(validate_retired_content("apps/wear/nexus-wrist/README.md", unrelated).is_empty());
    }
}
