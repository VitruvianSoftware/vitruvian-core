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

//! Retired product and mirror names (`RET001`) enforced across paths and file
//! contents, with an explicit allowlist for historical records and kept live
//! infrastructure/domain/credential identifiers.
//!
//! Retired token literals use `concat!` so this source file itself does not
//! match raw `git grep` sweeps for retired product names.

use crate::pystr::basename;
use crate::textio::{decode_ignore, translate_newlines};
use crate::violation::{Severity, Violation};

/// Rule identifier for retired product-name violations.
pub const RULE_ID: &str = "RET001";

struct RetiredRule {
    needle: &'static str,
    case_sensitive: bool,
    word_stem_only: bool,
    replacement: &'static str,
    path_fix: &'static str,
}

const RETIRED_RULES: &[RetiredRule] = &[
    // Vitruvian Code retired name variants
    RetiredRule {
        needle: concat!("nexus", " agent"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Code / vitruvian-code / VitruvianCode",
        path_fix: "vitruvian-code",
    },
    RetiredRule {
        needle: concat!("nexus", "-agent"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Code / vitruvian-code / VitruvianCode",
        path_fix: "vitruvian-code",
    },
    RetiredRule {
        needle: concat!("nexus", "_agent"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Code / vitruvian-code / VitruvianCode",
        path_fix: "vitruvian-code",
    },
    RetiredRule {
        needle: concat!("nexus", "agent"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Code / vitruvian-code / VitruvianCode",
        path_fix: "vitruvian-code",
    },
    // Vitruvian Speaker retired name variants (space-separated "home speaker" is
    // excluded because "Google Home speakers" names the physical Nest/Cast hardware)
    RetiredRule {
        needle: concat!("home", "-speaker"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Speaker / vitruvian-speaker / VitruvianSpeaker",
        path_fix: "vitruvian-speaker",
    },
    RetiredRule {
        needle: concat!("home", "_speaker"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Speaker / vitruvian-speaker / VitruvianSpeaker",
        path_fix: "vitruvian-speaker",
    },
    RetiredRule {
        needle: concat!("home", "speaker"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Speaker / vitruvian-speaker / VitruvianSpeaker",
        path_fix: "vitruvian-speaker",
    },
    // Vitruvian Tabs retired name (word-stem bounded so English "tabular" / "tabulate" pass)
    RetiredRule {
        needle: concat!("tab", "ula"),
        case_sensitive: false,
        word_stem_only: true,
        replacement: "Vitruvian Tabs / vitruvian-tabs / VitruvianTabs",
        path_fix: "vitruvian-tabs",
    },
    // Bare old MCP & firmware mirror slugs -> vitruvian-*-mcp / vitruvian-deck
    RetiredRule {
        needle: concat!("mcp", "-slack"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "vitruvian-slack-mcp",
        path_fix: "vitruvian-slack-mcp",
    },
    RetiredRule {
        needle: concat!("mcp", "_slack"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "vitruvian-slack-mcp",
        path_fix: "vitruvian-slack-mcp",
    },
    RetiredRule {
        needle: concat!("mcp", "-roborock"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "vitruvian-roborock-mcp",
        path_fix: "vitruvian-roborock-mcp",
    },
    RetiredRule {
        needle: concat!("mcp", "_roborock"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "vitruvian-roborock-mcp",
        path_fix: "vitruvian-roborock-mcp",
    },
    RetiredRule {
        needle: concat!("esp32", "-desk-companion"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Deck / vitruvian-deck",
        path_fix: "vitruvian-deck",
    },
    RetiredRule {
        needle: concat!("esp32", "_desk_companion"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Deck / vitruvian-deck",
        path_fix: "vitruvian-deck",
    },
    RetiredRule {
        needle: concat!("esp32", " desk companion"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Deck / vitruvian-deck",
        path_fix: "vitruvian-deck",
    },
    RetiredRule {
        needle: concat!("esp32", "-s3 desk companion"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Deck / vitruvian-deck",
        path_fix: "vitruvian-deck",
    },
    // Vitruvian Atrium proposed/retired host-app brand variants
    RetiredRule {
        needle: concat!("Vitruvian", " Desktop"),
        case_sensitive: true,
        word_stem_only: false,
        replacement: "Vitruvian Atrium / vitruvian-atrium / VitruvianAtrium",
        path_fix: "vitruvian-atrium",
    },
    RetiredRule {
        needle: concat!("vitruvian", "-desktop"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Atrium / vitruvian-atrium / VitruvianAtrium",
        path_fix: "vitruvian-atrium",
    },
    RetiredRule {
        needle: concat!("vitruvian", "_desktop"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Atrium / vitruvian-atrium / VitruvianAtrium",
        path_fix: "vitruvian-atrium",
    },
    RetiredRule {
        needle: concat!("vitruvian", "desktop"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Atrium / vitruvian-atrium / VitruvianAtrium",
        path_fix: "vitruvian-atrium",
    },
    // Vitruvian GitHub retired folder/component/mirror variants
    RetiredRule {
        needle: concat!("vitruvian", "-tool-github"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian GitHub / vitruvian-github",
        path_fix: "vitruvian-github",
    },
    RetiredRule {
        needle: concat!("vitruvian", "_tool_github"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian GitHub / vitruvian-github",
        path_fix: "vitruvian-github",
    },
    RetiredRule {
        needle: concat!("vitruvian", "toolgithub"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian GitHub / vitruvian-github",
        path_fix: "vitruvian-github",
    },
    // Vitruvian TV retired folder/component variants
    RetiredRule {
        needle: concat!("vitruvian", "-tool-tv"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian TV / vitruvian-tv",
        path_fix: "vitruvian-tv",
    },
    RetiredRule {
        needle: concat!("vitruvian", "_tool_tv"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian TV / vitruvian-tv",
        path_fix: "vitruvian-tv",
    },
    RetiredRule {
        needle: concat!("vitruvian", "tooltv"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian TV / vitruvian-tv",
        path_fix: "vitruvian-tv",
    },
    // Vitruvian Remote retired folder/component/brand variants (space-separated
    // lowercase "Android remote" is allowed when describing what the app is)
    RetiredRule {
        needle: concat!("Android", " Remote"),
        case_sensitive: true,
        word_stem_only: false,
        replacement: "Vitruvian Remote / vitruvian-remote / VitruvianRemote",
        path_fix: "vitruvian-remote",
    },
    RetiredRule {
        needle: concat!("android", "-remote"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Remote / vitruvian-remote / VitruvianRemote",
        path_fix: "vitruvian-remote",
    },
    RetiredRule {
        needle: concat!("android", "_remote"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Remote / vitruvian-remote / VitruvianRemote",
        path_fix: "vitruvian-remote",
    },
    RetiredRule {
        needle: concat!("android", "remote"),
        case_sensitive: false,
        word_stem_only: false,
        replacement: "Vitruvian Remote / vitruvian-remote / VitruvianRemote",
        path_fix: "vitruvian-remote",
    },
];

const FAST_CANDIDATE_ROOTS: &[&[u8]] = &[
    b"nexus",
    b"speaker",
    concat!("tab", "ula").as_bytes(),
    b"slack",
    b"roborock",
    b"companion",
    b"desktop",
    b"tool",
    b"remote",
];

const BINARY_EXTENSIONS: &[&str] = &[
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico", ".icns", ".pdf", ".zip", ".tar", ".gz",
    ".tgz", ".xz", ".zst", ".woff", ".woff2", ".ttf", ".otf", ".eot", ".mp3", ".mp4", ".mov",
    ".wav", ".ogg", ".wasm", ".bin", ".der", ".p12", ".sqlite", ".db",
];

/// Deliberately kept live cloud, DNS, Kubernetes, GitHub team, CI unit, and
/// published JSON schema identifiers (documented in `docs/standards/brand.md` §3).
/// Ordered longest-first so compound domains scrub cleanly before shorter prefixes.
const KEPT_INFRA_TOKENS: &[&str] = &[
    // Vitruvian Tabs live domains, Chrome Web Store slug, GCP Cloud Run services,
    // Pulumi stacks, Artifact Registry repos, GitHub Environments, team & secret prefix
    concat!("tab", "ula.staging.vitruviansoftware.dev"),
    concat!("tab", "ula.dev.vitruviansoftware.dev"),
    concat!("tab", "ula.vitruviansoftware.dev"),
    concat!("tab", "ula-staging.com"),
    concat!("tab", "ula.com"),
    concat!("tab", "ula.app"),
    concat!("tab", "ula.dev"),
    concat!("tab", "ula-tab-manager"),
    concat!("tab", "ula-nonproduction"),
    concat!("tab", "ula-development"),
    concat!("tab", "ula-production"),
    concat!("tab", "ula-dev-latest"),
    concat!("tab", "ula-nonprod"),
    concat!("tab", "ula-preview"),
    concat!("tab", "ula-deploy"),
    concat!("tab", "ula-identity"),
    concat!("tab", "ula-build"),
    concat!("tab", "ula-data"),
    concat!("tab", "ula-prod"),
    concat!("tab", "ula-team"),
    concat!("tab", "ula-api"),
    concat!("tab", "ula-web"),
    concat!("tab", "ula-app"),
    concat!("tab", "ula-rt"),
    concat!("tab", "ula/api"),
    concat!("tab", "ula/app"),
    concat!("tab", "ula/web"),
    concat!("pulumi_", "tab", "ula_"),
    concat!("bu2-", "tab", "ula-"),
    concat!("tab", "ula_deploy_service_account"),
    concat!("tab", "ula_workload_enabled"),
    concat!("var-service=", "tab", "ula"),
    concat!("TAB", "ULA_"),
    // Slack MCP kept Zitadel Pulumi stack, k8s namespace/ArgoCD app, team & secret prefix
    concat!("pulumi_zitadel_apps_", "mcp", "_slack"),
    concat!("zitadel-apps-", "mcp", "-slack"),
    concat!("gitops/argocd/applications/", "mcp", "-slack.yaml"),
    concat!("gitops/argocd/platform/", "mcp", "-slack"),
    concat!("imageupdater-", "mcp", "-slack"),
    concat!("mcp", "-slack_workload_enabled"),
    concat!("mcp", "-slack-tokens"),
    concat!("mcp", "-slack-team"),
    concat!("namespace=\"", "mcp", "-slack\""),
    concat!("namespace=", "mcp", "-slack"),
    concat!("-n ", "mcp", "-slack"),
    concat!("MCP", "_SLACK_"),
    // Atrium kept CI pipeline unit & published website JSON keys
    concat!("vitruvian", "-desktop-macos"),
    concat!("vitruvian", "DesktopTools"),
    concat!("vitruvian", "DesktopSignature"),
];

fn normalize_rel_path(rel_path: &str) -> String {
    let norm = rel_path.replace('\\', "/");
    norm.trim_start_matches("./").to_string()
}

/// Returns true when the entire path is allowlisted: historical changelogs,
/// dated/parked design archives, the brand and pre-cutover naming standards,
/// live Pulumi/GitOps stacks, Copybara export workflows, Stripe donate pages,
/// and the publish-signed website catalog copy.
pub fn is_allowlisted_path(rel_path: &str) -> bool {
    let norm = normalize_rel_path(rel_path);
    let base = basename(&norm);

    if base == "CHANGELOG.md"
        || norm == "apps/desktop/vitruvian-atrium/UPSTREAM.md"
        || norm == "2026-11-11_DRIFT_REPORT.md"
    {
        return true;
    }
    if norm.starts_with("docs/superpowers/")
        || norm.starts_with("docs/archive/")
        || norm.starts_with("docs/github-relay/")
        || norm.starts_with("apps/mcp/vitruvian-slack-mcp/docs/plans/")
    {
        return true;
    }
    if matches!(
        norm.as_str(),
        "docs/standards/brand.md"
            | "docs/standards/naming-audit.md"
            | "docs/standards/naming-conventions.md"
            | "docs/standards/naming-migration-plan.md"
    ) {
        return true;
    }
    if norm == "infrastructure"
        || norm.starts_with("infrastructure/")
        || norm.starts_with("apps/suites/vitruvian-tabs/infra/")
        || norm.starts_with("gitops/argocd/")
    {
        return true;
    }
    if norm == concat!(".github/workflows/copybara-export-", "nexus", "-agent.yaml")
        || norm
            == concat!(
                ".github/workflows/copybara-export-",
                "home",
                "-speaker.yaml"
            )
        || norm == concat!(".github/workflows/copybara-export-", "mcp", "-slack.yaml")
        || norm
            == concat!(
                ".github/workflows/copybara-export-",
                "mcp",
                "-roborock.yaml"
            )
        || norm
            == concat!(
                ".github/workflows/copybara-export-",
                "esp32",
                "-desk-companion.yaml"
            )
        || norm
            == concat!(
                ".github/workflows/copybara-export-vitruvian",
                "-tool-github.yaml"
            )
        || norm
            == concat!(
                ".github/workflows/zitadel-apps-",
                "mcp",
                "-slack-apply.yaml"
            )
    {
        return true;
    }
    if norm == "apps/web/vitruviansoftware-dev/tools/catalog/tools.json"
        || norm == "apps/desktop/vitruvian-atrium/Tests/Fixtures/release-feed/ls-refs-vitruvian-atrium.pkt"
    {
        return true;
    }
    matches!(
        norm.as_str(),
        "apps/web/vitruviansoftware-dev/_data/donations.yml"
            | "apps/web/vitruviansoftware-dev/donate/vitruvian-code/index.html"
            | "apps/desktop/vitruvian-code/.github/FUNDING.yml"
            | "apps/desktop/vitruvian-speaker/.github/FUNDING.yml"
            | "apps/mcp/vitruvian-slack-mcp/.github/FUNDING.yml"
            | "apps/mcp/vitruvian-roborock-mcp/.github/FUNDING.yml"
            | "apps/embedded/vitruvian-deck/.github/FUNDING.yml"
    ) || norm
        == concat!(
            "apps/web/vitruviansoftware-dev/donate/",
            "nexus",
            "-agent.html"
        )
        || norm
            == concat!(
                "apps/web/vitruviansoftware-dev/donate/",
                "home",
                "-speaker.html"
            )
        || norm
            == concat!(
                "apps/web/vitruviansoftware-dev/donate/",
                "mcp",
                "-slack.html"
            )
        || norm
            == concat!(
                "apps/web/vitruviansoftware-dev/donate/",
                "mcp",
                "-roborock.html"
            )
        || norm
            == concat!(
                "apps/web/vitruviansoftware-dev/donate/",
                "esp32",
                "-desk-companion.html"
            )
}

/// Exact substrings allowed within specific files where an external/infra-owned
/// identifier or historical handover note remains load-bearing; any other retired
/// mention in the same file still triggers `RET001`.
fn allowed_line_tokens(norm: &str) -> &'static [&'static str] {
    match norm {
        // Kept GitHub team slug in repo-config
        ".github/CODEOWNERS"
        | "apps/desktop/vitruvian-code/OWNERS"
        | "apps/desktop/vitruvian-code/catalog-info.yaml"
        | "catalog-info.yaml"
        | "docs/engineering/service-maturity-scorecards.md" => &[concat!("nexus", "-agent-team")],
        // Kept Homebrew cask token in homebrew-tap
        "apps/desktop/vitruvian-code/.github/workflows/release.yml" => &[
            concat!("Casks/", "nexus", "-agent.rb"),
            concat!("cask \"", "nexus", "-agent\""),
            concat!("nexus", "-agent Cask"),
        ],
        "apps/web/vitruviansoftware-dev/_data/downloads.yml" => &[
            concat!("vitruviansoftware/tap/", "nexus", "-agent"),
            concat!("releases/download/android", "-remote-v0.1.39/"),
            concat!("releases/tag/android", "-remote-v0.1.39"),
        ],
        "tools/conformance/src/checks/brew.rs" => &[concat!("\"", "nexus", "-agent\"")],
        // Catalog handover `replaces` IDs & frozen pre-cutover release download URLs
        "catalog/tools.json" => &[
            concat!("\"replaces\": [\"dev.vitruvian.", "nexus", "-agent\"]"),
            concat!("\"replaces\": [\"dev.vitruvian.", "home", "speaker\"]"),
            concat!(
                "VitruvianSoftware/vitruvian",
                "-tool-github/releases/download/v1.6.0/"
            ),
            concat!("releases/download/android", "-remote-v0.1.39/"),
            concat!("releases/download/vitruvian", "-tool-tv-v0.1.0/"),
        ],
        "apps/web/vitruviansoftware-dev/_data/tools.yml" => &[
            concat!(
                "VitruvianSoftware/vitruvian",
                "-tool-github/releases/download/v1.6.0/"
            ),
            concat!("releases/download/android", "-remote-v0.1.39/"),
            concat!("releases/download/vitruvian", "-tool-tv-v0.1.0/"),
        ],
        "catalog/src/catalog_test.rs" => &[concat!("Home", "Speaker 1.41.0")],
        "apps/desktop/vitruvian-speaker/README.md" => &[
            concat!("Formerly **Home", "Speaker**"),
            concat!("`home", "-speaker-v*`"),
        ],
        "apps/extensions/atrium/vitruvian-github/README.md" => &[
            concat!("Formerly **vitruvian", "-tool-github**"),
            concat!("`vitruvian", "-tool-github-v*`"),
        ],
        "apps/extensions/atrium/vitruvian-tv/README.md" => &[
            concat!("Formerly **vitruvian", "-tool-tv**"),
            concat!("`vitruvian", "-tool-tv-v*`"),
        ],
        "apps/mobile/vitruvian-remote/README.md" => &[
            concat!("Formerly **android", "-remote**"),
            concat!("`android", "-remote-v*`"),
        ],
        // Kept on-device legacy Speaker migration keys in Vitruvian Remote (#4703)
        "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/MainActivity.kt" => &[
            concat!("Home", "Speaker"),
            concat!("LEGACY_CHANNEL_HOME", "SPEAKER_ID"),
            concat!("vitruvian-home", "speaker-announcements"),
        ],
        "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/Persistence.kt" => {
            &[
                concat!("Home", "Speaker"),
                concat!("\"home", "SpeakerSettingsExpanded\""),
                concat!("\"home", "SpeakerMirror\""),
            ]
        }
        "apps/mobile/vitruvian-remote/src/main/kotlin/dev/vitruvian/remote/state/Wire.kt" => {
            &[concat!("Home", "Speaker"), concat!("\"home", "speaker\"")]
        }
        "apps/mobile/vitruvian-remote/src/test/kotlin/dev/vitruvian/remote/state/WireTest.kt" => &[
            concat!("Home", "Speaker"),
            concat!("\"home", "speaker\""),
            concat!("apps/home", "speaker"),
        ],
        "apps/desktop/vitruvian-atrium/Tests/AboutAndReleaseFeedTests.swift" => {
            &[concat!("vitruvian", "-tool-github-v")]
        }
        // Google Home cast speaker hold duration (not the retired product name)
        "apps/desktop/vitruvian-speaker/Sources/VitruvianSpeakerCore/Announcer.swift" => {
            &[concat!("home", "SpeakerHold")]
        }
        // Kept GitHub Actions secret names for Speaker's Google OAuth client
        ".github/workflows/vitruvian-speaker-release.yaml" => &[
            concat!("HOME", "SPEAKER_GOOGLE_CLIENT_ID"),
            concat!("HOME", "SPEAKER_GOOGLE_CLIENT_SECRET"),
        ],
        // Legacy catalog ID fallback in site template
        "apps/web/vitruviansoftware-dev/ai.html" => &[concat!("\"dev.vitruvian.home", "speaker\"")],
        // Copybara workflow keys, `*_REV_ID` trailers & break-glass publisher component key
        "tools/copybara/copy.bara.sky" => &[
            concat!("NEXUS", "_AGENT_REV_ID"),
            concat!("HOME", "_SPEAKER_REV_ID"),
            concat!("MCP", "_ROBOROCK_REV_ID"),
            concat!("MCP", "_SLACK_REV_ID"),
            concat!("ESP32", "_DESK_COMPANION_REV_ID"),
            concat!("VITRUVIAN", "_TOOL_GITHUB_REV_ID"),
            concat!("mcp", "-slack"),
            concat!("mcp", "-roborock"),
            concat!("home", "-speaker"),
            concat!("esp32", "-desk-companion"),
            concat!("vitruvian", "-tool-github"),
        ],
        "tools/copybara/conflict-precheck/src/lib.rs"
        | "tools/copybara/conflict-precheck/src/lib_test.rs" => &[
            concat!("NEXUS", "_AGENT_REV_ID"),
            concat!("HOME", "_SPEAKER_REV_ID"),
            concat!("MCP", "_ROBOROCK_REV_ID"),
            concat!("MCP", "_SLACK_REV_ID"),
            concat!("ESP32", "_DESK_COMPANION_REV_ID"),
            concat!("VITRUVIAN", "_TOOL_GITHUB_REV_ID"),
            concat!("\"", "mcp", "-slack\""),
        ],
        "tools/copybara/sync/src/lib.rs" | "tools/copybara/sync/src/lib_test.rs" => {
            &[concat!("mcp", "-slack"), concat!("mcp", "_slack")]
        }
        "docs/admin/copybara-sync.md" => &[
            concat!("NEXUS", "_AGENT_SYNC_SSH_KEY"),
            concat!("NEXUS", "_AGENT_*"),
            concat!("`", "nexus", "-agent`"),
            concat!("\"", "nexus", "-agent\""),
            concat!("mcp", "-slack"),
        ],
        "docs/operations/key-rotation.md" => &[concat!("NEXUS", "_AGENT_SYNC_SSH_KEY")],
        "docs/operations/break-glass-deploy-runbook.md" | "tools/release/src/lib.rs" => {
            &[concat!("mcp", "-slack")]
        }
        ".github/workflows/_await-repo-config.yaml" => &[concat!("and ", "mcp", "-slack exports")],
        // Slack MCP kept k8s namespace & ArgoCD app links in Backstage entity & CI tests
        "apps/mcp/vitruvian-slack-mcp/catalog-info.yaml" => &[
            concat!("kubernetes-namespace: ", "mcp", "-slack"),
            concat!("app-name: ", "mcp", "-slack"),
            concat!("applications/", "mcp", "-slack"),
        ],
        "tools/ci/src/foundation_app_digest_guard/lib.rs"
        | "tools/ci/src/foundation_app_digest_guard/tests.rs" => &[concat!("mcp", "-slack")],
        // Vitruvian Tabs kept delivery/Pulumi/Artifact Registry/domain regex & test fixtures
        ".github/workflows/_deploy-cloud-run.yaml" => &[
            concat!("e.g. ", "tab", "ula "),
            concat!("e.g. ", "TAB", "ULA\""),
        ],
        ".github/workflows/delivery-vitruvian-tabs.yaml" => &[
            concat!("app-name: \"", "tab", "ula\""),
            concat!("env-prefix: \"", "TAB", "ULA\""),
        ],
        "tools/delivery/gen/src/tests.rs" => &[
            concat!("(\"app-name\", \"", "tab", "ula\")"),
            concat!("(\"env-prefix\", \"", "TAB", "ULA\")"),
            concat!("\"", "tab", "ula-{env}\""),
        ],
        "tools/deploy/defs.bzl" => &[concat!("\"", "TAB", "ULA\"")],
        "tools/pulumi/defs.bzl" => &[concat!("Service ", "tab", "ula ")],
        "tools/ci/src/preview_reaper/cli_test.rs" => &[concat!("tab", "ula-pr-")],
        "tools/ci/src/ensure_site_verification/tests.rs" => {
            &[concat!("the ", "tab", "ula regression")]
        }
        "apps/suites/vitruvian-tabs/extension/BUILD" => &[
            concat!("(app ", "tab", "ula)"),
            concat!("renamed_from_app = \"", "tab", "ula\""),
        ],
        "apps/suites/vitruvian-tabs/extension/src/background/index.ts" => &[
            concat!("tab", "ula\\.com"),
            concat!("tab", "ula-staging\\.com"),
        ],
        // Historical engineering notes & internal comments
        "apps/web/oauth-user-inspector/devx.yaml" => &[concat!("with ", "tab", "ula.")],
        "apps/web/oauth-user-inspector/infra/identity/BUILD" => {
            &[concat!("tab", "ula/infra/identity/BUILD")]
        }
        "tools/conformance/public-targets.tsv" => &[concat!("//apps/suites/", "tab", "ula")],
        ".github/CI_DEFINITIONS.md" => &[concat!("`", "tab", "ula-e2e.yaml`")],
        "docs/concepts/monorepo-architecture.md" => &[concat!("TAB", "ULA[\"vitruvian-tabs")],
        "docs/engineering/application-alignment-gaps.md" => &[
            concat!("BlueCentre/", "tab", "ula"),
            concat!("tab", "ulaVars"),
            concat!("tab", "ula-specific"),
        ],
        "docs/engineering/domain-zone-conventions.md" => &[
            concat!("`", "tab", "ula`"),
            concat!("`", "tab", "ula.staging`"),
        ],
        "docs/engineering/vitruvian-tabs-app-infra-alignment.md" => {
            &[concat!("(", "tab", "ula-only)")]
        }
        _ => &[],
    }
}

fn rule_matches(text: &str, lower: &str, rule: &RetiredRule) -> bool {
    let hay = if rule.case_sensitive { text } else { lower };
    if !rule.word_stem_only {
        return hay.contains(rule.needle);
    }
    let tb = text.as_bytes();
    for (start, _) in hay.match_indices(rule.needle) {
        let end = start + rule.needle.len();
        if start > 0 {
            let prev = tb[start - 1];
            if prev.is_ascii_alphabetic()
                && !(prev.is_ascii_lowercase() && tb[start].is_ascii_uppercase())
            {
                continue;
            }
        }
        if end < tb.len() {
            let next = tb[end];
            if next.is_ascii_alphabetic()
                && !(next.is_ascii_uppercase() && tb[end - 1].is_ascii_lowercase())
            {
                continue;
            }
        }
        return true;
    }
    false
}

fn find_retired_rule(text: &str) -> Option<&'static RetiredRule> {
    let lower = text.to_ascii_lowercase();
    RETIRED_RULES
        .iter()
        .find(|rule| rule_matches(text, &lower, rule))
}

/// Fast ASCII case-insensitive check for any retired-name root token before decoding UTF-8.
pub fn contains_retired_candidate_bytes(bytes: &[u8]) -> bool {
    for i in 0..bytes.len() {
        let b = bytes[i].to_ascii_lowercase();
        if !matches!(b, b'n' | b's' | b't' | b'r' | b'c' | b'd') {
            continue;
        }
        let rem = &bytes[i..];
        for root in FAST_CANDIDATE_ROOTS {
            if rem.len() >= root.len() && rem[..root.len()].eq_ignore_ascii_case(root) {
                return true;
            }
        }
    }
    false
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
    if let Some(rule) = find_retired_rule(name) {
        return vec![Violation::new(
            RULE_ID,
            rel_path,
            None,
            format!(
                "Path '{}' uses retired product name '{}'; rename to {}.",
                rel_path, rule.needle, rule.replacement
            ),
            Severity::Error,
            Some(rule.path_fix.into()),
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
    let file_tokens = allowed_line_tokens(&norm);
    let mut violations = Vec::new();

    for (idx, line) in content.lines().enumerate() {
        let mut scrubbed = line.to_string();
        for tok in KEPT_INFRA_TOKENS {
            if scrubbed.contains(tok) {
                scrubbed = scrubbed.replace(tok, "");
            }
        }
        for tok in file_tokens {
            if scrubbed.contains(tok) {
                scrubbed = scrubbed.replace(tok, "");
            }
        }
        if let Some(rule) = find_retired_rule(&scrubbed) {
            violations.push(Violation::new(
                RULE_ID,
                rel_path,
                Some((idx + 1) as i64),
                format!(
                    "Line references retired product name '{}'; use {}.",
                    rule.needle, rule.replacement
                ),
                Severity::Error,
                Some(rule.replacement.into()),
            ));
        }
    }
    violations
}

/// Reads raw file bytes and checks text contents when applicable.
pub fn validate_retired_file_bytes(rel_path: &str, bytes: &[u8]) -> Vec<Violation> {
    if is_allowlisted_path(rel_path)
        || bytes.contains(&0)
        || !contains_retired_candidate_bytes(bytes)
    {
        return Vec::new();
    }
    let content = translate_newlines(&decode_ignore(bytes));
    validate_retired_content(rel_path, &content)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn flags_all_retired_names_in_paths_and_contents() {
        let cases: &[(&str, &str, &str)] = &[
            (
                concat!("Install ", "Nexus", " Agent from the catalog.\n"),
                "vitruvian-code",
                concat!(".github/workflows/", "nexus", "-agent-ci.yaml"),
            ),
            (
                concat!("Open ", "Home", "Speaker in the menu bar.\n"),
                "vitruvian-speaker",
                concat!("apps/desktop/", "home", "-speaker"),
            ),
            (
                concat!("Sign in to ", "Tab", "ula to sync workspaces.\n"),
                "vitruvian-tabs",
                concat!("apps/suites/", "tab", "ula"),
            ),
            (
                concat!("Clone VitruvianSoftware/", "mcp", "-slack.\n"),
                "vitruvian-slack-mcp",
                concat!("apps/mcp/", "mcp", "-slack"),
            ),
            (
                concat!("Clone VitruvianSoftware/", "mcp", "-roborock.\n"),
                "vitruvian-roborock-mcp",
                concat!("apps/mcp/", "mcp", "-roborock"),
            ),
            (
                concat!("Flash ", "esp32", "-desk-companion firmware.\n"),
                "vitruvian-deck",
                concat!("apps/embedded/", "esp32", "-desk-companion"),
            ),
            (
                concat!("Install ", "Vitruvian", " Desktop on macOS.\n"),
                "vitruvian-atrium",
                concat!("apps/desktop/", "vitruvian", "-desktop"),
            ),
            (
                concat!("Build //apps/desktop/vitruvian", "-tool-github:all.\n"),
                "vitruvian-github",
                concat!("apps/desktop/vitruvian", "-tool-github"),
            ),
            (
                concat!("Build //apps/desktop/vitruvian", "-tool-tv:all.\n"),
                "vitruvian-tv",
                concat!("apps/desktop/vitruvian", "-tool-tv"),
            ),
            (
                concat!("Open ", "Android", " Remote on your foldable.\n"),
                "vitruvian-remote",
                concat!("apps/mobile/android", "-remote"),
            ),
        ];

        for (prose, expected_fix_substr, bad_path) in cases {
            let v_prose =
                validate_retired_file_bytes("docs/guides/getting-started.md", prose.as_bytes());
            assert_eq!(v_prose.len(), 1, "expected content hit for {}", prose);
            assert_eq!(v_prose[0].rule_id, RULE_ID);
            assert_eq!(v_prose[0].severity, Severity::Error);
            assert_eq!(v_prose[0].line_number, Some(1));
            assert!(
                v_prose[0]
                    .suggested_fix
                    .as_deref()
                    .unwrap_or("")
                    .contains(expected_fix_substr),
                "unexpected fix {:?} for {}",
                v_prose[0].suggested_fix,
                prose
            );

            let v_path = validate_retired_path(bad_path);
            assert_eq!(v_path.len(), 1, "expected path hit for {}", bad_path);
            assert_eq!(v_path[0].rule_id, RULE_ID);
            assert_eq!(
                v_path[0].suggested_fix.as_deref(),
                Some(*expected_fix_substr)
            );
        }

        // Compound PascalCase / camelCase / SCREAMING_SNAKE_CASE variants also fail.
        for snippet in [
            concat!("struct ", "Nexus", "AgentView {}\n"),
            concat!("export ", "NEXUS", "_AGENT_HOME=/tmp\n"),
            concat!("struct ", "Home", "SpeakerApp {}\n"),
            concat!("class ", "Tab", "ulaClient {}\n"),
            concat!("const x = use", "Tab", "ulaStore();\n"),
            concat!("struct ", "Vitruvian", "DesktopHost {}\n"),
            concat!("struct Vitruvian", "ToolGitHub {}\n"),
            concat!("struct Vitruvian", "ToolTV {}\n"),
            concat!("class Android", "RemoteActivity {}\n"),
        ] {
            let v = validate_retired_content("src/App.swift", snippet);
            assert_eq!(v.len(), 1, "expected hit for {}", snippet);
        }
    }

    #[test]
    fn permits_allowlisted_paths_and_scoped_tokens_only() {
        let prose = concat!(
            "Migrated from ",
            "Nexus",
            " Agent, ",
            "Home",
            "Speaker, and ",
            "Tab",
            "ula.\n"
        );
        assert!(validate_retired_content("CHANGELOG.md", prose).is_empty());
        assert!(
            validate_retired_content("apps/desktop/vitruvian-code/CHANGELOG.md", prose).is_empty()
        );
        assert!(
            validate_retired_content("apps/desktop/vitruvian-atrium/UPSTREAM.md", prose).is_empty()
        );
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

        // Kept cloud/domain identifiers pass, while product prose on the next line fails.
        let kept_and_stray = concat!(
            "const url = \"https://",
            "tab",
            "ula.com/s/123\";\n// Welcome to ",
            "Tab",
            "ula\n"
        );
        let v_tabs = validate_retired_content(
            "apps/suites/vitruvian-tabs/web/app/page.tsx",
            kept_and_stray,
        );
        assert_eq!(v_tabs.len(), 1);
        assert_eq!(v_tabs[0].line_number, Some(2));

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
    fn ignores_unrelated_english_and_hardware_terms() {
        let unrelated = concat!(
            "wear/nexus-wrist/.nexus.yaml uses NexusSparkleMotion\n",
            "Tabular digits, tabular-nums, TABULAR layout, untabulated rows\n",
            "Speaks on your Google Home speakers over Cast\n",
            "// Vitruvian desktop app written in Swift\n",
            "An Android remote and observability console for a Mac\n",
        );
        assert!(validate_retired_path("apps/wear/nexus-wrist").is_empty());
        assert!(validate_retired_path(".nexus.yaml").is_empty());
        assert!(validate_retired_content("apps/wear/nexus-wrist/README.md", unrelated).is_empty());
    }
}
