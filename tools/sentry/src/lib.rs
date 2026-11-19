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

//! Idempotent bootstrap for Sentry's PagerDuty integration via Sentry's
//! `integration_pipeline` session API without registering a PagerDuty OAuth app.

pub mod ci_integration;
pub mod http;
pub mod send_test_event;

use http::{HttpClient, Response};
use serde::Serialize;
use serde_json::Value;
use std::io::Write;

pub const DEFAULT_URL: &str = "https://sentry.lab.ipv1337.dev";
pub const DEFAULT_ORG: &str = "sentry";

pub const USAGE: &str = "\
usage: bazel run //tools/sentry:pagerduty-install -- --subdomain <subdomain> --name <name> [--url <url>] [--org <org>]

One-shot, idempotent bootstrap for Sentry's PagerDuty integration without
registering a PagerDuty app.

Required:
  --subdomain <subdomain>  PagerDuty account subdomain (e.g. vitruviansoftware)
  --name <name>            PagerDuty account display name (e.g. \"Vitruvian Software\")

Options:
  --url <url>              Sentry base URL (default: https://sentry.lab.ipv1337.dev)
  --org <org>              Sentry organization slug (default: sentry)
  -h, --help               Show this help message and exit

Environment:
  SENTRY_TOKEN             Sentry user auth token (prefix sntryu_) with org:integrations
                           scope; export from Bitwarden item 'sentry.lab.ipv1337.dev',
                           field 'SENTRY_TOKEN' (see infrastructure/pulumi/platform/sentry/README.md).
";

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Args {
    pub subdomain: String,
    pub name: String,
    pub url: String,
    pub org: String,
    pub help: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Integration {
    pub id: String,
    pub name: String,
}

pub(crate) fn valid_url(url: &str) -> bool {
    if url.chars().any(|c| c.is_control() || c.is_whitespace()) {
        return false;
    }
    // https only: the request carries the Bearer token.
    let rest = url.strip_prefix("https://");
    let Some(after_scheme) = rest else {
        return false;
    };
    let host = after_scheme.split(['/', '?']).next().unwrap_or("");
    !host.is_empty()
}

pub(crate) fn valid_org(org: &str) -> bool {
    !org.is_empty()
        && org
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
}

pub fn parse_args(argv: &[String]) -> Result<Args, String> {
    let mut subdomain: Option<String> = None;
    let mut name: Option<String> = None;
    let mut url = DEFAULT_URL.to_string();
    let mut org = DEFAULT_ORG.to_string();
    let mut help = false;

    let mut it = argv.iter();
    while let Some(flag) = it.next() {
        if flag == "-h" || flag == "--help" {
            help = true;
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
            "--subdomain" => subdomain = Some(take_value()?),
            "--name" => name = Some(take_value()?),
            "--url" => url = take_value()?,
            "--org" => org = take_value()?,
            other if other.starts_with('-') => return Err(format!("unknown argument: {other}")),
            other => return Err(format!("unexpected positional argument: {other}")),
        }
    }

    if help {
        return Ok(Args {
            subdomain: subdomain.unwrap_or_default(),
            name: name.unwrap_or_default(),
            url,
            org,
            help: true,
        });
    }

    let subdomain = subdomain.ok_or_else(|| "--subdomain is required".to_string())?;
    if subdomain.trim().is_empty() {
        return Err("--subdomain cannot be empty".into());
    }
    let name = name.ok_or_else(|| "--name is required".to_string())?;
    if name.trim().is_empty() {
        return Err("--name cannot be empty".into());
    }
    if !valid_url(&url) {
        return Err(format!(
            "--url '{url}' must be an https:// URL (the token must not travel in cleartext)"
        ));
    }
    if !valid_org(&org) {
        return Err(format!(
            "--org '{org}' must contain only ASCII letters, digits, '.', '_', or '-'"
        ));
    }

    Ok(Args {
        subdomain,
        name,
        url,
        org,
        help: false,
    })
}

pub fn validate_token(raw: Option<&str>) -> Result<String, String> {
    let Some(token) = raw.filter(|s| !s.is_empty()) else {
        return Err(
            "SENTRY_TOKEN is not set; export it from Bitwarden item 'sentry.lab.ipv1337.dev', \
             field 'SENTRY_TOKEN' (see infrastructure/pulumi/platform/sentry/README.md)"
                .into(),
        );
    };
    if token.chars().any(|c| c.is_control()) {
        return Err("SENTRY_TOKEN contains invalid control characters".into());
    }
    if !token.starts_with("sntryu_") || token == "sntryu_" {
        return Err(
            "SENTRY_TOKEN must start with 'sntryu_': the install pipeline needs a user token \
             (not an org token)"
                .into(),
        );
    }
    Ok(token.to_string())
}

#[derive(Serialize)]
struct InitializePayload {
    action: &'static str,
    provider: &'static str,
}

#[derive(Serialize)]
struct PagerDutyAccount<'a> {
    subdomain: &'a str,
    name: &'a str,
}

#[derive(Serialize)]
struct PagerDutyConfig<'a> {
    account: PagerDutyAccount<'a>,
    integration_keys: [&'a str; 0],
}

#[derive(Serialize)]
struct ConfigPayload {
    config: String,
}

pub fn build_initialize_body() -> String {
    serde_json::to_string(&InitializePayload {
        action: "initialize",
        provider: "pagerduty",
    })
    .expect("initialize payload serializes")
}

pub fn build_config_body(subdomain: &str, name: &str) -> String {
    let inner = serde_json::to_string(&PagerDutyConfig {
        account: PagerDutyAccount { subdomain, name },
        integration_keys: [],
    })
    .expect("inner config serializes");
    serde_json::to_string(&ConfigPayload { config: inner }).expect("config payload serializes")
}

pub fn extract_detail(body: &[u8]) -> String {
    let Ok(val) = serde_json::from_slice::<Value>(body) else {
        return "<no detail>".into();
    };
    match val.get("detail") {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Object(m)) => match m.get("message") {
            Some(Value::String(s)) => s.clone(),
            _ => serde_json::to_string(m).unwrap_or_else(|_| "<no detail>".into()),
        },
        Some(v) if !v.is_null() => v.to_string(),
        _ => "<no detail>".into(),
    }
}

pub fn parse_integrations(body: &[u8]) -> Result<Vec<Integration>, String> {
    let val: Value =
        serde_json::from_slice(body).map_err(|e| format!("response is not valid JSON: {e}"))?;
    let arr = val
        .as_array()
        .ok_or_else(|| "expected JSON array of integrations".to_string())?;
    let mut out = Vec::with_capacity(arr.len());
    for (idx, item) in arr.iter().enumerate() {
        let id = match item.get("id") {
            Some(Value::String(s)) => s.clone(),
            Some(Value::Number(n)) => n.to_string(),
            _ => return Err(format!("integration[{idx}] missing string/numeric 'id'")),
        };
        let name = match item.get("name") {
            Some(Value::String(s)) => s.clone(),
            _ => return Err(format!("integration[{idx}] missing string 'name'")),
        };
        out.push(Integration { id, name });
    }
    Ok(out)
}

fn check_http(resp: &Response, is_initialize: bool, err: &mut dyn Write) -> bool {
    if (200..300).contains(&resp.status) {
        return true;
    }
    let detail = extract_detail(&resp.body);
    if is_initialize && resp.status == 403 {
        let _ = writeln!(
            err,
            "pagerduty-install: HTTP 403: {detail} (token lacks org:integrations scope)"
        );
    } else {
        let _ = writeln!(err, "pagerduty-install: HTTP {}: {detail}", resp.status);
    }
    false
}

pub fn execute<C: HttpClient>(
    args: &Args,
    client: &mut C,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    let base = args.url.trim_end_matches('/');
    let integrations_url = format!(
        "{base}/api/0/organizations/{}/integrations/?provider_key=pagerduty",
        args.org
    );
    let pipeline_url = format!(
        "{base}/api/0/organizations/{}/pipeline/integration_pipeline/",
        args.org
    );

    // 1. Check whether PagerDuty is already installed.
    let resp = match client.request("GET", &integrations_url, None) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "pagerduty-install: {e}");
            return 1;
        }
    };
    if !check_http(&resp, false, err) {
        return 1;
    }
    let existing = match parse_integrations(&resp.body) {
        Ok(list) => list,
        Err(e) => {
            let _ = writeln!(err, "pagerduty-install: invalid integrations response: {e}");
            return 1;
        }
    };
    if let Some(first) = existing.first() {
        let _ = writeln!(
            out,
            "already installed: id={} name={}",
            first.id, first.name
        );
        return 0;
    }

    // 2. Initialize the pipeline (captures the Django session cookie).
    let init_body = build_initialize_body();
    let resp = match client.request("POST", &pipeline_url, Some(&init_body)) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "pagerduty-install: {e}");
            return 1;
        }
    };
    if !check_http(&resp, true, err) {
        return 1;
    }

    // 3. Submit the single PagerDutyInstallationApiStep payload with the same session cookie.
    let config_body = build_config_body(&args.subdomain, &args.name);
    let resp = match client.request("POST", &pipeline_url, Some(&config_body)) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "pagerduty-install: {e}");
            return 1;
        }
    };
    if !check_http(&resp, false, err) {
        return 1;
    }

    // 4. Verify the integration now exists.
    let resp = match client.request("GET", &integrations_url, None) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "pagerduty-install: {e}");
            return 1;
        }
    };
    if !check_http(&resp, false, err) {
        return 1;
    }
    let installed = match parse_integrations(&resp.body) {
        Ok(list) => list,
        Err(e) => {
            let _ = writeln!(err, "pagerduty-install: invalid integrations response: {e}");
            return 1;
        }
    };
    if let Some(first) = installed.first() {
        let _ = writeln!(out, "installed: id={} name={}", first.id, first.name);
        0
    } else {
        let _ = writeln!(
            err,
            "pagerduty-install: installation completed without error, but pagerduty integration is still missing"
        );
        1
    }
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

    fn default_args() -> Args {
        Args {
            subdomain: "vitruviansoftware".into(),
            name: "Vitruvian Software".into(),
            url: DEFAULT_URL.into(),
            org: DEFAULT_ORG.into(),
            help: false,
        }
    }

    #[test]
    fn builds_exact_initialize_and_config_bodies() {
        assert_eq!(
            build_initialize_body(),
            r#"{"action":"initialize","provider":"pagerduty"}"#
        );
        assert_eq!(
            build_config_body("vitruviansoftware", "Vitruvian Software"),
            r#"{"config":"{\"account\":{\"subdomain\":\"vitruviansoftware\",\"name\":\"Vitruvian Software\"},\"integration_keys\":[]}"}"#
        );
    }

    #[test]
    fn config_body_escapes_special_characters_in_name() {
        let tricky = "Vitruvian \"Ops\" \\ Team\nCafé";
        let payload = build_config_body("vitruvian-ops", tricky);
        let outer: Value = serde_json::from_str(&payload).unwrap();
        let inner_str = outer["config"].as_str().unwrap();
        let inner: Value = serde_json::from_str(inner_str).unwrap();
        assert_eq!(inner["account"]["subdomain"], "vitruvian-ops");
        assert_eq!(inner["account"]["name"], tricky);
        assert_eq!(inner["integration_keys"], serde_json::json!([]));
    }

    #[test]
    fn token_validation_enforces_user_token_and_bitwarden_guidance() {
        let unset = validate_token(None).unwrap_err();
        assert!(unset.contains("sentry.lab.ipv1337.dev"), "{unset}");
        assert!(unset.contains("SENTRY_TOKEN"), "{unset}");

        let empty = validate_token(Some("")).unwrap_err();
        assert!(empty.contains("sentry.lab.ipv1337.dev"), "{empty}");

        let org_secret = "sntrys_super_secret_org_token";
        let org_err = validate_token(Some(org_secret)).unwrap_err();
        assert!(org_err.contains("sntryu_"), "{org_err}");
        assert!(org_err.contains("user token"), "{org_err}");
        assert!(!org_err.contains(org_secret), "must not leak token");

        assert!(validate_token(Some("sntryu_")).is_err());
        assert!(validate_token(Some("sntryu_abc\n")).is_err());
        assert_eq!(
            validate_token(Some("sntryu_valid123")).unwrap(),
            "sntryu_valid123"
        );
    }

    #[test]
    fn parse_args_handles_help_defaults_inline_flags_and_validation() {
        let help = parse_args(&["--help".into()]).unwrap();
        assert!(help.help);

        let a = parse_args(&[
            "--subdomain=acme".into(),
            "--name".into(),
            "Acme Corp".into(),
        ])
        .unwrap();
        assert_eq!(a.subdomain, "acme");
        assert_eq!(a.name, "Acme Corp");
        assert_eq!(a.url, DEFAULT_URL);
        assert_eq!(a.org, DEFAULT_ORG);
        assert!(!a.help);

        assert!(parse_args(&["--subdomain".into(), "acme".into()]).is_err());
        // The token must never travel in cleartext.
        let plain = parse_args(&[
            "--subdomain".into(),
            "acme".into(),
            "--name".into(),
            "Acme".into(),
            "--url".into(),
            "http://sentry.example".into(),
        ]);
        assert!(plain.unwrap_err().contains("https://"));
        assert!(parse_args(&["--name".into(), "Acme".into()]).is_err());
        assert!(parse_args(&[
            "--subdomain".into(),
            "acme".into(),
            "--name".into(),
            "Acme".into(),
            "--url".into(),
            "ftp://bad".into(),
        ])
        .is_err());
        assert!(parse_args(&[
            "--subdomain".into(),
            "acme".into(),
            "--name".into(),
            "Acme".into(),
            "--org".into(),
            "bad/org".into(),
        ])
        .is_err());
    }

    #[test]
    fn idempotent_already_installed_stops_after_first_get() {
        let mut client = FakeHttp::new(vec![resp(
            200,
            r#"[{"id":"7","name":"Vitruvian Software"}]"#,
        )]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute(&default_args(), &mut client, &mut out, &mut err);
        assert_eq!(code, 0);
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "already installed: id=7 name=Vitruvian Software\n"
        );
        assert!(err.is_empty());
        assert_eq!(client.calls.len(), 1);
        assert_eq!(client.calls[0].method, "GET");
        assert_eq!(
            client.calls[0].url,
            "https://sentry.lab.ipv1337.dev/api/0/organizations/sentry/integrations/?provider_key=pagerduty"
        );
    }

    #[test]
    fn full_four_step_install_succeeds_with_numeric_and_string_ids() {
        let mut args = default_args();
        args.url = "https://sentry.example.com/".into();
        args.org = "my-org".into();

        let mut client = FakeHttp::new(vec![
            resp(200, "[]"),
            resp(200, "{}"),
            resp(200, "{}"),
            resp(200, r#"[{"id":99,"name":"Vitruvian Software"}]"#),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute(&args, &mut client, &mut out, &mut err);
        assert_eq!(code, 0);
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "installed: id=99 name=Vitruvian Software\n"
        );
        assert!(err.is_empty());
        assert_eq!(
            client.calls,
            vec![
                RecordedCall {
                    method: "GET".into(),
                    url: "https://sentry.example.com/api/0/organizations/my-org/integrations/?provider_key=pagerduty".into(),
                    body: None,
                },
                RecordedCall {
                    method: "POST".into(),
                    url: "https://sentry.example.com/api/0/organizations/my-org/pipeline/integration_pipeline/".into(),
                    body: Some(r#"{"action":"initialize","provider":"pagerduty"}"#.into()),
                },
                RecordedCall {
                    method: "POST".into(),
                    url: "https://sentry.example.com/api/0/organizations/my-org/pipeline/integration_pipeline/".into(),
                    body: Some(r#"{"config":"{\"account\":{\"subdomain\":\"vitruviansoftware\",\"name\":\"Vitruvian Software\"},\"integration_keys\":[]}"}"#.into()),
                },
                RecordedCall {
                    method: "GET".into(),
                    url: "https://sentry.example.com/api/0/organizations/my-org/integrations/?provider_key=pagerduty".into(),
                    body: None,
                },
            ]
        );
    }

    #[test]
    fn step_four_missing_integration_fails() {
        let mut client = FakeHttp::new(vec![
            resp(200, "[]"),
            resp(200, "{}"),
            resp(200, "{}"),
            resp(200, "[]"),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute(&default_args(), &mut client, &mut out, &mut err);
        assert_ne!(code, 0);
        assert!(out.is_empty());
        assert!(String::from_utf8(err).unwrap().contains("still missing"));
    }

    #[test]
    fn step_two_403_explains_missing_org_integrations_scope() {
        let mut client = FakeHttp::new(vec![
            resp(200, "[]"),
            resp(
                403,
                r#"{"detail":"You do not have permission to perform this action."}"#,
            ),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();

        let code = execute(&default_args(), &mut client, &mut out, &mut err);
        assert_ne!(code, 0);
        assert!(out.is_empty());
        let err_str = String::from_utf8(err).unwrap();
        assert!(err_str.contains("403"), "{err_str}");
        assert!(
            err_str.contains("You do not have permission to perform this action."),
            "{err_str}"
        );
        assert!(err_str.contains("org:integrations"), "{err_str}");
    }

    #[test]
    fn error_paths_print_status_and_detail_across_all_steps() {
        // Step 1 non-2xx
        let mut client = FakeHttp::new(vec![resp(401, r#"{"detail":"Invalid token"}"#)]);
        let mut out = Vec::new();
        let mut err = Vec::new();
        assert_ne!(execute(&default_args(), &mut client, &mut out, &mut err), 0);
        let msg = String::from_utf8(err).unwrap();
        assert!(
            msg.contains("401") && msg.contains("Invalid token"),
            "{msg}"
        );

        // Step 3 non-2xx
        let mut client = FakeHttp::new(vec![
            resp(200, "[]"),
            resp(200, "{}"),
            resp(400, r#"{"detail":"Invalid config payload"}"#),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();
        assert_ne!(execute(&default_args(), &mut client, &mut out, &mut err), 0);
        let msg = String::from_utf8(err).unwrap();
        assert!(
            msg.contains("400") && msg.contains("Invalid config payload"),
            "{msg}"
        );

        // Step 4 non-2xx
        let mut client = FakeHttp::new(vec![
            resp(200, "[]"),
            resp(200, "{}"),
            resp(200, "{}"),
            resp(502, r#"{"detail":"Bad gateway"}"#),
        ]);
        let mut out = Vec::new();
        let mut err = Vec::new();
        assert_ne!(execute(&default_args(), &mut client, &mut out, &mut err), 0);
        let msg = String::from_utf8(err).unwrap();
        assert!(msg.contains("502") && msg.contains("Bad gateway"), "{msg}");
    }

    #[test]
    fn parse_integrations_rejects_non_array_and_missing_fields() {
        let non_array = parse_integrations(br#"{"id":"1","name":"PagerDuty"}"#).unwrap_err();
        assert!(non_array.contains("array"), "{non_array}");

        let missing_id = parse_integrations(br#"[{"name":"Vitruvian Software"}]"#).unwrap_err();
        assert!(missing_id.contains("id"), "{missing_id}");

        let missing_name = parse_integrations(br#"[{"id":"1"}]"#).unwrap_err();
        assert!(missing_name.contains("name"), "{missing_name}");
    }

    #[test]
    fn extract_detail_handles_nested_message_non_json_and_missing_detail() {
        assert_eq!(extract_detail(br#"{"detail":{"message":"x"}}"#), "x");
        assert_eq!(extract_detail(b"not valid json"), "<no detail>");
        assert_eq!(extract_detail(br#"{"error":"other"}"#), "<no detail>");
    }
}
