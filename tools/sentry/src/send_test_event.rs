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

//! Send a synthetic Sentry error event to prove Sentry → PagerDuty alerting
//! end to end.

use crate::http::{redact, HttpClient};
use serde::Serialize;
use std::collections::BTreeMap;
use std::fs::File;
use std::io::{Read, Write};
use std::time::{SystemTime, UNIX_EPOCH};

pub const SENTRY_CLIENT: &str = "vitruvian-send-test-event/1.0";
pub const SENTRY_USER_AGENT: &str = "sentry.rust/0.35.0";
pub const ENVELOPE_CONTENT_TYPE: &str = "application/x-sentry-envelope";

pub const USAGE: &str = "\
usage: bazel run //tools/sentry:send-test-event -- --dsn <DSN> [--level fatal] [--message <text>]

Send one synthetic Sentry error event with a unique fingerprint so Sentry creates
a new issue and triggers first-seen / PagerDuty alert rules end to end.
Resolve the created issue in Sentry afterwards.

Required:
  --dsn <DSN>              Sentry project DSN (https://<public_key>@<host>/<project_id>)

Options:
  --level <level>          Event severity: fatal|error|warning|info (default: fatal)
  --message <text>         Custom event message
  -h, --help               Show this help message and exit
";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum Level {
    #[default]
    Fatal,
    Error,
    Warning,
    Info,
}

impl Level {
    pub fn parse(raw: &str) -> Result<Self, String> {
        match raw {
            "fatal" => Ok(Self::Fatal),
            "error" => Ok(Self::Error),
            "warning" => Ok(Self::Warning),
            "info" => Ok(Self::Info),
            other => Err(format!(
                "--level '{other}' must be one of: fatal, error, warning, info"
            )),
        }
    }

    pub fn as_str(&self) -> &'static str {
        match self {
            Self::Fatal => "fatal",
            Self::Error => "error",
            Self::Warning => "warning",
            Self::Info => "info",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Dsn {
    pub raw: String,
    pub public_key: String,
    pub host: String,
    pub path_prefix: String,
    pub project_id: String,
}

fn valid_key_part(s: &str) -> bool {
    !s.is_empty()
        && s.bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
}

fn valid_host(host: &str) -> bool {
    if host.is_empty()
        || !host
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'-' | b':' | b'[' | b']'))
    {
        return false;
    }
    if let Some(after_open) = host.strip_prefix('[') {
        let Some((addr, rest)) = after_open.split_once(']') else {
            return false;
        };
        if addr.is_empty() {
            return false;
        }
        if rest.is_empty() {
            return true;
        }
        let Some(port) = rest.strip_prefix(':') else {
            return false;
        };
        return !port.is_empty()
            && port.bytes().all(|b| b.is_ascii_digit())
            && port.parse::<u16>().is_ok_and(|p| p > 0);
    }
    if let Some((name, port)) = host.split_once(':') {
        if name.is_empty() || port.contains(':') {
            return false;
        }
        return !port.is_empty()
            && port.bytes().all(|b| b.is_ascii_digit())
            && port.parse::<u16>().is_ok_and(|p| p > 0);
    }
    true
}

impl Dsn {
    pub fn parse(raw: &str) -> Result<Self, String> {
        // Never include `raw` or the public key in error messages so a malformed
        // DSN does not echo keys to logs or terminals.
        if raw.is_empty() {
            return Err("DSN cannot be empty".into());
        }
        if raw.chars().any(|c| c.is_control() || c.is_whitespace()) {
            return Err("DSN cannot contain whitespace or control characters".into());
        }
        if raw.contains('?') || raw.contains('#') {
            return Err("DSN cannot contain query parameters or fragments".into());
        }
        let Some(after_scheme) = raw.strip_prefix("https://") else {
            return Err("DSN must use https:// (cleartext http:// is rejected)".into());
        };
        let Some((userinfo, rest)) = after_scheme.split_once('@') else {
            return Err("DSN is missing '<public_key>@'".into());
        };
        if rest.contains('@') {
            return Err("DSN host/path cannot contain '@'".into());
        }
        let public_key = match userinfo.split_once(':') {
            Some((pk, sk)) => {
                if pk.is_empty() {
                    return Err("DSN is missing a public key before '@'".into());
                }
                if !valid_key_part(pk) || !valid_key_part(sk) {
                    return Err("DSN key contains invalid characters".into());
                }
                pk.to_string()
            }
            None => {
                if userinfo.is_empty() {
                    return Err("DSN is missing a public key before '@'".into());
                }
                if !valid_key_part(userinfo) {
                    return Err("DSN public key contains invalid characters".into());
                }
                userinfo.to_string()
            }
        };

        let Some((host, path)) = rest.split_once('/') else {
            return Err("DSN is missing '/<project_id>'".into());
        };
        if !valid_host(host) {
            return Err("DSN contains an invalid host or port".into());
        }
        if path.is_empty() || path.ends_with('/') {
            return Err("DSN is missing '/<project_id>'".into());
        }

        let segments: Vec<&str> = path.split('/').collect();
        for (idx, seg) in segments.iter().enumerate() {
            if seg.is_empty() || *seg == "." || *seg == ".." {
                return Err("DSN path contains empty or relative segments".into());
            }
            let is_last = idx + 1 == segments.len();
            let valid_seg = if is_last {
                seg.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-'))
            } else {
                seg.bytes()
                    .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'_' | b'-' | b'.'))
            };
            if !valid_seg {
                return Err(if is_last {
                    "DSN project_id contains invalid characters".into()
                } else {
                    "DSN path prefix contains invalid characters".into()
                });
            }
        }

        let project_id = segments[segments.len() - 1].to_string();
        let path_prefix = if segments.len() == 1 {
            String::new()
        } else {
            format!("/{}", segments[..segments.len() - 1].join("/"))
        };

        Ok(Self {
            raw: raw.to_string(),
            public_key,
            host: host.to_string(),
            path_prefix,
            project_id,
        })
    }

    pub fn envelope_url(&self) -> String {
        format!(
            "https://{}{}/api/{}/envelope/",
            self.host, self.path_prefix, self.project_id
        )
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SendArgs {
    pub dsn: Option<Dsn>,
    pub level: Level,
    pub message: Option<String>,
    pub help: bool,
}

pub fn parse_args(argv: &[String]) -> Result<SendArgs, String> {
    let mut dsn_raw: Option<String> = None;
    let mut level_raw: Option<String> = None;
    let mut message: Option<String> = None;
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
            "--dsn" => dsn_raw = Some(take_value()?),
            "--level" => level_raw = Some(take_value()?),
            "--message" => message = Some(take_value()?),
            other if other.starts_with('-') => return Err(format!("unknown argument: {other}")),
            other => return Err(format!("unexpected positional argument: {other}")),
        }
    }

    if help {
        return Ok(SendArgs {
            dsn: None,
            level: Level::Fatal,
            message,
            help: true,
        });
    }

    let dsn_str = dsn_raw.ok_or_else(|| "--dsn is required".to_string())?;
    let dsn = Dsn::parse(&dsn_str)?;
    let level = match level_raw {
        Some(raw) => Level::parse(&raw)?,
        None => Level::Fatal,
    };
    if let Some(ref msg) = message {
        if msg.trim().is_empty() {
            return Err("--message cannot be empty".into());
        }
    }

    Ok(SendArgs {
        dsn: Some(dsn),
        level,
        message,
        help: false,
    })
}

pub fn generate_event_id() -> Result<String, String> {
    let mut bytes = [0u8; 16];
    let mut f = File::open("/dev/urandom")
        .map_err(|e| format!("failed to open /dev/urandom for event_id: {e}"))?;
    f.read_exact(&mut bytes)
        .map_err(|e| format!("failed to read /dev/urandom for event_id: {e}"))?;
    let mut out = String::with_capacity(32);
    for b in bytes {
        use std::fmt::Write as _;
        let _ = write!(out, "{b:02x}");
    }
    Ok(out)
}

pub fn format_rfc3339_utc(time: SystemTime) -> Result<String, String> {
    let secs = time
        .duration_since(UNIX_EPOCH)
        .map_err(|e| format!("system clock is before UNIX_EPOCH: {e}"))?
        .as_secs();
    let days = (secs / 86_400) as i64;
    let rem = (secs % 86_400) as u32;
    let hour = rem / 3_600;
    let minute = (rem % 3_600) / 60;
    let second = rem % 60;

    // Howard Hinnant's civil-from-days algorithm in pure integer arithmetic.
    let z = days + 719_468;
    let era = if z >= 0 { z } else { z - 146_096 } / 146_097;
    let doe = (z - era * 146_097) as u64;
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365;
    let y = (yoe as i64) + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let day = doy - (153 * mp + 2) / 5 + 1;
    let month = if mp < 10 { mp + 3 } else { mp - 9 };
    let year = y + if month <= 2 { 1 } else { 0 };

    Ok(format!(
        "{year:04}-{month:02}-{day:02}T{hour:02}:{minute:02}:{second:02}Z"
    ))
}

#[derive(Serialize)]
struct EnvelopeHeader<'a> {
    event_id: &'a str,
    dsn: &'a str,
    sent_at: &'a str,
}

#[derive(Serialize)]
struct ItemHeader {
    #[serde(rename = "type")]
    item_type: &'static str,
}

#[derive(Serialize)]
struct EventMessage<'a> {
    formatted: &'a str,
}

#[derive(Serialize)]
struct EventPayload<'a> {
    event_id: &'a str,
    timestamp: &'a str,
    level: &'a str,
    platform: &'static str,
    logger: &'static str,
    message: EventMessage<'a>,
    fingerprint: [&'a str; 2],
    tags: BTreeMap<&'static str, &'static str>,
}

pub fn build_envelope(
    dsn: &Dsn,
    event_id: &str,
    sent_at: &str,
    level: Level,
    message: Option<&str>,
) -> String {
    let default_message =
        format!("PagerDuty test page from //tools/sentry:send-test-event at {sent_at}");
    let formatted_message = message.unwrap_or(&default_message);

    let line1 = serde_json::to_string(&EnvelopeHeader {
        event_id,
        dsn: &dsn.raw,
        sent_at,
    })
    .expect("envelope header serializes");

    let line2 =
        serde_json::to_string(&ItemHeader { item_type: "event" }).expect("item header serializes");

    let mut tags = BTreeMap::new();
    tags.insert("vitruvian.test", "pagerduty");

    let line3 = serde_json::to_string(&EventPayload {
        event_id,
        timestamp: sent_at,
        level: level.as_str(),
        platform: "other",
        logger: "vitruvian.send-test-event",
        message: EventMessage {
            formatted: formatted_message,
        },
        fingerprint: ["vitruvian-send-test-event", event_id],
        tags,
    })
    .expect("event payload serializes");

    format!("{line1}\n{line2}\n{line3}\n")
}

pub fn execute<C: HttpClient>(
    args: &SendArgs,
    event_id: &str,
    sent_at: &str,
    client: &mut C,
    out: &mut dyn Write,
    err: &mut dyn Write,
) -> i32 {
    let Some(dsn) = args.dsn.as_ref() else {
        let _ = writeln!(err, "send-test-event: --dsn is required");
        return 1;
    };
    let url = dsn.envelope_url();
    let envelope = build_envelope(dsn, event_id, sent_at, args.level, args.message.as_deref());

    let resp = match client.request("POST", &url, Some(&envelope)) {
        Ok(r) => r,
        Err(e) => {
            let _ = writeln!(err, "send-test-event: {e}");
            return 1;
        }
    };

    if (200..300).contains(&resp.status) {
        let _ = writeln!(
            out,
            "sent: event_id={event_id} project={} host={}",
            dsn.project_id, dsn.host
        );
        0
    } else {
        let raw_body = String::from_utf8_lossy(&resp.body);
        let safe_body = redact(raw_body.trim(), &dsn.public_key);
        let display = if safe_body.is_empty() {
            "<empty body>".to_string()
        } else {
            safe_body
        };
        let _ = writeln!(err, "send-test-event: HTTP {}: {display}", resp.status);
        1
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::http::Response;
    use serde_json::Value;
    use std::time::Duration;

    struct FakeHttp {
        calls: Vec<(String, String, Option<String>)>,
        response: Result<Response, String>,
    }

    impl FakeHttp {
        fn new(response: Result<Response, String>) -> Self {
            Self {
                calls: Vec::new(),
                response,
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
            self.calls
                .push((method.into(), url.into(), body.map(str::to_string)));
            self.response.clone()
        }
    }

    #[test]
    fn dsn_parse_handles_standard_and_path_prefix_and_ports() {
        let dsn = Dsn::parse("https://abc123def@sentry-ingest.ipv1337.dev/18").unwrap();
        assert_eq!(dsn.public_key, "abc123def");
        assert_eq!(dsn.host, "sentry-ingest.ipv1337.dev");
        assert_eq!(dsn.path_prefix, "");
        assert_eq!(dsn.project_id, "18");
        assert_eq!(
            dsn.envelope_url(),
            "https://sentry-ingest.ipv1337.dev/api/18/envelope/"
        );

        let prefixed =
            Dsn::parse("https://pub_key-1:sec_key@sentry.example.com:8443/prefix/sub/42").unwrap();
        assert_eq!(prefixed.public_key, "pub_key-1");
        assert_eq!(prefixed.host, "sentry.example.com:8443");
        assert_eq!(prefixed.path_prefix, "/prefix/sub");
        assert_eq!(prefixed.project_id, "42");
        assert_eq!(
            prefixed.envelope_url(),
            "https://sentry.example.com:8443/prefix/sub/api/42/envelope/"
        );
    }

    #[test]
    fn dsn_parse_rejects_http_and_malformed_inputs_without_leaking_key() {
        let key = "secret_pub_key_should_not_echo";

        let http_err = Dsn::parse(&format!("http://{key}@sentry.example.com/1")).unwrap_err();
        assert!(http_err.contains("https://"), "{http_err}");
        assert!(!http_err.contains(key), "key leaked: {http_err}");

        assert!(Dsn::parse("").is_err());
        assert!(Dsn::parse("https://sentry.example.com/1").is_err());
        assert!(Dsn::parse("https://@sentry.example.com/1").is_err());
        assert!(Dsn::parse(&format!("https://{key}@sentry.example.com")).is_err());
        assert!(Dsn::parse(&format!("https://{key}@sentry.example.com/")).is_err());
        assert!(Dsn::parse(&format!("https://{key}@sentry.example.com/1/")).is_err());
        assert!(Dsn::parse(&format!("https://{key}@sentry.example.com//1")).is_err());
        assert!(Dsn::parse(&format!("https://{key}@sentry.example.com/1?foo=bar")).is_err());
        assert!(Dsn::parse(&format!("https://{key}@sentry.example.com:0/1")).is_err());
    }

    #[test]
    fn parse_args_handles_help_defaults_and_validation() {
        let help = parse_args(&["--help".into()]).unwrap();
        assert!(help.help);

        let args = parse_args(&["--dsn=https://abc123@sentry.example.com/7".into()]).unwrap();
        assert!(!args.help);
        assert_eq!(args.level, Level::Fatal);
        assert!(args.message.is_none());
        assert_eq!(args.dsn.unwrap().project_id, "7");

        let custom = parse_args(&[
            "--dsn".into(),
            "https://abc123@sentry.example.com/7".into(),
            "--level".into(),
            "warning".into(),
            "--message".into(),
            "Custom test".into(),
        ])
        .unwrap();
        assert_eq!(custom.level, Level::Warning);
        assert_eq!(custom.message.as_deref(), Some("Custom test"));

        assert!(parse_args(&[]).is_err());
        assert!(parse_args(&[
            "--dsn".into(),
            "https://abc123@sentry.example.com/7".into(),
            "--level".into(),
            "debug".into(),
        ])
        .is_err());
        assert!(parse_args(&[
            "--dsn".into(),
            "https://abc123@sentry.example.com/7".into(),
            "--message".into(),
            "   ".into(),
        ])
        .is_err());
    }

    #[test]
    fn generate_event_id_produces_32_lowercase_hex_and_varies() {
        let a = generate_event_id().unwrap();
        let b = generate_event_id().unwrap();
        assert_eq!(a.len(), 32);
        assert!(a
            .bytes()
            .all(|c| c.is_ascii_digit() || (b'a'..=b'f').contains(&c)));
        assert_ne!(a, b);
    }

    #[test]
    fn format_rfc3339_utc_formats_epoch_leap_year_and_standard_dates() {
        assert_eq!(
            format_rfc3339_utc(UNIX_EPOCH).unwrap(),
            "1970-01-01T00:00:00Z"
        );
        // 2024-02-29T12:34:56Z = 1709210096
        assert_eq!(
            format_rfc3339_utc(UNIX_EPOCH + Duration::from_secs(1_709_210_096)).unwrap(),
            "2024-02-29T12:34:56Z"
        );
        // 2026-11-17T01:02:03Z = 1794877323
        assert_eq!(
            format_rfc3339_utc(UNIX_EPOCH + Duration::from_secs(1_794_877_323)).unwrap(),
            "2026-11-17T01:02:03Z"
        );
    }

    #[test]
    fn build_envelope_produces_three_valid_json_lines_with_expected_fields() {
        let dsn = Dsn::parse("https://abc123@sentry-ingest.ipv1337.dev/18").unwrap();
        let event_id = "0123456789abcdef0123456789abcdef";
        let sent_at = "2026-11-17T17:00:00Z";

        let env = build_envelope(&dsn, event_id, sent_at, Level::Fatal, None);
        let lines: Vec<&str> = env.lines().collect();
        assert_eq!(lines.len(), 3, "envelope must have 3 lines: {env}");

        let header: Value = serde_json::from_str(lines[0]).unwrap();
        assert_eq!(header["event_id"], event_id);
        assert_eq!(header["dsn"], dsn.raw);
        assert_eq!(header["sent_at"], sent_at);

        let item_header: Value = serde_json::from_str(lines[1]).unwrap();
        assert_eq!(item_header["type"], "event");

        let payload: Value = serde_json::from_str(lines[2]).unwrap();
        assert_eq!(payload["event_id"], event_id);
        assert_eq!(payload["timestamp"], sent_at);
        assert_eq!(payload["level"], "fatal");
        assert_eq!(payload["platform"], "other");
        assert_eq!(payload["logger"], "vitruvian.send-test-event");
        assert_eq!(
            payload["message"]["formatted"],
            "PagerDuty test page from //tools/sentry:send-test-event at 2026-11-17T17:00:00Z"
        );
        assert_eq!(
            payload["fingerprint"],
            serde_json::json!(["vitruvian-send-test-event", event_id])
        );
        assert_eq!(payload["tags"]["vitruvian.test"], "pagerduty");
    }

    #[test]
    fn execute_handles_2xx_and_non_2xx_responses() {
        let dsn = Dsn::parse("https://abc123@sentry-ingest.ipv1337.dev/18").unwrap();
        let event_id = "0123456789abcdef0123456789abcdef";
        let sent_at = "2026-11-17T17:00:00Z";

        let ok_args = SendArgs {
            dsn: Some(dsn.clone()),
            level: Level::Fatal,
            message: None,
            help: false,
        };
        let mut ok_client = FakeHttp::new(Ok(Response {
            status: 200,
            body: br#"{"id":"0123456789abcdef0123456789abcdef"}"#.to_vec(),
        }));
        let mut out = Vec::new();
        let mut err = Vec::new();
        let code = execute(
            &ok_args,
            event_id,
            sent_at,
            &mut ok_client,
            &mut out,
            &mut err,
        );
        assert_eq!(code, 0);
        assert_eq!(
            String::from_utf8(out).unwrap(),
            "sent: event_id=0123456789abcdef0123456789abcdef project=18 host=sentry-ingest.ipv1337.dev\n"
        );
        assert!(err.is_empty());
        assert_eq!(ok_client.calls.len(), 1);
        assert_eq!(ok_client.calls[0].0, "POST");
        assert_eq!(
            ok_client.calls[0].1,
            "https://sentry-ingest.ipv1337.dev/api/18/envelope/"
        );

        let bad_args = SendArgs {
            dsn: Some(dsn),
            level: Level::Error,
            message: Some("custom".into()),
            help: false,
        };
        let mut bad_client = FakeHttp::new(Ok(Response {
            status: 429,
            body: br#"{"detail":"rate limited abc123"}"#.to_vec(),
        }));
        let mut out = Vec::new();
        let mut err = Vec::new();
        let code = execute(
            &bad_args,
            event_id,
            sent_at,
            &mut bad_client,
            &mut out,
            &mut err,
        );
        assert_eq!(code, 1);
        assert!(out.is_empty());
        let err_str = String::from_utf8(err).unwrap();
        assert!(err_str.contains("HTTP 429"), "{err_str}");
        assert!(err_str.contains("rate limited <redacted>"), "{err_str}");
    }
}
