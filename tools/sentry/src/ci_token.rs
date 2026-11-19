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

//! Provision or reconcile a self-hosted Sentry internal integration and mint a
//! scoped CI token for `infrastructure/pulumi/platform/sentry-pagerduty`.
//!
//! Endpoint paths, payloads, and auth semantics verified against
//! `getsentry/sentry` @ tag `26.10.1`.

use crate::http::{redact, HttpClient, Response};
use crate::{valid_org, valid_url, DEFAULT_ORG, DEFAULT_URL};
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeSet;
use std::fs::{self, DirBuilder, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{DirBuilderExt, OpenOptionsExt, PermissionsExt};
use std::path::Path;
use std::sync::atomic::{AtomicUsize, Ordering};

/// Scopes granted to the internal integration for
/// `infrastructure/pulumi/platform/sentry-pagerduty`.
/// Validated against `ApiScopes` (`src/sentry/models/apiscopes.py`) and closed
/// under `SENTRY_SCOPE_HIERARCHY_MAPPING` (`src/sentry/conf/server.py`).
/// `org:write` is required because the stack POSTs the PagerDuty service table
/// to `/api/0/organizations/{org}/integrations/{id}/`.
pub const REQUIRED_SCOPES: [&str; 5] = [
    "alerts:read",
    "alerts:write",
    "org:read",
    "org:write",
    "project:read",
];

pub const APP_AUTHOR: &str = "Vitruvian Software";
pub const APP_OVERVIEW: &str =
    "CI applies infrastructure/pulumi/platform/sentry-pagerduty. Managed by //tools/sentry:ci-token.";

/// `SentryAppParser.validate_name` caps names at `64 - UUID_CHARS_IN_SLUG (6) - 1 = 57`
/// (`src/sentry/sentry_apps/api/parsers/sentry_app.py`).
pub const MAX_APP_NAME_LEN: usize = 57;

static TMP_OUT_COUNTER: AtomicUsize = AtomicUsize::new(0);

pub const USAGE: &str = "\
usage: bazel run //tools/sentry:ci-token -- --name <name> --out <path> [--url <url>] [--org <org>] [--force] [--revoke-others]

Ensure an internal Sentry integration exists with the exact CI scopes needed by
infrastructure/pulumi/platform/sentry-pagerduty, mint an API token for it, and
write the raw token to --out (mode 0600, parent dirs 0700).

Required:
  --name <name>            Internal integration name (e.g. vitruvian-ci; max 57 chars)
  --out <path>             Destination file for the minted token (refuses overwrite unless --force)

Options:
  --url <url>              Sentry base URL (default: https://sentry.lab.ipv1337.dev)
  --org <org>              Sentry organization slug (default: sentry)
  --force                  Replace --out atomically if it already exists
  --revoke-others          After writing the new token, delete all other tokens on the app
  -h, --help               Show this help message and exit

Environment:
  SENTRY_TOKEN             Sentry user auth token (prefix sntryu_) with org:write/org:admin.
  SENTRY_USER              Optional Sentry username/email for session auth when the server
  SENTRY_PASSWORD          enforces SessionNoAuthTokenAuthentication on /api-tokens/.
";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CiTokenArgs {
    pub name: String,
    pub out: String,
    pub url: String,
    pub org: String,
    pub force: bool,
    pub revoke_others: bool,
    pub help: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthConfig {
    Bearer(String),
    Session {
        username: String,
        password: String,
        extra_redact: Option<String>,
    },
}

impl AuthConfig {
    pub fn is_bearer(&self) -> bool {
        matches!(self, Self::Bearer(_))
    }

    pub fn redact_secret(&self) -> &str {
        match self {
            Self::Bearer(t) => t,
            Self::Session { password, .. } => password,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SentryApp {
    pub slug: String,
    pub name: String,
    pub is_internal: bool,
    pub scopes: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MintedToken {
    pub id: Option<String>,
    pub token: String,
}

pub fn parse_args(argv: &[String]) -> Result<CiTokenArgs, String> {
    let mut name: Option<String> = None;
    let mut out: Option<String> = None;
    let mut url = DEFAULT_URL.to_string();
    let mut org = DEFAULT_ORG.to_string();
    let mut force = false;
    let mut revoke_others = false;
    let mut help = false;

    let mut it = argv.iter();
    while let Some(flag) = it.next() {
        if flag == "-h" || flag == "--help" {
            help = true;
            continue;
        }
        if flag == "--force" {
            force = true;
            continue;
        }
        if flag == "--revoke-others" {
            revoke_others = true;
            continue;
        }
        let (key, inline) = match flag.split_once('=') {
            Some((k, v)) if k.starts_with("--") => (k.to_string(), Some(v.to_string())),
            _ => (flag.clone(), None),
        };
        let mut take_value = || -> Result<String, String> {
            match &inline {
                Some(v) => Ok(v.clone()),
                None => it
                    .next()
                    .cloned()
                    .ok_or_else(|| format!("{key} requires a value")),
            }
        };
        match key.as_str() {
            "--name" => name = Some(take_value()?),
            "--out" => out = Some(take_value()?),
            "--url" => url = take_value()?,
            "--org" => org = take_value()?,
            "--force" => return Err("--force does not take a value".into()),
            "--revoke-others" => return Err("--revoke-others does not take a value".into()),
            other if other.starts_with('-') => return Err(format!("unknown argument: {other}")),
            other => return Err(format!("unexpected positional argument: {other}")),
        }
    }

    if help {
        return Ok(CiTokenArgs {
            name: name.unwrap_or_default(),
            out: out.unwrap_or_default(),
            url,
            org,
            force,
            revoke_others,
            help: true,
        });
    }

    let name = name.ok_or_else(|| "--name is required".to_string())?;
    if name.trim().is_empty() {
        return Err("--name cannot be empty".into());
    }
    if name.chars().any(|c| c.is_control()) {
        return Err("--name cannot contain control characters".into());
    }
    if name.len() > MAX_APP_NAME_LEN {
        return Err(format!(
            "--name exceeds Sentry's {MAX_APP_NAME_LEN}-character limit"
        ));
    }

    let out = out.ok_or_else(|| "--out is required".to_string())?;
    if out.trim().is_empty() || out.contains('\0') {
        return Err("--out must be a non-empty valid file path".into());
    }
    if out.ends_with('/') {
        return Err("--out must name a file, not a directory".into());
    }

    if !valid_url(&url) {
        return Err(format!(
            "--url '{url}' must be an https:// URL (credentials must not travel in cleartext)"
        ));
    }
    if !valid_org(&org) {
        return Err(format!(
            "--org '{org}' must contain only ASCII letters, digits, '.', '_', or '-'"
        ));
    }

    Ok(CiTokenArgs {
        name,
        out,
        url,
        org,
        force,
        revoke_others,
        help: false,
    })
}

pub fn resolve_auth(
    sentry_token: Option<&str>,
    sentry_user: Option<&str>,
    sentry_password: Option<&str>,
) -> Result<AuthConfig, String> {
    let user_set = sentry_user.filter(|s| !s.is_empty());
    let pass_set = sentry_password.filter(|s| !s.is_empty());
    match (user_set, pass_set) {
        (Some(u), Some(p)) => {
            if u.chars().any(|c| c.is_control()) || p.chars().any(|c| c.is_control()) {
                return Err(
                    "SENTRY_USER / SENTRY_PASSWORD contains invalid control characters".into(),
                );
            }
            Ok(AuthConfig::Session {
                username: u.to_string(),
                password: p.to_string(),
                extra_redact: sentry_token.filter(|s| !s.is_empty()).map(str::to_string),
            })
        }
        (Some(_), None) => Err("SENTRY_USER is set without SENTRY_PASSWORD".into()),
        (None, Some(_)) => Err("SENTRY_PASSWORD is set without SENTRY_USER".into()),
        (None, None) => Ok(AuthConfig::Bearer(crate::validate_token(sentry_token)?)),
    }
}

pub fn valid_slug(slug: &str) -> bool {
    !slug.is_empty()
        && slug
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
}

pub fn valid_token_id(id: &str) -> bool {
    !id.is_empty()
        && id
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
}

pub fn extract_host_from_url(url: &str) -> Result<String, String> {
    let after = url
        .strip_prefix("https://")
        .ok_or_else(|| "URL must start with https://".to_string())?;
    let authority = after.split(['/', '?']).next().unwrap_or("");
    let host = if let Some(rest) = authority.strip_prefix('[') {
        rest.split(']')
            .next()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| "invalid IPv6 host in --url".to_string())?
    } else {
        authority
            .split(':')
            .next()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| "missing host in --url".to_string())?
    };
    Ok(host.to_string())
}

#[derive(Serialize)]
struct CreateAppPayload<'a> {
    name: &'a str,
    organization: &'a str,
    #[serde(rename = "isInternal")]
    is_internal: bool,
    scopes: &'a [&'static str],
    #[serde(rename = "verifyInstall")]
    verify_install: bool,
    events: [&'a str; 0],
    author: &'a str,
    overview: &'a str,
}

#[derive(Serialize)]
struct UpdateScopesPayload<'a> {
    scopes: &'a [&'static str],
}

#[derive(Serialize)]
struct LoginPayload<'a> {
    username: &'a str,
    password: &'a str,
    #[serde(rename = "orgSlug")]
    org_slug: &'a str,
}

/// Request payload for `POST /api/0/sentry-apps/` following
/// `SentryAppsEndpoint.post` (`src/sentry/sentry_apps/api/endpoints/sentry_apps.py`)
/// and `SentryAppParser` (`src/sentry/sentry_apps/api/parsers/sentry_app.py`).
pub fn build_create_app_body(name: &str, org: &str) -> String {
    serde_json::to_string(&CreateAppPayload {
        name,
        organization: org,
        is_internal: true,
        scopes: &REQUIRED_SCOPES,
        verify_install: false,
        events: [],
        author: APP_AUTHOR,
        overview: APP_OVERVIEW,
    })
    .expect("create app payload serializes")
}

/// Request payload for `PUT /api/0/sentry-apps/{slug}/` following
/// `SentryAppDetailsEndpoint.put` (`src/sentry/sentry_apps/api/endpoints/sentry_app_details.py`).
pub fn build_update_scopes_body() -> String {
    serde_json::to_string(&UpdateScopesPayload {
        scopes: &REQUIRED_SCOPES,
    })
    .expect("update scopes payload serializes")
}

/// Request payload for `POST /api/0/auth/login/` following
/// `AuthLoginEndpoint.post` (`src/sentry/api/endpoints/auth_login.py`).
pub fn build_login_body(username: &str, password: &str, org: &str) -> String {
    serde_json::to_string(&LoginPayload {
        username,
        password,
        org_slug: org,
    })
    .expect("login payload serializes")
}

fn parse_sentry_app_value(val: &Value, context: &str) -> Result<SentryApp, String> {
    let obj = val
        .as_object()
        .ok_or_else(|| format!("{context} must be a JSON object"))?;
    let slug = obj
        .get("slug")
        .and_then(Value::as_str)
        .filter(|s| valid_slug(s))
        .ok_or_else(|| format!("{context} missing valid 'slug'"))?
        .to_string();
    let name = obj
        .get("name")
        .and_then(Value::as_str)
        .ok_or_else(|| format!("{context} missing string 'name'"))?
        .to_string();

    // `SentryAppSerializer` (`src/sentry/sentry_apps/api/serializers/sentry_app.py`)
    // returns `"status": "internal"` (`SentryAppStatus.INTERNAL_STR`), not an `isInternal`
    // response field (`isInternal` is an input-only parser field per `sentry_app_details.py`).
    // Support `isInternal: true` as a fallback only when `"status"` is omitted.
    let is_internal = match obj.get("status").and_then(Value::as_str) {
        Some(status) => {
            status == "internal" && obj.get("isInternal").and_then(Value::as_bool) != Some(false)
        }
        None => obj.get("isInternal").and_then(Value::as_bool) == Some(true),
    };

    let scopes_val = obj
        .get("scopes")
        .and_then(Value::as_array)
        .ok_or_else(|| format!("{context} missing array 'scopes'"))?;
    let mut scopes = Vec::with_capacity(scopes_val.len());
    for (idx, item) in scopes_val.iter().enumerate() {
        let s = item
            .as_str()
            .ok_or_else(|| format!("{context}.scopes[{idx}] must be a string"))?;
        scopes.push(s.to_string());
    }

    Ok(SentryApp {
        slug,
        name,
        is_internal,
        scopes,
    })
}

/// Parses `GET /api/0/organizations/{org}/sentry-apps/` response matching
/// `OrganizationSentryAppsEndpoint.get`
/// (`src/sentry/sentry_apps/api/endpoints/organization_sentry_apps.py`).
pub fn parse_sentry_apps(body: &[u8]) -> Result<Vec<SentryApp>, String> {
    let val: Value =
        serde_json::from_slice(body).map_err(|e| format!("response is not valid JSON: {e}"))?;
    let arr = val
        .as_array()
        .ok_or_else(|| "expected JSON array of sentry apps".to_string())?;
    let mut out = Vec::with_capacity(arr.len());
    for (idx, item) in arr.iter().enumerate() {
        out.push(parse_sentry_app_value(item, &format!("sentry_app[{idx}]"))?);
    }
    Ok(out)
}

pub fn parse_sentry_app(body: &[u8]) -> Result<SentryApp, String> {
    let val: Value =
        serde_json::from_slice(body).map_err(|e| format!("response is not valid JSON: {e}"))?;
    parse_sentry_app_value(&val, "sentry_app")
}

pub fn scopes_match(actual: &[String], expected: &[&str]) -> bool {
    let actual_set: BTreeSet<&str> = actual.iter().map(String::as_str).collect();
    let expected_set: BTreeSet<&str> = expected.iter().copied().collect();
    actual_set == expected_set
}

pub fn normalized_scopes(actual: &[String]) -> Vec<String> {
    let set: BTreeSet<String> = actual.iter().cloned().collect();
    set.into_iter().collect()
}

fn parse_id_field(val: Option<&Value>) -> Result<Option<String>, String> {
    let Some(v) = val else {
        return Ok(None);
    };
    let s = match v {
        Value::String(s) => s.clone(),
        Value::Number(n) => n.to_string(),
        _ => return Err("token 'id' must be a string or integer".into()),
    };
    if !valid_token_id(&s) {
        return Err("token 'id' contains invalid characters".into());
    }
    Ok(Some(s))
}

/// Parses `POST /api/0/sentry-apps/{slug}/api-tokens/` response matching
/// `SentryInternalAppTokensEndpoint.post`
/// (`src/sentry/sentry_apps/api/endpoints/sentry_internal_app_tokens.py`)
/// and `ApiTokenSerializer` (`src/sentry/api/serializers/models/apitoken.py`).
pub fn parse_minted_token(body: &[u8]) -> Result<MintedToken, String> {
    let val: Value =
        serde_json::from_slice(body).map_err(|e| format!("response is not valid JSON: {e}"))?;
    let obj = val
        .as_object()
        .ok_or_else(|| "minted token response must be a JSON object".to_string())?;
    let id = parse_id_field(obj.get("id"))?;
    let token = obj
        .get("token")
        .and_then(Value::as_str)
        .ok_or_else(|| "minted token response missing string 'token'".to_string())?;
    if token.is_empty() || token.chars().any(|c| c.is_control() || c.is_whitespace()) {
        return Err("minted token is empty or contains whitespace/control characters".into());
    }
    // `sentry_internal_app_tokens.py` replaces `"token"` with `MASKED_VALUE` (`"*" * 64`)
    // when `!sentry_app.show_auth_info(request.access)`. Never write a masked placeholder.
    if token.bytes().all(|b| b == b'*') {
        return Err(
            "Sentry returned a masked token placeholder ('*'); caller lacks scopes covered by the internal integration"
                .into(),
        );
    }
    Ok(MintedToken {
        id,
        token: token.to_string(),
    })
}

/// Parses `GET /api/0/sentry-apps/{slug}/api-tokens/` response matching
/// `SentryInternalAppTokensEndpoint.get`
/// (`src/sentry/sentry_apps/api/endpoints/sentry_internal_app_tokens.py`).
pub fn parse_token_ids(body: &[u8]) -> Result<Vec<String>, String> {
    let val: Value =
        serde_json::from_slice(body).map_err(|e| format!("response is not valid JSON: {e}"))?;
    let arr = val
        .as_array()
        .ok_or_else(|| "expected JSON array of api-tokens".to_string())?;
    let mut ids = Vec::with_capacity(arr.len());
    for (idx, item) in arr.iter().enumerate() {
        let obj = item
            .as_object()
            .ok_or_else(|| format!("api_token[{idx}] must be a JSON object"))?;
        let id = parse_id_field(obj.get("id"))?
            .ok_or_else(|| format!("api_token[{idx}] missing 'id'"))?;
        ids.push(id);
    }
    Ok(ids)
}

/// Extract a concise error summary from a Sentry non-2xx JSON response without
/// ever echoing request headers.
pub fn extract_error_detail(body: &[u8]) -> String {
    let Ok(val) = serde_json::from_slice::<Value>(body) else {
        return "<no detail>".into();
    };
    match &val {
        Value::String(s) => s.clone(),
        Value::Object(map) => match map.get("detail") {
            Some(Value::String(s)) => s.clone(),
            Some(Value::Object(m)) => match m.get("message") {
                Some(Value::String(s)) => s.clone(),
                _ => serde_json::to_string(m).unwrap_or_else(|_| "<no detail>".into()),
            },
            Some(v) if !v.is_null() => v.to_string(),
            _ => {
                if map.is_empty() {
                    "<no detail>".into()
                } else {
                    serde_json::to_string(map).unwrap_or_else(|_| "<no detail>".into())
                }
            }
        },
        _ => "<no detail>".into(),
    }
}

fn redact_all(text: &str, secrets: &[&str]) -> String {
    let mut out = text.to_string();
    for secret in secrets {
        out = redact(&out, secret);
    }
    out
}

fn check_http(
    resp: &Response,
    bearer_token_api_hint: bool,
    secrets: &[&str],
    err: &mut dyn Write,
) -> bool {
    if (200..300).contains(&resp.status) {
        return true;
    }
    let detail = redact_all(&extract_error_detail(&resp.body), secrets);
    if bearer_token_api_hint && matches!(resp.status, 401 | 403) {
        let _ = writeln!(
            err,
            "ci-token: HTTP {}: {detail} (Sentry 26.10.1 /api-tokens/ uses SessionNoAuthTokenAuthentication, which rejects Bearer tokens; re-run with SENTRY_USER and SENTRY_PASSWORD set)",
            resp.status
        );
    } else {
        let _ = writeln!(err, "ci-token: HTTP {}: {detail}", resp.status);
    }
    false
}

/// Verify `--out` can be written before making any network calls so an existing
/// file does not trigger unwanted app creation or token minting.
pub fn preflight_out_path(path: &Path, force: bool) -> Result<(), String> {
    if path.is_dir() {
        return Err(format!("--out '{}' is a directory", path.display()));
    }
    if !force && fs::symlink_metadata(path).is_ok() {
        return Err(format!(
            "refusing to overwrite existing file '{}' (pass --force to replace)",
            path.display()
        ));
    }
    Ok(())
}

fn ensure_parent_dirs_0700(parent: &Path) -> Result<(), String> {
    if parent.as_os_str().is_empty() || parent.is_dir() {
        return Ok(());
    }
    if fs::symlink_metadata(parent).is_ok() {
        return Err(format!(
            "parent path '{}' exists and is not a directory",
            parent.display()
        ));
    }
    let mut missing = Vec::new();
    let mut cur = parent;
    while !cur.as_os_str().is_empty() && fs::symlink_metadata(cur).is_err() {
        missing.push(cur.to_path_buf());
        match cur.parent() {
            Some(p) => cur = p,
            None => break,
        }
    }
    if !cur.as_os_str().is_empty() && !cur.is_dir() {
        return Err(format!(
            "parent path '{}' exists and is not a directory",
            cur.display()
        ));
    }
    for dir in missing.into_iter().rev() {
        DirBuilder::new()
            .recursive(false)
            .mode(0o700)
            .create(&dir)
            .map_err(|e| format!("failed to create directory '{}': {e}", dir.display()))?;
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o700)).map_err(|e| {
            format!(
                "failed to set mode 0700 on directory '{}': {e}",
                dir.display()
            )
        })?;
    }
    Ok(())
}

/// Write `secret` to `path` with mode `0600` (and `0700` for any newly created
/// parent directories). Never creates a file with permissive permissions, even
/// transiently or under a lax umask.
pub fn write_secret_file(path: &Path, secret: &str, force: bool) -> Result<(), String> {
    preflight_out_path(path, force)?;

    let parent = path.parent().unwrap_or_else(|| Path::new(""));
    ensure_parent_dirs_0700(parent)?;

    if !force {
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(path)
            .map_err(|e| format!("failed to create '{}': {e}", path.display()))?;
        if let Err(e) = f
            .set_permissions(fs::Permissions::from_mode(0o600))
            .and_then(|()| f.write_all(secret.as_bytes()))
            .and_then(|()| f.sync_all())
        {
            drop(f);
            let _ = fs::remove_file(path);
            return Err(format!("failed to write '{}': {e}", path.display()));
        }
        return Ok(());
    }

    let tmp_dir = if parent.as_os_str().is_empty() {
        Path::new(".")
    } else {
        parent
    };
    let pid = std::process::id();
    let (tmp_path, mut tmp_file) = loop {
        let seq = TMP_OUT_COUNTER.fetch_add(1, Ordering::SeqCst);
        let candidate = tmp_dir.join(format!(".ci-token-{pid}-{seq}.tmp"));
        match OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(&candidate)
        {
            Ok(f) => break (candidate, f),
            Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => continue,
            Err(e) => {
                return Err(format!(
                    "failed to create temporary file in '{}': {e}",
                    tmp_dir.display()
                ))
            }
        }
    };

    let write_res = tmp_file
        .set_permissions(fs::Permissions::from_mode(0o600))
        .and_then(|()| tmp_file.write_all(secret.as_bytes()))
        .and_then(|()| tmp_file.sync_all());
    drop(tmp_file);
    if let Err(e) = write_res {
        let _ = fs::remove_file(&tmp_path);
        return Err(format!(
            "failed to write temporary file '{}': {e}",
            tmp_path.display()
        ));
    }

    if let Err(e) = fs::rename(&tmp_path, path) {
        let _ = fs::remove_file(&tmp_path);
        return Err(format!(
            "failed to replace '{}' atomically: {e}",
            path.display()
        ));
    }
    Ok(())
}

/// Authenticate the cookie jar via Django session login when `SENTRY_USER` and
/// `SENTRY_PASSWORD` are supplied:
/// 1. `GET /api/0/auth/config/` sets Django's session test cookie
///    (`src/sentry/api/endpoints/auth_config.py`).
/// 2. `POST /api/0/auth/login/` logs in with `{username, password, orgSlug}`
///    (`src/sentry/api/endpoints/auth_login.py`).
pub fn login_session<C: HttpClient>(
    base_url: &str,
    org: &str,
    username: &str,
    password: &str,
    client: &mut C,
    err: &mut dyn Write,
) -> Result<(), ()> {
    let base = base_url.trim_end_matches('/');
    let secrets = [password];

    let config_url = format!("{base}/api/0/auth/config/");
    let resp = match client.request("GET", &config_url, None) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "ci-token: {}", redact_all(&e, &secrets));
            return Err(());
        }
    };
    if !check_http(&resp, false, &secrets, err) {
        return Err(());
    }

    let login_url = format!("{base}/api/0/auth/login/");
    let login_body = build_login_body(username, password, org);
    let resp = match client.request("POST", &login_url, Some(&login_body)) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "ci-token: {}", redact_all(&e, &secrets));
            return Err(());
        }
    };
    if resp.status == 202 {
        let _ = writeln!(
            err,
            "ci-token: login requires interactive MFA (HTTP 202); non-interactive session login cannot proceed"
        );
        return Err(());
    }
    if !check_http(&resp, false, &secrets, err) {
        return Err(());
    }
    Ok(())
}

pub fn execute<C: HttpClient>(
    args: &CiTokenArgs,
    out_path: &Path,
    is_bearer_auth: bool,
    secret_to_redact: &str,
    client: &mut C,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    if let Err(e) = preflight_out_path(out_path, args.force) {
        let _ = writeln!(err, "ci-token: {e}");
        return 1;
    }

    let base = args.url.trim_end_matches('/');
    let org_apps_url = format!("{base}/api/0/organizations/{}/sentry-apps/", args.org);
    let apps_url = format!("{base}/api/0/sentry-apps/");
    let caller_secrets = [secret_to_redact];

    // 1. Find internal integration by name on `OrganizationSentryAppsEndpoint.get`
    // (`src/sentry/sentry_apps/api/endpoints/organization_sentry_apps.py`).
    let resp = match client.request("GET", &org_apps_url, None) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "ci-token: {}", redact_all(&e, &caller_secrets));
            return 1;
        }
    };
    if !check_http(&resp, false, &caller_secrets, err) {
        return 1;
    }
    let existing = match parse_sentry_apps(&resp.body) {
        Ok(apps) => apps,
        Err(e) => {
            let _ = writeln!(err, "ci-token: invalid sentry-apps response: {e}");
            return 1;
        }
    };

    let matches: Vec<&SentryApp> = existing
        .iter()
        .filter(|app| app.is_internal && app.name == args.name)
        .collect();

    let app = match matches.as_slice() {
        [] => {
            // 2a. Create internal integration via `SentryAppsEndpoint.post`
            // (`src/sentry/sentry_apps/api/endpoints/sentry_apps.py`).
            let create_body = build_create_app_body(&args.name, &args.org);
            let resp = match client.request("POST", &apps_url, Some(&create_body)) {
                Ok(r) => r,
                Err(e) => {
                    let _ = writeln!(err, "ci-token: {}", redact_all(&e, &caller_secrets));
                    return 1;
                }
            };
            if !check_http(&resp, false, &caller_secrets, err) {
                return 1;
            }
            match parse_sentry_app(&resp.body) {
                Ok(created) => created,
                Err(e) => {
                    let _ = writeln!(err, "ci-token: invalid created sentry-app response: {e}");
                    return 1;
                }
            }
        }
        [found] => {
            if scopes_match(&found.scopes, &REQUIRED_SCOPES) {
                (*found).clone()
            } else {
                // 2b. Reconcile scopes via `SentryAppDetailsEndpoint.put`
                // (`src/sentry/sentry_apps/api/endpoints/sentry_app_details.py`).
                let app_url = format!("{base}/api/0/sentry-apps/{}/", found.slug);
                let update_body = build_update_scopes_body();
                let resp = match client.request("PUT", &app_url, Some(&update_body)) {
                    Ok(r) => r,
                    Err(e) => {
                        let _ = writeln!(err, "ci-token: {}", redact_all(&e, &caller_secrets));
                        return 1;
                    }
                };
                if !check_http(&resp, false, &caller_secrets, err) {
                    return 1;
                }
                match parse_sentry_app(&resp.body) {
                    Ok(updated) => updated,
                    Err(e) => {
                        let _ = writeln!(err, "ci-token: invalid updated sentry-app response: {e}");
                        return 1;
                    }
                }
            }
        }
        many => {
            let slugs: Vec<&str> = many.iter().map(|a| a.slug.as_str()).collect();
            let _ = writeln!(
                err,
                "ci-token: found multiple internal integrations named '{}' ({}); cannot disambiguate",
                args.name,
                slugs.join(", ")
            );
            return 1;
        }
    };

    // 3. Mint an internal integration API token via `SentryInternalAppTokensEndpoint.post`
    // (`src/sentry/sentry_apps/api/endpoints/sentry_internal_app_tokens.py`).
    let tokens_url = format!("{base}/api/0/sentry-apps/{}/api-tokens/", app.slug);
    let resp = match client.request("POST", &tokens_url, Some("{}")) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "ci-token: {}", redact_all(&e, &caller_secrets));
            return 1;
        }
    };
    if !check_http(&resp, is_bearer_auth, &caller_secrets, err) {
        return 1;
    }
    let minted = match parse_minted_token(&resp.body) {
        Ok(t) => t,
        Err(e) => {
            let _ = writeln!(err, "ci-token: invalid api-tokens response: {e}");
            return 1;
        }
    };
    let all_secrets = [secret_to_redact, minted.token.as_str()];

    if args.revoke_others && minted.id.is_none() {
        let _ = writeln!(
            err,
            "ci-token: minted token response missing 'id'; cannot safely --revoke-others"
        );
        return 1;
    }

    // 4. Persist the raw token safely before revoking any older tokens.
    if let Err(e) = write_secret_file(out_path, &minted.token, args.force) {
        let _ = writeln!(err, "ci-token: {}", redact_all(&e, &all_secrets));
        return 1;
    }

    // 5. Optionally revoke all other tokens via `SentryInternalAppTokensEndpoint.get`
    // and `SentryInternalAppTokenDetailsEndpoint.delete`
    // (`src/sentry/sentry_apps/api/endpoints/sentry_internal_app_token_details.py`).
    if args.revoke_others {
        let keep_id = minted.id.as_deref().expect("checked above");
        let resp = match client.request("GET", &tokens_url, None) {
            Ok(r) => r,
            Err(e) => {
                let _ = writeln!(err, "ci-token: {}", redact_all(&e, &all_secrets));
                return 1;
            }
        };
        if !check_http(&resp, is_bearer_auth, &all_secrets, err) {
            return 1;
        }
        let ids = match parse_token_ids(&resp.body) {
            Ok(list) => list,
            Err(e) => {
                let _ = writeln!(err, "ci-token: invalid api-tokens list response: {e}");
                return 1;
            }
        };
        for id in ids {
            if id == keep_id {
                continue;
            }
            let delete_url = format!("{base}/api/0/sentry-apps/{}/api-tokens/{id}/", app.slug);
            let resp = match client.request("DELETE", &delete_url, None) {
                Ok(r) => r,
                Err(e) => {
                    let _ = writeln!(err, "ci-token: {}", redact_all(&e, &all_secrets));
                    return 1;
                }
            };
            if !check_http(&resp, is_bearer_auth, &all_secrets, err) {
                return 1;
            }
        }
    }

    let final_scopes = normalized_scopes(&app.scopes);
    let _ = writeln!(
        out,
        "token written: {} app={} scopes={}",
        out_path.display(),
        app.slug,
        final_scopes.join(",")
    );
    0
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;
    use std::os::unix::fs::MetadataExt;
    use std::path::PathBuf;

    #[derive(Debug, Clone, PartialEq, Eq)]
    struct RecordedCall {
        method: String,
        url: String,
        body: Option<String>,
    }

    struct FakeHttp {
        responses: VecDeque<Result<Response, String>>,
        calls: Vec<RecordedCall>,
    }

    impl FakeHttp {
        fn new(responses: Vec<Result<Response, String>>) -> Self {
            Self {
                responses: responses.into(),
                calls: Vec::new(),
            }
        }
    }

    impl HttpClient for FakeHttp {
        fn request(
            &mut self,
            method: &str,
            url: &str,
            body: Option<&str>,
        ) -> Result<Response, String> {
            self.calls.push(RecordedCall {
                method: method.to_string(),
                url: url.to_string(),
                body: body.map(str::to_string),
            });
            self.responses
                .pop_front()
                .expect("unexpected extra HTTP call")
        }
    }

    fn resp(status: u16, body: &str) -> Result<Response, String> {
        Ok(Response {
            status,
            body: body.as_bytes().to_vec(),
        })
    }

    fn tempdir(tag: &str) -> PathBuf {
        let base = std::env::temp_dir();
        static COUNTER: AtomicUsize = AtomicUsize::new(0);
        let d = base.join(format!(
            "ci-token-unit-{tag}-{}-{}",
            std::process::id(),
            COUNTER.fetch_add(1, Ordering::SeqCst)
        ));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    fn default_args(out: &Path) -> CiTokenArgs {
        CiTokenArgs {
            name: "vitruvian-ci".into(),
            out: out.to_string_lossy().into_owned(),
            url: DEFAULT_URL.into(),
            org: DEFAULT_ORG.into(),
            force: false,
            revoke_others: false,
            help: false,
        }
    }

    #[test]
    fn parse_args_validates_flags_defaults_and_limits() {
        let help = parse_args(&["--help".into()]).unwrap();
        assert!(help.help);

        let ok = parse_args(&[
            "--name=vitruvian-ci".into(),
            "--out".into(),
            "/tmp/token".into(),
            "--force".into(),
            "--revoke-others".into(),
        ])
        .unwrap();
        assert_eq!(ok.name, "vitruvian-ci");
        assert_eq!(ok.out, "/tmp/token");
        assert_eq!(ok.url, DEFAULT_URL);
        assert_eq!(ok.org, DEFAULT_ORG);
        assert!(ok.force);
        assert!(ok.revoke_others);

        assert!(parse_args(&["--out".into(), "/tmp/tok".into()]).is_err());
        assert!(parse_args(&["--name".into(), "ci".into()]).is_err());
        assert!(parse_args(&[
            "--name".into(),
            "x".repeat(MAX_APP_NAME_LEN + 1),
            "--out".into(),
            "/tmp/tok".into(),
        ])
        .is_err());
        assert!(parse_args(&[
            "--name".into(),
            "ci".into(),
            "--out".into(),
            "/tmp/dir/".into(),
        ])
        .is_err());
        assert!(parse_args(&[
            "--name".into(),
            "ci".into(),
            "--out".into(),
            "/tmp/tok".into(),
            "--url".into(),
            "http://sentry.example".into(),
        ])
        .is_err());
        assert!(parse_args(&[
            "--name".into(),
            "ci".into(),
            "--out".into(),
            "/tmp/tok".into(),
            "--org".into(),
            "bad/org".into(),
        ])
        .is_err());
    }

    #[test]
    fn resolve_auth_handles_bearer_and_session_without_leaking_secrets() {
        assert_eq!(
            resolve_auth(Some("sntryu_abc"), None, None).unwrap(),
            AuthConfig::Bearer("sntryu_abc".into())
        );
        assert_eq!(
            resolve_auth(None, Some("admin@ipv1337.dev"), Some("pw_secret")).unwrap(),
            AuthConfig::Session {
                username: "admin@ipv1337.dev".into(),
                password: "pw_secret".into(),
                extra_redact: None,
            }
        );
        let partial_err = resolve_auth(None, None, Some("pw_secret_should_not_echo")).unwrap_err();
        assert!(!partial_err.contains("pw_secret_should_not_echo"));
    }

    #[test]
    fn builds_exact_create_and_update_payloads() {
        let created: Value =
            serde_json::from_str(&build_create_app_body("vitruvian-ci", "sentry")).unwrap();
        assert_eq!(created["name"], "vitruvian-ci");
        assert_eq!(created["organization"], "sentry");
        assert_eq!(created["isInternal"], true);
        assert_eq!(
            created["scopes"],
            serde_json::json!([
                "alerts:read",
                "alerts:write",
                "org:read",
                "org:write",
                "project:read"
            ])
        );
        assert_eq!(created["verifyInstall"], false);
        assert_eq!(created["events"], serde_json::json!([]));
        assert_eq!(created["author"], APP_AUTHOR);
        assert_eq!(created["overview"], APP_OVERVIEW);

        let updated: Value = serde_json::from_str(&build_update_scopes_body()).unwrap();
        assert_eq!(updated["scopes"], created["scopes"]);
    }

    #[test]
    fn parse_sentry_apps_matches_status_internal_or_fallback_is_internal() {
        let raw = br#"[
            {"name":"vitruvian-ci","slug":"vitruvian-ci-pub","status":"unpublished","scopes":["org:read"]},
            {"name":"vitruvian-ci","slug":"vitruvian-ci-int","status":"internal","scopes":["org:read","org:write"]},
            {"name":"other-app","slug":"other-app-111111","isInternal":true,"scopes":["project:read"]}
        ]"#;
        let apps = parse_sentry_apps(raw).unwrap();
        assert_eq!(apps.len(), 3);
        assert!(!apps[0].is_internal);
        assert!(apps[1].is_internal);
        assert!(apps[2].is_internal);
    }

    #[test]
    fn parse_minted_token_rejects_masked_placeholder() {
        let masked = "*".repeat(64);
        let err = parse_minted_token(format!(r#"{{"id":"1","token":"{masked}"}}"#).as_bytes())
            .unwrap_err();
        assert!(err.contains("masked"), "{err}");

        let ok = parse_minted_token(br#"{"id":42,"token":"sntrya_real_token_value"}"#).unwrap();
        assert_eq!(ok.id.as_deref(), Some("42"));
        assert_eq!(ok.token, "sntrya_real_token_value");
    }

    #[test]
    fn execute_create_path_creates_0700_parent_0600_file_and_redacts_token() {
        let dir = tempdir("create");
        let out_path = dir.join("nested/secrets/ci_token");
        let args = default_args(&out_path);
        let minted = "sntrya_unit_created_secret_123";
        let mut client = FakeHttp::new(vec![
            resp(200, "[]"),
            resp(
                201,
                r#"{"name":"vitruvian-ci","slug":"vitruvian-ci-abc123","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read"]}"#,
            ),
            resp(201, &format!(r#"{{"id":"9","token":"{minted}"}}"#)),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute(
            &args,
            &out_path,
            true,
            "sntryu_caller",
            &mut client,
            &mut out,
            &mut err,
        );
        assert_eq!(code, 0, "err={}", String::from_utf8_lossy(&err));
        let stdout = String::from_utf8(out).unwrap();
        assert_eq!(
            stdout,
            format!(
                "token written: {} app=vitruvian-ci-abc123 scopes=alerts:read,alerts:write,org:read,org:write,project:read\n",
                out_path.display()
            )
        );
        assert!(!stdout.contains(minted));
        assert!(err.is_empty());
        assert_eq!(fs::read_to_string(&out_path).unwrap(), minted);
        assert_eq!(fs::metadata(&out_path).unwrap().mode() & 0o777, 0o600);
        assert_eq!(
            fs::metadata(out_path.parent().unwrap()).unwrap().mode() & 0o777,
            0o700
        );
        assert_eq!(client.calls.len(), 3);
        assert_eq!(client.calls[0].method, "GET");
        assert_eq!(client.calls[1].method, "POST");
        assert_eq!(client.calls[2].method, "POST");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn execute_already_present_skips_create_and_put() {
        let dir = tempdir("present");
        let out_path = dir.join("token");
        let args = default_args(&out_path);
        let mut client = FakeHttp::new(vec![
            resp(
                200,
                r#"[{"name":"vitruvian-ci","slug":"vitruvian-ci-111111","status":"internal","scopes":["project:read","org:write","org:read","alerts:write","alerts:read"]}]"#,
            ),
            resp(201, r#"{"id":"7","token":"sntrya_existing_ok"}"#),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute(
            &args,
            &out_path,
            true,
            "sntryu_caller",
            &mut client,
            &mut out,
            &mut err,
        );
        assert_eq!(code, 0);
        assert_eq!(client.calls.len(), 2);
        assert_eq!(client.calls[0].method, "GET");
        assert_eq!(client.calls[1].method, "POST");
        assert_eq!(fs::read_to_string(&out_path).unwrap(), "sntrya_existing_ok");
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn execute_scope_update_puts_required_scopes_and_revoke_others_deletes_old_ids() {
        let dir = tempdir("update-revoke");
        let out_path = dir.join("token");
        let mut args = default_args(&out_path);
        args.revoke_others = true;

        let mut client = FakeHttp::new(vec![
            resp(
                200,
                r#"[{"name":"vitruvian-ci","slug":"vitruvian-ci-222222","status":"internal","scopes":["org:read","project:read"]}]"#,
            ),
            resp(
                200,
                r#"{"name":"vitruvian-ci","slug":"vitruvian-ci-222222","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read"]}"#,
            ),
            resp(201, r#"{"id":"55","token":"sntrya_rotated_55"}"#),
            resp(
                200,
                r#"[{"id":"11","token":null},{"id":"55","token":null},{"id":"99","token":null}]"#,
            ),
            resp(204, ""),
            resp(204, ""),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute(
            &args,
            &out_path,
            true,
            "sntryu_caller",
            &mut client,
            &mut out,
            &mut err,
        );
        assert_eq!(code, 0, "err={}", String::from_utf8_lossy(&err));
        assert_eq!(client.calls.len(), 6);
        assert_eq!(client.calls[1].method, "PUT");
        assert_eq!(
            client.calls[1].url,
            "https://sentry.lab.ipv1337.dev/api/0/sentry-apps/vitruvian-ci-222222/"
        );
        assert_eq!(client.calls[3].method, "GET");
        assert_eq!(client.calls[4].method, "DELETE");
        assert_eq!(
            client.calls[4].url,
            "https://sentry.lab.ipv1337.dev/api/0/sentry-apps/vitruvian-ci-222222/api-tokens/11/"
        );
        assert_eq!(client.calls[5].method, "DELETE");
        assert_eq!(
            client.calls[5].url,
            "https://sentry.lab.ipv1337.dev/api/0/sentry-apps/vitruvian-ci-222222/api-tokens/99/"
        );
        let _ = fs::remove_dir_all(&dir);
    }

    #[test]
    fn execute_refuses_existing_out_before_any_http_call() {
        let dir = tempdir("no-overwrite");
        let out_path = dir.join("existing");
        fs::write(&out_path, "keep-me").unwrap();
        let args = default_args(&out_path);
        let mut client = FakeHttp::new(vec![]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute(
            &args,
            &out_path,
            true,
            "sntryu_caller",
            &mut client,
            &mut out,
            &mut err,
        );
        assert_eq!(code, 1);
        assert!(client.calls.is_empty());
        assert_eq!(fs::read_to_string(&out_path).unwrap(), "keep-me");
        let _ = fs::remove_dir_all(&dir);
    }
}
