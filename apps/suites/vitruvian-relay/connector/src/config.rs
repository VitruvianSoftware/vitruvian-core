// Copyright (c) 2026 VitruvianSoftware
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

//! Settings: where to sign in, where the relay is, and the one TLS setup every
//! HTTPS call uses (Task 8's WebSocket reuses `client_config`).

use std::path::PathBuf;
use std::sync::Arc;
use std::time::Duration;

pub const DEFAULT_ISSUER: &str = "https://auth.ipv1337.dev";
pub const DEFAULT_RELAY_URL: &str = "https://relay.vitruviansoftware.dev";
/// The `relay-connector-v2` client (native app, device flow + refresh; its
/// tokens carry the user's roles): `zitadel-apps-relay` output
/// `connectorV2ClientId`.
pub const DEFAULT_CLIENT_ID: &str = "400571151425800521";
/// The `relay` Zitadel project (`projectId`). Its id must be in the token's audience.
pub const DEFAULT_PROJECT_ID: &str = "398912441632687930";
/// The `relay-claude-v2` client (`claudeV2ClientId`): what a person pastes into Claude.
pub const DEFAULT_CLAUDE_CLIENT_ID: &str = "400571151425734985";

/// Refresh the access token when it has less than this long to live.
pub const REFRESH_MARGIN_SECS: u64 = 300;
/// A link status older than this means no `vrelay run` is alive.
pub const STATUS_STALE_SECS: u64 = 60;

#[derive(Debug, Clone)]
pub struct Config {
    pub issuer: String,
    pub relay_url: String,
    pub client_id: String,
    pub project_id: String,
    pub claude_client_id: String,
    /// The state directory (`VRELAY_HOME`, else `~/Library/Application Support/vrelay`).
    pub dir: PathBuf,
    /// Where `calls.log` goes (`VRELAY_LOG_DIR`, else `~/Library/Logs/vrelay`).
    pub log_dir: PathBuf,
    /// `HOME` (`.` if unset): where `~` in a call's path points, and the
    /// base of the folders remote calls may not touch (rules.rs `Guard`).
    pub home: PathBuf,
    /// Wait before the one retry of a failed token refresh.
    pub retry_delay: Duration,
}

impl Config {
    pub fn from_env() -> Config {
        Config::from_lookup(|k| std::env::var(k).ok())
    }

    pub fn from_lookup(get: impl Fn(&str) -> Option<String>) -> Config {
        let val = |k: &str, d: &str| {
            get(k)
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty())
                .unwrap_or_else(|| d.to_string())
        };
        let home = || PathBuf::from(get("HOME").unwrap_or_else(|| ".".into()));
        let dir = match get("VRELAY_HOME").filter(|v| !v.trim().is_empty()) {
            Some(d) => PathBuf::from(d),
            None => home().join("Library/Application Support/vrelay"),
        };
        let log_dir = match get("VRELAY_LOG_DIR").filter(|v| !v.trim().is_empty()) {
            Some(d) => PathBuf::from(d),
            None => home().join("Library/Logs/vrelay"),
        };
        Config {
            issuer: val("VRELAY_ISSUER", DEFAULT_ISSUER)
                .trim_end_matches('/')
                .to_string(),
            relay_url: val("VRELAY_RELAY_URL", DEFAULT_RELAY_URL)
                .trim_end_matches('/')
                .to_string(),
            client_id: val("VRELAY_CLIENT_ID", DEFAULT_CLIENT_ID),
            project_id: val("VRELAY_PROJECT_ID", DEFAULT_PROJECT_ID),
            claude_client_id: val("VRELAY_CLAUDE_CLIENT_ID", DEFAULT_CLAUDE_CLIENT_ID),
            dir,
            log_dir,
            home: home(),
            retry_delay: Duration::from_secs(1),
        }
    }

    /// Scope for the device flow and refresh: puts the relay project in the
    /// token's audience.
    pub fn scope(&self) -> String {
        format!(
            "openid offline_access urn:zitadel:iam:org:project:id:{}:aud",
            self.project_id
        )
    }
}

/// rustls on ring, trusting the system certificate store: the one setup
/// the relay's token checker uses too (`vitruvian_mcp_auth`), built once and
/// shared. Its warnings go to vrelay's log (stderr).
pub fn client_config() -> Arc<rustls::ClientConfig> {
    fn warn(message: &str) {
        eprintln!("vrelay: {message}");
    }
    vitruvian_mcp_auth::set_tls_warning_hook(warn);
    vitruvian_mcp_auth::tls_client_config()
}

pub fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(30))
        .tls_config(client_config())
        .user_agent("vrelay")
        .build()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn defaults_and_overrides() {
        let c = Config::from_lookup(|k| match k {
            "HOME" => Some("/home/x".into()),
            "VRELAY_RELAY_URL" => Some("http://127.0.0.1:1/".into()),
            _ => None,
        });
        assert_eq!(c.issuer, DEFAULT_ISSUER);
        assert_eq!(c.relay_url, "http://127.0.0.1:1");
        assert_eq!(
            c.dir,
            PathBuf::from("/home/x/Library/Application Support/vrelay")
        );
        assert_eq!(
            c.scope(),
            "openid offline_access urn:zitadel:iam:org:project:id:398912441632687930:aud"
        );
        assert_eq!(c.log_dir, PathBuf::from("/home/x/Library/Logs/vrelay"));
        assert_eq!(c.retry_delay, Duration::from_secs(1));
        let c = Config::from_lookup(|k| match k {
            "VRELAY_HOME" => Some("/t".into()),
            "VRELAY_LOG_DIR" => Some("/l".into()),
            _ => None,
        });
        assert_eq!(c.dir, PathBuf::from("/t"));
        assert_eq!(c.log_dir, PathBuf::from("/l"));
    }

    #[test]
    fn the_shared_tls_config_is_reused() {
        assert!(Arc::ptr_eq(&client_config(), &client_config()));
    }

    /// A scalar as YAML reads it: a quoted value is everything up to its
    /// closing quote (a `#` inside it is kept); a plain value ends at a
    /// comment, which YAML only starts after whitespace.
    fn clean(v: &str) -> String {
        let v = v.trim();
        for q in ['"', '\''] {
            if let Some(rest) = v.strip_prefix(q) {
                return rest.split(q).next().unwrap().to_string();
            }
        }
        let end = v
            .char_indices()
            .find(|&(i, c)| c == '#' && i > 0 && v[..i].ends_with(char::is_whitespace))
            .map_or(v.len(), |(i, _)| i);
        v[..end].trim().to_string()
    }

    /// `key:` under the top-level `section:` of a values file (a flat
    /// two-level read; enough for these files), or None.
    fn find_entry(text: &str, section: &str, key: &str) -> Option<String> {
        let mut in_section = false;
        for line in text.lines() {
            if line.starts_with(&format!("{section}:")) {
                in_section = true;
            } else if line.trim_start().starts_with('#') {
                // A comment, at any indent, neither ends the section nor is a key.
            } else if in_section && !line.starts_with(' ') && !line.trim().is_empty() {
                in_section = false;
            } else if in_section {
                if let Some(rest) = line.trim().strip_prefix(&format!("{key}:")) {
                    return Some(clean(rest));
                }
            }
        }
        None
    }

    fn values_entry(text: &str, section: &str, key: &str) -> String {
        find_entry(text, section, key).unwrap_or_else(|| panic!("{section}.{key} not found"))
    }

    /// A top-level `key: value`, or None.
    fn find_top(text: &str, key: &str) -> Option<String> {
        text.lines()
            .find_map(|l| l.strip_prefix(&format!("{key}:")))
            .map(clean)
    }

    fn top_entry(text: &str, key: &str) -> String {
        find_top(text, key).unwrap_or_else(|| panic!("{key} not found"))
    }

    #[test]
    fn values_parser_strips_comments() {
        let t = "hostname: a.example  # the record\nname: \"q\"\noidc:\n  issuer: https://i # why\n  other: x\n";
        assert_eq!(top_entry(t, "hostname"), "a.example");
        assert_eq!(top_entry(t, "name"), "q");
        assert_eq!(values_entry(t, "oidc", "issuer"), "https://i");
        assert_eq!(find_top(t, "missing"), None);
        assert_eq!(find_entry(t, "oidc", "missing"), None);
        // Quoted values keep a `#`; single quotes work; a `#` with no space
        // before it is part of a plain value.
        let q = "a: \"x # y\"  # note\nb: 'z'\nc: u#v\n";
        assert_eq!(top_entry(q, "a"), "x # y");
        assert_eq!(top_entry(q, "b"), "z");
        assert_eq!(top_entry(q, "c"), "u#v");
        // A column-0 comment inside a section does not end it.
        let c = "oidc:\n  a: 1\n# about issuer\n  issuer: https://j\n";
        assert_eq!(values_entry(c, "oidc", "issuer"), "https://j");
    }

    fn runfile_text(rel: &str) -> String {
        let base = std::env::var("TEST_SRCDIR").expect("run under bazel test");
        std::fs::read_to_string(PathBuf::from(base).join("_main").join(rel)).unwrap()
    }

    /// The compiled-in defaults are the relay's new-mode values: if those
    /// values or the chart defaults change (or these constants do), the
    /// connector would sign in to, or call, the wrong place.
    ///
    /// They are checked against `chart-render/vitruvian-relay.values.yaml`,
    /// the new mode with its real ids, not against the Argo CD file alone: the
    /// Argo CD file keeps running the old relay (the old host and client ids)
    /// until the digest PR switches it to the new one, so it cannot be the
    /// reference yet. This file is what the digest PR copies, so a client
    /// recreated in the Zitadel stack still fails here. Once the Argo CD file
    /// is on the new host it is held to the same defaults too (second half).
    #[test]
    fn defaults_match_relay_stack() {
        let new_mode = runfile_text("tools/ci/chart-render/vitruvian-relay.values.yaml");
        let chart = runfile_text("apps/suites/vitruvian-relay/relay/deploy/chart/values.yaml");
        assert_eq!(
            values_entry(&new_mode, "oidc", "connectorClientId"),
            DEFAULT_CLIENT_ID
        );
        assert_eq!(
            values_entry(&new_mode, "oidc", "projectId"),
            DEFAULT_PROJECT_ID
        );
        let mcp = values_entry(&new_mode, "oidc", "mcpClientIds");
        assert!(
            mcp.split(',').any(|c| c == DEFAULT_CLAUDE_CLIENT_ID),
            "mcpClientIds {mcp} lacks the claude client"
        );
        let issuer = find_entry(&new_mode, "oidc", "issuer")
            .unwrap_or_else(|| values_entry(&chart, "oidc", "issuer"));
        assert_eq!(issuer, DEFAULT_ISSUER);
        // The new host is named in the file itself: the chart's own default is
        // still the old host until the old relay is gone.
        let host = top_entry(&new_mode, "hostname");
        assert_eq!(format!("https://{host}"), DEFAULT_RELAY_URL);

        // What Argo CD deploys. While it still runs the old relay (another
        // host) it is not the reference; once it has moved to this host, its
        // ids and issuer must be the defaults as well.
        let live = runfile_text("gitops/argocd/platform/relay/values.yaml");
        if find_top(&live, "hostname").as_deref() == Some(host.as_str()) {
            assert_eq!(
                values_entry(&live, "oidc", "connectorClientId"),
                DEFAULT_CLIENT_ID
            );
            assert_eq!(values_entry(&live, "oidc", "projectId"), DEFAULT_PROJECT_ID);
            let mcp = values_entry(&live, "oidc", "mcpClientIds");
            assert!(
                mcp.split(',').any(|c| c == DEFAULT_CLAUDE_CLIENT_ID),
                "the Argo CD mcpClientIds {mcp} lacks the claude client"
            );
            let issuer = find_entry(&live, "oidc", "issuer")
                .unwrap_or_else(|| values_entry(&chart, "oidc", "issuer"));
            assert_eq!(issuer, DEFAULT_ISSUER);
        }
    }
}
