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

//! Settings read from the environment once at start-up.

use std::path::PathBuf;

#[derive(Debug, Clone, PartialEq)]
pub struct Settings {
    pub port: u16,
    /// Public origin with no trailing slash, e.g. https://relay.ipv1337.dev
    pub public_url: String,
    pub issuer: String,
    pub project_id: String,
    /// Client ids of the AI apps allowed on `/mcp/d/{device_id}` (Claude).
    pub mcp_client_ids: Vec<String>,
    /// Client id of the connector, the only one allowed on `/devices` and `/connect`.
    pub connector_client_id: String,
    pub allowed_subjects: Vec<String>,
    /// Where `devices.json` lives.
    pub data_dir: PathBuf,
    /// Overrides where signing keys are fetched. Unset in production (keys come
    /// from `{issuer}/oauth/v2/keys`); set for local runs against test keys.
    pub jwks_uri: Option<String>,
}

fn csv(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect()
}

impl Settings {
    /// Reads settings from a key lookup (the environment in production).
    /// Every id list is required: a missing client id or subject list would
    /// otherwise widen who can get in.
    pub fn from_lookup(get: impl Fn(&str) -> Option<String>) -> Result<Settings, String> {
        let opt = |k: &str| {
            get(k)
                .map(|v| v.trim().to_string())
                .filter(|v| !v.is_empty())
        };
        let req = |k: &str| opt(k).ok_or_else(|| format!("{k} is required"));
        let port = match opt("PORT") {
            None => 3000,
            Some(v) => v
                .parse()
                .map_err(|_| format!("PORT={v:?} is not a port number"))?,
        };
        let public_url = req("PUBLIC_URL")?.trim_end_matches('/').to_string();
        if !public_url.starts_with("https://") && !public_url.starts_with("http://localhost") {
            return Err(format!(
                "PUBLIC_URL={public_url:?} must be https (or http://localhost for local runs)"
            ));
        }
        let mcp_client_ids = csv(&req("MCP_CLIENT_IDS")?);
        let allowed_subjects = csv(&req("ALLOWED_SUBJECTS")?);
        if mcp_client_ids.is_empty() || allowed_subjects.is_empty() {
            return Err(
                "MCP_CLIENT_IDS and ALLOWED_SUBJECTS must each name at least one id".into(),
            );
        }
        let connector_client_id = req("CONNECTOR_CLIENT_ID")?;
        if mcp_client_ids.contains(&connector_client_id) {
            // The connector's token must never work on /mcp, nor an AI app's
            // on /connect.
            return Err("CONNECTOR_CLIENT_ID must not also be in MCP_CLIENT_IDS".into());
        }
        Ok(Settings {
            port,
            public_url,
            issuer: req("ISSUER")?.trim_end_matches('/').to_string(),
            project_id: req("PROJECT_ID")?,
            mcp_client_ids,
            connector_client_id,
            allowed_subjects,
            data_dir: PathBuf::from(opt("DATA_DIR").unwrap_or_else(|| "/data".into())),
            jwks_uri: opt("JWKS_URI"),
        })
    }

    /// The URL an AI app is given for one device.
    pub fn device_mcp_url(&self, device_id: &str) -> String {
        format!("{}/mcp/d/{device_id}", self.public_url)
    }

    /// Where that device's protected-resource metadata is served.
    pub fn device_metadata_url(&self, device_id: &str) -> String {
        format!(
            "{}/.well-known/oauth-protected-resource/mcp/d/{device_id}",
            self.public_url
        )
    }

    /// The relay's own metadata, for clients that look at the bare path first.
    pub fn relay_metadata_url(&self) -> String {
        format!("{}/.well-known/oauth-protected-resource", self.public_url)
    }

    pub fn devices_file(&self) -> PathBuf {
        self.data_dir.join("devices.json")
    }
}

/// True when the command line asks only for the version.
pub fn wants_version(args: impl IntoIterator<Item = String>) -> bool {
    args.into_iter()
        .skip(1)
        .any(|a| a == "--version" || a == "-V")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    fn base() -> HashMap<&'static str, &'static str> {
        [
            ("PUBLIC_URL", "https://relay.example.dev/"),
            ("ISSUER", "https://auth.example.dev/"),
            ("PROJECT_ID", "123"),
            ("MCP_CLIENT_IDS", "claude-id, ,chatgpt-id"),
            ("CONNECTOR_CLIENT_ID", "conn-id"),
            ("ALLOWED_SUBJECTS", "sub-1"),
        ]
        .into_iter()
        .collect()
    }

    fn load(env: &HashMap<&str, &str>) -> Result<Settings, String> {
        Settings::from_lookup(|k| env.get(k).map(|v| v.to_string()))
    }

    #[test]
    fn settings_trim_and_default() {
        let s = load(&base()).unwrap();
        assert_eq!(s.port, 3000);
        assert_eq!(s.public_url, "https://relay.example.dev");
        assert_eq!(s.issuer, "https://auth.example.dev");
        assert_eq!(s.mcp_client_ids, vec!["claude-id", "chatgpt-id"]);
        assert_eq!(s.data_dir, PathBuf::from("/data"));
        assert_eq!(s.devices_file(), PathBuf::from("/data/devices.json"));
        assert_eq!(s.jwks_uri, None);
        assert_eq!(
            s.device_mcp_url("d-1"),
            "https://relay.example.dev/mcp/d/d-1"
        );
        assert_eq!(
            s.device_metadata_url("d-1"),
            "https://relay.example.dev/.well-known/oauth-protected-resource/mcp/d/d-1"
        );

        let mut env = base();
        env.insert("PORT", "8080");
        env.insert("DATA_DIR", "/var/relay");
        let s = load(&env).unwrap();
        assert_eq!((s.port, s.data_dir), (8080, PathBuf::from("/var/relay")));
    }

    #[test]
    fn settings_refuse_missing_or_unsafe_values() {
        for drop in [
            "PUBLIC_URL",
            "ISSUER",
            "PROJECT_ID",
            "MCP_CLIENT_IDS",
            "CONNECTOR_CLIENT_ID",
            "ALLOWED_SUBJECTS",
        ] {
            let mut env = base();
            env.remove(drop);
            assert!(load(&env).is_err(), "missing {drop} must be refused");
        }
        for (k, v, why) in [
            ("ALLOWED_SUBJECTS", " , ", "separators-only subject list"),
            ("MCP_CLIENT_IDS", ",", "separators-only client list"),
            (
                "PUBLIC_URL",
                "http://relay.example.dev",
                "plain http public URL",
            ),
            ("PORT", "eighty", "non-numeric port"),
            (
                "CONNECTOR_CLIENT_ID",
                "claude-id",
                "connector id shared with an AI app",
            ),
        ] {
            let mut env = base();
            env.insert(k, v);
            assert!(load(&env).is_err(), "{why} must be refused");
        }
    }

    #[test]
    fn version_flag() {
        let args = |a: &[&str]| a.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert!(wants_version(args(&["vitruvian-relay", "--version"])));
        assert!(wants_version(args(&["vitruvian-relay", "-V"])));
        assert!(!wants_version(args(&["vitruvian-relay"])));
        assert!(
            !wants_version(args(&["--version"])),
            "argv[0] is not a flag"
        );
    }
}
