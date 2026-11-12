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

//! Pure logic for `relay-spike-client`, the spike's test client:
//! - **Spike B:** sign in the way the connector will, with Zitadel's device
//!   flow (RFC 8628): show a code, the person approves it in a browser, the
//!   client polls for a token.
//! - **Spike C:** hold `/connect` open for a day, reconnecting on drops and
//!   timing echo round trips.
//!
//! The network code is in `client_main.rs`; everything here is testable offline.

use serde_json::{json, Value};

pub const DEFAULT_ISSUER: &str = "https://auth.ipv1337.dev";
pub const DEFAULT_RELAY_URL: &str = "https://relay-spike.ipv1337.dev";
/// The `relay-connector` client (native app, device flow + refresh).
pub const DEFAULT_CLIENT_ID: &str = "398912442404505402";
/// The `relay` Zitadel project. Its id must be in the token's audience.
pub const DEFAULT_PROJECT_ID: &str = "398912441632687930";
pub const DEVICE_CODE_GRANT: &str = "urn:ietf:params:oauth:grant-type:device_code";

/// Refresh the access token when it has less than this long to live.
pub const REFRESH_MARGIN_SECS: u64 = 300;
/// Seconds between the client's own echo probes on `/connect`.
pub const PROBE_INTERVAL_SECS: u64 = 30;
/// A socket that has answered nothing (no echo, no server ping) for this long is dead.
pub const SILENCE_LIMIT_SECS: u64 = 90;
/// Longest wait between reconnect attempts.
pub const MAX_BACKOFF_SECS: u64 = 60;

/// The answer to a device authorization request.
#[derive(Debug, Clone, PartialEq)]
pub struct DeviceStart {
    pub device_code: String,
    pub user_code: String,
    pub verification_uri: String,
    pub verification_uri_complete: Option<String>,
    pub interval_secs: u64,
    pub expires_in_secs: u64,
}

fn str_field(body: &Value, key: &str) -> Option<String> {
    body.get(key)
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

pub fn parse_device_start(body: &Value) -> Result<DeviceStart, String> {
    let need = |k: &str| {
        str_field(body, k).ok_or_else(|| format!("device authorization answer has no {k}: {body}"))
    };
    Ok(DeviceStart {
        device_code: need("device_code")?,
        user_code: need("user_code")?,
        verification_uri: need("verification_uri")?,
        verification_uri_complete: str_field(body, "verification_uri_complete"),
        // RFC 8628 §3.2: the default polling interval is 5 seconds.
        interval_secs: body
            .get("interval")
            .and_then(Value::as_u64)
            .unwrap_or(5)
            .max(1),
        expires_in_secs: body
            .get("expires_in")
            .and_then(Value::as_u64)
            .unwrap_or(600),
    })
}

#[derive(Debug, Clone, PartialEq)]
pub struct Tokens {
    pub access_token: String,
    pub refresh_token: Option<String>,
    pub expires_at_unix: u64,
}

/// What one token request came back with.
#[derive(Debug, Clone, PartialEq)]
pub enum Poll {
    Done(Tokens),
    /// The person has not approved yet; ask again after the interval.
    Pending,
    /// Ask less often: add 5 seconds to the interval (RFC 8628 §3.5).
    SlowDown,
    Failed(String),
}

/// Reads a token endpoint answer, for the device grant and for refreshes.
pub fn parse_token_response(status: u16, body: &Value, now_unix: u64) -> Poll {
    if status == 200 {
        return match str_field(body, "access_token") {
            Some(access_token) => Poll::Done(Tokens {
                access_token,
                refresh_token: str_field(body, "refresh_token"),
                expires_at_unix: now_unix
                    + body
                        .get("expires_in")
                        .and_then(Value::as_u64)
                        .unwrap_or(3600),
            }),
            None => Poll::Failed(format!("token answer has no access_token: {body}")),
        };
    }
    match str_field(body, "error").as_deref() {
        Some("authorization_pending") => Poll::Pending,
        Some("slow_down") => Poll::SlowDown,
        Some(err) => Poll::Failed(match str_field(body, "error_description") {
            Some(desc) => format!("{err}: {desc}"),
            None => err.to_string(),
        }),
        None => Poll::Failed(format!("HTTP {status}: {body}")),
    }
}

pub fn needs_refresh(t: &Tokens, now_unix: u64) -> bool {
    now_unix + REFRESH_MARGIN_SECS >= t.expires_at_unix
}

pub fn tokens_to_json(t: &Tokens) -> Value {
    json!({
        "access_token": t.access_token,
        "refresh_token": t.refresh_token,
        "expires_at_unix": t.expires_at_unix,
    })
}

pub fn tokens_from_json(v: &Value) -> Result<Tokens, String> {
    Ok(Tokens {
        access_token: str_field(v, "access_token").ok_or("saved token has no access_token")?,
        refresh_token: str_field(v, "refresh_token"),
        expires_at_unix: v
            .get("expires_at_unix")
            .and_then(Value::as_u64)
            .ok_or("saved token has no expiry")?,
    })
}

/// The middle part of a JWT, still base64url. Errors if the token is not three parts.
pub fn jwt_payload_segment(token: &str) -> Result<&str, String> {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 || parts[1].is_empty() {
        return Err(format!("not a JWT: {} part(s)", parts.len()));
    }
    Ok(parts[1])
}

/// The claims spike B checks, from a decoded JWT payload.
#[derive(Debug, Clone, PartialEq)]
pub struct Claims {
    pub sub: Option<String>,
    pub azp: Option<String>,
    pub client_id: Option<String>,
    pub aud: Vec<String>,
    pub exp: Option<u64>,
}

pub fn claims_from_payload(payload: &Value) -> Claims {
    let aud = match payload.get("aud") {
        Some(Value::String(s)) => vec![s.clone()],
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(Value::as_str)
            .map(str::to_string)
            .collect(),
        _ => Vec::new(),
    };
    Claims {
        sub: str_field(payload, "sub"),
        azp: str_field(payload, "azp"),
        client_id: str_field(payload, "client_id"),
        aud,
        exp: payload.get("exp").and_then(Value::as_u64),
    }
}

/// Spike B's pass condition: a JWT issued to the connector, for the relay project.
pub fn check_claims(c: &Claims, client_id: &str, project_id: &str) -> Result<(), String> {
    let issued_to = c.azp.as_deref().or(c.client_id.as_deref());
    if issued_to != Some(client_id) {
        return Err(format!(
            "token was issued to {issued_to:?}, expected {client_id}"
        ));
    }
    if !c.aud.iter().any(|a| a == project_id) {
        return Err(format!(
            "audience {:?} does not include the relay project {project_id}",
            c.aud
        ));
    }
    if c.sub.is_none() {
        return Err("token has no subject".to_string());
    }
    Ok(())
}

/// Where to open the socket: scheme security, host and port, from the relay's origin.
#[derive(Debug, Clone, PartialEq)]
pub struct Endpoint {
    pub tls: bool,
    pub host: String,
    pub port: u16,
    /// `wss://host[:port]/connect` (or `ws://` for plain HTTP).
    pub url: String,
}

pub fn connect_endpoint(relay_url: &str) -> Result<Endpoint, String> {
    let trimmed = relay_url.trim_end_matches('/');
    let (tls, rest) = if let Some(r) = trimmed.strip_prefix("https://") {
        (true, r)
    } else if let Some(r) = trimmed.strip_prefix("http://") {
        (false, r)
    } else {
        return Err(format!(
            "relay URL must start with https:// or http://: {relay_url}"
        ));
    };
    if rest.is_empty() || rest.contains('/') {
        return Err(format!(
            "relay URL must be an origin with no path: {relay_url}"
        ));
    }
    let (host, port) = match rest.rsplit_once(':') {
        Some((h, p)) => (
            h,
            p.parse::<u16>()
                .map_err(|_| format!("bad port in {relay_url}"))?,
        ),
        None => (rest, if tls { 443 } else { 80 }),
    };
    if host.is_empty() {
        return Err(format!("relay URL has no host: {relay_url}"));
    }
    Ok(Endpoint {
        tls,
        host: host.to_string(),
        port,
        url: format!("{}://{rest}/connect", if tls { "wss" } else { "ws" }),
    })
}

/// Wait before reconnect attempt `attempt` (0-based): 1, 2, 4 … seconds, capped.
pub fn backoff_secs(attempt: u32) -> u64 {
    1u64.checked_shl(attempt)
        .unwrap_or(u64::MAX)
        .min(MAX_BACKOFF_SECS)
}

/// The text the client sends to time a round trip, and reads back from the echo.
pub fn probe_text(sent_ms: u128) -> String {
    format!("probe:{sent_ms}")
}

pub fn parse_probe(text: &str) -> Option<u128> {
    text.strip_prefix("probe:")?.parse().ok()
}

/// Spike C's running tally across every connection in one run.
#[derive(Debug, Default, Clone, PartialEq)]
pub struct HoldStats {
    pub connections: u32,
    /// Sessions that ended before the run's deadline.
    pub drops: u32,
    pub longest_secs: u64,
    pub connected_secs: u64,
    pub rtt_ms: Vec<u64>,
    /// Seconds from each drop to the next successful connection.
    pub reconnect_secs: Vec<u64>,
}

fn percentile(sorted: &[u64], p: f64) -> Option<u64> {
    if sorted.is_empty() {
        return None;
    }
    let idx = ((sorted.len() - 1) as f64 * p).round() as usize;
    Some(sorted[idx.min(sorted.len() - 1)])
}

impl HoldStats {
    pub fn record_session(&mut self, secs: u64, dropped: bool) {
        self.connections += 1;
        self.connected_secs += secs;
        self.longest_secs = self.longest_secs.max(secs);
        if dropped {
            self.drops += 1;
        }
    }

    pub fn summary(&self, run_secs: u64) -> Value {
        let mut rtt = self.rtt_ms.clone();
        rtt.sort_unstable();
        let mut gaps = self.reconnect_secs.clone();
        gaps.sort_unstable();
        json!({
            "run_secs": run_secs,
            "connected_secs": self.connected_secs,
            "connected_pct": if run_secs == 0 { 0.0 } else {
                (self.connected_secs as f64 * 1000.0 / run_secs as f64).round() / 10.0
            },
            "connections": self.connections,
            "drops": self.drops,
            "longest_secs": self.longest_secs,
            "reconnect_secs_max": gaps.last(),
            "probes": rtt.len(),
            "rtt_ms_p50": percentile(&rtt, 0.5),
            "rtt_ms_p95": percentile(&rtt, 0.95),
            "rtt_ms_max": rtt.last(),
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn device_start_reads_zitadels_answer_and_defaults_the_interval() {
        let body = json!({
            "device_code": "dc", "user_code": "ABCD-EFGH",
            "verification_uri": "https://auth.ipv1337.dev/device",
            "verification_uri_complete": "https://auth.ipv1337.dev/device?user_code=ABCD-EFGH",
            "expires_in": 300
        });
        let s = parse_device_start(&body).unwrap();
        assert_eq!(s.user_code, "ABCD-EFGH");
        assert_eq!(s.interval_secs, 5);
        assert_eq!(s.expires_in_secs, 300);
        assert!(s.verification_uri_complete.unwrap().ends_with("ABCD-EFGH"));
    }

    #[test]
    fn device_start_without_a_code_is_an_error() {
        let err =
            parse_device_start(&json!({"verification_uri": "x", "user_code": "u"})).unwrap_err();
        assert!(err.contains("device_code"), "{err}");
    }

    #[test]
    fn token_polls_map_rfc8628_errors() {
        assert_eq!(
            parse_token_response(400, &json!({"error": "authorization_pending"}), 0),
            Poll::Pending
        );
        assert_eq!(
            parse_token_response(400, &json!({"error": "slow_down"}), 0),
            Poll::SlowDown
        );
        assert_eq!(
            parse_token_response(
                400,
                &json!({"error": "access_denied", "error_description": "no"}),
                0
            ),
            Poll::Failed("access_denied: no".into())
        );
        assert!(
            matches!(parse_token_response(502, &json!(null), 0), Poll::Failed(m) if m.contains("502"))
        );
    }

    #[test]
    fn a_granted_token_gets_an_absolute_expiry() {
        let p = parse_token_response(
            200,
            &json!({"access_token": "a", "refresh_token": "r", "expires_in": 43200}),
            1000,
        );
        assert_eq!(
            p,
            Poll::Done(Tokens {
                access_token: "a".into(),
                refresh_token: Some("r".into()),
                expires_at_unix: 44200
            })
        );
    }

    #[test]
    fn refresh_starts_five_minutes_before_expiry() {
        let t = Tokens {
            access_token: "a".into(),
            refresh_token: None,
            expires_at_unix: 1000,
        };
        assert!(!needs_refresh(&t, 699));
        assert!(needs_refresh(&t, 700));
    }

    #[test]
    fn saved_tokens_round_trip() {
        let t = Tokens {
            access_token: "a".into(),
            refresh_token: Some("r".into()),
            expires_at_unix: 9,
        };
        assert_eq!(tokens_from_json(&tokens_to_json(&t)).unwrap(), t);
        let no_refresh = Tokens {
            refresh_token: None,
            ..t
        };
        assert_eq!(
            tokens_from_json(&tokens_to_json(&no_refresh)).unwrap(),
            no_refresh
        );
    }

    #[test]
    fn jwt_payload_needs_three_parts() {
        assert_eq!(jwt_payload_segment("h.p.s").unwrap(), "p");
        assert!(jwt_payload_segment("opaque-token").is_err());
        assert!(jwt_payload_segment("h..s").is_err());
    }

    #[test]
    fn claims_pass_only_for_the_connector_and_the_relay_project() {
        let good = claims_from_payload(&json!({
            "sub": "378818267051722263", "azp": DEFAULT_CLIENT_ID,
            "aud": [DEFAULT_PROJECT_ID, DEFAULT_CLIENT_ID], "exp": 5
        }));
        assert_eq!(
            check_claims(&good, DEFAULT_CLIENT_ID, DEFAULT_PROJECT_ID),
            Ok(())
        );

        let claude = Claims {
            azp: Some("398912442404439866".into()),
            ..good.clone()
        };
        assert!(check_claims(&claude, DEFAULT_CLIENT_ID, DEFAULT_PROJECT_ID)
            .unwrap_err()
            .contains("issued to"));

        let no_project = Claims {
            aud: vec![DEFAULT_CLIENT_ID.into()],
            ..good.clone()
        };
        assert!(
            check_claims(&no_project, DEFAULT_CLIENT_ID, DEFAULT_PROJECT_ID)
                .unwrap_err()
                .contains("audience")
        );

        // A string audience and a client_id claim instead of azp also count.
        let alt = claims_from_payload(
            &json!({"sub": "s", "client_id": DEFAULT_CLIENT_ID, "aud": DEFAULT_PROJECT_ID}),
        );
        assert_eq!(
            check_claims(&alt, DEFAULT_CLIENT_ID, DEFAULT_PROJECT_ID),
            Ok(())
        );
    }

    #[test]
    fn connect_endpoint_follows_the_scheme() {
        let e = connect_endpoint("https://relay-spike.ipv1337.dev/").unwrap();
        assert_eq!(
            (e.tls, e.host.as_str(), e.port),
            (true, "relay-spike.ipv1337.dev", 443)
        );
        assert_eq!(e.url, "wss://relay-spike.ipv1337.dev/connect");
        let local = connect_endpoint("http://127.0.0.1:3000").unwrap();
        assert_eq!(
            (local.tls, local.port, local.url.as_str()),
            (false, 3000, "ws://127.0.0.1:3000/connect")
        );
        assert!(connect_endpoint("relay-spike.ipv1337.dev").is_err());
        assert!(connect_endpoint("https://h/mcp").is_err());
        assert!(connect_endpoint("https://h:notaport").is_err());
    }

    #[test]
    fn backoff_doubles_and_caps() {
        assert_eq!(
            (0..8).map(backoff_secs).collect::<Vec<_>>(),
            vec![1, 2, 4, 8, 16, 32, 60, 60]
        );
        assert_eq!(backoff_secs(200), MAX_BACKOFF_SECS);
    }

    #[test]
    fn probes_round_trip_and_ignore_other_text() {
        assert_eq!(parse_probe(&probe_text(1794448869705)), Some(1794448869705));
        assert_eq!(parse_probe("hello"), None);
    }

    #[test]
    fn summary_counts_drops_and_rtt_percentiles() {
        let mut s = HoldStats::default();
        s.record_session(3600, true);
        s.record_session(82800, false);
        s.reconnect_secs.push(2);
        s.rtt_ms.extend([40, 10, 30, 20, 1000]);
        let v = s.summary(86400);
        assert_eq!(v["connections"], 2);
        assert_eq!(v["drops"], 1);
        assert_eq!(v["longest_secs"], 82800);
        assert_eq!(v["connected_pct"], 100.0);
        assert_eq!(v["rtt_ms_p50"], 30);
        assert_eq!(v["rtt_ms_max"], 1000);
        assert_eq!(v["reconnect_secs_max"], 2);
        assert_eq!(HoldStats::default().summary(0)["rtt_ms_p50"], Value::Null);
    }
}
