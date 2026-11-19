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

//! Provision or reconcile a self-hosted Sentry internal integration and verify
//! a UI-created token for CI applies of `infrastructure/pulumi/platform/sentry`
//! and `infrastructure/pulumi/platform/sentry-pagerduty`.
//!
//! Endpoint paths, payloads, and scope/auth semantics verified against
//! `getsentry/sentry` @ tag `26.10.1`.
//!
//! Why token creation is manual in the Sentry UI:
//! - `SentryAppsEndpoint.post` (`src/sentry/sentry_apps/api/endpoints/sentry_apps.py`)
//!   sets `skip_default_auth_token=True`, so API-created internal apps have no
//!   initial token.
//! - `SentryInternalAppTokensEndpoint`
//!   (`src/sentry/sentry_apps/api/endpoints/sentry_internal_app_tokens.py`)
//!   enforces `authentication_classes = (SessionNoAuthTokenAuthentication,)`
//!   (`src/sentry/api/authentication.py`), which rejects Bearer/token auth.
//! - `SentryAppInstallationTokenCreator._create_api_token`
//!   (`src/sentry/sentry_apps/installations.py`) creates an `ApiToken` with
//!   default `token_type=AuthTokenType.__empty__` (`src/sentry/models/apitoken.py`),
//!   yielding an unprefixed 64-character hex token when created in the UI.

use crate::http::{redact, HttpClient, Response};
use crate::{valid_org, valid_url, DEFAULT_ORG, DEFAULT_URL};
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeSet;
use std::io::Write;

/// Scopes granted to the internal integration for CI applies of
/// `infrastructure/pulumi/platform/sentry` (`sentry`) and
/// `infrastructure/pulumi/platform/sentry-pagerduty` (`sentry-pagerduty`).
///
/// Closed under `SENTRY_SCOPE_HIERARCHY_MAPPING` (`src/sentry/conf/server.py`)
/// and valid in `ApiScopes` (`src/sentry/models/apiscopes.py`). All `*:admin`
/// scopes are intentionally omitted so CI cannot delete projects
/// (`src/sentry/core/endpoints/project_details.py`) or teams
/// (`src/sentry/api/bases/team.py`).
///
/// Scope-to-stack mapping verified against `getsentry/sentry` @ tag `26.10.1`:
/// - `alerts:read` (`sentry-pagerduty`): read error detectors
///   (`GET /api/0/organizations/{org}/detectors/`,
///   `src/sentry/workflow_engine/endpoints/organization_detector_index.py`,
///   `OrganizationDetectorPermission` in `src/sentry/api/bases/organization.py`)
///   and workflow alerts (`GET /api/0/organizations/{org}/workflows/[{id}/]`,
///   `src/sentry/workflow_engine/endpoints/organization_workflow_index.py`,
///   `src/sentry/workflow_engine/endpoints/organization_workflow_details.py`).
/// - `alerts:write` (`sentry-pagerduty`): create/update/delete workflow alerts
///   (`POST`/`PUT`/`DELETE` `/api/0/organizations/{org}/workflows/[{id}/]`,
///   `src/sentry/workflow_engine/endpoints/organization_workflow_index.py`,
///   `src/sentry/workflow_engine/endpoints/organization_workflow_details.py`,
///   `src/sentry/workflow_engine/endpoints/utils/permissions.py`,
///   `src/sentry/workflow_engine/endpoints/validators/utils.py`).
/// - `org:read` (`sentry`, `sentry-pagerduty`): `sentry` lists custom dashboards
///   (`GET /api/0/organizations/{org}/dashboards/`,
///   `src/sentry/dashboards/endpoints/organization_dashboards.py`; translated to
///   `dashboard:read`/`dashboard:write` via `DEPRECATED_SCOPE_TRANSLATIONS` in
///   `src/sentry/conf/server.py`); `sentry-pagerduty` reads PagerDuty org
///   integrations (`GET /api/0/organizations/{org}/integrations/[{id}/]`,
///   `src/sentry/integrations/api/endpoints/organization_integrations_index.py`,
///   `src/sentry/integrations/api/endpoints/organization_integration_details.py`,
///   `OrganizationIntegrationsPermission` in `src/sentry/api/bases/organization.py`)
///   and lists org projects (`GET /api/0/organizations/{org}/projects/`,
///   `src/sentry/core/endpoints/organization_projects.py`).
/// - `org:write` (`sentry`, `sentry-pagerduty`): `sentry` updates org
///   `scrubIPAddresses` (`PUT /api/0/organizations/{org}/`,
///   `src/sentry/core/endpoints/organization_details.py`,
///   `OrganizationPermission` in `src/sentry/api/bases/organization.py`),
///   creates/updates custom dashboards
///   (`POST`/`PUT` `/api/0/organizations/{org}/dashboards/[{id}/]`,
///   `src/sentry/dashboards/endpoints/organization_dashboards.py`,
///   `src/sentry/dashboards/endpoints/organization_dashboard_details.py`), and
///   permits project creation when `disable_member_project_creation` is set
///   (`src/sentry/core/endpoints/team_projects.py`); `sentry-pagerduty` posts the
///   PagerDuty service table (`POST /api/0/organizations/{org}/integrations/{id}/`,
///   `src/sentry/integrations/api/endpoints/organization_integration_details.py`,
///   `OrganizationIntegrationsPermission` in `src/sentry/api/bases/organization.py`;
///   internal integrations cannot be granted `org:integrations` without
///   `org:admin` per `src/sentry/conf/server.py`).
/// - `project:read` (`sentry`, `sentry-pagerduty`): `sentry` reads projects
///   (`GET /api/0/projects/{org}/{project}/`,
///   `src/sentry/core/endpoints/project_details.py`), reads DSN client keys
///   (`GET /api/0/projects/{org}/{project}/keys/[{key_id}/]`,
///   `src/sentry/core/endpoints/project_keys.py`,
///   `src/sentry/core/endpoints/project_key_details.py`, `ProjectPermission` in
///   `src/sentry/api/bases/project.py`), and validates dashboard widget project
///   filters (`src/sentry/dashboards/endpoints/organization_dashboards.py`);
///   `sentry-pagerduty` enumerates accessible projects for `GetAllProjects`,
///   detectors, and workflow links
///   (`src/sentry/core/endpoints/organization_projects.py`,
///   `src/sentry/workflow_engine/endpoints/organization_detector_index.py`,
///   `src/sentry/workflow_engine/endpoints/validators/utils.py`).
/// - `project:write` (`sentry`): creates projects
///   (`POST /api/0/teams/{org}/{team}/projects/`,
///   `src/sentry/core/endpoints/team_projects.py`), updates project settings
///   (`PUT /api/0/projects/{org}/{project}/`,
///   `src/sentry/core/endpoints/project_details.py`), attaches/detaches project
///   teams (`POST`/`DELETE /api/0/projects/{org}/{project}/teams/{team}/`,
///   `src/sentry/core/endpoints/project_team_details.py`), creates/updates DSN
///   client keys (`POST`/`PUT` `/api/0/projects/{org}/{project}/keys/...`,
///   `src/sentry/core/endpoints/project_keys.py`,
///   `src/sentry/core/endpoints/project_key_details.py`, `ProjectPermission` in
///   `src/sentry/api/bases/project.py`), and enables inbound data filters
///   (`PUT /api/0/projects/{org}/{project}/filters/{filter_id}/`,
///   `src/sentry/api/endpoints/project_filter_details.py`).
/// - `team:read` (`sentry`): reads teams (`GET /api/0/teams/{org}/{team}/`,
///   `src/sentry/core/endpoints/team_details.py`, `TeamPermission` in
///   `src/sentry/api/bases/team.py`).
/// - `team:write` (`sentry`): creates teams
///   (`POST /api/0/organizations/{org}/teams/`,
///   `src/sentry/core/endpoints/organization_teams.py`) and updates teams
///   (`PUT /api/0/teams/{org}/{team}/`,
///   `src/sentry/core/endpoints/team_details.py`, `TeamPermission` in
///   `src/sentry/api/bases/team.py`).
pub const REQUIRED_SCOPES: [&str; 8] = [
    "alerts:read",
    "alerts:write",
    "org:read",
    "org:write",
    "project:read",
    "project:write",
    "team:read",
    "team:write",
];

pub const DEFAULT_APP_NAME: &str = "vitruvian-ci";
pub const APP_AUTHOR: &str = "Vitruvian Software";
pub const APP_OVERVIEW: &str =
    "CI applies infrastructure/pulumi/platform/sentry and infrastructure/pulumi/platform/sentry-pagerduty. Managed by //tools/sentry:ci-integration.";

/// `SentryAppParser.validate_name` caps names at `64 - UUID_CHARS_IN_SLUG (6) - 1 = 57`
/// (`src/sentry/sentry_apps/api/parsers/sentry_app.py`).
pub const MAX_APP_NAME_LEN: usize = 57;

pub const USAGE: &str = "\
usage:
  bazel run //tools/sentry:ci-integration -- [--name <name>] [--url <url>] [--org <org>]
  bazel run //tools/sentry:ci-integration -- --check [--url <url>] [--org <org>]

Reconcile the internal Sentry integration (default: vitruvian-ci) with the exact
CI scopes needed by infrastructure/pulumi/platform/sentry and
infrastructure/pulumi/platform/sentry-pagerduty, and print its slug and UI link
for creating or rotating a token in the Sentry UI.

With --check, test the UI-created token in SENTRY_CI_TOKEN against Sentry's
organization projects read endpoint without mutating anything.

Options:
  --name <name>            Internal integration name (default: vitruvian-ci; max 57 chars)
  --check                  Verify SENTRY_CI_TOKEN against GET /api/0/organizations/{org}/projects/
  --url <url>              Sentry base URL (default: https://sentry.lab.ipv1337.dev)
  --org <org>              Sentry organization slug (default: sentry)
  -h, --help               Show this help message and exit

Environment:
  SENTRY_TOKEN             Reconcile mode: Sentry user auth token (prefix sntryu_) with
                           org:write plus all granted scopes (alerts:read/write, org:read/write,
                           project:read/write, team:read/write).
  SENTRY_CI_TOKEN          --check mode: internal integration token created in the Sentry UI.
";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CiIntegrationArgs {
    pub name: String,
    pub check: bool,
    pub url: String,
    pub org: String,
    pub help: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SentryApp {
    pub slug: String,
    pub name: String,
    pub is_internal: bool,
    pub scopes: Vec<String>,
}

pub fn parse_args(argv: &[String]) -> Result<CiIntegrationArgs, String> {
    let mut name = DEFAULT_APP_NAME.to_string();
    let mut check = false;
    let mut url = DEFAULT_URL.to_string();
    let mut org = DEFAULT_ORG.to_string();
    let mut help = false;

    let mut it = argv.iter();
    while let Some(flag) = it.next() {
        if flag == "-h" || flag == "--help" {
            help = true;
            continue;
        }
        if flag == "--check" {
            check = true;
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
            "--name" => name = take_value()?,
            "--url" => url = take_value()?,
            "--org" => org = take_value()?,
            "--check" => return Err("--check does not take a value".into()),
            other if other.starts_with('-') => return Err(format!("unknown argument: {other}")),
            other => return Err(format!("unexpected positional argument: {other}")),
        }
    }

    if help {
        return Ok(CiIntegrationArgs {
            name,
            check,
            url,
            org,
            help: true,
        });
    }

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

    Ok(CiIntegrationArgs {
        name,
        check,
        url,
        org,
        help: false,
    })
}

/// Validates `SENTRY_CI_TOKEN` for `--check` mode without echoing its value.
///
/// Internal integration tokens minted by `SentryAppInstallationTokenCreator`
/// (`src/sentry/sentry_apps/installations.py`) use `ApiToken` with default
/// `token_type=AuthTokenType.__empty__` (`src/sentry/models/apitoken.py`),
/// producing unprefixed 64-character hex tokens (unlike `sntryu_` user tokens).
pub fn validate_ci_token(raw: Option<&str>) -> Result<String, String> {
    let Some(token) = raw.filter(|s| !s.is_empty()) else {
        return Err(
            "SENTRY_CI_TOKEN is not set; export the UI-created internal integration token before running --check"
                .into(),
        );
    };
    if token.chars().any(|c| c.is_control() || c.is_whitespace()) {
        return Err("SENTRY_CI_TOKEN contains invalid control or whitespace characters".into());
    }
    Ok(token.to_string())
}

pub fn valid_slug(slug: &str) -> bool {
    !slug.is_empty()
        && slug
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'-' | b'_'))
}

pub fn ui_settings_url(base: &str, org: &str, slug: &str) -> String {
    let base = base.trim_end_matches('/');
    format!("{base}/settings/{org}/developer-settings/{slug}/")
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

/// Extract sorted token scopes if present in a JSON response object (`"scopes"`
/// or `IndexEndpoint.get`'s `"auth": {"scopes": [...]}` in
/// `src/sentry/api/endpoints/index.py`).
pub fn extract_response_scopes(val: &Value) -> Option<Vec<String>> {
    let arr = val
        .as_object()
        .and_then(|obj| {
            obj.get("scopes")
                .or_else(|| obj.get("auth").and_then(Value::as_object)?.get("scopes"))
        })
        .and_then(Value::as_array)?;
    let mut set = BTreeSet::new();
    for item in arr {
        let s = item.as_str()?;
        set.insert(s.to_string());
    }
    if set.is_empty() {
        None
    } else {
        Some(set.into_iter().collect())
    }
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

fn check_http(resp: &Response, secret: &str, err: &mut dyn Write) -> bool {
    if (200..300).contains(&resp.status) {
        return true;
    }
    let detail = redact(&extract_error_detail(&resp.body), secret);
    let _ = writeln!(err, "ci-integration: HTTP {}: {detail}", resp.status);
    false
}

/// Reconcile the internal Sentry integration and print its slug and UI link.
pub fn execute_reconcile<C: HttpClient>(
    args: &CiIntegrationArgs,
    caller_token: &str,
    client: &mut C,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    let base = args.url.trim_end_matches('/');
    let org_apps_url = format!("{base}/api/0/organizations/{}/sentry-apps/", args.org);
    let apps_url = format!("{base}/api/0/sentry-apps/");

    // 1. Find internal integration by name on `OrganizationSentryAppsEndpoint.get`
    // (`src/sentry/sentry_apps/api/endpoints/organization_sentry_apps.py`).
    let resp = match client.request("GET", &org_apps_url, None) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "ci-integration: {}", redact(&e, caller_token));
            return 1;
        }
    };
    if !check_http(&resp, caller_token, err) {
        return 1;
    }
    let existing = match parse_sentry_apps(&resp.body) {
        Ok(apps) => apps,
        Err(e) => {
            let _ = writeln!(err, "ci-integration: invalid sentry-apps response: {e}");
            return 1;
        }
    };

    let matches: Vec<&SentryApp> = existing
        .iter()
        .filter(|app| app.is_internal && app.name == args.name)
        .collect();

    let (state, app) = match matches.as_slice() {
        [] => {
            // 2a. Create internal integration via `SentryAppsEndpoint.post`
            // (`src/sentry/sentry_apps/api/endpoints/sentry_apps.py`).
            let create_body = build_create_app_body(&args.name, &args.org);
            let resp = match client.request("POST", &apps_url, Some(&create_body)) {
                Ok(r) => r,
                Err(e) => {
                    let _ = writeln!(err, "ci-integration: {}", redact(&e, caller_token));
                    return 1;
                }
            };
            if !check_http(&resp, caller_token, err) {
                return 1;
            }
            match parse_sentry_app(&resp.body) {
                Ok(created) => ("created", created),
                Err(e) => {
                    let _ = writeln!(
                        err,
                        "ci-integration: invalid created sentry-app response: {e}"
                    );
                    return 1;
                }
            }
        }
        [found] => {
            if scopes_match(&found.scopes, &REQUIRED_SCOPES) {
                ("unchanged", (*found).clone())
            } else {
                // 2b. Reconcile scopes via `SentryAppDetailsEndpoint.put`
                // (`src/sentry/sentry_apps/api/endpoints/sentry_app_details.py`).
                let app_url = format!("{base}/api/0/sentry-apps/{}/", found.slug);
                let update_body = build_update_scopes_body();
                let resp = match client.request("PUT", &app_url, Some(&update_body)) {
                    Ok(r) => r,
                    Err(e) => {
                        let _ = writeln!(err, "ci-integration: {}", redact(&e, caller_token));
                        return 1;
                    }
                };
                if !check_http(&resp, caller_token, err) {
                    return 1;
                }
                match parse_sentry_app(&resp.body) {
                    Ok(updated) => ("updated", updated),
                    Err(e) => {
                        let _ = writeln!(
                            err,
                            "ci-integration: invalid updated sentry-app response: {e}"
                        );
                        return 1;
                    }
                }
            }
        }
        many => {
            let slugs: Vec<&str> = many.iter().map(|a| a.slug.as_str()).collect();
            let _ = writeln!(
                err,
                "ci-integration: found multiple internal integrations named '{}' ({}); cannot disambiguate",
                args.name,
                slugs.join(", ")
            );
            return 1;
        }
    };

    let final_scopes = normalized_scopes(&app.scopes);
    let ui_url = ui_settings_url(base, &args.org, &app.slug);
    let _ = writeln!(
        out,
        "{state}: slug={} scopes={} ui={ui_url}",
        app.slug,
        final_scopes.join(",")
    );
    0
}

/// Verify `SENTRY_CI_TOKEN` against `OrganizationProjectsEndpoint.get`
/// (`GET /api/0/organizations/{org}/projects/`,
/// `src/sentry/core/endpoints/organization_projects.py`,
/// `OrganizationProjectsPermission` requiring `org:read`/`org:write`/`org:admin`).
pub fn execute_check<C: HttpClient>(
    args: &CiIntegrationArgs,
    ci_token: &str,
    client: &mut C,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    let base = args.url.trim_end_matches('/');
    let projects_url = format!("{base}/api/0/organizations/{}/projects/", args.org);

    let resp = match client.request("GET", &projects_url, None) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "ci-integration: {}", redact(&e, ci_token));
            return 1;
        }
    };

    if (200..300).contains(&resp.status) {
        let parsed: Value = match serde_json::from_slice(&resp.body) {
            Ok(v) => v,
            Err(e) => {
                let _ = writeln!(err, "ci-integration: invalid projects response: {e}");
                return 1;
            }
        };
        if let Some(scopes) = extract_response_scopes(&parsed) {
            let _ = writeln!(out, "ok scopes={}", scopes.join(","));
        } else {
            let _ = writeln!(out, "ok");
        }
        return 0;
    }

    if resp.status == 401 || resp.status == 403 {
        let _ = writeln!(out, "denied");
    }
    let detail = redact(&extract_error_detail(&resp.body), ci_token);
    let _ = writeln!(err, "ci-integration: HTTP {}: {detail}", resp.status);
    1
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::VecDeque;

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

    fn default_args() -> CiIntegrationArgs {
        CiIntegrationArgs {
            name: DEFAULT_APP_NAME.into(),
            check: false,
            url: DEFAULT_URL.into(),
            org: DEFAULT_ORG.into(),
            help: false,
        }
    }

    #[test]
    fn parse_args_validates_defaults_check_and_limits() {
        let help = parse_args(&["--help".into()]).unwrap();
        assert!(help.help);

        let defaults = parse_args(&[]).unwrap();
        assert_eq!(defaults.name, DEFAULT_APP_NAME);
        assert!(!defaults.check);
        assert_eq!(defaults.url, DEFAULT_URL);
        assert_eq!(defaults.org, DEFAULT_ORG);

        let check = parse_args(&["--check".into(), "--org=acme".into()]).unwrap();
        assert!(check.check);
        assert_eq!(check.org, "acme");

        assert!(parse_args(&["--name".into(), "".into()]).is_err());
        assert!(parse_args(&["--name".into(), "x".repeat(MAX_APP_NAME_LEN + 1)]).is_err());
        assert!(parse_args(&["--check=1".into()]).is_err());
        assert!(parse_args(&["--out".into(), "/tmp/tok".into()]).is_err());
        assert!(parse_args(&["--force".into()]).is_err());
        assert!(parse_args(&["--revoke-others".into()]).is_err());
        assert!(parse_args(&["--url".into(), "http://sentry.example".into()]).is_err());
        assert!(parse_args(&["--org".into(), "bad/org".into()]).is_err());
    }

    #[test]
    fn validate_ci_token_accepts_unprefixed_tokens_and_never_echoes_secret() {
        let missing = validate_ci_token(None).unwrap_err();
        assert!(missing.contains("SENTRY_CI_TOKEN"), "{missing}");

        let empty = validate_ci_token(Some("")).unwrap_err();
        assert!(empty.contains("SENTRY_CI_TOKEN"), "{empty}");

        let bad = "deadbeef\nsecret_probe";
        let bad_err = validate_ci_token(Some(bad)).unwrap_err();
        assert!(!bad_err.contains("secret_probe"), "{bad_err}");

        let hex64 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";
        assert_eq!(validate_ci_token(Some(hex64)).unwrap(), hex64);
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
                "project:read",
                "project:write",
                "team:read",
                "team:write"
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
    fn execute_reconcile_create_path_prints_slug_and_ui_link() {
        let args = default_args();
        let caller = "sntryu_unit_create_secret";
        let mut client = FakeHttp::new(vec![
            resp(200, "[]"),
            resp(
                201,
                r#"{"name":"vitruvian-ci","slug":"vitruvian-ci-abc123","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}"#,
            ),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute_reconcile(&args, caller, &mut client, &mut out, &mut err);
        assert_eq!(code, 0, "err={}", String::from_utf8_lossy(&err));
        assert!(err.is_empty());
        let stdout = String::from_utf8(out).unwrap();
        assert_eq!(
            stdout,
            "created: slug=vitruvian-ci-abc123 scopes=alerts:read,alerts:write,org:read,org:write,project:read,project:write,team:read,team:write ui=https://sentry.lab.ipv1337.dev/settings/sentry/developer-settings/vitruvian-ci-abc123/\n"
        );
        assert!(!stdout.contains(caller));
        assert_eq!(client.calls.len(), 2);
        assert_eq!(client.calls[0].method, "GET");
        assert_eq!(client.calls[1].method, "POST");
    }

    #[test]
    fn execute_reconcile_already_present_skips_create_and_put() {
        let args = default_args();
        let mut client = FakeHttp::new(vec![resp(
            200,
            r#"[{"name":"vitruvian-ci","slug":"vitruvian-ci-111111","status":"internal","scopes":["team:write","team:read","project:write","project:read","org:write","org:read","alerts:write","alerts:read"]}]"#,
        )]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute_reconcile(&args, "sntryu_caller", &mut client, &mut out, &mut err);
        assert_eq!(code, 0);
        assert!(err.is_empty());
        assert_eq!(client.calls.len(), 1);
        assert_eq!(client.calls[0].method, "GET");
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "unchanged: slug=vitruvian-ci-111111 scopes=alerts:read,alerts:write,org:read,org:write,project:read,project:write,team:read,team:write ui=https://sentry.lab.ipv1337.dev/settings/sentry/developer-settings/vitruvian-ci-111111/\n"
        );
    }

    #[test]
    fn execute_reconcile_scope_update_puts_required_scopes() {
        let args = default_args();
        let mut client = FakeHttp::new(vec![
            resp(
                200,
                r#"[{"name":"vitruvian-ci","slug":"vitruvian-ci-222222","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read"]}]"#,
            ),
            resp(
                200,
                r#"{"name":"vitruvian-ci","slug":"vitruvian-ci-222222","status":"internal","scopes":["alerts:read","alerts:write","org:read","org:write","project:read","project:write","team:read","team:write"]}"#,
            ),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute_reconcile(&args, "sntryu_caller", &mut client, &mut out, &mut err);
        assert_eq!(code, 0, "err={}", String::from_utf8_lossy(&err));
        assert!(err.is_empty());
        assert_eq!(client.calls.len(), 2);
        assert_eq!(client.calls[1].method, "PUT");
        assert_eq!(
            client.calls[1].url,
            "https://sentry.lab.ipv1337.dev/api/0/sentry-apps/vitruvian-ci-222222/"
        );
        let put_body: Value =
            serde_json::from_str(client.calls[1].body.as_deref().unwrap()).unwrap();
        assert_eq!(
            put_body["scopes"],
            serde_json::json!([
                "alerts:read",
                "alerts:write",
                "org:read",
                "org:write",
                "project:read",
                "project:write",
                "team:read",
                "team:write"
            ])
        );
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "updated: slug=vitruvian-ci-222222 scopes=alerts:read,alerts:write,org:read,org:write,project:read,project:write,team:read,team:write ui=https://sentry.lab.ipv1337.dev/settings/sentry/developer-settings/vitruvian-ci-222222/\n"
        );
    }

    #[test]
    fn execute_check_prints_ok_or_denied_and_optional_scopes() {
        let mut args = default_args();
        args.check = true;
        let secret = "deadbeef_ci_token_check_secret";

        let mut ok_client = FakeHttp::new(vec![resp(200, r#"[{"id":"1","slug":"backstage"}]"#)]);
        let mut out = Vec::new();
        let mut err = Vec::new();
        assert_eq!(
            execute_check(&args, secret, &mut ok_client, &mut out, &mut err),
            0
        );
        assert_eq!(String::from_utf8(out).unwrap(), "ok\n");
        assert!(err.is_empty());
        assert_eq!(
            ok_client.calls[0].url,
            "https://sentry.lab.ipv1337.dev/api/0/organizations/sentry/projects/"
        );

        let mut scoped_client = FakeHttp::new(vec![resp(
            200,
            r#"{"auth":{"scopes":["project:read","org:read"]}}"#,
        )]);
        let mut out = Vec::new();
        let mut err = Vec::new();
        assert_eq!(
            execute_check(&args, secret, &mut scoped_client, &mut out, &mut err),
            0
        );
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "ok scopes=org:read,project:read\n"
        );
        assert!(err.is_empty());

        for status in [401u16, 403u16] {
            let mut denied_client = FakeHttp::new(vec![resp(
                status,
                &format!(r#"{{"detail":"You do not have permission ({secret})"}}"#),
            )]);
            let mut out = Vec::new();
            let mut err = Vec::new();
            assert_eq!(
                execute_check(&args, secret, &mut denied_client, &mut out, &mut err),
                1
            );
            assert_eq!(String::from_utf8(out).unwrap(), "denied\n");
            let err_str = String::from_utf8(err).unwrap();
            assert!(err_str.contains(&status.to_string()), "{err_str}");
            assert!(!err_str.contains(secret), "{err_str}");
            assert!(err_str.contains("<redacted>"), "{err_str}");
        }
    }
}
