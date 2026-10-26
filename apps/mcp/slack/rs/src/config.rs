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

use std::collections::{BTreeMap, HashMap, HashSet};
use std::fmt;

use crate::channel_allowlist::{create_channel_guard, ChannelGuard, ChannelGuardOptions};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TransportMode {
    Stdio,
    Http,
}

impl TransportMode {
    pub fn as_str(self) -> &'static str {
        match self {
            TransportMode::Stdio => "stdio",
            TransportMode::Http => "http",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum WriteTokenPreference {
    Bot,
    User,
}

impl WriteTokenPreference {
    pub fn as_str(self) -> &'static str {
        match self {
            WriteTokenPreference::Bot => "bot",
            WriteTokenPreference::User => "user",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ConfigError {
    pub message: String,
}

impl ConfigError {
    pub fn new(message: impl Into<String>) -> Self {
        Self {
            message: message.into(),
        }
    }
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message)
    }
}

impl std::error::Error for ConfigError {}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SlackCredentials {
    pub bot_token: String,
    pub user_token: Option<String>,
    pub team_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpConfig {
    pub port: u16,
    pub issuer: String,
    pub project_id: String,
    pub allowed_subjects: Vec<String>,
    pub allowed_client_id: String,
}

#[derive(Debug, Clone)]
pub struct ServerConfig {
    pub transport: TransportMode,
    pub slack: SlackCredentials,
    pub channel_guard: ChannelGuard,
    pub write_token: WriteTokenPreference,
    pub http: Option<HttpConfig>,
}

pub trait EnvSource {
    fn get_var(&self, name: &str) -> Option<&str>;
}

impl EnvSource for BTreeMap<String, String> {
    fn get_var(&self, name: &str) -> Option<&str> {
        self.get(name).map(|s| s.as_str())
    }
}

impl EnvSource for HashMap<String, String> {
    fn get_var(&self, name: &str) -> Option<&str> {
        self.get(name).map(|s| s.as_str())
    }
}

impl EnvSource for [(&str, &str)] {
    fn get_var(&self, name: &str) -> Option<&str> {
        self.iter().rev().find(|(k, _)| *k == name).map(|(_, v)| *v)
    }
}

impl<const N: usize> EnvSource for [(&str, &str); N] {
    fn get_var(&self, name: &str) -> Option<&str> {
        self.as_slice().get_var(name)
    }
}

impl EnvSource for Vec<(&str, &str)> {
    fn get_var(&self, name: &str) -> Option<&str> {
        self.as_slice().get_var(name)
    }
}

fn env_get<'a, E: EnvSource + ?Sized>(env: &'a E, name: &str) -> Option<&'a str> {
    env.get_var(name)
}

fn required<E: EnvSource + ?Sized>(env: &E, name: &str, why: &str) -> Result<String, ConfigError> {
    let val = env.get_var(name).map(str::trim).unwrap_or("");
    if val.is_empty() {
        return Err(ConfigError::new(format!("{name} is required {why}.")));
    }
    Ok(val.to_string())
}

pub fn parse_transport_mode(raw: Option<&str>) -> Result<TransportMode, ConfigError> {
    let value = raw
        .map(|r| r.trim().to_ascii_lowercase())
        .unwrap_or_default();
    if value.is_empty() || value == "stdio" {
        return Ok(TransportMode::Stdio);
    }
    if value == "http" {
        return Ok(TransportMode::Http);
    }
    Err(ConfigError::new(format!(
        "MCP_TRANSPORT must be \"stdio\" or \"http\" (got \"{}\"). Omit it for the default stdio behaviour.",
        raw.unwrap_or("")
    )))
}

fn parse_subjects(raw: Option<&str>) -> Result<Vec<String>, ConfigError> {
    let mut seen = HashSet::new();
    let mut subjects = Vec::new();
    for part in raw.unwrap_or("").split(',') {
        let value = part.trim();
        if value.is_empty() || seen.contains(value) {
            continue;
        }
        seen.insert(value.to_string());
        subjects.push(value.to_string());
    }
    if subjects.is_empty() {
        return Err(ConfigError::new(
            "OIDC_ALLOWED_SUBJECTS must list at least one Zitadel subject (sub) \
when MCP_TRANSPORT=http. Without it any account this Zitadel \
instance will issue a token to reaches this endpoint, which is a \
much larger set than the people it is meant to serve. The value is \
the numeric user ID; a rejected caller's sub is named in the 403.",
        ));
    }
    Ok(subjects)
}

fn parse_port(raw: Option<&str>) -> Result<u16, ConfigError> {
    let trimmed = raw.map(str::trim).unwrap_or("");
    if trimmed.is_empty() {
        return Ok(3000);
    }
    let parsed: i64 = trimmed.parse().map_err(|_| {
        ConfigError::new(format!(
            "PORT must be an integer 1-65535 (got \"{}\").",
            raw.unwrap_or("")
        ))
    })?;
    if !(1..=65535).contains(&parsed) {
        return Err(ConfigError::new(format!(
            "PORT must be an integer 1-65535 (got \"{}\").",
            raw.unwrap_or("")
        )));
    }
    Ok(parsed as u16)
}

pub fn parse_write_mode(
    raw: Option<&str>,
    has_user_token: bool,
) -> Result<WriteTokenPreference, ConfigError> {
    let value = raw
        .map(|r| r.trim().to_ascii_lowercase())
        .unwrap_or_default();
    if value.is_empty() {
        return Ok(if has_user_token {
            WriteTokenPreference::User
        } else {
            WriteTokenPreference::Bot
        });
    }
    if value == "user" {
        return Ok(WriteTokenPreference::User);
    }
    if value == "bot" {
        return Ok(WriteTokenPreference::Bot);
    }
    Err(ConfigError::new(format!(
        "SLACK_WRITE_MODE must be \"user\" or \"bot\" (got \"{}\"). Omit it to default based on whether SLACK_USER_TOKEN is present.",
        raw.unwrap_or("")
    )))
}

pub fn resolve_config<E: EnvSource + ?Sized>(env: &E) -> Result<ServerConfig, ConfigError> {
    let transport = parse_transport_mode(env_get(env, "MCP_TRANSPORT"))?;
    let team_id = required(env, "SLACK_TEAM_ID", "to scope Slack API calls")?;
    let bot_token = required(env, "SLACK_BOT_TOKEN", "for all Slack reads")?;

    if transport == TransportMode::Stdio {
        let user_token = required(
            env,
            "SLACK_USER_TOKEN",
            "on the stdio transport, which posts and searches as the authenticated user",
        )?;
        let channel_guard = create_channel_guard(
            env_get(env, "SLACK_CHANNEL_IDS"),
            ChannelGuardOptions {
                required: false,
                enforce_visibility: false,
            },
            env_get(env, "SLACK_PRIVATE_CHANNEL_IDS"),
        )
        .map_err(|e| ConfigError::new(e.message()))?;

        return Ok(ServerConfig {
            transport,
            slack: SlackCredentials {
                bot_token,
                user_token: Some(user_token),
                team_id,
            },
            channel_guard,
            write_token: WriteTokenPreference::User,
            http: None,
        });
    }

    let user_token = env_get(env, "SLACK_USER_TOKEN")
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    let write_mode = parse_write_mode(env_get(env, "SLACK_WRITE_MODE"), user_token.is_some())?;

    if write_mode == WriteTokenPreference::User && user_token.is_none() {
        return Err(ConfigError::new(
            "SLACK_WRITE_MODE=user requires SLACK_USER_TOKEN to be set. The \
user token is the credential that posts as the authenticated \
human. Either set it, or use SLACK_WRITE_MODE=bot.",
        ));
    }

    let channel_guard = create_channel_guard(
        env_get(env, "SLACK_CHANNEL_IDS"),
        ChannelGuardOptions {
            required: user_token.is_none(),
            enforce_visibility: user_token.is_none(),
        },
        env_get(env, "SLACK_PRIVATE_CHANNEL_IDS"),
    )
    .map_err(|e| ConfigError::new(e.message()))?;

    let port = parse_port(env_get(env, "PORT"))?;
    let issuer = required(
        env,
        "OIDC_ISSUER",
        "to verify bearer tokens (e.g. https://auth.ipv1337.dev)",
    )?;
    let project_id = required(
        env,
        "OIDC_PROJECT_ID",
        "to check the token audience; it is a stack output of zitadel-apps-mcp-slack",
    )?;
    let allowed_subjects = parse_subjects(env_get(env, "OIDC_ALLOWED_SUBJECTS"))?;
    let allowed_client_id = required(
        env,
        "OIDC_ALLOWED_CLIENT_ID",
        "to pin the caller to this server's own OIDC client (#1491); it is a stack output of zitadel-apps-mcp-slack, distinct from OIDC_PROJECT_ID",
    )?;

    Ok(ServerConfig {
        transport,
        slack: SlackCredentials {
            bot_token,
            user_token,
            team_id,
        },
        channel_guard,
        write_token: write_mode,
        http: Some(HttpConfig {
            port,
            issuer,
            project_id,
            allowed_subjects,
            allowed_client_id,
        }),
    })
}

/// Extracts every environment variable name read in `config.ts` or `config.rs`.
pub fn environment_variables_read(source: &str) -> Vec<String> {
    let mut names = HashSet::new();
    let bytes = source.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if source[i..].starts_with("env.") {
            let start = i + 4;
            let mut end = start;
            while end < bytes.len()
                && (bytes[end].is_ascii_uppercase()
                    || bytes[end].is_ascii_digit()
                    || bytes[end] == b'_')
            {
                end += 1;
            }
            if end > start && bytes[start].is_ascii_uppercase() {
                names.insert(source[start..end].to_string());
            }
            i = end;
            continue;
        }
        for prefix in ["required(", "env_get("] {
            if source[i..].starts_with(prefix) {
                let rest = &source[i + prefix.len()..];
                if let Some(q1) = rest.find('"') {
                    let after_q1 = &rest[q1 + 1..];
                    if let Some(q2) = after_q1.find('"') {
                        let candidate = &after_q1[..q2];
                        if !candidate.is_empty()
                            && candidate
                                .bytes()
                                .all(|b| b.is_ascii_uppercase() || b.is_ascii_digit() || b == b'_')
                        {
                            names.insert(candidate.to_string());
                        }
                    }
                }
            }
        }
        i += 1;
    }
    let mut list: Vec<String> = names.into_iter().collect();
    list.sort();
    list
}

#[cfg(test)]
mod tests {
    use super::*;

    fn stdio_env() -> BTreeMap<String, String> {
        let mut m = BTreeMap::new();
        m.insert("SLACK_BOT_TOKEN".to_string(), "xoxb-test".to_string());
        m.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        m.insert("SLACK_TEAM_ID".to_string(), "T123".to_string());
        m
    }

    fn http_env() -> BTreeMap<String, String> {
        let mut m = BTreeMap::new();
        m.insert("MCP_TRANSPORT".to_string(), "http".to_string());
        m.insert("SLACK_BOT_TOKEN".to_string(), "xoxb-test".to_string());
        m.insert("SLACK_TEAM_ID".to_string(), "T123".to_string());
        m.insert("SLACK_CHANNEL_IDS".to_string(), "C1,C2".to_string());
        m.insert(
            "OIDC_ISSUER".to_string(),
            "https://auth.example.test".to_string(),
        );
        m.insert("OIDC_PROJECT_ID".to_string(), "999".to_string());
        m.insert(
            "OIDC_ALLOWED_SUBJECTS".to_string(),
            "379361013981513322".to_string(),
        );
        m.insert(
            "OIDC_ALLOWED_CLIENT_ID".to_string(),
            "111222333".to_string(),
        );
        m
    }

    #[test]
    fn parse_transport_mode_behaves_correctly() {
        assert_eq!(parse_transport_mode(None).unwrap(), TransportMode::Stdio);
        assert_eq!(
            parse_transport_mode(Some("")).unwrap(),
            TransportMode::Stdio
        );
        assert_eq!(
            parse_transport_mode(Some("http")).unwrap(),
            TransportMode::Http
        );
        assert_eq!(
            parse_transport_mode(Some("HTTP")).unwrap(),
            TransportMode::Http
        );
        assert_eq!(
            parse_transport_mode(Some(" stdio ")).unwrap(),
            TransportMode::Stdio
        );
        assert!(parse_transport_mode(Some("htp")).is_err());
        assert!(parse_transport_mode(Some("sse")).is_err());
    }

    #[test]
    fn parse_write_mode_behaves_correctly() {
        assert_eq!(
            parse_write_mode(None, true).unwrap(),
            WriteTokenPreference::User
        );
        assert_eq!(
            parse_write_mode(Some(""), true).unwrap(),
            WriteTokenPreference::User
        );
        assert_eq!(
            parse_write_mode(None, false).unwrap(),
            WriteTokenPreference::Bot
        );
        assert_eq!(
            parse_write_mode(Some(""), false).unwrap(),
            WriteTokenPreference::Bot
        );
        assert_eq!(
            parse_write_mode(Some("user"), false).unwrap(),
            WriteTokenPreference::User
        );
        assert_eq!(
            parse_write_mode(Some("bot"), true).unwrap(),
            WriteTokenPreference::Bot
        );
        assert_eq!(
            parse_write_mode(Some("USER"), true).unwrap(),
            WriteTokenPreference::User
        );
        assert_eq!(
            parse_write_mode(Some(" Bot "), false).unwrap(),
            WriteTokenPreference::Bot
        );
        assert!(parse_write_mode(Some("impersonate"), true).is_err());
        assert!(parse_write_mode(Some("auto"), false).is_err());
    }

    #[test]
    fn stdio_configuration_preserves_contract() {
        let config = resolve_config(&stdio_env()).unwrap();
        assert_eq!(config.transport, TransportMode::Stdio);
        assert_eq!(config.slack.user_token.as_deref(), Some("xoxp-test"));
        assert_eq!(config.write_token, WriteTokenPreference::User);
        assert!(config.http.is_none());
        assert!(config.channel_guard.is_allowed("any-channel"));

        let mut without_user = stdio_env();
        without_user.remove("SLACK_USER_TOKEN");
        assert!(resolve_config(&without_user).is_err());

        let mut with_allowlist = stdio_env();
        with_allowlist.insert("SLACK_CHANNEL_IDS".to_string(), "C1".to_string());
        let cfg = resolve_config(&with_allowlist).unwrap();
        assert!(cfg.channel_guard.is_allowed("C1"));
        assert!(!cfg.channel_guard.is_allowed("C2"));
    }

    #[test]
    fn http_configuration_validates_all_settings() {
        let config = resolve_config(&http_env()).unwrap();
        assert_eq!(config.transport, TransportMode::Http);
        assert_eq!(config.write_token, WriteTokenPreference::Bot);
        assert!(config.slack.user_token.is_none());
        assert_eq!(
            config.http,
            Some(HttpConfig {
                port: 3000,
                issuer: "https://auth.example.test".to_string(),
                project_id: "999".to_string(),
                allowed_subjects: vec!["379361013981513322".to_string()],
                allowed_client_id: "111222333".to_string(),
            })
        );
        assert_eq!(config.channel_guard.allowed, vec!["C1", "C2"]);

        // Impersonation mode
        let mut imp = http_env();
        imp.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        let imp_cfg = resolve_config(&imp).unwrap();
        assert_eq!(imp_cfg.write_token, WriteTokenPreference::User);
        assert_eq!(imp_cfg.slack.user_token.as_deref(), Some("xoxp-test"));

        imp.insert("SLACK_WRITE_MODE".to_string(), "user".to_string());
        assert_eq!(
            resolve_config(&imp).unwrap().write_token,
            WriteTokenPreference::User
        );

        imp.insert("SLACK_WRITE_MODE".to_string(), "bot".to_string());
        let bot_cfg = resolve_config(&imp).unwrap();
        assert_eq!(bot_cfg.write_token, WriteTokenPreference::Bot);
        assert_eq!(bot_cfg.slack.user_token.as_deref(), Some("xoxp-test"));

        // Fail fast if SLACK_WRITE_MODE=user without user token
        let mut bad_write = http_env();
        bad_write.insert("SLACK_WRITE_MODE".to_string(), "user".to_string());
        let err = resolve_config(&bad_write).unwrap_err();
        assert!(err.message.contains("SLACK_USER_TOKEN"));
        assert!(err.message.contains("SLACK_WRITE_MODE=user"));

        // Requires allowlist in bot-only mode
        let mut no_allow = http_env();
        no_allow.remove("SLACK_CHANNEL_IDS");
        assert!(resolve_config(&no_allow)
            .unwrap_err()
            .message
            .contains("SLACK_CHANNEL_IDS must list at least one channel"));

        // Allows allowlist omitted in impersonation mode
        no_allow.insert("SLACK_USER_TOKEN".to_string(), "xoxp-test".to_string());
        assert!(resolve_config(&no_allow)
            .unwrap()
            .channel_guard
            .is_allowed("any-channel"));

        // Token validation settings
        let mut no_issuer = http_env();
        no_issuer.remove("OIDC_ISSUER");
        assert!(resolve_config(&no_issuer)
            .unwrap_err()
            .message
            .contains("OIDC_ISSUER is required"));

        let mut no_project = http_env();
        no_project.remove("OIDC_PROJECT_ID");
        assert!(resolve_config(&no_project)
            .unwrap_err()
            .message
            .contains("OIDC_PROJECT_ID is required"));

        let mut no_subjects = http_env();
        no_subjects.remove("OIDC_ALLOWED_SUBJECTS");
        assert!(resolve_config(&no_subjects)
            .unwrap_err()
            .message
            .contains("OIDC_ALLOWED_SUBJECTS must list at least one"));

        let mut blank_subjects = http_env();
        blank_subjects.insert("OIDC_ALLOWED_SUBJECTS".to_string(), "  , ,, ".to_string());
        assert!(resolve_config(&blank_subjects).is_err());

        let mut no_client = http_env();
        no_client.remove("OIDC_ALLOWED_CLIENT_ID");
        assert!(resolve_config(&no_client)
            .unwrap_err()
            .message
            .contains("OIDC_ALLOWED_CLIENT_ID is required"));

        let mut multi_sub = http_env();
        multi_sub.insert(
            "OIDC_ALLOWED_SUBJECTS".to_string(),
            " 111, 222 ,111,".to_string(),
        );
        assert_eq!(
            resolve_config(&multi_sub)
                .unwrap()
                .http
                .unwrap()
                .allowed_subjects,
            vec!["111", "222"]
        );

        // Port validation
        let mut port_env = http_env();
        port_env.insert("PORT".to_string(), "8080".to_string());
        assert_eq!(resolve_config(&port_env).unwrap().http.unwrap().port, 8080);

        for invalid_port in ["0", "70000", "http"] {
            port_env.insert("PORT".to_string(), invalid_port.to_string());
            assert!(resolve_config(&port_env).is_err());
        }

        // Bot token and team ID
        let mut no_bot = http_env();
        no_bot.remove("SLACK_BOT_TOKEN");
        assert!(resolve_config(&no_bot)
            .unwrap_err()
            .message
            .contains("SLACK_BOT_TOKEN is required"));

        let mut no_team = http_env();
        no_team.remove("SLACK_TEAM_ID");
        assert!(resolve_config(&no_team)
            .unwrap_err()
            .message
            .contains("SLACK_TEAM_ID is required"));
    }

    #[test]
    fn every_environment_variable_is_documented_in_readme() {
        let config_source = include_str!("config.rs");
        let names = environment_variables_read(config_source);
        for mandatory in [
            "SLACK_BOT_TOKEN",
            "SLACK_TEAM_ID",
            "MCP_TRANSPORT",
            "OIDC_ALLOWED_SUBJECTS",
        ] {
            assert!(
                names.contains(&mandatory.to_string()),
                "expected {mandatory} in extracted env vars: {names:?}"
            );
        }
        assert!(names.len() >= 8);

        let readme = std::fs::read_to_string("apps/mcp/slack/README.md")
            .or_else(|_| std::fs::read_to_string("README.md"))
            .expect("README.md must be readable");
        let undocumented: Vec<String> = names
            .into_iter()
            .filter(|name| !readme.contains(name.as_str()))
            .collect();
        assert!(
            undocumented.is_empty(),
            "Undocumented environment variables: {undocumented:?}"
        );
    }
}
