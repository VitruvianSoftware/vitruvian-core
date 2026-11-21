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

//! The real relay against the real connector: the relay's `App` on a
//! loopback port, the connector's `Link` dialling it, an AI app speaking MCP
//! over HTTP. Only the edges are fakes: the tools, the dialog, the sign-in
//! (tokens signed with a throwaway key the relay's key set trusts).
//!
//! Each side's own tests drive a hand-written fake of the other. These
//! check what only shows when both real loops run together: how each judges
//! the other's silence, a close at the token's expiry, a re-registration.
//!
//! Real time throughout, with the ping intervals shrunk so a silence check
//! trips in well under a second. No assertion depends on a tight bound.

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::SocketAddr;
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU32, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper_util::rt::TokioIo;
use ring::rand::SystemRandom;
use ring::signature::{RsaKeyPair, RSA_PKCS1_SHA256};
use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::{mpsc, watch};
use vitruvian_mcp_auth::{verifier, VerifierConfig};
use vitruvian_relay::config::Settings;
use vitruvian_relay::http::{serve, App, Timing as RelayTiming};
use vitruvian_relay::store::MemStore;
use vitruvian_relay::LogSink;
use vitruvian_relay_connector::bridge::BridgeOutput;
use vitruvian_relay_connector::keys::{load_or_create, public_key_b64};
use vitruvian_relay_connector::link::{
    Asker, Link, StillWanted, Timing as LinkTiming, TokenError, TokenSource, Tools,
};
use vitruvian_relay_connector::prompt::Waited;
use vitruvian_relay_connector::state::{save_device, DeviceInfo};
use vitruvian_relay_protocol::ToolDef;

const PUBLIC_URL: &str = "https://relay.example.test";
const ISSUER: &str = "https://auth.example.test";
const PROJECT_ID: &str = "123456789";
const MCP_CLIENT: &str = "claude-client";
const CONNECTOR_CLIENT: &str = "connector-client";
const ALICE: &str = "alice";

/// The longest any one step may take before a test gives up. Only a failing
/// test waits this long.
const WAIT: Duration = Duration::from_secs(20);

// A throwaway 2048-bit RSA key (PKCS#8 DER, base64url): the test-only key the
// relay's and vitruvian-mcp-auth's own tests use. Used nowhere else.
const TEST_RSA_KEY: &str = concat!(
    "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCvutM9Ruknu7rIHzvYC02EWEa-9e1c7uKxV81fV2",
    "RMN-iBE4rlA_sxIccFC8QeISKKeIg8dxlY3V1EbkRjY7TYyGcsie28b6dWUi9uUkZqTCG0cMu5laAR8YxUbWdetOHp",
    "fwiD70KTDd_n2-Mgb84FfjpzEwSvFrdNgwGccDkcPzAqMkQcy7r-vEqKpLfLbw3iile4Tq_PILB6GriFVl63TEsosP",
    "WVyGEncch5YPzngHL94zkoKmUQMKBgR5CTIE7V157bvw_OkXAfjG6LjGDNlS1rUN0nuuO56pZcSdhVNT0qkLainlmh",
    "flaudwusJGEfrBjBXTHYnxZdHFMXUrmDAgMBAAECggEAVa34B5T24hYQhDliUrx0D5aA6-N5V0nsAn6mVhmEf_r0ZF",
    "a0bmPqCfMHl8i8Vtpd_ni1KBIDrEXGDzLaKkF3cAkJ8PfRD4K66oYItTftOC-lcVZbpkEzOfx1KMbs0wrLaS60Zqt1",
    "4MAvjtsxmuOYZio88lVv_7RKLEM3OmCnH8NJ7HJ2AZtk_9pBhWs3gVWNnf2HwZe2g9LpFKEpD1VZLKd9fv7IQ9Pki3",
    "Om1m_EIuJhDTMS2ZtY52E5YDQzixuD2J1CylcofbwOCf02MXEvfWhZw_IzmTFuAr8VaxPBTpF3U_AMCvU5rOT-svEs",
    "lh0ezfMS9FF8gJJhzwlEv82UuQKBgQDjw02gBCXfVmKmUN8PQiFVC7le3tdGREU6DetDeUiCH_fhkZLhZGCJ7XN0pL",
    "FAD0kQy5JgIMRI_AmmCwLy5FBUyKlHCGS064ati-4m0Xu8j_q-MMp1co5J4d_S_b0hf3qyezHqCAiZb30rTTIQHQxI",
    "mHCCW1MOLquW9hJ1kHDAawKBgQDFhBrAg1Xw6RgdhDr7P4UZUKHTWZnUVVL3Coqj5CYd6wSdhJOKG4IwIxELWk_TYl",
    "dHR-LbBLKGTqkGWNxSigjU7bLL2ne7JtDvEJ82StD6Q9BFdifrYUCGNsdpdyTeQ_2fwaVXhpLgpUEyn3whbHZPMvqz",
    "tL8XeUPtcGVAeV5RSQKBgElAyTiL3PpluDixjexEYqANs0L1_NrWnkU7sMz0twNS8NCVl13ygLIbsqRzS6bEw8UpFB",
    "zirP6kQR4sMHiaQdPi7b6wzmL51Uj_1kqZ2WgeDpEY9CSuAWF1yhz8CtY5P-cjhDw29T0UBHfmzhEspoS6soTahm3r",
    "SLi2z90L5ZedAoGAWRs17m_Rz7N426gR69NGOptzxiOAEJjFqwmobjO5NnoWRPHQlde_LfRD9jkyFg0hjtjRcTl3SL",
    "wn6OMh0mLPhTAPH4RZy6bBT3jSOu4ZxS3ewdeCPuBK-cGwyNWlXliSDQaRjyD5Fju3ZB0rJPEHlsdK7tO1-eMNUAsK",
    "wsF-WXECgYEAwPw6ZR4Qkg3Nvgm3gXg6u0kikIRkNwtrh1gFZCTb2OVt6pYGnTXlmv6dsUZEz7k3p7PRMsavi3sd8i",
    "hKXawoJUsQ9-eQi6wO_uiFVIdV566aclIo_0nuVRjs8tQ5KI6eUZ0woMsrqfavYnwZ9H7RfOQW8Sjkc5hG1z5pc2gM",
    "xLI",
);

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

fn b64url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

fn rsa_key() -> Arc<RsaKeyPair> {
    let der = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(TEST_RSA_KEY)
        .unwrap();
    Arc::new(RsaKeyPair::from_pkcs8(&der).unwrap())
}

fn jwks(pair: &RsaKeyPair) -> Value {
    let public: ring::signature::RsaPublicKeyComponents<Vec<u8>> = pair.public().into();
    json!({"keys": [{
        "kty": "RSA", "kid": "k1", "alg": "RS256", "use": "sig",
        "n": b64url(&public.n), "e": b64url(&public.e),
    }]})
}

fn mint(pair: &RsaKeyPair, client_id: &str, exp: u64) -> String {
    let header = b64url(json!({"alg": "RS256", "kid": "k1"}).to_string().as_bytes());
    let claims = json!({
        "iss": ISSUER, "aud": [PROJECT_ID], "sub": ALICE, "client_id": client_id,
        "iat": now_secs(), "exp": exp,
    });
    let input = format!("{header}.{}", b64url(claims.to_string().as_bytes()));
    let mut sig = vec![0u8; pair.public().modulus_len()];
    pair.sign(
        &RSA_PKCS1_SHA256,
        &SystemRandom::new(),
        input.as_bytes(),
        &mut sig,
    )
    .unwrap();
    format!("{input}.{}", b64url(&sig))
}

/// Serves the key set on a loopback port from a plain thread.
fn start_jwks_server(body: String) -> String {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/oauth/v2/keys", listener.local_addr().unwrap());
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut line = String::new();
            while reader.read_line(&mut line).is_ok_and(|n| n > 0) && line != "\r\n" {
                line.clear();
            }
            let _ = write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
        }
    });
    url
}

fn temp_dir(name: &str) -> PathBuf {
    static N: AtomicU32 = AtomicU32::new(0);
    let dir = std::env::var_os("TEST_TMPDIR")
        .map(PathBuf::from)
        .unwrap_or_else(std::env::temp_dir)
        .join(format!(
            "relay-e2e-{}-{}-{name}",
            std::process::id(),
            N.fetch_add(1, Ordering::SeqCst)
        ));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).unwrap();
    dir
}

async fn until(what: &str, f: impl Fn() -> bool) {
    let end = Instant::now() + WAIT;
    while !f() {
        assert!(Instant::now() < end, "timed out waiting for {what}");
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

// ------------------------------------------------------------------- relay

struct Relay {
    addr: SocketAddr,
    rsa: Arc<RsaKeyPair>,
    logs: Arc<Mutex<Vec<String>>>,
    /// Where this relay keeps its devices: a relay started over the same store
    /// is this one restarted, with none of its calls.
    store: Arc<MemStore>,
}

/// In-call pings every 2 s, as in production: three missed (6 s) is a drop
/// on either side. Shorter would be faster, but with the relay, the
/// connector and the slow proxy below sharing one test process, a loaded
/// machine (8 copies at once) has been seen to stall a task for over 3 s.
const IN_CALL: Duration = Duration::from_secs(2);

fn relay_timing() -> RelayTiming {
    RelayTiming {
        idle_ping: Duration::from_secs(1),
        in_call_ping: IN_CALL,
        transit_margin: IN_CALL * 3,
        ..RelayTiming::default()
    }
}

async fn start_relay() -> Relay {
    start_relay_with(relay_timing()).await
}

async fn start_relay_with(timing: RelayTiming) -> Relay {
    start_relay_in(timing, Arc::new(MemStore::new())).await
}

/// A relay keeping its devices in `store`: a second one started over the
/// same store is the first one restarted, with none of its calls.
async fn start_relay_in(timing: RelayTiming, store: Arc<MemStore>) -> Relay {
    let rsa = rsa_key();
    let jwks_uri = start_jwks_server(jwks(&rsa).to_string());
    let env: HashMap<&str, String> = [
        ("PUBLIC_URL", PUBLIC_URL.to_string()),
        ("ISSUER", ISSUER.to_string()),
        ("PROJECT_ID", PROJECT_ID.to_string()),
        ("MCP_CLIENT_IDS", MCP_CLIENT.to_string()),
        ("CONNECTOR_CLIENT_ID", CONNECTOR_CLIENT.to_string()),
        ("ALLOWED_SUBJECTS", ALICE.to_string()),
        (
            "DATABASE_URL",
            "postgres://unused@localhost/unused".to_string(),
        ),
        ("JWKS_URI", jwks_uri.clone()),
    ]
    .into_iter()
    .collect();
    let settings = Settings::from_lookup(|k| env.get(k).cloned()).unwrap();
    let verifier_for = |ids: Vec<String>| {
        verifier(VerifierConfig {
            issuer: ISSUER.into(),
            project_id: PROJECT_ID.into(),
            allowed_client_ids: ids,
            allowed_subjects: vec![ALICE.into()],
            jwks_uri: Some(jwks_uri.clone()),
            user_agent: "vitruvian-relay-e2e".into(),
        })
        .unwrap()
    };
    let logs = Arc::new(Mutex::new(Vec::new()));
    let sink_logs = logs.clone();
    let sink: LogSink = Arc::new(move |line| sink_logs.lock().unwrap().push(line.to_string()));
    let app = App::new(
        settings,
        verifier_for(vec![MCP_CLIENT.into()]),
        verifier_for(vec![CONNECTOR_CLIENT.into()]),
        store.clone(),
        timing,
        sink,
    );
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(serve(listener, app));
    Relay {
        addr,
        rsa,
        logs,
        store,
    }
}

struct Reply {
    status: u16,
    session: Option<String>,
    body: String,
}

impl Reply {
    fn json(&self) -> Value {
        serde_json::from_str(&self.body).unwrap_or_else(|_| panic!("not JSON: {}", self.body))
    }
}

impl Relay {
    fn url(&self) -> String {
        format!("http://{}", self.addr)
    }

    fn logs(&self) -> String {
        self.logs.lock().unwrap().join("\n")
    }

    async fn post(&self, path: &str, token: &str, session: Option<&str>, body: Value) -> Reply {
        post(self.addr, path, token, session, body).await
    }

    /// Registers a device key for Alice, as `vrelay login` does; the id.
    async fn register(&self, public_key_b64: &str) -> String {
        let token = mint(&self.rsa, CONNECTOR_CLIENT, now_secs() + 600);
        let r = self
            .post(
                "/devices",
                &token,
                None,
                json!({"public_key": public_key_b64}),
            )
            .await;
        assert_eq!(r.status, 200, "{}", r.body);
        r.json()["device_id"].as_str().unwrap().to_string()
    }

    /// An AI app's MCP session on Alice's device.
    async fn mcp(&self, device_id: &str) -> Mcp {
        let token = mint(&self.rsa, MCP_CLIENT, now_secs() + 600);
        let path = format!("/mcp/d/{device_id}");
        let r = self
            .post(
                &path,
                &token,
                None,
                json!({"jsonrpc": "2.0", "id": 0, "method": "initialize",
                       "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                  "clientInfo": {"name": "e2e", "version": "0"}}}),
            )
            .await;
        assert_eq!(r.status, 200, "{}", r.body);
        Mcp {
            addr: self.addr,
            path,
            token,
            session: r.session.expect("a session id"),
            next: AtomicU64::new(1),
        }
    }
}

/// One HTTP request on a new connection.
async fn post(
    addr: SocketAddr,
    path: &str,
    token: &str,
    session: Option<&str>,
    body: Value,
) -> Reply {
    let stream = TcpStream::connect(addr).await.unwrap();
    let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(stream))
        .await
        .unwrap();
    let conn = tokio::spawn(conn);
    let mut req = http::Request::builder()
        .method("POST")
        .uri(path)
        .header("host", "relay.example.test")
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/json")
        .header("accept", "application/json, text/event-stream");
    if let Some(s) = session {
        req = req.header("mcp-session-id", s);
    }
    let resp = sender
        .send_request(req.body(Full::new(Bytes::from(body.to_string()))).unwrap())
        .await
        .unwrap();
    let status = resp.status().as_u16();
    let session = resp
        .headers()
        .get("mcp-session-id")
        .map(|v| v.to_str().unwrap().to_string());
    let body = resp.into_body().collect().await.unwrap().to_bytes();
    conn.abort();
    Reply {
        status,
        session,
        body: String::from_utf8_lossy(&body).into_owned(),
    }
}

/// An AI app's MCP session on one device.
struct Mcp {
    addr: SocketAddr,
    path: String,
    token: String,
    session: String,
    next: AtomicU64,
}

impl Mcp {
    async fn rpc(&self, method: &str, params: Value) -> Value {
        let id = self.next.fetch_add(1, Ordering::SeqCst);
        self.rpc_id(id, method, params).await
    }

    async fn rpc_id(&self, id: u64, method: &str, params: Value) -> Value {
        let r = post(
            self.addr,
            &self.path,
            &self.token,
            Some(&self.session),
            json!({"jsonrpc": "2.0", "id": id, "method": method, "params": params}),
        )
        .await;
        assert_eq!(r.status, 200, "{}", r.body);
        r.json()
    }

    async fn notify(&self, method: &str, params: Value) {
        let r = post(
            self.addr,
            &self.path,
            &self.token,
            Some(&self.session),
            json!({"jsonrpc": "2.0", "method": method, "params": params}),
        )
        .await;
        assert_eq!(r.status, 202, "{}", r.body);
    }

    /// The device's tools: what its connector listed, without the relay's
    /// own `check_request` that every list ends with.
    async fn tool_names(&self) -> Vec<String> {
        let v = self.rpc("tools/list", json!({})).await;
        let mut names: Vec<String> = v["result"]["tools"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["name"].as_str().unwrap().to_string())
            .collect();
        assert_eq!(names.pop().as_deref(), Some("check_request"), "{v}");
        names
    }

    /// A tool's text and its error flag.
    async fn call(&self, tool: &str, args: Value) -> (String, bool) {
        let v = self
            .rpc("tools/call", json!({"name": tool, "arguments": args}))
            .await;
        result_text(&v)
    }
}

fn result_text(v: &Value) -> (String, bool) {
    let r = &v["result"];
    (
        r["content"][0]["text"]
            .as_str()
            .unwrap_or_default()
            .to_string(),
        r["isError"].as_bool().unwrap_or(false),
    )
}

// --------------------------------------------------------------- connector

fn tool(name: &str) -> ToolDef {
    ToolDef {
        name: name.into(),
        description: format!("{name} tool"),
        input_schema: json!({"type": "object"}),
    }
}

/// `read_file` (runs without asking) answers `read <path>`, or `big_bytes`
/// of text for `/big`, or, for `/gated`, `read /gated` once the test has
/// called `gate.notify_one()`; `start_process` (asks first) answers
/// `ran <command>`.
#[derive(Default)]
struct E2eTools {
    ran: Mutex<Vec<(String, Value)>>,
    big_bytes: AtomicUsize,
    gate: tokio::sync::Notify,
}

impl E2eTools {
    fn ran(&self, tool: &str) -> usize {
        self.ran
            .lock()
            .unwrap()
            .iter()
            .filter(|(t, _)| t == tool)
            .count()
    }
}

impl Tools for E2eTools {
    fn list(&self) -> impl std::future::Future<Output = Vec<ToolDef>> + Send {
        std::future::ready(vec![tool("read_file"), tool("start_process")])
    }

    fn call(
        &self,
        tool: &str,
        args: Value,
        _deadline: Instant,
        wanted: StillWanted,
    ) -> impl std::future::Future<Output = Option<BridgeOutput>> + Send {
        let tool = tool.to_string();
        async move {
            if !wanted() {
                return None;
            }
            self.ran.lock().unwrap().push((tool.clone(), args.clone()));
            let path = args["path"].as_str();
            let text = match (tool.as_str(), path, args["command"].as_str()) {
                ("read_file", Some("/big"), _) => "b".repeat(self.big_bytes.load(Ordering::SeqCst)),
                ("read_file", Some(p), _) => format!("read {p}"),
                ("start_process", _, Some(c)) => format!("ran {c}"),
                _ => "?".into(),
            };
            if path == Some("/gated") {
                self.gate.notified().await;
            }
            Some(BridgeOutput {
                content: json!([{"type": "text", "text": text}]),
                is_error: false,
                truncated: false,
            })
        }
    }
}

/// The dialog: waits for the test's answer, or for the link to close it.
#[derive(Default)]
struct E2eAsker {
    answer: Mutex<Option<Waited>>,
    opened: AtomicUsize,
    dismissed: AtomicUsize,
}

impl Asker for E2eAsker {
    fn ask(&self, _tool: &str, _summary: &str, timeout: Duration, dismiss: &AtomicBool) -> Waited {
        self.opened.fetch_add(1, Ordering::SeqCst);
        let end = Instant::now() + timeout;
        loop {
            if dismiss.load(Ordering::SeqCst) {
                self.dismissed.fetch_add(1, Ordering::SeqCst);
                return Waited::Dismissed;
            }
            if let Some(a) = *self.answer.lock().unwrap() {
                return a;
            }
            if Instant::now() >= end {
                return Waited::TimedOut;
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }
}

/// Mints connector tokens. The first `short` of them expire `short_secs`
/// after they are made; the rest live ten minutes.
struct MintTokens {
    rsa: Arc<RsaKeyPair>,
    short: AtomicUsize,
    short_secs: u64,
    issued: AtomicUsize,
}

impl TokenSource for MintTokens {
    fn token(&self) -> std::result::Result<Option<String>, TokenError> {
        self.issued.fetch_add(1, Ordering::SeqCst);
        let life = if self
            .short
            .fetch_update(Ordering::SeqCst, Ordering::SeqCst, |n| n.checked_sub(1))
            .is_ok()
        {
            self.short_secs
        } else {
            600
        };
        Ok(Some(mint(&self.rsa, CONNECTOR_CLIENT, now_secs() + life)))
    }
}

fn link_timing() -> LinkTiming {
    LinkTiming {
        ping_every: Duration::from_secs(1),
        in_call_every: IN_CALL,
        status_every: Duration::from_millis(100),
        token_poll: Duration::from_millis(50),
        backoff_unit: Duration::from_millis(10),
        connect_timeout: WAIT,
        welcome_timeout: WAIT,
        ..LinkTiming::default()
    }
}

struct Connector {
    dir: PathBuf,
    tools: Arc<E2eTools>,
    asker: Arc<E2eAsker>,
    tokens: Arc<MintTokens>,
    device_id: String,
    log: Arc<Mutex<Vec<String>>>,
    task: tokio::task::JoinHandle<()>,
    _reload: mpsc::Sender<()>,
    _stop: watch::Sender<bool>,
}

impl Drop for Connector {
    fn drop(&mut self) {
        self.task.abort();
    }
}

impl Connector {
    fn logged(&self, needle: &str) -> bool {
        self.log.lock().unwrap().iter().any(|l| l.contains(needle))
    }

    fn calls_log(&self) -> String {
        std::fs::read_to_string(self.dir.join("logs").join("calls.log")).unwrap_or_default()
    }
}

/// Registers a fresh device key with the relay (as `vrelay login` does) and
/// starts a `Link` for it, dialling `url` (the relay, or a proxy to it).
async fn start_connector(relay: &Relay, name: &str, url: &str, short_tokens: usize) -> Connector {
    start_connector_with(relay, name, url, short_tokens, link_timing()).await
}

async fn start_connector_with(
    relay: &Relay,
    name: &str,
    url: &str,
    short_tokens: usize,
    timing: LinkTiming,
) -> Connector {
    let dir = temp_dir(name);
    let key = load_or_create(&dir).unwrap();
    let device_id = relay.register(&public_key_b64(&key)).await;
    save_device(
        &dir,
        &DeviceInfo {
            device_id: device_id.clone(),
            mcp_url: format!("{PUBLIC_URL}/mcp/d/{device_id}"),
        },
    )
    .unwrap();
    let tools = Arc::new(E2eTools::default());
    let asker = Arc::new(E2eAsker::default());
    let tokens = Arc::new(MintTokens {
        rsa: relay.rsa.clone(),
        short: AtomicUsize::new(short_tokens),
        short_secs: 2,
        issued: AtomicUsize::new(0),
    });
    let log = Arc::new(Mutex::new(Vec::new()));
    let l = log.clone();
    let tag = name.to_string();
    let link = Link {
        dir: dir.clone(),
        log_dir: dir.join("logs"),
        relay_url: url.to_string(),
        tools: tools.clone(),
        asker: asker.clone(),
        tokens: tokens.clone(),
        rules: vitruvian_relay_connector::rules::load(&dir).unwrap(),
        // Not started: the test must not hold the machine awake.
        awake: Arc::new(vitruvian_relay_connector::awake::Awake::system()),
        key: Arc::new(key),
        timing,
        clock: Arc::new(now_secs),
        rng: Arc::new(Mutex::new(|cap: u64| cap)),
        log: Arc::new(move |s: &str| {
            eprintln!("{tag}: {s}");
            l.lock().unwrap().push(s.to_string());
        }),
        tls: None,
    };
    let (reload, reload_rx) = mpsc::channel(4);
    let (stop, stop_rx) = watch::channel(false);
    let task = tokio::spawn(link.run(reload_rx, stop_rx));
    Connector {
        dir,
        tools,
        asker,
        tokens,
        device_id,
        log,
        task,
        _reload: reload,
        _stop: stop,
    }
}

/// Waits until the relay lists the device's tools: the link is up.
async fn until_online(mcp: &Mcp) {
    let end = Instant::now() + WAIT;
    while mcp.tool_names().await.is_empty() {
        assert!(Instant::now() < end, "the connector never came online");
        tokio::time::sleep(Duration::from_millis(20)).await;
    }
}

// ------------------------------------------------------------------- proxy

/// A loopback proxy in front of the relay that passes what the relay sends
/// at once, but what the connector sends at `bytes_per_sec`: a slow uplink.
async fn slow_uplink(to: SocketAddr, bytes_per_sec: usize) -> String {
    let socket = tokio::net::TcpSocket::new_v4().unwrap();
    // Small buffers, so the connector's send really waits on the uplink.
    socket.set_recv_buffer_size(16 * 1024).unwrap();
    socket.bind("127.0.0.1:0".parse().unwrap()).unwrap();
    let listener = socket.listen(16).unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(async move {
        while let Ok((down, _)) = listener.accept().await {
            let Ok(up) = TcpStream::connect(to).await else {
                continue;
            };
            let (mut down_r, mut down_w) = down.into_split();
            let (mut up_r, mut up_w) = up.into_split();
            tokio::spawn(async move {
                let _ = tokio::io::copy(&mut up_r, &mut down_w).await;
            });
            tokio::spawn(async move {
                // Paced by bytes passed, whatever size each read comes in,
                // with no credit saved up while idle.
                let mut next = tokio::time::Instant::now();
                let mut buf = vec![0u8; 32 * 1024];
                loop {
                    match down_r.read(&mut buf).await {
                        Ok(0) | Err(_) => break,
                        Ok(n) => {
                            if up_w.write_all(&buf[..n]).await.is_err() {
                                break;
                            }
                            let cost = Duration::from_secs_f64(n as f64 / bytes_per_sec as f64);
                            next = next.max(tokio::time::Instant::now()) + cost;
                            tokio::time::sleep_until(next).await;
                        }
                    }
                }
                let _ = up_w.shutdown().await;
            });
        }
    });
    format!("http://{addr}")
}

/// A loopback proxy in front of the relay that can be cut: every open
/// connection through it dies, and new ones are refused until it is reopened.
/// A network reset between the two.
struct CutProxy {
    url: String,
    down: Arc<AtomicBool>,
    open: Arc<Mutex<Vec<tokio::task::JoinHandle<()>>>>,
    /// Where new connections go: changed to point the connector at a
    /// restarted relay.
    to: Arc<Mutex<SocketAddr>>,
}

impl CutProxy {
    async fn start(to: SocketAddr) -> CutProxy {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let url = format!("http://{}", listener.local_addr().unwrap());
        let down = Arc::new(AtomicBool::new(false));
        let open: Arc<Mutex<Vec<tokio::task::JoinHandle<()>>>> = Arc::default();
        let (d, o) = (down.clone(), open.clone());
        let to = Arc::new(Mutex::new(to));
        let target = to.clone();
        tokio::spawn(async move {
            while let Ok((mut from, _)) = listener.accept().await {
                if d.load(Ordering::SeqCst) {
                    continue; // dropped: refused
                }
                let to = *target.lock().unwrap();
                let Ok(mut up) = TcpStream::connect(to).await else {
                    continue;
                };
                o.lock().unwrap().push(tokio::spawn(async move {
                    let _ = tokio::io::copy_bidirectional(&mut from, &mut up).await;
                }));
            }
        });
        CutProxy {
            url,
            down,
            open,
            to,
        }
    }

    fn cut(&self) {
        self.down.store(true, Ordering::SeqCst);
        for h in self.open.lock().unwrap().drain(..) {
            h.abort();
        }
    }

    fn reopen(&self) {
        self.down.store(false, Ordering::SeqCst);
    }

    /// New connections go to `to` (a restarted relay).
    fn retarget(&self, to: SocketAddr) {
        *self.to.lock().unwrap() = to;
    }
}

// ------------------------------------------------------------------- tests

#[tokio::test(flavor = "multi_thread")]
async fn hello_welcome_call_result() {
    let relay = start_relay().await;
    let c = start_connector(&relay, "e-call", &relay.url(), 0).await;
    let mcp = relay.mcp(&c.device_id).await;
    until_online(&mcp).await;
    // The rules' visible tools, as the connector's hello listed them.
    assert_eq!(mcp.tool_names().await, ["read_file", "start_process"]);
    let (text, is_error) = mcp.call("read_file", json!({"path": "/tmp/a"})).await;
    assert_eq!((text.as_str(), is_error), ("read /tmp/a", false));
    // Ask first: Allow runs it.
    *c.asker.answer.lock().unwrap() = Some(Waited::Allow);
    let (text, is_error) = mcp.call("start_process", json!({"command": "ls"})).await;
    assert_eq!((text.as_str(), is_error), ("ran ls", false));
    assert_eq!(c.tools.ran("start_process"), 1);
    // A hidden tool is refused on the Mac, whatever the relay forwards.
    let (text, is_error) = mcp.call("set_config_value", json!({})).await;
    assert!(
        is_error && text.contains("Refused on the computer"),
        "{text}"
    );
    assert!(
        relay.logs().contains("\"event\":\"connect\""),
        "{}",
        relay.logs()
    );
}

#[tokio::test(flavor = "multi_thread")]
async fn a_cancel_at_the_dialog_closes_it_and_nothing_runs() {
    let relay = start_relay().await;
    let c = start_connector(&relay, "e-cancel", &relay.url(), 0).await;
    let mcp = Arc::new(relay.mcp(&c.device_id).await);
    until_online(&mcp).await;
    let m = mcp.clone();
    let call = async move {
        m.rpc_id(
            41,
            "tools/call",
            json!({"name": "start_process", "arguments": {"command": "rm -rf /tmp/x"}}),
        )
        .await
    };
    let (answer, ()) = tokio::join!(call, async {
        until("the dialog to open", || {
            c.asker.opened.load(Ordering::SeqCst) == 1
        })
        .await;
        mcp.notify("notifications/cancelled", json!({"requestId": 41}))
            .await;
    });
    assert_eq!(answer["error"]["code"], -32800, "{answer}");
    until("the dialog to close", || {
        c.asker.dismissed.load(Ordering::SeqCst) == 1
    })
    .await;
    // A late Allow after the cancel runs nothing.
    *c.asker.answer.lock().unwrap() = Some(Waited::Allow);
    until("the calls log line", || {
        c.calls_log().contains("cancelled at prompt")
    })
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(c.tools.ran("start_process"), 0);
    // The link stayed up through it.
    let (text, _) = mcp.call("read_file", json!({"path": "/after"})).await;
    assert_eq!(text, "read /after");
}

#[tokio::test(flavor = "multi_thread")]
async fn the_relay_closes_at_token_expiry_and_the_connector_comes_back() {
    let relay = start_relay().await;
    // The first token lives 2 s; the relay closes the socket then (1008).
    let c = start_connector(&relay, "e-expiry", &relay.url(), 1).await;
    let mcp = relay.mcp(&c.device_id).await;
    until_online(&mcp).await;
    // The relay closes it with 1008 and the reason; the connector may be
    // mid-ping then and see only the broken socket, so the relay's log is
    // the witness.
    until("the relay to close at the token's expiry", || {
        relay.logs().contains("token expired")
    })
    .await;
    until("a reconnect with a fresh token", || {
        c.tokens.issued.load(Ordering::SeqCst) >= 2
    })
    .await;
    until_online(&mcp).await;
    let (text, is_error) = mcp.call("read_file", json!({"path": "/again"})).await;
    assert_eq!((text.as_str(), is_error), ("read /again", false));
}

#[tokio::test(flavor = "multi_thread")]
async fn registering_again_kicks_the_old_link_and_the_new_key_takes_over() {
    let relay = start_relay().await;
    let old = start_connector(&relay, "e-old", &relay.url(), 0).await;
    let mcp = relay.mcp(&old.device_id).await;
    until_online(&mcp).await;
    // `vrelay login` again with a new key (one device per person: same id).
    let new = start_connector(&relay, "e-new", &relay.url(), 0).await;
    assert_eq!(new.device_id, old.device_id);
    until("the old link to be kicked", || old.logged("link down")).await;
    // The old key is now refused, and never takes the device back.
    until("the old key to be refused", || old.logged("bad signature")).await;
    until_online(&mcp).await;
    for i in 0..3 {
        let path = format!("/n{i}");
        let (text, _) = mcp.call("read_file", json!({"path": path})).await;
        assert_eq!(text, format!("read {path}"));
    }
    assert_eq!(old.tools.ran("read_file"), 0);
    assert_eq!(new.tools.ran("read_file"), 3);
}

/// Final review I1: a result that takes longer to upload than the silence
/// limit, while another call waits at its dialog, must not drop the link.
#[tokio::test(flavor = "multi_thread")]
async fn a_slow_large_result_during_a_dialog_keeps_the_link() {
    // This is about the link, not the waiting reply: that comes much later.
    let relay = start_relay_with(RelayTiming {
        approval_reply: Duration::from_secs(120),
        ..relay_timing()
    })
    .await;
    // 320 KiB/s: a 3 MiB result takes about 10 s, the silence limit is 6 s.
    let url = slow_uplink(relay.addr, 320 * 1024).await;
    let c = start_connector(&relay, "e-big", &url, 0).await;
    c.tools.big_bytes.store(3 * 1024 * 1024, Ordering::SeqCst);
    let mcp = Arc::new(relay.mcp(&c.device_id).await);
    until_online(&mcp).await;
    let m = mcp.clone();
    let waiting =
        tokio::spawn(async move { m.call("start_process", json!({"command": "make"})).await });
    until("the dialog to open", || {
        c.asker.opened.load(Ordering::SeqCst) == 1
    })
    .await;
    // One upload: with these timings the old code dropped the link here
    // only about 1 run in 4 (much of the send fits in the kernel's buffers);
    // link_tests.rs has the deterministic check.
    let (text, is_error) = mcp.call("read_file", json!({"path": "/big"})).await;
    assert!(
        !is_error,
        "{} / relay: {}",
        &text[..text.len().min(200)],
        relay.logs()
    );
    assert_eq!(text.len(), 3 * 1024 * 1024);
    assert_eq!(
        c.asker.dismissed.load(Ordering::SeqCst),
        0,
        "the dialog was closed"
    );
    assert!(!c.logged("link down"), "the link dropped");
    *c.asker.answer.lock().unwrap() = Some(Waited::Allow);
    let (text, is_error) = waiting.await.unwrap();
    assert_eq!((text.as_str(), is_error), ("ran make", false));
}

/// The real connector tells the real relay when its dialog opens, so the AI
/// app is answered "waiting" before it would give up (the relay's reply time
/// is 400 ms here, 10 s in production). Its retry joins the open dialog, and
/// `check_request` brings back the result once the person allows it.
#[tokio::test(flavor = "multi_thread")]
async fn a_slow_approval_is_fetched_with_check_request() {
    let relay = start_relay_with(RelayTiming {
        approval_reply: Duration::from_millis(400),
        ..relay_timing()
    })
    .await;
    let c = start_connector(&relay, "e-approval", &relay.url(), 0).await;
    let mcp = Arc::new(relay.mcp(&c.device_id).await);
    until_online(&mcp).await;
    let args = json!({"command": "ls"});

    let started = Instant::now();
    let (text, is_error) = mcp.call("start_process", args.clone()).await;
    assert!(!is_error, "{text}");
    assert!(started.elapsed() >= Duration::from_millis(400));
    let id = text
        .split("request_id \"")
        .nth(1)
        .and_then(|t| t.split('"').next())
        .unwrap_or_else(|| panic!("no request id in {text}"))
        .to_string();
    assert!(
        text.starts_with("Waiting for you to allow this on"),
        "{text}"
    );
    assert_eq!(c.asker.opened.load(Ordering::SeqCst), 1);

    // The AI app's retry of the same call: the same id, and no second dialog.
    let (again, _) = mcp.call("start_process", args).await;
    assert!(again.contains(&id), "{again}");
    assert_eq!(c.asker.opened.load(Ordering::SeqCst), 1, "a second dialog");

    // Still unanswered: `check_request` says so, with the same id.
    let (still, is_error) = mcp.call("check_request", json!({"request_id": id})).await;
    assert!(!is_error && still.contains(&id), "{still}");

    // The person allows it; the command runs once and the result comes back.
    *c.asker.answer.lock().unwrap() = Some(Waited::Allow);
    let (text, is_error) = mcp.call("check_request", json!({"request_id": id})).await;
    assert_eq!((text.as_str(), is_error), ("ran ls", false));
    assert_eq!(c.tools.ran("start_process"), 1);
    assert_eq!(c.asker.opened.load(Ordering::SeqCst), 1);
}

/// Most drops are network resets that recover in about a second. A command
/// that was running through one must still answer the AI, and not run twice.
#[tokio::test(flavor = "multi_thread")]
async fn result_after_a_one_second_drop_reaches_the_ai() {
    let relay = start_relay().await;
    let proxy = CutProxy::start(relay.addr).await;
    let c = start_connector(&relay, "e-drop", &proxy.url, 0).await;
    let mcp = Arc::new(relay.mcp(&c.device_id).await);
    until_online(&mcp).await;
    let m = mcp.clone();
    let call = tokio::spawn(async move { m.call("read_file", json!({"path": "/gated"})).await });
    until("the command to start", || c.tools.ran("read_file") == 1).await;
    // The link is reset mid-call and stays down for about a second.
    let dropped = Instant::now();
    proxy.cut();
    until("the connector to see the drop", || c.logged("link down")).await;
    // The command finishes while there is no link to send its result on.
    c.tools.gate.notify_one();
    tokio::time::sleep(Duration::from_millis(800)).await;
    proxy.reopen();
    let (text, is_error) = tokio::time::timeout(WAIT, call).await.unwrap().unwrap();
    assert_eq!((text.as_str(), is_error), ("read /gated", false));
    assert!(dropped.elapsed() < Duration::from_secs(10));
    // Never run twice.
    assert_eq!(c.tools.ran("read_file"), 1);
    // And the link works again.
    let (text, _) = mcp.call("read_file", json!({"path": "/after"})).await;
    assert_eq!(text, "read /after");
}

#[tokio::test(flavor = "multi_thread")]
async fn drop_longer_than_grace_fails_disconnected() {
    let grace = Duration::from_millis(600);
    let relay = start_relay_with(RelayTiming {
        reconnect_grace: grace,
        ..relay_timing()
    })
    .await;
    let proxy = CutProxy::start(relay.addr).await;
    let c = start_connector(&relay, "e-gone", &proxy.url, 0).await;
    let mcp = Arc::new(relay.mcp(&c.device_id).await);
    until_online(&mcp).await;
    let m = mcp.clone();
    let call = tokio::spawn(async move { m.call("read_file", json!({"path": "/gated"})).await });
    until("the command to start", || c.tools.ran("read_file") == 1).await;
    let dropped = Instant::now();
    proxy.cut();
    // The link does not come back.
    let (text, is_error) = tokio::time::timeout(WAIT, call).await.unwrap().unwrap();
    assert_eq!(
        (text.as_str(), is_error),
        ("Your computer disconnected. The command may already have run; check before trying again.", true)
    );
    assert!(
        dropped.elapsed() >= grace,
        "failed after {:?}, inside the {grace:?} grace",
        dropped.elapsed()
    );
}

/// The device comes back inside the grace period with its dialog still open.
/// Long after the grace the call is still the AI's to cancel, and when it
/// does the dialog closes on the new link: a late Allow runs nothing.
#[tokio::test(flavor = "multi_thread")]
async fn a_dialog_kept_across_a_reset_is_closed_when_the_ai_cancels() {
    let relay = start_relay_with(RelayTiming {
        reconnect_grace: Duration::from_millis(300),
        ..relay_timing()
    })
    .await;
    let proxy = CutProxy::start(relay.addr).await;
    let c = start_connector(&relay, "e-dialog-reset", &proxy.url, 0).await;
    let mcp = Arc::new(relay.mcp(&c.device_id).await);
    until_online(&mcp).await;
    let m = mcp.clone();
    let call = async move {
        m.rpc_id(
            52,
            "tools/call",
            json!({"name": "start_process", "arguments": {"command": "rm -rf /tmp/x"}}),
        )
        .await
    };
    let (answer, ()) = tokio::join!(call, async {
        until("the dialog to open", || {
            c.asker.opened.load(Ordering::SeqCst) == 1
        })
        .await;
        proxy.cut();
        until("the connector to see the drop", || c.logged("link down")).await;
        proxy.reopen();
        until("the link to be back", || {
            relay.logs().matches("\"event\":\"connect\"").count() >= 2
        })
        .await;
        // Past the relay's grace: a relay that failed the call here would
        // have told the AI already, and left the dialog open.
        tokio::time::sleep(Duration::from_millis(800)).await;
        assert_eq!(c.asker.dismissed.load(Ordering::SeqCst), 0);
        mcp.notify("notifications/cancelled", json!({"requestId": 52}))
            .await;
    });
    assert_eq!(answer["error"]["code"], -32800, "{answer}");
    until("the dialog to close", || {
        c.asker.dismissed.load(Ordering::SeqCst) == 1
    })
    .await;
    *c.asker.answer.lock().unwrap() = Some(Waited::Allow);
    until("the calls log line", || {
        c.calls_log().contains("cancelled at prompt")
    })
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(c.tools.ran("start_process"), 0);
}

/// Final review, Important 2. The relay restarts while a dialog is open: its
/// calls, and the `Cancel`s it owed, were only in memory, so the new relay
/// knows nothing of the call and the AI was long since told it failed.
/// Whatever is clicked at the old dialog after the connector is back, nothing
/// may run: the new relay never says it holds the call.
#[tokio::test(flavor = "multi_thread")]
async fn a_relay_restart_never_lets_an_old_dialog_run() {
    let relay = start_relay().await;
    let proxy = CutProxy::start(relay.addr).await;
    let c = start_connector_with(
        &relay,
        "e-restart",
        &proxy.url,
        0,
        LinkTiming {
            // Not the production 10 s: the new relay's silence about the
            // call is what is being waited for.
            reconnect_grace: Duration::from_millis(600),
            ..link_timing()
        },
    )
    .await;
    let mcp = Arc::new(relay.mcp(&c.device_id).await);
    until_online(&mcp).await;
    let m = mcp.clone();
    let _call = tokio::spawn(async move {
        m.rpc_id(
            61,
            "tools/call",
            json!({"name": "start_process", "arguments": {"command": "rm -rf /tmp/x"}}),
        )
        .await
    });
    until("the dialog to open", || {
        c.asker.opened.load(Ordering::SeqCst) == 1
    })
    .await;
    // The relay goes away and a new one, with the same devices and no calls,
    // takes its place.
    proxy.cut();
    until("the connector to see the drop", || c.logged("link down")).await;
    let restarted = start_relay_in(relay_timing(), relay.store.clone()).await;
    proxy.retarget(restarted.addr);
    proxy.reopen();
    until("the connector to be back", || {
        c.log
            .lock()
            .unwrap()
            .iter()
            .filter(|l| l.contains("connected to the relay"))
            .count()
            >= 2
    })
    .await;
    // The dialog is still open, and the person clicks Allow now.
    assert_eq!(c.asker.dismissed.load(Ordering::SeqCst), 0);
    *c.asker.answer.lock().unwrap() = Some(Waited::Allow);
    until("the calls log line", || {
        c.calls_log().contains("cancelled at prompt")
    })
    .await;
    tokio::time::sleep(Duration::from_millis(300)).await;
    assert_eq!(c.tools.ran("start_process"), 0, "an old dialog ran");
}
