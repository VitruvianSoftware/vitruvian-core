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
use std::sync::{Arc, OnceLock};
use std::time::Duration;

pub const DEFAULT_ISSUER: &str = "https://auth.ipv1337.dev";
pub const DEFAULT_RELAY_URL: &str = "https://relay.ipv1337.dev";
/// The `relay-connector` client (native app, device flow + refresh):
/// `zitadel-apps-relay` output `connectorClientId`.
pub const DEFAULT_CLIENT_ID: &str = "398912442404505402";
/// The `relay` Zitadel project (`projectId`). Its id must be in the token's audience.
pub const DEFAULT_PROJECT_ID: &str = "398912441632687930";
/// The `relay-claude` client (`claudeClientId`): what a person pastes into Claude.
pub const DEFAULT_CLAUDE_CLIENT_ID: &str = "398912442404439866";

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

/// rustls on ring, trusting the system certificate store as
/// rustls-native-certs 0.8 finds it. Built the way vitruvian-slack-mcp's
/// `tls::client_config()` builds it: ureq's own `native-certs` feature would
/// pull in rustls-native-certs 0.7 and the unmaintained rustls-pemfile.
/// Built once and shared.
pub fn client_config() -> Arc<rustls::ClientConfig> {
    static CONFIG: OnceLock<Arc<rustls::ClientConfig>> = OnceLock::new();
    CONFIG
        .get_or_init(|| {
            let loaded = rustls_native_certs::load_native_certs();
            for err in &loaded.errors {
                eprintln!("vrelay: could not read a system CA certificate: {err}");
            }
            let mut roots = rustls::RootCertStore::empty();
            let (added, _unparsable) = roots.add_parsable_certificates(loaded.certs);
            if added == 0 {
                eprintln!("vrelay: no CA certificates found; every HTTPS call will fail");
            }
            let provider = Arc::new(rustls::crypto::ring::default_provider());
            Arc::new(
                rustls::ClientConfig::builder_with_provider(provider)
                    .with_safe_default_protocol_versions()
                    .expect("ring supports rustls's default protocol versions")
                    .with_root_certificates(roots)
                    .with_no_client_auth(),
            )
        })
        .clone()
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
}
