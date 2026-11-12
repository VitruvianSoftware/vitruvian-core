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

//! Published Homebrew instructions for our tap must work on Homebrew 7.
//!
//! Homebrew 7 trusts only its official taps. It refuses to load a formula or
//! cask from any other tap until the user runs `brew trust <tap>`, and
//! `brew upgrade` / `brew outdated` skip an untrusted tap without a word.
//! Nothing in the tap can change that, so every instruction we publish has to
//! say it. The canonical form is:
//!
//! ```text
//! brew tap vitruviansoftware/tap
//! brew trust vitruviansoftware/tap
//! brew install [--cask] vitruviansoftware/tap/<name>
//! ```
//!
//! For every published text file (Markdown, HTML, YAML, JSON) this fails:
//! - a `brew install|upgrade|reinstall` of one of our products by its short
//!   name (`brew install devx`): Homebrew 7 won't load it, and on a Mac with a
//!   same-named formula elsewhere it installs the wrong thing;
//! - a file that tells people to tap or install from our tap without also
//!   telling them `brew trust vitruviansoftware/tap`.
//!
//! Plans, specs, changelogs, test data and dot-directories (CI workflows run
//! on runners, not on users' Macs) are history or machinery, not instructions,
//! and are skipped.

use std::fs;

use crate::Context;

/// Our tap, lower-case (Homebrew compares tap names case-insensitively).
const TAP: &str = "vitruviansoftware/tap";

/// Every formula and cask in VitruvianSoftware/homebrew-tap. A short-name
/// install of one of these is an instruction that fails on Homebrew 7.
const OUR_NAMES: &[&str] = &[
    "courier",
    "devx",
    "gravastar-mouse",
    "home-speaker",
    "homelab",
    "nexus-agent",
    "vitruvian",
    "vitruvian-tool",
];

/// The file types that carry instructions people copy.
const EXTENSIONS: &[&str] = &["*.md", "*.html", "*.yml", "*.yaml", "*.json"];

/// Paths (workspace-relative prefixes) that are records, not instructions.
const SKIP_PREFIXES: &[&str] = &[
    "docs/superpowers/",
    "docs/archive/",
    "apps/cli/vitruvian-devx/docs/plans/",
];

fn skipped(rel: &str) -> bool {
    if SKIP_PREFIXES.iter().any(|p| rel.starts_with(p)) {
        return true;
    }
    let mut parts = rel.split('/').peekable();
    while let Some(part) = parts.next() {
        let is_file = parts.peek().is_none();
        if is_file {
            return part == "CHANGELOG.md";
        }
        if part.starts_with('.') || part == "testdata" || part == "_site" || part == "node_modules"
        {
            return true;
        }
    }
    false
}

/// What is wrong with one file's Homebrew instructions for our tap, if
/// anything. Each entry is a short, human-readable finding.
pub fn problems(text: &str) -> Vec<String> {
    let lower = text.to_lowercase();
    let mut found = Vec::new();
    let mut uses_our_tap = lower.contains(&format!("brew tap {TAP}"));

    for verb in ["install", "upgrade", "reinstall"] {
        let needle = format!("brew {verb} ");
        let mut from = 0;
        while let Some(at) = lower[from..].find(&needle) {
            let start = from + at + needle.len();
            from = start;
            // The command runs to the end of the line or the next shell or
            // markup boundary.
            let end = lower[start..]
                .find(|c: char| matches!(c, '\n' | '`' | '&' | ';' | '|' | '<' | '"' | ')'))
                .map_or(lower.len(), |e| start + e);
            for arg in lower[start..end].split_whitespace() {
                if arg.starts_with('-') {
                    continue;
                }
                let arg = arg.trim_end_matches(['.', ',', ':']);
                if let Some(rest) = arg.strip_prefix(TAP) {
                    if rest.starts_with('/') {
                        uses_our_tap = true;
                    }
                } else if OUR_NAMES.contains(&arg) {
                    found.push(format!(
                        "`brew {verb} {arg}` uses the short name: write `brew {verb} {TAP}/{arg}`"
                    ));
                }
            }
        }
    }

    if uses_our_tap && !lower.contains(&format!("brew trust {TAP}")) {
        found.push(format!(
            "installs from our tap but never says `brew trust {TAP}` (Homebrew 7 refuses an untrusted tap)"
        ));
    }
    found
}

pub fn check_brew_tap_instructions(ctx: &Context) {
    let mut files: Vec<String> = EXTENSIONS
        .iter()
        .flat_map(|glob| ctx.files.discover(&ctx.root, glob))
        .collect();
    files.sort();
    files.dedup();

    for abs in files {
        let rel = ctx.rel(&abs);
        if skipped(&rel) {
            continue;
        }
        let Ok(text) = fs::read_to_string(&abs) else {
            continue;
        };
        if !text.to_lowercase().contains(TAP) {
            continue;
        }
        let found = problems(&text);
        if found.is_empty() {
            if text.to_lowercase().contains(&format!("brew trust {TAP}")) {
                ctx.emit_ok(
                    "brewtap",
                    &rel,
                    "brew trust",
                    "trust + full name",
                    "Homebrew instructions work on Homebrew 7",
                );
            }
            continue;
        }
        for problem in found {
            ctx.emit_fail(
                "brewtap",
                &rel,
                "untrusted tap",
                "trust + full name",
                &problem,
                &format!(
                    "brew tap {TAP} && brew trust {TAP} && brew install [--cask] {TAP}/<name>"
                ),
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn canonical_instructions_pass() {
        let text = "brew tap vitruviansoftware/tap\nbrew trust vitruviansoftware/tap\nbrew install --cask vitruviansoftware/tap/courier\n";
        assert!(problems(text).is_empty(), "{:?}", problems(text));
        // Homebrew compares tap names case-insensitively, and so does this.
        let text = "`brew trust VitruvianSoftware/tap && brew upgrade VitruvianSoftware/tap/devx`";
        assert!(problems(text).is_empty(), "{:?}", problems(text));
    }

    // The devx README before this check: tapped and trusted, then installed by
    // the short name.
    #[test]
    fn short_name_fails() {
        let old =
            "brew tap vitruviansoftware/tap\nbrew trust vitruviansoftware/tap\nbrew install devx\n";
        let got = problems(old);
        assert_eq!(got.len(), 1, "{got:?}");
        assert!(got[0].contains("brew install vitruviansoftware/tap/devx"));
        let got = problems("Run `brew trust vitruviansoftware/tap && brew upgrade devx`.");
        assert_eq!(got.len(), 1, "{got:?}");
        let got = problems("brew trust vitruviansoftware/tap; brew upgrade --cask courier");
        assert_eq!(got.len(), 1, "{got:?}");
    }

    // The homelab README and the downloads page before this check: tapped and
    // installed by full name, but never trusted.
    #[test]
    fn missing_trust_fails() {
        let old = "brew tap vitruviansoftware/tap\nbrew install vitruviansoftware/tap/homelab\n";
        let got = problems(old);
        assert_eq!(got.len(), 1, "{got:?}");
        assert!(got[0].contains("brew trust vitruviansoftware/tap"));
        assert_eq!(
            problems("  command: brew tap VitruvianSoftware/tap\n").len(),
            1
        );
        assert_eq!(
            problems("`brew install --cask vitruviansoftware/tap/courier`").len(),
            1
        );
    }

    #[test]
    fn other_taps_and_core_formulae_are_not_ours() {
        let text = "brew install cloudflare/cloudflare/cloudflared\nbrew install gh\nbrew install --cask docker\nbrew install ffmpeg";
        assert!(problems(text).is_empty(), "{:?}", problems(text));
        // A mention of the tap that is not an instruction needs no trust.
        assert!(problems("Casks/<app>.rb in VitruvianSoftware/homebrew-tap").is_empty());
        assert!(problems("`brew info --cask vitruviansoftware/tap/courier`").is_empty());
    }

    #[test]
    fn records_and_machinery_are_skipped() {
        assert!(skipped("apps/cli/vitruvian-devx/CHANGELOG.md"));
        assert!(skipped("docs/superpowers/plans/x.md"));
        assert!(skipped("apps/cli/vitruvian-devx/docs/plans/idea.md"));
        assert!(skipped(".github/workflows/x.yaml"));
        assert!(skipped("apps/desktop/x/.github/workflows/release.yml"));
        assert!(skipped("tools/sync-downloads/testdata/downloads.yml"));
        assert!(!skipped(
            "apps/web/vitruviansoftware-dev/_data/downloads.yml"
        ));
        assert!(!skipped("CONTRIBUTING.md"));
        assert!(!skipped("apps/cli/vitruvian-homelab/README.md"));
    }
}
