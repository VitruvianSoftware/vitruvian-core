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

//! `relay-spike-client`: the spike's test client. Blocking I/O on purpose;
//! it is one person's terminal tool, not the connector.
//!
//!   relay-spike-client login            spike B: device-flow sign-in, saves the token
//!   relay-spike-client whoami           decodes the saved token's claims
//!   relay-spike-client hold [--hours N] spike C: hold /connect open (default 24 h)
//!
//! Settings (all optional): RELAY_ISSUER, RELAY_URL, RELAY_CLIENT_ID,
//! RELAY_PROJECT_ID, RELAY_TOKEN_FILE (default ~/.config/relay-spike/token.json).
//! Output is one JSON object per line on stdout, like the server's log.

use mcp_slack_rs_lib::{auth::full_scope_string, base64, tls, url::encode_query_params};
use relay_spike::client::*;
use serde_json::{json, Value};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::path::PathBuf;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio_tungstenite::tungstenite::{
    self, client::IntoClientRequest, protocol::Message, Error as WsError,
};

struct Config {
    issuer: String,
    relay_url: String,
    client_id: String,
    project_id: String,
    token_file: PathBuf,
}

impl Config {
    fn from_env() -> Config {
        let get = |k: &str, d: &str| {
            std::env::var(k)
                .ok()
                .filter(|v| !v.is_empty())
                .unwrap_or_else(|| d.to_string())
        };
        let home = std::env::var("HOME").unwrap_or_else(|_| ".".to_string());
        Config {
            issuer: get("RELAY_ISSUER", DEFAULT_ISSUER)
                .trim_end_matches('/')
                .to_string(),
            relay_url: get("RELAY_URL", DEFAULT_RELAY_URL),
            client_id: get("RELAY_CLIENT_ID", DEFAULT_CLIENT_ID),
            project_id: get("RELAY_PROJECT_ID", DEFAULT_PROJECT_ID),
            token_file: PathBuf::from(get(
                "RELAY_TOKEN_FILE",
                &format!("{home}/.config/relay-spike/token.json"),
            )),
        }
    }
}

fn now_ms() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0)
}

fn now_unix() -> u64 {
    (now_ms() / 1000) as u64
}

fn log(event: &str, fields: Value) {
    let mut line = json!({"ts_ms": now_ms(), "event": event});
    if let (Some(obj), Some(extra)) = (line.as_object_mut(), fields.as_object()) {
        for (k, v) in extra {
            obj.insert(k.clone(), v.clone());
        }
    }
    println!("{line}");
    let _ = std::io::stdout().flush();
}

fn agent() -> ureq::Agent {
    ureq::AgentBuilder::new()
        .timeout(Duration::from_secs(30))
        .tls_config(tls::client_config())
        .user_agent("relay-spike-client")
        .build()
}

fn read_json(r: ureq::Response) -> Value {
    r.into_string()
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(Value::Null)
}

fn post_form(
    agent: &ureq::Agent,
    url: &str,
    params: &[(&str, String)],
) -> Result<(u16, Value), String> {
    match agent
        .post(url)
        .set("Content-Type", "application/x-www-form-urlencoded")
        .send_string(&encode_query_params(params))
    {
        Ok(r) => Ok((r.status(), read_json(r))),
        Err(ureq::Error::Status(code, r)) => Ok((code, read_json(r))),
        Err(e) => Err(format!("POST {url}: {e}")),
    }
}

struct Endpoints {
    device: String,
    token: String,
}

fn discover(agent: &ureq::Agent, issuer: &str) -> Result<Endpoints, String> {
    let url = format!("{issuer}/.well-known/openid-configuration");
    let doc = agent
        .get(&url)
        .call()
        .map(read_json)
        .map_err(|e| format!("GET {url}: {e}"))?;
    let field = |k: &str| {
        doc.get(k)
            .and_then(Value::as_str)
            .map(str::to_string)
            .ok_or_else(|| format!("{url} has no {k}"))
    };
    Ok(Endpoints {
        device: field("device_authorization_endpoint")?,
        token: field("token_endpoint")?,
    })
}

fn save_tokens(cfg: &Config, t: &Tokens) -> Result<(), String> {
    if let Some(dir) = cfg.token_file.parent() {
        std::fs::create_dir_all(dir).map_err(|e| format!("create {}: {e}", dir.display()))?;
    }
    let body = tokens_to_json(t).to_string();
    let tmp = cfg.token_file.with_extension("tmp");
    let mut opts = std::fs::OpenOptions::new();
    opts.write(true).create(true).truncate(true);
    #[cfg(unix)]
    {
        use std::os::unix::fs::OpenOptionsExt;
        opts.mode(0o600);
    }
    let mut f = opts
        .open(&tmp)
        .map_err(|e| format!("write {}: {e}", tmp.display()))?;
    f.write_all(body.as_bytes())
        .map_err(|e| format!("write {}: {e}", tmp.display()))?;
    std::fs::rename(&tmp, &cfg.token_file)
        .map_err(|e| format!("save {}: {e}", cfg.token_file.display()))
}

fn load_tokens(cfg: &Config) -> Result<Tokens, String> {
    let text = std::fs::read_to_string(&cfg.token_file).map_err(|e| {
        format!(
            "no saved token at {} ({e}); run `login` first",
            cfg.token_file.display()
        )
    })?;
    let v: Value =
        serde_json::from_str(&text).map_err(|e| format!("{}: {e}", cfg.token_file.display()))?;
    tokens_from_json(&v)
}

fn claims_of(token: &str) -> Result<Claims, String> {
    let segment = jwt_payload_segment(token)?;
    let payload: Value = serde_json::from_slice(&base64::decode_node(segment))
        .map_err(|e| format!("token payload is not JSON: {e}"))?;
    Ok(claims_from_payload(&payload))
}

/// Prints the claims and checks them. Never prints the token itself.
fn report_claims(cfg: &Config, token: &str) -> Result<(), String> {
    let c = claims_of(token)?;
    let verdict = check_claims(&c, &cfg.client_id, &cfg.project_id);
    log(
        "claims",
        json!({"sub": c.sub, "azp": c.azp, "client_id": c.client_id, "aud": c.aud, "exp": c.exp,
               "ok": verdict.is_ok(), "problem": verdict.as_ref().err()}),
    );
    verdict
}

fn login(cfg: &Config) -> Result<(), String> {
    let agent = agent();
    let ep = discover(&agent, &cfg.issuer)?;
    let (status, body) = post_form(
        &agent,
        &ep.device,
        &[
            ("client_id", cfg.client_id.clone()),
            ("scope", full_scope_string(&cfg.project_id)),
        ],
    )?;
    if status != 200 {
        return Err(format!(
            "device authorization refused (HTTP {status}): {body}"
        ));
    }
    let start = parse_device_start(&body)?;
    eprintln!();
    eprintln!(
        "  Open:  {}",
        start
            .verification_uri_complete
            .as_deref()
            .unwrap_or(&start.verification_uri)
    );
    eprintln!("  Code:  {}", start.user_code);
    eprintln!("  (expires in {} minutes)", start.expires_in_secs / 60);
    eprintln!();
    log(
        "device_code_issued",
        json!({"verification_uri": start.verification_uri, "user_code": start.user_code,
               "expires_in": start.expires_in_secs}),
    );

    let began = Instant::now();
    let mut interval = start.interval_secs;
    loop {
        if began.elapsed().as_secs() >= start.expires_in_secs {
            return Err("the code expired before it was approved".to_string());
        }
        std::thread::sleep(Duration::from_secs(interval));
        let (status, body) = post_form(
            &agent,
            &ep.token,
            &[
                ("grant_type", DEVICE_CODE_GRANT.to_string()),
                ("device_code", start.device_code.clone()),
                ("client_id", cfg.client_id.clone()),
            ],
        )?;
        match parse_token_response(status, &body, now_unix()) {
            Poll::Pending => {}
            Poll::SlowDown => interval += 5,
            Poll::Failed(why) => return Err(format!("sign-in failed: {why}")),
            Poll::Done(tokens) => {
                log(
                    "signed_in",
                    json!({"after_secs": began.elapsed().as_secs(), "has_refresh_token": tokens.refresh_token.is_some(),
                           "expires_at_unix": tokens.expires_at_unix}),
                );
                save_tokens(cfg, &tokens)?;
                return report_claims(cfg, &tokens.access_token);
            }
        }
    }
}

fn refresh(
    cfg: &Config,
    agent: &ureq::Agent,
    token_endpoint: &str,
    old: &Tokens,
) -> Result<Tokens, String> {
    let rt = old
        .refresh_token
        .clone()
        .ok_or("no refresh token saved; run `login` again")?;
    let (status, body) = post_form(
        agent,
        token_endpoint,
        &[
            ("grant_type", "refresh_token".to_string()),
            ("refresh_token", rt.clone()),
            ("client_id", cfg.client_id.clone()),
            ("scope", full_scope_string(&cfg.project_id)),
        ],
    )?;
    match parse_token_response(status, &body, now_unix()) {
        Poll::Done(mut t) => {
            // Zitadel may rotate the refresh token; keep the old one if it doesn't.
            t.refresh_token = t.refresh_token.or(Some(rt));
            save_tokens(cfg, &t)?;
            log("refreshed", json!({"expires_at_unix": t.expires_at_unix}));
            Ok(t)
        }
        other => Err(format!("refresh failed: {other:?}")),
    }
}

/// Plain TCP or TLS, so one socket loop serves both.
enum Stream {
    Plain(TcpStream),
    Tls(Box<rustls::StreamOwned<rustls::ClientConnection, TcpStream>>),
}

impl Stream {
    fn tcp(&self) -> &TcpStream {
        match self {
            Stream::Plain(s) => s,
            Stream::Tls(s) => &s.sock,
        }
    }
}

impl Read for Stream {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        match self {
            Stream::Plain(s) => s.read(buf),
            Stream::Tls(s) => s.read(buf),
        }
    }
}

impl Write for Stream {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        match self {
            Stream::Plain(s) => s.write(buf),
            Stream::Tls(s) => s.write(buf),
        }
    }
    fn flush(&mut self) -> std::io::Result<()> {
        match self {
            Stream::Plain(s) => s.flush(),
            Stream::Tls(s) => s.flush(),
        }
    }
}

fn open_socket(
    ep: &Endpoint,
    access_token: &str,
) -> Result<tungstenite::WebSocket<Stream>, String> {
    let tcp = TcpStream::connect((ep.host.as_str(), ep.port))
        .map_err(|e| format!("connect {}:{}: {e}", ep.host, ep.port))?;
    tcp.set_nodelay(true).ok();
    tcp.set_read_timeout(Some(Duration::from_secs(30))).ok();
    let stream = if ep.tls {
        let name = rustls::pki_types::ServerName::try_from(ep.host.clone())
            .map_err(|e| format!("server name: {e}"))?;
        let conn = rustls::ClientConnection::new(tls::client_config(), name)
            .map_err(|e| format!("TLS: {e}"))?;
        Stream::Tls(Box::new(rustls::StreamOwned::new(conn, tcp)))
    } else {
        Stream::Plain(tcp)
    };
    let mut request = ep
        .url
        .as_str()
        .into_client_request()
        .map_err(|e| format!("request: {e}"))?;
    request.headers_mut().insert(
        "Authorization",
        format!("Bearer {access_token}")
            .parse()
            .map_err(|_| "token is not a valid header value".to_string())?,
    );
    let (ws, _resp) = tungstenite::client(request, stream).map_err(|e| match e {
        tungstenite::HandshakeError::Failure(WsError::Http(resp)) => {
            format!("upgrade refused: HTTP {}", resp.status())
        }
        other => format!("handshake: {other}"),
    })?;
    // Short reads from here on, so the loop can send probes and notice silence.
    ws.get_ref()
        .tcp()
        .set_read_timeout(Some(Duration::from_secs(1)))
        .ok();
    Ok(ws)
}

/// One connection, until it drops or the deadline passes. Returns (reason, dropped).
fn run_session(
    mut ws: tungstenite::WebSocket<Stream>,
    deadline: Instant,
    stats: &mut HoldStats,
) -> (String, bool) {
    let mut last_probe = Instant::now()
        .checked_sub(Duration::from_secs(PROBE_INTERVAL_SECS))
        .unwrap_or_else(Instant::now);
    let mut last_heard = Instant::now();
    let mut server_pings = 0u64;
    loop {
        if Instant::now() >= deadline {
            let _ = ws.close(None);
            let _ = ws.flush();
            return ("run finished".to_string(), false);
        }
        if last_heard.elapsed().as_secs() >= SILENCE_LIMIT_SECS {
            return (format!("nothing heard for {SILENCE_LIMIT_SECS}s"), true);
        }
        if last_probe.elapsed().as_secs() >= PROBE_INTERVAL_SECS {
            last_probe = Instant::now();
            if let Err(e) = ws.send(Message::Text(probe_text(now_ms()))) {
                return (format!("probe send failed: {e}"), true);
            }
        }
        match ws.read() {
            Ok(Message::Text(t)) => {
                last_heard = Instant::now();
                if let Some(sent) = parse_probe(&t) {
                    let rtt = now_ms().saturating_sub(sent) as u64;
                    stats.rtt_ms.push(rtt);
                    // One line per ~10 minutes keeps a day's log readable.
                    if stats.rtt_ms.len() % 20 == 1 {
                        log(
                            "probe",
                            json!({"rtt_ms": rtt, "server_pings": server_pings}),
                        );
                    }
                }
            }
            Ok(Message::Ping(_)) => {
                last_heard = Instant::now();
                server_pings += 1;
            }
            Ok(Message::Close(frame)) => {
                return (
                    format!(
                        "server closed: {:?}",
                        frame.map(|f| (u16::from(f.code), f.reason.to_string()))
                    ),
                    true,
                )
            }
            Ok(_) => last_heard = Instant::now(),
            Err(WsError::Io(e))
                if matches!(
                    e.kind(),
                    std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                ) => {}
            Err(e) => return (format!("read: {e}"), true),
        }
    }
}

fn hold(cfg: &Config, hours: f64) -> Result<(), String> {
    let endpoint = connect_endpoint(&cfg.relay_url)?;
    let agent = agent();
    let token_endpoint = discover(&agent, &cfg.issuer)?.token;
    let mut tokens = load_tokens(cfg)?;
    let run_started = Instant::now();
    let deadline = run_started + Duration::from_secs_f64(hours * 3600.0);
    let mut stats = HoldStats::default();
    let mut failures = 0u32;
    let mut dropped_at: Option<Instant> = None;
    log("hold_start", json!({"url": endpoint.url, "hours": hours}));

    while Instant::now() < deadline {
        if needs_refresh(&tokens, now_unix()) {
            match refresh(cfg, &agent, &token_endpoint, &tokens) {
                Ok(t) => tokens = t,
                Err(e) => {
                    log("refresh_failed", json!({"error": e}));
                    std::thread::sleep(Duration::from_secs(backoff_secs(failures)));
                    failures += 1;
                    continue;
                }
            }
        }
        match open_socket(&endpoint, &tokens.access_token) {
            Ok(ws) => {
                failures = 0;
                if let Some(t) = dropped_at.take() {
                    stats.reconnect_secs.push(t.elapsed().as_secs());
                }
                let opened = Instant::now();
                log("connected", json!({"connection": stats.connections + 1}));
                let (reason, dropped) = run_session(ws, deadline, &mut stats);
                let secs = opened.elapsed().as_secs();
                stats.record_session(secs, dropped);
                log(
                    "disconnected",
                    json!({"after_secs": secs, "reason": reason, "dropped": dropped}),
                );
                if dropped {
                    dropped_at = Some(Instant::now());
                }
            }
            Err(e) => {
                log(
                    "connect_failed",
                    json!({"error": e, "attempt": failures + 1}),
                );
                std::thread::sleep(Duration::from_secs(backoff_secs(failures)));
                failures += 1;
            }
        }
    }
    log("summary", stats.summary(run_started.elapsed().as_secs()));
    Ok(())
}

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let cfg = Config::from_env();
    let result = match args.first().map(String::as_str) {
        Some("login") => login(&cfg),
        Some("whoami") => load_tokens(&cfg).and_then(|t| report_claims(&cfg, &t.access_token)),
        Some("hold") => {
            let hours = match args.iter().position(|a| a == "--hours") {
                Some(i) => match args
                    .get(i + 1)
                    .and_then(|h| h.parse::<f64>().ok())
                    .filter(|h| *h > 0.0)
                {
                    Some(h) => h,
                    None => {
                        eprintln!("--hours needs a positive number");
                        std::process::exit(2);
                    }
                },
                None => 24.0,
            };
            hold(&cfg, hours)
        }
        Some("--version") | Some("-V") => {
            println!("relay-spike-client {}", env!("CARGO_PKG_VERSION"));
            Ok(())
        }
        _ => {
            eprintln!("usage: relay-spike-client login | whoami | hold [--hours N]");
            std::process::exit(2);
        }
    };
    if let Err(e) = result {
        log("error", json!({"error": e}));
        std::process::exit(1);
    }
}
