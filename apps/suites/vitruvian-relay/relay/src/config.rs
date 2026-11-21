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
    /// The Zitadel project role that marks an invited person. Being able to
    /// sign in is not enough: a token without it is refused (`role_missing`).
    pub required_role: String,
    /// The Postgres URL (`postgres://user:password@host:5432/dbname`). It
    /// carries the password, so it never prints.
    pub database_url: Secret,
    /// The PEM file of the CA that signed the database's certificate (the CNPG
    /// cluster's `ca.crt`). Unset means the system's certificates. Not needed
    /// when the URL says `sslmode=disable` (tests).
    pub database_ca_file: Option<PathBuf>,
    /// REMOVE IN TASK 13: the P1 device file, read once at start to copy its
    /// devices into Postgres if the database has none.
    pub legacy_devices_file: PathBuf,
    /// Overrides where signing keys are fetched. Unset in production (keys come
    /// from `{issuer}/oauth/v2/keys`); set for local runs against test keys.
    pub jwks_uri: Option<String>,
}

/// The role an invited person holds, unless `REQUIRED_ROLE` says otherwise.
pub const DEFAULT_REQUIRED_ROLE: &str = "relay-user";

/// A setting that must never reach a log or a test failure message.
#[derive(Clone, PartialEq, Eq)]
pub struct Secret(String);

impl Secret {
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Debug for Secret {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("Secret(<hidden>)")
    }
}

fn csv(raw: &str) -> Vec<String> {
    raw.split(',')
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(String::from)
        .collect()
}

/// PUBLIC_URL is an origin: https on any host, or http only on this machine
/// (`localhost` or `127.0.0.1`, for local runs). No user, path or query.
fn check_public_url(url: &str) -> Result<(), String> {
    let refuse = || {
        Err(format!(
            "PUBLIC_URL={url:?} must be an https origin (or http://localhost or http://127.0.0.1 for local runs), with no path or query"
        ))
    };
    let Ok(uri) = url.parse::<http::Uri>() else {
        return refuse();
    };
    let (Some(scheme), Some(authority)) = (uri.scheme_str(), uri.authority()) else {
        return refuse();
    };
    let host = authority.host();
    let bare = !authority.as_str().contains('@')
        && !host.is_empty()
        && matches!(uri.path(), "" | "/")
        && uri.query().is_none();
    match (bare, scheme, host) {
        (true, "https", _) => Ok(()),
        (true, "http", "localhost" | "127.0.0.1") => Ok(()),
        _ => refuse(),
    }
}

impl Settings {
    /// Reads settings from a key lookup (the environment in production).
    /// Every client id list is required: a missing one would otherwise
    /// widen who can get in. Who may sign in is not a list of people but the
    /// role (`REQUIRED_ROLE`, default `relay-user`).
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
        check_public_url(&public_url)?;
        let mcp_client_ids = csv(&req("MCP_CLIENT_IDS")?);
        if mcp_client_ids.is_empty() {
            return Err("MCP_CLIENT_IDS must name at least one id".into());
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
            required_role: opt("REQUIRED_ROLE").unwrap_or_else(|| DEFAULT_REQUIRED_ROLE.into()),
            database_url: Secret(req("DATABASE_URL")?),
            database_ca_file: opt("DATABASE_CA_FILE").map(PathBuf::from),
            legacy_devices_file: PathBuf::from(
                opt("LEGACY_DEVICES_FILE").unwrap_or_else(|| "/data/devices.json".into()),
            ),
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
            ("DATABASE_URL", "postgres://relay:pw@relay-db-rw:5432/relay"),
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
        assert_eq!(
            s.database_url.expose(),
            "postgres://relay:pw@relay-db-rw:5432/relay"
        );
        assert_eq!(s.database_ca_file, None);
        assert_eq!(s.legacy_devices_file, PathBuf::from("/data/devices.json"));
        assert_eq!(s.jwks_uri, None);
        assert_eq!(s.required_role, "relay-user");
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
        env.insert("REQUIRED_ROLE", " relay-tester ");
        env.insert("DATABASE_CA_FILE", "/etc/relay-db-ca/ca.crt");
        env.insert("LEGACY_DEVICES_FILE", "/var/relay/devices.json");
        let s = load(&env).unwrap();
        assert_eq!(s.port, 8080);
        assert_eq!(s.required_role, "relay-tester");
        assert_eq!(
            s.database_ca_file,
            Some(PathBuf::from("/etc/relay-db-ca/ca.crt"))
        );
        assert_eq!(
            s.legacy_devices_file,
            PathBuf::from("/var/relay/devices.json")
        );
    }

    /// Access is by role now: the old list of people is not a setting any
    /// more, and a blank role means the default, never "no role".
    #[test]
    fn access_is_by_role_not_a_list_of_people() {
        let mut env = base();
        env.insert("ALLOWED_SUBJECTS", "someone");
        let s = load(&env).unwrap();
        assert_eq!(s.required_role, "relay-user");
        assert!(!format!("{s:?}").contains("someone"));
        env.insert("REQUIRED_ROLE", "  ");
        assert_eq!(load(&env).unwrap().required_role, "relay-user");
    }

    #[test]
    fn the_database_password_never_prints() {
        let shown = format!("{:?}", load(&base()).unwrap());
        assert!(!shown.contains("relay:pw"), "{shown}");
        assert!(!shown.contains("postgres://"), "{shown}");
    }

    #[test]
    fn settings_refuse_missing_or_unsafe_values() {
        for drop in [
            "PUBLIC_URL",
            "ISSUER",
            "PROJECT_ID",
            "MCP_CLIENT_IDS",
            "CONNECTOR_CLIENT_ID",
            "DATABASE_URL",
        ] {
            let mut env = base();
            env.remove(drop);
            assert!(load(&env).is_err(), "missing {drop} must be refused");
        }
        for (k, v, why) in [
            ("MCP_CLIENT_IDS", ",", "separators-only client list"),
            (
                "PUBLIC_URL",
                "http://relay.example.dev",
                "plain http public URL",
            ),
            ("PORT", "eighty", "non-numeric port"),
            (
                "PUBLIC_URL",
                "http://localhost.example.com",
                "a host that only starts with localhost",
            ),
            (
                "PUBLIC_URL",
                "http://localhost@evil.example",
                "userinfo naming localhost",
            ),
            ("PUBLIC_URL", "https://", "no host"),
            ("PUBLIC_URL", "ftp://relay.example.dev", "another scheme"),
            ("PUBLIC_URL", "https://relay.example.dev/path", "a path"),
            ("PUBLIC_URL", "https://relay.example.dev?q=1", "a query"),
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
    fn public_url_accepts_https_or_local_http() {
        for ok in [
            "https://relay.example.dev",
            "https://relay.example.dev:8443/",
            "http://localhost",
            "http://localhost:3000",
            "http://127.0.0.1:8080",
        ] {
            let mut env = base();
            env.insert("PUBLIC_URL", ok);
            assert!(load(&env).is_ok(), "{ok} must be accepted");
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
