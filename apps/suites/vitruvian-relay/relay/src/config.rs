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

use crate::oauth::AppKeys;

#[derive(Debug, Clone, PartialEq)]
pub struct Settings {
    pub port: u16,
    /// Public origin with no trailing slash, e.g. https://relay.ipv1337.dev
    pub public_url: String,
    pub issuer: String,
    pub project_id: String,
    /// Client ids of the AI apps allowed on `/mcp/d/{device_id}` (Claude).
    pub mcp_client_ids: Vec<String>,
    /// What to call each AI app in the dashboard (`Claude=<id>`), from
    /// `MCP_CLIENT_LABELS`. Optional; an app with no label is "an AI app".
    pub mcp_client_labels: Vec<(String, String)>,
    /// Client id of the connector, the only one allowed on `/devices` and `/connect`.
    pub connector_client_id: String,
    /// Client id of the dashboard's sign-in (`relay-dashboard`), the only one
    /// allowed on `/auth/*`. In neither of the other two lists.
    pub dashboard_client_id: String,
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
    /// Overrides where signing keys are fetched. Unset in production (keys come
    /// from `{issuer}/oauth/v2/keys`); set for local runs against test keys.
    pub jwks_uri: Option<String>,
    /// Overrides where the dashboard's sign-in code is exchanged. Unset in
    /// production (`{issuer}/oauth/v2/token`); set for local runs and tests.
    pub token_uri: Option<String>,
    /// Sign-in for AI apps that register themselves (Gemini). None unless both
    /// `APP_SIGNIN_KEY` and `APPS_CLIENT_ID` are set; then every `/oauth/*`
    /// and `/mcp/app/*` path answers 404.
    pub app_signin: Option<AppSignin>,
}

/// What the app sign-in needs: the server key and the one client id that
/// tokens it issues carry (which must be an MCP client id).
#[derive(Debug, Clone)]
pub struct AppSignin {
    pub keys: AppKeys,
    pub client_id: String,
}

/// Compares the client id only: key material is never compared with `==`.
/// Settings need `PartialEq` for tests that compare two loads.
impl PartialEq for AppSignin {
    fn eq(&self, other: &Self) -> bool {
        self.client_id == other.client_id
    }
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

/// True for an https URL on any host, or an http one only on this machine
/// (`localhost` or `127.0.0.1`, for local runs and tests), with no user part.
/// `bare` also requires it to be an origin: no path, no query.
fn safe_url(url: &str, bare: bool) -> bool {
    let Ok(uri) = url.parse::<http::Uri>() else {
        return false;
    };
    let (Some(scheme), Some(authority)) = (uri.scheme_str(), uri.authority()) else {
        return false;
    };
    let host = authority.host();
    let shaped = !authority.as_str().contains('@')
        && !host.is_empty()
        && (!bare || (matches!(uri.path(), "" | "/") && uri.query().is_none()));
    shaped
        && match scheme {
            "https" => true,
            "http" => matches!(host, "localhost" | "127.0.0.1"),
            _ => false,
        }
}

/// PUBLIC_URL is an origin: https on any host, or http only on this machine
/// (`localhost` or `127.0.0.1`, for local runs). No user, path or query.
fn check_public_url(url: &str) -> Result<(), String> {
    if safe_url(url, true) {
        return Ok(());
    }
    Err(format!(
        "PUBLIC_URL={url:?} must be an https origin (or http://localhost or http://127.0.0.1 for local runs), with no path or query"
    ))
}

/// ISSUER, JWKS_URI and TOKEN_URI point at the identity service, so a token or
/// a sign-in code must never travel to them in plain text: the same rule as
/// PUBLIC_URL, but they may have a path.
fn check_endpoint_url(name: &str, url: &str) -> Result<(), String> {
    if safe_url(url, false) {
        return Ok(());
    }
    Err(format!(
        "{name}={url:?} must be an https URL (or http://localhost or http://127.0.0.1 for local runs), with no user name in it"
    ))
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
        let mut mcp_client_labels = Vec::new();
        for entry in csv(&opt("MCP_CLIENT_LABELS").unwrap_or_default()) {
            let pair = entry
                .split_once('=')
                .map(|(label, id)| (label.trim(), id.trim()))
                .filter(|(label, id)| !label.is_empty() && !id.is_empty());
            let Some((label, id)) = pair else {
                return Err(format!(
                    "MCP_CLIENT_LABELS entry {entry:?} must look like Claude=<client id>"
                ));
            };
            if !mcp_client_ids.iter().any(|known| known == id) {
                return Err(format!(
                    "MCP_CLIENT_LABELS names {id:?}, which is not in MCP_CLIENT_IDS"
                ));
            }
            mcp_client_labels.push((label.to_string(), id.to_string()));
        }
        let connector_client_id = req("CONNECTOR_CLIENT_ID")?;
        if mcp_client_ids.contains(&connector_client_id) {
            // The connector's token must never work on /mcp, nor an AI app's
            // on /connect.
            return Err("CONNECTOR_CLIENT_ID must not also be in MCP_CLIENT_IDS".into());
        }
        let dashboard_client_id = req("DASHBOARD_CLIENT_ID")?;
        if mcp_client_ids.contains(&dashboard_client_id)
            || dashboard_client_id == connector_client_id
        {
            // The same rule for the dashboard: its token must never work on
            // /mcp, /devices or /connect, nor theirs on /auth/*.
            return Err(
                "DASHBOARD_CLIENT_ID must not also be in MCP_CLIENT_IDS or be CONNECTOR_CLIENT_ID"
                    .into(),
            );
        }
        // The issuer is where people are sent to sign in, and where the keys
        // that check every token come from: the same rule as the endpoints
        // under it.
        let issuer = req("ISSUER")?.trim_end_matches('/').to_string();
        check_endpoint_url("ISSUER", &issuer)?;
        let jwks_uri = opt("JWKS_URI");
        let token_uri = opt("TOKEN_URI");
        for (name, value) in [("JWKS_URI", &jwks_uri), ("TOKEN_URI", &token_uri)] {
            if let Some(url) = value {
                check_endpoint_url(name, url)?;
            }
        }
        let app_signin = match (opt("APP_SIGNIN_KEY"), opt("APPS_CLIENT_ID")) {
            (None, None) => None,
            (Some(key), Some(client_id)) => {
                // Tokens it issues must pass the same audience check as every
                // other AI app's. (It cannot be the connector's or the
                // dashboard's id either: both are refused above if they are in
                // MCP_CLIENT_IDS.)
                if !mcp_client_ids.contains(&client_id) {
                    return Err("APPS_CLIENT_ID must also be in MCP_CLIENT_IDS".into());
                }
                // Apps-client tokens are refused on /mcp/d/, so sharing Claude's
                // id would lock Claude out of every call.
                if mcp_client_labels
                    .iter()
                    .any(|(label, id)| label == "Claude" && *id == client_id)
                {
                    return Err("APPS_CLIENT_ID must not be the Claude client".into());
                }
                Some(AppSignin {
                    keys: AppKeys::from_b64(&key)?,
                    client_id,
                })
            }
            _ => {
                return Err("APP_SIGNIN_KEY and APPS_CLIENT_ID must be set together".into());
            }
        };
        Ok(Settings {
            port,
            public_url,
            issuer,
            project_id: req("PROJECT_ID")?,
            mcp_client_ids,
            mcp_client_labels,
            connector_client_id,
            dashboard_client_id,
            required_role: opt("REQUIRED_ROLE").unwrap_or_else(|| DEFAULT_REQUIRED_ROLE.into()),
            database_url: Secret(req("DATABASE_URL")?),
            database_ca_file: opt("DATABASE_CA_FILE").map(PathBuf::from),
            jwks_uri,
            token_uri,
            app_signin,
        })
    }

    /// What the dashboard calls the AI app with this client id.
    pub fn mcp_client_label(&self, client_id: &str) -> Option<&str> {
        self.mcp_client_labels
            .iter()
            .find(|(_, id)| id == client_id)
            .map(|(label, _)| label.as_str())
    }

    /// The client id of the AI app labelled `label` (case does not matter).
    pub fn mcp_client_id_of(&self, label: &str) -> Option<&str> {
        self.mcp_client_labels
            .iter()
            .find(|(l, _)| l.eq_ignore_ascii_case(label))
            .map(|(_, id)| id.as_str())
    }

    /// Where the dashboard sends a person to sign in.
    pub fn authorize_url(&self) -> String {
        format!("{}/oauth/v2/authorize", self.issuer)
    }

    /// Where the dashboard exchanges a sign-in code for a token.
    pub fn token_url(&self) -> String {
        self.token_uri
            .clone()
            .unwrap_or_else(|| format!("{}/oauth/v2/token", self.issuer))
    }

    /// Where Zitadel sends a person back to after signing in.
    pub fn dashboard_callback_url(&self) -> String {
        format!("{}/auth/callback", self.public_url)
    }

    /// Where a person can end their sign-in on the identity service itself,
    /// and come back to the relay's front page.
    pub fn end_session_url(&self) -> String {
        format!(
            "{}/oidc/v1/end_session?client_id={}&post_logout_redirect_uri={}",
            self.issuer,
            crate::dashboard::form_encode(&self.dashboard_client_id),
            crate::dashboard::form_encode(&format!("{}/", self.public_url)),
        )
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

    /// The URL a self-registering AI app is given for one device.
    pub fn app_mcp_url(&self, device_id: &str) -> String {
        format!("{}/mcp/app/{device_id}", self.public_url)
    }

    /// Where that device's protected-resource metadata is served for apps.
    pub fn app_metadata_url(&self, device_id: &str) -> String {
        format!(
            "{}/.well-known/oauth-protected-resource/mcp/app/{device_id}",
            self.public_url
        )
    }

    /// Where Zitadel sends a person back to after signing in for an app.
    pub fn apps_callback_url(&self) -> String {
        format!("{}/oauth/callback", self.public_url)
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
            ("DASHBOARD_CLIENT_ID", "dash-id"),
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
        assert_eq!(s.jwks_uri, None);
        assert_eq!(s.token_uri, None);
        assert_eq!(s.dashboard_client_id, "dash-id");
        assert_eq!(s.required_role, "relay-user");
        assert_eq!(
            s.authorize_url(),
            "https://auth.example.dev/oauth/v2/authorize"
        );
        assert_eq!(s.token_url(), "https://auth.example.dev/oauth/v2/token");
        assert_eq!(
            s.dashboard_callback_url(),
            "https://relay.example.dev/auth/callback"
        );
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
        let s = load(&env).unwrap();
        assert_eq!(s.port, 8080);
        assert_eq!(s.required_role, "relay-tester");
        assert_eq!(
            s.database_ca_file,
            Some(PathBuf::from("/etc/relay-db-ca/ca.crt"))
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
            "DASHBOARD_CLIENT_ID",
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
            (
                "DASHBOARD_CLIENT_ID",
                "claude-id",
                "dashboard id shared with an AI app",
            ),
            (
                "DASHBOARD_CLIENT_ID",
                "conn-id",
                "dashboard id shared with the connector",
            ),
            ("MCP_CLIENT_LABELS", "Claude", "a label with no id"),
            (
                "MCP_CLIENT_LABELS",
                "Claude=nobody",
                "a label for an unknown id",
            ),
        ] {
            let mut env = base();
            env.insert(k, v);
            assert!(load(&env).is_err(), "{why} must be refused");
        }
    }

    #[test]
    fn ai_apps_can_be_given_names_for_the_dashboard() {
        let mut env = base();
        env.insert("MCP_CLIENT_LABELS", "Claude=claude-id, Gemini = chatgpt-id");
        env.insert("TOKEN_URI", " http://127.0.0.1:9/token ");
        let s = load(&env).unwrap();
        assert_eq!(s.mcp_client_label("claude-id"), Some("Claude"));
        assert_eq!(s.mcp_client_label("chatgpt-id"), Some("Gemini"));
        assert_eq!(s.mcp_client_label("other"), None);
        assert_eq!(s.mcp_client_id_of("claude"), Some("claude-id"));
        assert_eq!(s.token_url(), "http://127.0.0.1:9/token");
    }

    fn key_b64() -> String {
        use base64::Engine;
        base64::engine::general_purpose::STANDARD.encode([5u8; 32])
    }

    #[test]
    fn config_needs_both_or_neither() {
        // Neither: the feature is off and nothing else changes.
        let off = load(&base()).unwrap();
        assert_eq!(off.app_signin, None);

        let key = key_b64();
        let mut both = base();
        both.insert("APP_SIGNIN_KEY", &key);
        both.insert("APPS_CLIENT_ID", "chatgpt-id");
        let on = load(&both).unwrap();
        let app = on.app_signin.as_ref().expect("both set turns it on");
        assert_eq!(app.client_id, "chatgpt-id");
        assert_eq!(
            Settings {
                app_signin: None,
                ..on.clone()
            },
            off
        );

        let mut only_key = base();
        only_key.insert("APP_SIGNIN_KEY", &key);
        let err = load(&only_key).unwrap_err();
        assert!(err.contains("together"), "{err}");
        assert!(!err.contains(&key));

        let mut only_id = base();
        only_id.insert("APPS_CLIENT_ID", "chatgpt-id");
        assert!(load(&only_id).unwrap_err().contains("together"));

        // A bad key is refused without echoing it.
        let short = {
            use base64::Engine;
            base64::engine::general_purpose::STANDARD.encode([6u8; 16])
        };
        for bad in ["not-base64-secret-value!!", short.as_str()] {
            let mut env = both.clone();
            env.insert("APP_SIGNIN_KEY", bad);
            let err = load(&env).unwrap_err();
            assert!(err.contains("APP_SIGNIN_KEY"), "{err}");
            assert!(!err.contains(bad), "the error must not echo the key: {err}");
        }
        // The key never prints.
        assert!(!format!("{on:?}").contains(&key));
    }

    #[test]
    fn apps_client_must_not_be_claudes_client() {
        let key = key_b64();
        let mut env = base();
        env.insert("MCP_CLIENT_LABELS", "Claude=claude-id");
        env.insert("APP_SIGNIN_KEY", &key);
        env.insert("APPS_CLIENT_ID", "claude-id");
        let err = load(&env).unwrap_err();
        assert!(err.contains("must not be the Claude client"), "{err}");
        env.insert("APPS_CLIENT_ID", "chatgpt-id");
        assert!(load(&env).is_ok());
    }

    #[test]
    fn apps_client_must_be_an_mcp_client() {
        let key = key_b64();
        // Not an MCP client at all (including the connector's and the
        // dashboard's ids, which are not in the list).
        for id in ["unknown-id", "conn-id", "dash-id"] {
            let mut env = base();
            env.insert("APP_SIGNIN_KEY", &key);
            env.insert("APPS_CLIENT_ID", id);
            let err = load(&env).unwrap_err();
            assert!(
                err.contains("APPS_CLIENT_ID must also be in"),
                "{id}: {err}"
            );
        }
        // Forcing the connector's or the dashboard's id into the list does not
        // make it usable: the existing check refuses that first.
        for (id, name, list) in [
            ("conn-id", "CONNECTOR_CLIENT_ID", "claude-id,conn-id"),
            ("dash-id", "DASHBOARD_CLIENT_ID", "claude-id,dash-id"),
        ] {
            let mut env = base();
            env.insert("MCP_CLIENT_IDS", list);
            env.insert("APP_SIGNIN_KEY", &key);
            env.insert("APPS_CLIENT_ID", id);
            let err = load(&env).unwrap_err();
            assert!(err.starts_with(name), "{id}: {err}");
        }
        // An id that is in the list is accepted.
        let mut env = base();
        env.insert("APP_SIGNIN_KEY", &key);
        env.insert("APPS_CLIENT_ID", "claude-id");
        assert!(load(&env).is_ok());
    }

    #[test]
    fn app_urls_hang_off_the_public_url() {
        let s = load(&base()).unwrap();
        assert_eq!(
            s.app_mcp_url("dev1"),
            "https://relay.example.dev/mcp/app/dev1"
        );
        assert_eq!(
            s.app_metadata_url("dev1"),
            "https://relay.example.dev/.well-known/oauth-protected-resource/mcp/app/dev1"
        );
        assert_eq!(
            s.apps_callback_url(),
            "https://relay.example.dev/oauth/callback"
        );
    }

    #[test]
    fn identity_service_urls_are_https_or_local_http() {
        for name in ["ISSUER", "JWKS_URI", "TOKEN_URI"] {
            for ok in [
                "https://auth.example.dev/oauth/v2/keys",
                "http://localhost:9000/keys",
                "http://127.0.0.1:9000/oauth/v2/token",
            ] {
                let mut env = base();
                env.insert(name, ok);
                assert!(load(&env).is_ok(), "{name}={ok} must be accepted");
            }
            for (bad, why) in [
                ("http://auth.example.dev/keys", "plain http to another host"),
                ("ftp://auth.example.dev/keys", "another scheme"),
                ("auth.example.dev/keys", "no scheme"),
                (
                    "http://localhost@evil.example/keys",
                    "userinfo naming localhost",
                ),
                (
                    "http://localhost.example.com/keys",
                    "a host that starts with localhost",
                ),
                ("https://", "no host"),
            ] {
                let mut env = base();
                env.insert(name, bad);
                let err = load(&env).unwrap_err();
                assert!(err.contains(name), "{why}: {err}");
            }
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
