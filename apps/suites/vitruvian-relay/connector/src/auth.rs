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

//! Sign-in against Zitadel (OAuth device flow, RFC 8628), token refresh, and
//! registering the device with the relay. Blocking I/O on purpose: it is one
//! person's terminal tool, and Task 8 calls these from a worker thread.
//! The device-flow parsing is the spike's (`spike/src/client.rs`).

use std::time::{Duration, Instant};

use serde_json::{json, Value};

use crate::config::{agent, Config, REFRESH_MARGIN_SECS};
use crate::state::{now_unix, save_tokens, str_field, DeviceInfo, Tokens};
use crate::Result;

pub const DEVICE_CODE_GRANT: &str = "urn:ietf:params:oauth:grant-type:device_code";
pub const SIGN_IN_AGAIN: &str = "sign in again: run `vrelay login`";

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

pub fn parse_device_start(body: &Value) -> Result<DeviceStart> {
    let need = |k: &str| {
        str_field(body, k).ok_or_else(|| format!("device authorization answer has no {k}"))
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
/// Error text never includes the body, which could hold a token.
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
            None => Poll::Failed("token answer has no access_token".into()),
        };
    }
    match str_field(body, "error").as_deref() {
        Some("authorization_pending") => Poll::Pending,
        Some("slow_down") => Poll::SlowDown,
        Some(err) => Poll::Failed(match str_field(body, "error_description") {
            Some(desc) => format!("{err}: {desc}"),
            None => err.to_string(),
        }),
        None => Poll::Failed(format!("HTTP {status}")),
    }
}

pub fn needs_refresh(t: &Tokens, now_unix: u64) -> bool {
    now_unix + REFRESH_MARGIN_SECS >= t.expires_at_unix
}

fn encode_form(params: &[(&str, &str)]) -> String {
    fn enc(s: &str) -> String {
        let mut out = String::new();
        for b in s.bytes() {
            match b {
                b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                    out.push(b as char)
                }
                _ => out.push_str(&format!("%{b:02X}")),
            }
        }
        out
    }
    params
        .iter()
        .map(|(k, v)| format!("{}={}", enc(k), enc(v)))
        .collect::<Vec<_>>()
        .join("&")
}

fn read_json(r: ureq::Response) -> Value {
    r.into_string()
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or(Value::Null)
}

fn post_form(agent: &ureq::Agent, url: &str, params: &[(&str, &str)]) -> Result<(u16, Value)> {
    match agent
        .post(url)
        .set("Content-Type", "application/x-www-form-urlencoded")
        .send_string(&encode_form(params))
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

fn discover(agent: &ureq::Agent, issuer: &str) -> Result<Endpoints> {
    let url = format!("{issuer}/.well-known/openid-configuration");
    let doc = agent
        .get(&url)
        .call()
        .map(read_json)
        .map_err(|e| format!("GET {url}: {e}"))?;
    let field = |k: &str| str_field(&doc, k).ok_or_else(|| format!("{url} has no {k}"));
    Ok(Endpoints {
        device: field("device_authorization_endpoint")?,
        token: field("token_endpoint")?,
    })
}

/// Device-flow sign-in: prints a code, waits while the person approves it in a
/// browser, returns the tokens. The caller saves them.
pub fn login(cfg: &Config) -> Result<Tokens> {
    let agent = agent();
    let ep = discover(&agent, &cfg.issuer)?;
    let scope = cfg.scope();
    let (status, body) = post_form(
        &agent,
        &ep.device,
        &[("client_id", &cfg.client_id), ("scope", &scope)],
    )?;
    if status != 200 {
        return Err(format!("device authorization refused (HTTP {status})"));
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

    let began = Instant::now();
    let mut interval = start.interval_secs;
    loop {
        if began.elapsed().as_secs() >= start.expires_in_secs {
            return Err("the code expired before it was approved".into());
        }
        std::thread::sleep(Duration::from_secs(interval));
        let (status, body) = post_form(
            &agent,
            &ep.token,
            &[
                ("grant_type", DEVICE_CODE_GRANT),
                ("device_code", &start.device_code),
                ("client_id", &cfg.client_id),
            ],
        )?;
        match parse_token_response(status, &body, now_unix()) {
            Poll::Pending => {}
            Poll::SlowDown => interval += 5,
            Poll::Failed(why) => return Err(format!("sign-in failed: {why}")),
            Poll::Done(tokens) => return Ok(tokens),
        }
    }
}

/// Why a refresh did not give a token.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RefreshError {
    /// The sign-in is over: no refresh token is saved, or the token endpoint
    /// answered and said no (HTTP 400/401: revoked, expired, invalid). Only
    /// `vrelay login` fixes it, so asking again is pointless.
    Rejected(String),
    /// The issuer could not be reached or failed (network, discovery, 5xx).
    /// Worth trying again later.
    Unavailable(String),
}

impl std::fmt::Display for RefreshError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            RefreshError::Rejected(e) | RefreshError::Unavailable(e) => {
                write!(f, "{SIGN_IN_AGAIN} ({e})")
            }
        }
    }
}

fn refresh_once(
    cfg: &Config,
    agent: &ureq::Agent,
    endpoints: &mut Option<Endpoints>,
    rt: &str,
) -> std::result::Result<Tokens, RefreshError> {
    // Discovered once per `fresh_token` call; a failed discovery is tried again.
    if endpoints.is_none() {
        *endpoints = Some(discover(agent, &cfg.issuer).map_err(RefreshError::Unavailable)?);
    }
    let token_endpoint = &endpoints.as_ref().expect("set above").token;
    let scope = cfg.scope();
    let (status, body) = post_form(
        agent,
        token_endpoint,
        &[
            ("grant_type", "refresh_token"),
            ("refresh_token", rt),
            ("client_id", &cfg.client_id),
            ("scope", &scope),
        ],
    )
    .map_err(RefreshError::Unavailable)?;
    match parse_token_response(status, &body, now_unix()) {
        Poll::Done(mut t) => {
            // Zitadel may rotate the refresh token; keep the old one if it doesn't.
            t.refresh_token = t.refresh_token.or_else(|| Some(rt.to_string()));
            Ok(t)
        }
        Poll::Failed(why) if status == 400 || status == 401 => Err(RefreshError::Rejected(why)),
        Poll::Failed(why) => Err(RefreshError::Unavailable(why)),
        Poll::Pending | Poll::SlowDown => Err(RefreshError::Unavailable(
            "unexpected answer to a refresh".into(),
        )),
    }
}

/// An access token good for at least five more minutes. Refreshes (and saves
/// the result) when the current one is nearly expired. A failed refresh is
/// tried once more after `cfg.retry_delay` (P0: one failed on a connection
/// reset and worked a second later); a second failure says to sign in again.
/// With no refresh token saved there is nothing to retry, so it says so at once.
/// If the refreshed token cannot be saved, the good token is still returned
/// and a warning (never the token) goes to stderr.
pub fn fresh_token(cfg: &Config, tokens: &mut Tokens) -> Result<String> {
    fresh_token_checked(cfg, tokens).map_err(|e| e.to_string())
}

/// [`fresh_token`], saying whether the sign-in is over ([`RefreshError::Rejected`],
/// decided by the last attempt) or the issuer was out of reach.
pub fn fresh_token_checked(
    cfg: &Config,
    tokens: &mut Tokens,
) -> std::result::Result<String, RefreshError> {
    fresh_token_checked_from(cfg, tokens, None)
}

/// [`fresh_token_checked`] for `tokens` read from `before`, the bytes of
/// saved sign-in they came from: the result is saved only while the file
/// still holds exactly those (a logout or a new login since is never
/// undone). `None`: read the file now.
pub fn fresh_token_checked_from(
    cfg: &Config,
    tokens: &mut Tokens,
    before: Option<&[u8]>,
) -> std::result::Result<String, RefreshError> {
    if !needs_refresh(tokens, now_unix()) {
        return Ok(tokens.access_token.clone());
    }
    let rt = tokens
        .refresh_token
        .clone()
        .ok_or_else(|| RefreshError::Rejected("no refresh token saved".into()))?;
    // What the refresh starts from: its result is saved only over this.
    // (A file that cannot be read at all is not a sign-out: the result is
    // used, and saving it is tried as before.)
    let before = match before {
        Some(b) => Some(Some(b.to_vec())),
        None => match crate::state::load_token_bytes(&cfg.dir) {
            Ok(Some(b)) => Some(Some(b)),
            Ok(None) => None,
            Err(_) => Some(None),
        },
    };
    let agent = agent();
    let mut endpoints = None;
    let fresh = match refresh_once(cfg, &agent, &mut endpoints, &rt) {
        Ok(t) => t,
        Err(_) => {
            std::thread::sleep(cfg.retry_delay);
            refresh_once(cfg, &agent, &mut endpoints, &rt)?
        }
    };
    // Signed out (or in again) while the refresh was out: this result is
    // not the current sign-in's, so it is dropped and never written.
    let gone = || {
        RefreshError::Rejected("signed out on this Mac while the token was being refreshed".into())
    };
    let saved = match before.ok_or_else(gone)? {
        Some(b) => crate::state::save_tokens_if_unchanged(&cfg.dir, &b, &fresh),
        None => save_tokens(&cfg.dir, &fresh).map(|()| true),
    };
    match saved {
        Ok(true) => {}
        Ok(false) => return Err(gone()),
        Err(e) => eprintln!("vrelay: warning: could not save the refreshed token: {e}"),
    }
    *tokens = fresh;
    Ok(tokens.access_token.clone())
}

/// `POST /devices`: tells the relay this device's public key and learns the
/// device id and the MCP URL. With `device_id` (the one this Mac was given
/// when it first signed in) the relay keeps that id and replaces the key;
/// without one it registers a new computer. `name` is what the person sees
/// in their list; without one the relay keeps the old name (or "My Mac").
pub fn register_device(
    cfg: &Config,
    access_token: &str,
    public_key_b64: &str,
    device_id: Option<&str>,
    name: Option<&str>,
) -> Result<DeviceInfo> {
    let url = format!("{}/devices", cfg.relay_url);
    let mut body = json!({"public_key": public_key_b64});
    if let Some(id) = device_id {
        body["device_id"] = json!(id);
    }
    if let Some(name) = name {
        body["name"] = json!(name);
    }
    let resp = agent()
        .post(&url)
        .set("Authorization", &format!("Bearer {access_token}"))
        .set("Content-Type", "application/json")
        .send_string(&body.to_string());
    let body = match resp {
        Ok(r) => read_json(r),
        // The relay's own words for a full list (and only for that): they
        // say what to do. Any other body stays out of the message.
        Err(ureq::Error::Status(409, r)) => {
            let said = read_json(r);
            return Err(str_field(&said, "error")
                .filter(|m| m.chars().count() <= 300)
                .unwrap_or_else(|| "the relay refused the device (HTTP 409)".into()));
        }
        Err(ureq::Error::Status(403, _)) => {
            return Err(
                "the relay did not let this account in (HTTP 403). The relay is \
                 invite-only: ask whoever runs it to give you access, then run \
                 `vrelay login` again."
                    .into(),
            )
        }
        Err(ureq::Error::Status(code, _)) => {
            return Err(format!("the relay refused the device (HTTP {code})"))
        }
        Err(e) => return Err(format!("POST {url}: {e}")),
    };
    Ok(DeviceInfo {
        device_id: str_field(&body, "device_id").ok_or("the relay's answer has no device_id")?,
        mcp_url: str_field(&body, "mcp_url").ok_or("the relay's answer has no mcp_url")?,
    })
}

/// What this Mac calls itself in System Settings (`scutil --get
/// ComputerName`): the name `vrelay login` registers it under unless
/// `--name` says otherwise. `None` where there is no `scutil` or it has no
/// name, and the relay then says "My Mac".
pub fn computer_name() -> Option<String> {
    let out = std::process::Command::new("scutil")
        .args(["--get", "ComputerName"])
        .stdin(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let name = String::from_utf8(out.stdout).ok()?;
    let name = name.trim();
    (!name.is_empty()).then(|| name.to_string())
}

/// The arguments after `vrelay login`: `--name <name>` (or `--name=<name>`)
/// is the only one. `Some(name)` if given.
pub fn parse_login_args(args: &[String]) -> Result<Option<String>> {
    const USAGE: &str = "usage: vrelay login [--name <name for this computer>]";
    let mut name = None;
    let mut rest = args.iter();
    while let Some(arg) = rest.next() {
        let value = if arg == "--name" {
            rest.next().ok_or(USAGE)?.as_str()
        } else if let Some(v) = arg.strip_prefix("--name=") {
            v
        } else {
            return Err(USAGE.into());
        };
        if value.trim().is_empty() {
            return Err("the name for this computer cannot be empty. \
                 Use `vrelay login --name \"Studio Mac\"`."
                .into());
        }
        if name.replace(value.to_string()).is_some() {
            return Err(USAGE.into());
        }
    }
    Ok(name)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::state::{load_tokens, test_dir, token_path};
    use std::io::{Read, Write};
    use std::net::TcpListener;
    use std::os::unix::fs::PermissionsExt;
    use std::sync::{Arc, Mutex};

    type Handler = dyn FnMut(&str, &str, &str, &str) -> (u16, String) + Send;

    /// A tiny HTTP server: calls `handler(method, path, head, body)` per request;
    /// `head` is the request line and headers, lowercased.
    /// Returns its base URL.
    fn fake_server(handler: Box<Handler>) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let handler = Arc::new(Mutex::new(handler));
        std::thread::spawn(move || {
            for stream in listener.incoming() {
                let Ok(mut s) = stream else { continue };
                let handler = handler.clone();
                std::thread::spawn(move || {
                    let mut buf = Vec::new();
                    let mut chunk = [0u8; 4096];
                    let (head_end, len) = loop {
                        let n = s.read(&mut chunk).unwrap_or(0);
                        if n == 0 {
                            return;
                        }
                        buf.extend_from_slice(&chunk[..n]);
                        if let Some(p) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
                            let head = String::from_utf8_lossy(&buf[..p]).to_lowercase();
                            let len = head
                                .lines()
                                .find_map(|l| l.strip_prefix("content-length:"))
                                .and_then(|v| v.trim().parse::<usize>().ok())
                                .unwrap_or(0);
                            break (p + 4, len);
                        }
                    };
                    while buf.len() < head_end + len {
                        let n = s.read(&mut chunk).unwrap_or(0);
                        if n == 0 {
                            break;
                        }
                        buf.extend_from_slice(&chunk[..n]);
                    }
                    let head = String::from_utf8_lossy(&buf[..head_end]).to_string();
                    let mut first = head.lines().next().unwrap_or("").split(' ');
                    let (method, path) = (first.next().unwrap_or(""), first.next().unwrap_or(""));
                    let body = String::from_utf8_lossy(&buf[head_end..]).to_string();
                    let (status, out) =
                        (handler.lock().unwrap())(method, path, &head.to_lowercase(), &body);
                    let _ = write!(
                        s,
                        "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{out}",
                        out.len()
                    );
                });
            }
        });
        base
    }

    fn cfg_for(base: &str, dir: std::path::PathBuf) -> Config {
        Config {
            issuer: base.to_string(),
            relay_url: base.to_string(),
            client_id: "client".into(),
            project_id: "proj".into(),
            claude_client_id: "claude".into(),
            log_dir: dir.join("logs"),
            home: dir.clone(),
            dir,
            retry_delay: Duration::from_millis(10),
        }
    }

    fn discovery(base: &str) -> String {
        json!({
            "device_authorization_endpoint": format!("{base}/device"),
            "token_endpoint": format!("{base}/token"),
        })
        .to_string()
    }

    /// Serves discovery and a scripted sequence of token answers; counts token calls.
    fn token_server(
        answers: Vec<(u16, String)>,
    ) -> (
        String,
        Arc<Mutex<Vec<String>>>,
        Arc<std::sync::atomic::AtomicUsize>,
    ) {
        let discoveries = Arc::new(std::sync::atomic::AtomicUsize::new(0));
        let disc = discoveries.clone();
        let calls = Arc::new(Mutex::new(Vec::<String>::new()));
        let seen = calls.clone();
        let answers = Mutex::new(answers.into_iter());
        let base = Arc::new(Mutex::new(String::new()));
        let base2 = base.clone();
        let url = fake_server(Box::new(move |_m, path, _h, body| {
            if path == "/.well-known/openid-configuration" {
                disc.fetch_add(1, std::sync::atomic::Ordering::SeqCst);
                return (200, discovery(&base2.lock().unwrap()));
            }
            assert_eq!(path, "/token");
            seen.lock().unwrap().push(body.to_string());
            answers
                .lock()
                .unwrap()
                .next()
                .expect("more token calls than scripted")
        }));
        *base.lock().unwrap() = url.clone();
        (url, calls, discoveries)
    }

    fn near_expiry() -> Tokens {
        Tokens {
            access_token: "old-access".into(),
            refresh_token: Some("old-refresh".into()),
            expires_at_unix: now_unix() + 10,
        }
    }

    /// Coordinator's off-switch item 2: `vrelay logout` while the agent is
    /// mid-refresh. The refresh must not write `token.json` back (that
    /// would undo the logout), nor overwrite a newer sign-in made
    /// meanwhile; it says the sign-in is over instead.
    #[test]
    fn a_logout_during_a_refresh_is_not_undone() {
        for login_again in [false, true] {
            let dir = test_dir(if login_again {
                "auth-race-relogin"
            } else {
                "auth-race-logout"
            });
            let (at_tx, at_rx) = std::sync::mpsc::channel::<()>();
            let (go_tx, go_rx) = std::sync::mpsc::channel::<()>();
            let go_rx = Mutex::new(go_rx);
            let base = Arc::new(Mutex::new(String::new()));
            let b2 = base.clone();
            let url = fake_server(Box::new(move |_m, path, _h, _b| {
                if path == "/.well-known/openid-configuration" {
                    return (200, discovery(&b2.lock().unwrap()));
                }
                // The injected pause: the refresh is in flight here.
                let _ = at_tx.send(());
                let _ = go_rx.lock().unwrap().recv();
                ok_answer()
            }));
            *base.lock().unwrap() = url.clone();
            let cfg = cfg_for(&url, dir.clone());
            save_tokens(&dir, &near_expiry()).unwrap();
            let c = cfg.clone();
            let refresh = std::thread::spawn(move || {
                let mut t = load_tokens(&c.dir).unwrap().unwrap();
                fresh_token_checked(&c, &mut t)
            });
            at_rx.recv().unwrap();
            crate::state::clear_sign_in(&dir).unwrap();
            let newer = Tokens {
                access_token: "newer-login".into(),
                refresh_token: Some("newer-refresh".into()),
                expires_at_unix: now_unix() + 3600,
            };
            if login_again {
                save_tokens(&dir, &newer).unwrap();
            }
            go_tx.send(()).unwrap();
            let r = refresh.join().unwrap();
            assert!(matches!(r, Err(RefreshError::Rejected(_))), "{r:?}");
            if login_again {
                assert_eq!(load_tokens(&dir).unwrap(), Some(newer));
            } else {
                assert!(
                    crate::state::load_token_bytes(&dir).unwrap().is_none(),
                    "the logout was undone"
                );
            }
        }
    }

    /// Last review L1, second window: the refresh is given the very bytes
    /// its tokens were read from. A login that replaced `token.json` after
    /// they were read is never overwritten by the old session's refresh.
    #[test]
    fn a_refresh_saves_only_over_the_bytes_it_was_given() {
        let (base, _calls, _) = token_server(vec![ok_answer()]);
        let dir = test_dir("auth-before-bytes");
        save_tokens(&dir, &near_expiry()).unwrap();
        let read = crate::state::load_token_bytes(&dir).unwrap().unwrap();
        let newer = Tokens {
            access_token: "newer-login".into(),
            refresh_token: Some("newer-refresh".into()),
            expires_at_unix: now_unix() + 3600,
        };
        save_tokens(&dir, &newer).unwrap();
        let mut t = near_expiry();
        let r = fresh_token_checked_from(&cfg_for(&base, dir.clone()), &mut t, Some(&read));
        assert!(matches!(r, Err(RefreshError::Rejected(_))), "{r:?}");
        assert_eq!(load_tokens(&dir).unwrap(), Some(newer));
    }

    fn ok_answer() -> (u16, String) {
        (
            200,
            json!({"access_token": "new-access", "expires_in": 3600}).to_string(),
        )
    }

    #[test]
    fn fresh_token_does_not_call_the_network_when_valid() {
        let (base, calls, _) = token_server(vec![]);
        let dir = test_dir("fresh-valid");
        let mut t = Tokens {
            access_token: "still-good".into(),
            refresh_token: Some("r".into()),
            expires_at_unix: now_unix() + 3600,
        };
        assert_eq!(
            fresh_token(&cfg_for(&base, dir), &mut t).unwrap(),
            "still-good"
        );
        assert!(calls.lock().unwrap().is_empty());
    }

    #[test]
    fn fresh_token_refreshes_near_expiry() {
        let (base, calls, _) = token_server(vec![ok_answer()]);
        let dir = test_dir("fresh-near");
        let mut t = near_expiry();
        save_tokens(&dir, &t).unwrap();
        let got = fresh_token(&cfg_for(&base, dir.clone()), &mut t).unwrap();
        assert_eq!(got, "new-access");
        let calls = calls.lock().unwrap();
        assert_eq!(calls.len(), 1);
        assert!(
            calls[0].contains("grant_type=refresh_token"),
            "{}",
            calls[0]
        );
        assert!(
            calls[0].contains("refresh_token=old-refresh"),
            "{}",
            calls[0]
        );
        // The old refresh token is kept when the answer has none, and the result is saved 0600.
        assert_eq!(t.refresh_token.as_deref(), Some("old-refresh"));
        assert_eq!(
            load_tokens(&dir).unwrap().unwrap().access_token,
            "new-access"
        );
        let mode = std::fs::metadata(token_path(&dir))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(mode, 0o600);
    }

    #[test]
    fn fresh_token_retries_once_then_asks_to_sign_in() {
        // Fails once, then works: the retry rescues it.
        let (base, calls, _) = token_server(vec![(500, "{}".into()), ok_answer()]);
        let mut t = near_expiry();
        let dir = test_dir("fresh-retry-ok");
        save_tokens(&dir, &t).unwrap();
        assert_eq!(
            fresh_token(&cfg_for(&base, dir), &mut t).unwrap(),
            "new-access"
        );
        assert_eq!(calls.lock().unwrap().len(), 2);

        // Fails twice: exactly two attempts, then "sign in again".
        let (base, calls, discoveries) = token_server(vec![
            (400, json!({"error": "invalid_grant"}).to_string()),
            (500, "{}".into()),
        ]);
        let mut t = near_expiry();
        let dir = test_dir("fresh-retry-fail");
        let err = fresh_token(&cfg_for(&base, dir), &mut t).unwrap_err();
        assert!(err.starts_with("sign in again"), "{err}");
        assert_eq!(calls.lock().unwrap().len(), 2);
        // The discovery document is fetched once, not again for the retry.
        assert_eq!(discoveries.load(std::sync::atomic::Ordering::SeqCst), 1);
        assert_eq!(t.access_token, "old-access");
    }

    #[test]
    fn a_rejected_refresh_is_told_apart_from_an_outage() {
        let no = || (400, json!({"error": "invalid_grant"}).to_string());
        let check = |answers: Vec<(u16, String)>, name: &str| {
            let (base, _, _) = token_server(answers);
            fresh_token_checked(&cfg_for(&base, test_dir(name)), &mut near_expiry()).unwrap_err()
        };
        // The token endpoint says no: the sign-in is over.
        let e = check(vec![no(), no()], "rej-400");
        assert!(matches!(e, RefreshError::Rejected(_)), "{e:?}");
        assert!(e.to_string().starts_with("sign in again"), "{e}");
        let e = check(
            vec![
                (500, "{}".into()),
                (401, json!({"error": "invalid_client"}).to_string()),
            ],
            "rej-401",
        );
        assert!(matches!(e, RefreshError::Rejected(_)), "{e:?}");
        // A server error on the last try is an outage, not a sign-out.
        let e = check(vec![no(), (503, "{}".into())], "rej-503");
        assert!(matches!(e, RefreshError::Unavailable(_)), "{e:?}");
        // Nobody listening.
        let e = fresh_token_checked(
            &cfg_for("http://127.0.0.1:1", test_dir("rej-down")),
            &mut near_expiry(),
        )
        .unwrap_err();
        assert!(matches!(e, RefreshError::Unavailable(_)), "{e:?}");
        // No refresh token: nothing to retry, ever.
        let mut t = near_expiry();
        t.refresh_token = None;
        let e = fresh_token_checked(&cfg_for("http://127.0.0.1:1", test_dir("rej-none")), &mut t)
            .unwrap_err();
        assert!(matches!(e, RefreshError::Rejected(_)), "{e:?}");
    }

    #[test]
    fn no_refresh_token_fails_at_once_without_retry_or_network() {
        let (base, calls, discoveries) = token_server(vec![]);
        let mut cfg = cfg_for(&base, test_dir("fresh-norefresh"));
        cfg.retry_delay = Duration::from_secs(3);
        let mut t = near_expiry();
        t.refresh_token = None;
        let began = Instant::now();
        let err = fresh_token(&cfg, &mut t).unwrap_err();
        assert!(err.starts_with("sign in again"), "{err}");
        assert!(began.elapsed() < Duration::from_secs(1));
        assert!(calls.lock().unwrap().is_empty());
        assert_eq!(discoveries.load(std::sync::atomic::Ordering::SeqCst), 0);
    }

    #[test]
    fn a_failed_save_still_returns_the_good_token() {
        let (base, _calls, _) = token_server(vec![ok_answer()]);
        // The state "directory" is a file, so saving cannot work.
        let blocker = test_dir("fresh-nosave");
        std::fs::write(&blocker, b"x").unwrap();
        let mut t = near_expiry();
        let got = fresh_token(&cfg_for(&base, blocker.join("sub")), &mut t).unwrap();
        assert_eq!(got, "new-access");
        assert_eq!(t.access_token, "new-access");
    }

    #[test]
    fn login_follows_the_device_flow() {
        let n = Arc::new(Mutex::new(0u32));
        let base_cell = Arc::new(Mutex::new(String::new()));
        let b = base_cell.clone();
        let base = fake_server(Box::new(move |_m, path, _h, body| match path {
            "/.well-known/openid-configuration" => (200, discovery(&b.lock().unwrap())),
            "/device" => {
                assert!(body.contains("client_id=client"), "{body}");
                assert!(
                    body.contains("urn%3Azitadel%3Aiam%3Aorg%3Aproject%3Aid%3Aproj%3Aaud"),
                    "{body}"
                );
                (
                    200,
                    json!({"device_code": "dc", "user_code": "UC", "verification_uri": "https://v",
                           "interval": 1, "expires_in": 600})
                    .to_string(),
                )
            }
            "/token" => {
                assert!(body.contains("device_code=dc"), "{body}");
                let mut n = n.lock().unwrap();
                *n += 1;
                if *n == 1 {
                    (400, json!({"error": "authorization_pending"}).to_string())
                } else {
                    (
                        200,
                        json!({"access_token": "A", "refresh_token": "R", "expires_in": 100})
                            .to_string(),
                    )
                }
            }
            other => panic!("unexpected {other}"),
        }));
        *base_cell.lock().unwrap() = base.clone();
        let t = login(&cfg_for(&base, test_dir("login"))).unwrap();
        assert_eq!(t.access_token, "A");
        assert_eq!(t.refresh_token.as_deref(), Some("R"));
    }

    #[test]
    fn register_device_sends_bearer_and_key() {
        let base = fake_server(Box::new(|m, path, head, body| {
            assert_eq!((m, path), ("POST", "/devices"));
            assert!(head.contains("\r\nauthorization: bearer tok\r\n"), "{head}");
            assert!(
                head.contains("\r\ncontent-type: application/json\r\n"),
                "{head}"
            );
            assert_eq!(body, r#"{"public_key":"PK"}"#);
            (
                200,
                json!({"device_id": "d1", "mcp_url": "https://r/mcp/d/d1"}).to_string(),
            )
        }));
        let d = register_device(&cfg_for(&base, test_dir("reg")), "tok", "PK", None, None).unwrap();
        assert_eq!(d.device_id, "d1");
        assert_eq!(d.mcp_url, "https://r/mcp/d/d1");
    }

    #[test]
    fn register_device_sends_the_device_id_it_has_and_the_name() {
        let base = fake_server(Box::new(|_, _, _, body| {
            let sent: Value = serde_json::from_str(body).unwrap();
            assert_eq!(
                sent,
                json!({"public_key": "PK", "device_id": "d1", "name": "Studio Mac"})
            );
            (
                200,
                json!({"device_id": "d1", "mcp_url": "https://r/mcp/d/d1"}).to_string(),
            )
        }));
        let cfg = cfg_for(&base, test_dir("reg-id"));
        let d = register_device(&cfg, "tok", "PK", Some("d1"), Some("Studio Mac")).unwrap();
        assert_eq!(d.device_id, "d1");
    }

    #[test]
    fn a_full_list_is_reported_in_the_relays_words() {
        let words = "You already have 5 computers connected. Remove one in the dashboard first.";
        let base = fake_server(Box::new(move |_, _, _, _| {
            (409, json!({ "error": words }).to_string())
        }));
        let err = register_device(&cfg_for(&base, test_dir("reg409")), "tok", "PK", None, None)
            .unwrap_err();
        assert_eq!(err, words);
        // Anything else the relay says with a 409 stays out of the message.
        let base = fake_server(Box::new(|_, _, _, _| (409, "not json".into())));
        let err = register_device(
            &cfg_for(&base, test_dir("reg409b")),
            "tok",
            "PK",
            None,
            None,
        )
        .unwrap_err();
        assert!(err.contains("409") && !err.contains("not json"), "{err}");
    }

    #[test]
    fn someone_without_the_role_is_told_to_ask_for_access() {
        let base = fake_server(Box::new(|_, _, _, _| (403, "{\"error\":\"x\"}".into())));
        let err = register_device(&cfg_for(&base, test_dir("reg403")), "tok", "PK", None, None)
            .unwrap_err();
        assert!(
            err.contains("403") && err.contains("ask whoever runs it"),
            "{err}"
        );
        assert!(err.contains("vrelay login"), "{err}");
    }

    #[test]
    fn login_takes_an_optional_name() {
        let args = |a: &[&str]| a.iter().map(|s| s.to_string()).collect::<Vec<_>>();
        assert_eq!(parse_login_args(&args(&[])), Ok(None));
        assert_eq!(
            parse_login_args(&args(&["--name", "Studio Mac"])),
            Ok(Some("Studio Mac".into()))
        );
        assert_eq!(
            parse_login_args(&args(&["--name=Work"])),
            Ok(Some("Work".into()))
        );
        for bad in [
            args(&["--name"]),
            args(&["--name", "  "]),
            args(&["--name="]),
            args(&["--nme", "x"]),
            args(&["stray"]),
            args(&["--name", "a", "--name", "b"]),
        ] {
            let err = parse_login_args(&bad).unwrap_err();
            assert!(err.contains("vrelay login"), "{bad:?}: {err}");
        }
    }

    #[test]
    fn register_device_reports_a_refusal_without_the_body() {
        let base = fake_server(Box::new(|_, _, _, _| (401, "secret-ish body".into())));
        let err = register_device(&cfg_for(&base, test_dir("reg401")), "tok", "PK", None, None)
            .unwrap_err();
        assert!(err.contains("401") && !err.contains("secret-ish"), "{err}");
    }

    #[test]
    fn token_answers_parse_like_the_spike() {
        assert_eq!(
            parse_token_response(400, &json!({"error": "slow_down"}), 0),
            Poll::SlowDown
        );
        match parse_token_response(200, &json!({"access_token": "a", "expires_in": 5}), 10) {
            Poll::Done(t) => assert_eq!(t.expires_at_unix, 15),
            other => panic!("{other:?}"),
        }
        assert!(matches!(
            parse_token_response(200, &json!({"nope": 1}), 0),
            Poll::Failed(_)
        ));
        assert!(needs_refresh(
            &Tokens {
                access_token: "a".into(),
                refresh_token: None,
                expires_at_unix: 1000
            },
            700
        ));
        assert!(!needs_refresh(
            &Tokens {
                access_token: "a".into(),
                refresh_token: None,
                expires_at_unix: 1000
            },
            699
        ));
    }
}
