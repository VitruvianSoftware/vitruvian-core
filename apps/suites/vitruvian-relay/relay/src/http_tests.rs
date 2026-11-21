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

//! End-to-end tests of the relay's HTTP side: a real server on a loopback
//! port, a local key-set server, tokens signed with a throwaway RSA key, and a
//! fake connector on a real WebSocket.
//!
//! Real time throughout (tokio's `test-util` would unify into the production
//! build through the crate hub). Waits are bounded by `within` (10 s), and
//! no assertion depends on a tight wall-clock bound.

use super::*;
use crate::devices::NewDevice;
use crate::mcp::{LEGACY_VERSIONS, MODERN_VERSIONS, SERVER_NAME};
use crate::store::{MemStore, StoreError};
use futures_util::{SinkExt, StreamExt};
use http::header;
use http_body_util::BodyExt;
use ring::rand::SystemRandom;
use ring::signature::{Ed25519KeyPair, KeyPair, RsaKeyPair, RSA_PKCS1_SHA256};
use serde_json::{json, Value};
use std::io::{BufRead, BufReader, Write};
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::Mutex;
use std::time::Instant;
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;
use vitruvian_mcp_auth::VerifierConfig;
use vitruvian_relay_protocol::{
    decode_to_connector, encode, hello_message, Call, CallResult, Hello, ToConnector, ToRelay,
    ToolDef, PROTOCOL,
};

pub(crate) const PUBLIC_URL: &str = "https://relay.example.test";
pub(crate) const ISSUER: &str = "https://auth.example.test";
pub(crate) const PROJECT_ID: &str = "123456789";
pub(crate) const MCP_CLIENT: &str = "claude-client";
pub(crate) const CONNECTOR_CLIENT: &str = "connector-client";
pub(crate) const ALICE: &str = "alice";
pub(crate) const BOB: &str = "bob";
/// The Zitadel role that lets a person in.
pub(crate) const ROLE: &str = "relay-user";
pub(crate) const DASHBOARD_CLIENT: &str = "dashboard-client";
const ACCEPT: &str = "application/json, text/event-stream";

// A throwaway 2048-bit RSA key (PKCS#8 DER, base64url), the same test-only key
// vitruvian-mcp-auth's tests use. Used nowhere else.
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

pub(crate) async fn within<T>(f: impl std::future::Future<Output = T>) -> T {
    tokio::time::timeout(Duration::from_secs(10), f)
        .await
        .expect("timed out")
}

/// Waits until `f` holds.
pub(crate) async fn until(f: impl Fn() -> bool) {
    within(async {
        while !f() {
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
}

pub(crate) fn b64url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

pub(crate) fn b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

pub(crate) fn now_secs() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

fn rsa_key() -> RsaKeyPair {
    let der = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(TEST_RSA_KEY)
        .unwrap();
    RsaKeyPair::from_pkcs8(&der).unwrap()
}

fn jwks(pair: &RsaKeyPair) -> Value {
    let public: ring::signature::RsaPublicKeyComponents<Vec<u8>> = pair.public().into();
    json!({"keys": [{
        "kty": "RSA", "kid": "k1", "alg": "RS256", "use": "sig",
        "n": b64url(&public.n), "e": b64url(&public.e),
    }]})
}

pub(crate) fn mint(pair: &RsaKeyPair, client_id: &str, sub: &str) -> String {
    mint_exp(pair, client_id, sub, now_secs() + 600)
}

pub(crate) fn mint_exp(pair: &RsaKeyPair, client_id: &str, sub: &str, exp: u64) -> String {
    mint_claims(pair, client_id, sub, Some(exp))
}

/// `exp: None` leaves the claim out. The person holds the `relay-user` role.
fn mint_claims(pair: &RsaKeyPair, client_id: &str, sub: &str, exp: Option<u64>) -> String {
    mint_with_role(pair, client_id, sub, exp, Some(ROLE))
}

/// `role: None` is a person who signed in but was never invited.
pub(crate) fn mint_with_role(
    pair: &RsaKeyPair,
    client_id: &str,
    sub: &str,
    exp: Option<u64>,
    role: Option<&str>,
) -> String {
    let now = now_secs();
    let header = b64url(json!({"alg": "RS256", "kid": "k1"}).to_string().as_bytes());
    let mut claims = json!({
        "iss": ISSUER, "aud": [PROJECT_ID], "sub": sub, "client_id": client_id,
        "iat": now,
    });
    if let Some(exp) = exp {
        claims["exp"] = json!(exp);
    }
    if let Some(role) = role {
        claims[format!("urn:zitadel:iam:org:project:{PROJECT_ID}:roles")] =
            json!({ role: { "org-1": "example.test" } });
    }
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
pub(crate) fn start_jwks_server(body: String) -> String {
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

/// A stand-in for the identity service's token endpoint: records the forms
/// it is sent and answers with whatever the test last set.
pub(crate) struct TokenServer {
    pub(crate) url: String,
    requests: Arc<Mutex<Vec<String>>>,
    answer: Arc<Mutex<(u16, String)>>,
    stalled: Arc<AtomicBool>,
}

impl TokenServer {
    /// While stalled, the server reads each request and then says nothing.
    pub(crate) fn stall(&self, stalled: bool) {
        self.stalled.store(stalled, Ordering::SeqCst);
    }

    /// Answers every exchange with this access token.
    pub(crate) fn give_token(&self, access_token: &str) {
        *self.answer.lock().unwrap() = (
            200,
            json!({"access_token": access_token, "token_type": "Bearer", "expires_in": 3600})
                .to_string(),
        );
    }

    /// Answers every exchange with an error.
    pub(crate) fn refuse(&self) {
        *self.answer.lock().unwrap() = (400, json!({"error": "invalid_grant"}).to_string());
    }

    /// The form bodies sent so far.
    pub(crate) fn requests(&self) -> Vec<String> {
        self.requests.lock().unwrap().clone()
    }
}

fn start_token_server() -> TokenServer {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/oauth/v2/token", listener.local_addr().unwrap());
    let requests = Arc::new(Mutex::new(Vec::new()));
    let answer = Arc::new(Mutex::new((
        400,
        json!({"error": "invalid_grant"}).to_string(),
    )));
    let stalled = Arc::new(AtomicBool::new(false));
    let (seen, reply, hold) = (requests.clone(), answer.clone(), stalled.clone());
    std::thread::spawn(move || {
        for stream in listener.incoming() {
            let Ok(mut stream) = stream else { continue };
            let mut reader = BufReader::new(stream.try_clone().unwrap());
            let mut length = 0usize;
            let mut line = String::new();
            while reader.read_line(&mut line).is_ok_and(|n| n > 0) && line != "\r\n" {
                if let Some((k, v)) = line.split_once(':') {
                    if k.eq_ignore_ascii_case("content-length") {
                        length = v.trim().parse().unwrap_or(0);
                    }
                }
                line.clear();
            }
            let mut body = vec![0u8; length];
            std::io::Read::read_exact(&mut reader, &mut body).unwrap();
            seen.lock()
                .unwrap()
                .push(String::from_utf8_lossy(&body).into_owned());
            while hold.load(Ordering::SeqCst) {
                std::thread::sleep(Duration::from_millis(10));
            }
            let (status, text) = reply.lock().unwrap().clone();
            let _ = write!(
                stream,
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{text}",
                text.len()
            );
        }
    });
    TokenServer {
        url,
        requests,
        answer,
        stalled,
    }
}

pub(crate) struct Harness {
    pub(crate) app: Arc<App>,
    pub(crate) addr: std::net::SocketAddr,
    pub(crate) rsa: RsaKeyPair,
    pub(crate) logs: Arc<Mutex<Vec<String>>>,
    pub(crate) store: Arc<MemStore>,
    pub(crate) tokens: TokenServer,
}

pub(crate) struct Reply {
    pub(crate) status: StatusCode,
    pub(crate) headers: http::HeaderMap,
    pub(crate) body: String,
}

impl Reply {
    pub(crate) fn json(&self) -> Value {
        serde_json::from_str(&self.body).unwrap_or_else(|_| panic!("not JSON: {}", self.body))
    }
    pub(crate) fn header(&self, name: &str) -> Option<String> {
        self.headers
            .get(name)
            .map(|v| v.to_str().unwrap().to_string())
    }
}

pub(crate) async fn harness() -> Harness {
    harness_with(Timing::default()).await
}

pub(crate) async fn harness_with(timing: Timing) -> Harness {
    let rsa = rsa_key();
    let jwks_uri = start_jwks_server(jwks(&rsa).to_string());
    let tokens = start_token_server();
    let env: std::collections::HashMap<&str, String> = [
        ("PUBLIC_URL", PUBLIC_URL.to_string()),
        ("ISSUER", ISSUER.to_string()),
        ("PROJECT_ID", PROJECT_ID.to_string()),
        ("MCP_CLIENT_IDS", MCP_CLIENT.to_string()),
        ("CONNECTOR_CLIENT_ID", CONNECTOR_CLIENT.to_string()),
        ("DASHBOARD_CLIENT_ID", DASHBOARD_CLIENT.to_string()),
        ("MCP_CLIENT_LABELS", format!("Claude={MCP_CLIENT}")),
        ("TOKEN_URI", tokens.url.clone()),
        (
            "DATABASE_URL",
            "postgres://unused@localhost/unused".to_string(),
        ),
        ("JWKS_URI", jwks_uri.clone()),
    ]
    .into_iter()
    .collect();
    let settings = Settings::from_lookup(|k| env.get(k).cloned()).unwrap();
    let required_role = settings.required_role.clone();
    let verifier_for = |ids: Vec<String>| {
        vitruvian_mcp_auth::verifier(VerifierConfig {
            issuer: ISSUER.into(),
            project_id: PROJECT_ID.into(),
            allowed_client_ids: ids,
            allowed_subjects: Vec::new(),
            required_role: Some(required_role.clone()),
            jwks_uri: Some(jwks_uri.clone()),
            user_agent: "vitruvian-relay-test".into(),
        })
        .unwrap()
    };
    let store = Arc::new(MemStore::new());
    let logs = Arc::new(Mutex::new(Vec::new()));
    let sink_logs = logs.clone();
    let sink: LogSink = Arc::new(move |line| sink_logs.lock().unwrap().push(line.to_string()));
    let app = App::new(
        settings,
        verifier_for(vec![MCP_CLIENT.into()]),
        verifier_for(vec![CONNECTOR_CLIENT.into()]),
        verifier_for(vec![DASHBOARD_CLIENT.into()]),
        store.clone(),
        timing,
        sink,
    );
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(serve(listener, app.clone()));
    Harness {
        app,
        addr,
        rsa,
        logs,
        store,
        tokens,
    }
}

impl Harness {
    pub(crate) fn mcp_token(&self, sub: &str) -> String {
        mint(&self.rsa, MCP_CLIENT, sub)
    }

    pub(crate) fn connector_token(&self, sub: &str) -> String {
        mint(&self.rsa, CONNECTOR_CLIENT, sub)
    }

    pub(crate) fn dashboard_token(&self, sub: &str) -> String {
        mint(&self.rsa, DASHBOARD_CLIENT, sub)
    }

    pub(crate) fn logs(&self) -> String {
        self.logs.lock().unwrap().join("\n")
    }

    /// Opens a connection and sends one request. The returned future drives
    /// the response; dropping it (and the connection task) drops the request.
    pub(crate) async fn send(
        &self,
        method: &str,
        path: &str,
        headers: &[(&str, String)],
        body: &str,
    ) -> Reply {
        let stream = tokio::net::TcpStream::connect(self.addr).await.unwrap();
        let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(stream))
            .await
            .unwrap();
        let conn = tokio::spawn(conn);
        let mut req = Request::builder()
            .method(method)
            .uri(path)
            .header(header::HOST, "relay.example.test");
        for (k, v) in headers {
            req = req.header(*k, v);
        }
        let resp = sender
            .send_request(req.body(Full::new(Bytes::from(body.to_string()))).unwrap())
            .await
            .unwrap();
        let status = resp.status();
        let headers = resp.headers().clone();
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        conn.abort();
        Reply {
            status,
            headers,
            body: String::from_utf8_lossy(&body).into_owned(),
        }
    }

    /// Writes raw bytes and returns what comes back up to the end of the
    /// response head (or EOF). For requests hyper's client won't send.
    async fn raw(&self, bytes: &[u8]) -> String {
        use tokio::io::{AsyncReadExt, AsyncWriteExt};
        let mut stream = tokio::net::TcpStream::connect(self.addr).await.unwrap();
        stream.write_all(bytes).await.unwrap();
        let mut got = Vec::new();
        within(async {
            let mut buf = [0u8; 1024];
            loop {
                match stream.read(&mut buf).await {
                    Ok(0) | Err(_) => break,
                    Ok(n) => got.extend_from_slice(&buf[..n]),
                }
                if got.windows(4).any(|w| w == b"\r\n\r\n") {
                    break;
                }
            }
        })
        .await;
        String::from_utf8_lossy(&got).into_owned()
    }

    pub(crate) async fn get(&self, path: &str) -> Reply {
        self.send("GET", path, &[], "").await
    }

    /// A new device for `sub` (no name, no device id sent).
    pub(crate) async fn register(&self, sub: &str, key: &Ed25519KeyPair) -> Reply {
        self.register_with(sub, key, None, None).await
    }

    /// What `vrelay login` sends: the key, and a name and the device id when
    /// it has them.
    async fn register_with(
        &self,
        sub: &str,
        key: &Ed25519KeyPair,
        name: Option<&str>,
        device_id: Option<&str>,
    ) -> Reply {
        let mut body = json!({"public_key": b64(key.public_key().as_ref())});
        if let Some(name) = name {
            body["name"] = json!(name);
        }
        if let Some(id) = device_id {
            body["device_id"] = json!(id);
        }
        self.register_body(sub, &body.to_string()).await
    }

    pub(crate) async fn register_body(&self, sub: &str, body: &str) -> Reply {
        self.send(
            "POST",
            "/devices",
            &[
                (
                    "authorization",
                    format!("Bearer {}", self.connector_token(sub)),
                ),
                ("content-type", "application/json".into()),
            ],
            body,
        )
        .await
    }

    /// Registers `key` as the new key of a device `sub` already has.
    async fn reregister(&self, sub: &str, device: &str, key: &Ed25519KeyPair) -> Reply {
        self.register_with(sub, key, None, Some(device)).await
    }

    /// Registers a device for `sub` and returns its id and key.
    pub(crate) async fn new_device(&self, sub: &str) -> (String, Ed25519KeyPair) {
        let key = ed25519();
        let r = self.register(sub, &key).await;
        assert_eq!(r.status, StatusCode::OK, "{}", r.body);
        (r.json()["device_id"].as_str().unwrap().to_string(), key)
    }

    pub(crate) fn mcp_headers(
        &self,
        sub: &str,
        session: Option<&str>,
    ) -> Vec<(&'static str, String)> {
        let mut h = vec![
            ("authorization", format!("Bearer {}", self.mcp_token(sub))),
            ("accept", ACCEPT.to_string()),
            ("content-type", "application/json".to_string()),
        ];
        if let Some(s) = session {
            h.push(("mcp-session-id", s.to_string()));
        }
        h
    }

    pub(crate) async fn rpc(
        &self,
        device: &str,
        sub: &str,
        session: Option<&str>,
        body: Value,
    ) -> Reply {
        self.send(
            "POST",
            &format!("/mcp/d/{device}"),
            &self.mcp_headers(sub, session),
            &body.to_string(),
        )
        .await
    }

    /// `initialize`, then returns the session id it handed out.
    pub(crate) async fn session(&self, device: &str, sub: &str) -> String {
        let r = self
            .rpc(
                device,
                sub,
                None,
                json!({"jsonrpc": "2.0", "id": 0, "method": "initialize",
                       "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                                  "clientInfo": {"name": "test", "version": "0"}}}),
            )
            .await;
        assert_eq!(r.status, StatusCode::OK, "{}", r.body);
        r.header("mcp-session-id").expect("session id")
    }

    // The error is tungstenite's own (it carries the refused HTTP response).
    #[allow(clippy::result_large_err)]
    pub(crate) async fn ws(
        &self,
        token: &str,
    ) -> Result<
        tokio_tungstenite::WebSocketStream<tokio::net::TcpStream>,
        tokio_tungstenite::tungstenite::Error,
    > {
        let stream = tokio::net::TcpStream::connect(self.addr).await.unwrap();
        self.ws_on(stream, token).await
    }

    #[allow(clippy::result_large_err)]
    async fn ws_on<S>(
        &self,
        stream: S,
        token: &str,
    ) -> Result<tokio_tungstenite::WebSocketStream<S>, tokio_tungstenite::tungstenite::Error>
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
    {
        let mut req = format!("ws://{}/connect", self.addr)
            .into_client_request()
            .unwrap();
        req.headers_mut().insert(
            header::AUTHORIZATION,
            format!("Bearer {token}").parse().unwrap(),
        );
        tokio_tungstenite::client_async(req, stream)
            .await
            .map(|(ws, _)| ws)
    }

    /// Connects as the device and waits for `welcome`.
    pub(crate) async fn connect(
        &self,
        sub: &str,
        device: &str,
        key: &Ed25519KeyPair,
        tools: Vec<ToolDef>,
    ) -> FakeDevice {
        let stream = tokio::net::TcpStream::connect(self.addr).await.unwrap();
        self.connect_on(stream, sub, device, key, tools).await
    }

    /// `connect` over a stream the test chooses (e.g. a throttled one).
    async fn connect_on<S>(
        &self,
        stream: S,
        sub: &str,
        device: &str,
        key: &Ed25519KeyPair,
        tools: Vec<ToolDef>,
    ) -> FakeDevice
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        let token = self.connector_token(sub);
        let mut ws = self.ws_on(stream, &token).await.unwrap();
        ws.send(Message::Text(hello(device, key, &token, now_secs(), tools)))
            .await
            .unwrap();
        match next_frame(&mut ws).await {
            Some(ToConnector::Welcome { device_id }) => assert_eq!(device_id, device),
            other => panic!("expected welcome, got {other:?}"),
        }
        FakeDevice::spawn(ws)
    }
}

pub(crate) fn ed25519() -> Ed25519KeyPair {
    let doc = Ed25519KeyPair::generate_pkcs8(&SystemRandom::new()).unwrap();
    Ed25519KeyPair::from_pkcs8(doc.as_ref()).unwrap()
}

fn token_hash(token: &str) -> String {
    crate::hex(ring::digest::digest(&ring::digest::SHA256, token.as_bytes()).as_ref())
}

fn hello(device: &str, key: &Ed25519KeyPair, token: &str, ts: u64, tools: Vec<ToolDef>) -> String {
    let sig = key.sign(hello_message(device, ts, &token_hash(token)).as_bytes());
    encode(&ToRelay::Hello(Hello {
        device_id: device.into(),
        connector_version: "0.0.0".into(),
        protocol: PROTOCOL,
        ts,
        sig: b64(sig.as_ref()),
        tools,
    }))
    .unwrap()
}

async fn next_frame<S>(ws: &mut tokio_tungstenite::WebSocketStream<S>) -> Option<ToConnector>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    loop {
        match within(ws.next()).await? {
            Ok(Message::Text(t)) => return Some(decode_to_connector(&t).unwrap()),
            Ok(Message::Close(_)) | Err(_) => return None,
            Ok(_) => {}
        }
    }
}

pub(crate) fn tool(name: &str) -> ToolDef {
    ToolDef {
        name: name.into(),
        description: format!("the {name} tool"),
        input_schema: json!({"type": "object"}),
    }
}

/// A connector on a real WebSocket: answers pings (until told not to), hands
/// calls and cancels to the test, and sends what the test gives it.
pub(crate) struct FakeDevice {
    pub(crate) frames: mpsc::UnboundedReceiver<ToConnector>,
    pub(crate) out: mpsc::UnboundedSender<ToRelay>,
    pub(crate) answer_pings: Arc<AtomicBool>,
    pub(crate) auto_ack: Arc<AtomicBool>,
    pub(crate) starts: Arc<Mutex<Vec<String>>>,
    /// Ids the relay sent a `ResultAck` for (kept out of `frames`).
    pub(crate) result_acks: Arc<Mutex<Vec<String>>>,
    /// Pings received from the relay.
    pub(crate) pings: Arc<AtomicU32>,
    pub(crate) closed: Arc<tokio::sync::Notify>,
    pub(crate) is_closed: Arc<AtomicBool>,
}

impl FakeDevice {
    fn spawn<S>(ws: tokio_tungstenite::WebSocketStream<S>) -> Self
    where
        S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin + Send + 'static,
    {
        let (frames_tx, frames) = mpsc::unbounded_channel();
        let (out, mut out_rx) = mpsc::unbounded_channel::<ToRelay>();
        let answer_pings = Arc::new(AtomicBool::new(true));
        let auto_ack = Arc::new(AtomicBool::new(true));
        let starts = Arc::new(Mutex::new(Vec::new()));
        let result_acks = Arc::new(Mutex::new(Vec::new()));
        let result_acks2 = result_acks.clone();
        let pings = Arc::new(AtomicU32::new(0));
        let pings2 = pings.clone();
        let closed = Arc::new(tokio::sync::Notify::new());
        let is_closed = Arc::new(AtomicBool::new(false));
        let (answer, auto_ack2, starts2, closed2, is_closed2) = (
            answer_pings.clone(),
            auto_ack.clone(),
            starts.clone(),
            closed.clone(),
            is_closed.clone(),
        );
        tokio::spawn(async move {
            let (mut sink, mut stream) = ws.split();
            loop {
                tokio::select! {
                    f = out_rx.recv() => match f {
                        Some(f) => { let _ = sink.send(Message::Text(encode(&f).unwrap())).await; }
                        None => break,
                    },
                    m = stream.next() => match m {
                        Some(Ok(Message::Text(t))) => match decode_to_connector(&t).unwrap() {
                            ToConnector::Ping { n } => {
                                pings2.fetch_add(1, Ordering::SeqCst);
                                if answer.load(Ordering::SeqCst) {
                                    let _ = sink.send(Message::Text(encode(&ToRelay::Pong { n }).unwrap())).await;
                                }
                            }
                            ToConnector::Call(c) => {
                                if auto_ack2.load(Ordering::SeqCst) {
                                    let ack = encode(&ToRelay::Ack {
                                        call_id: c.call_id.clone(),
                                    })
                                    .unwrap();
                                    let _ = sink.send(Message::Text(ack)).await;
                                }
                                let _ = frames_tx.send(ToConnector::Call(c));
                            }
                            ToConnector::Start { call_id } => {
                                starts2.lock().unwrap().push(call_id.clone());
                                if !auto_ack2.load(Ordering::SeqCst) {
                                    let _ = frames_tx.send(ToConnector::Start { call_id });
                                }
                            }
                            ToConnector::ResultAck { call_id } => {
                                result_acks2.lock().unwrap().push(call_id);
                            }
                            other => { let _ = frames_tx.send(other); }
                        },
                        Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                        Some(Ok(_)) => {}
                    },
                }
            }
            is_closed2.store(true, Ordering::SeqCst);
            closed2.notify_waiters();
            closed2.notify_one();
        });
        FakeDevice {
            frames,
            out,
            answer_pings,
            auto_ack,
            starts,
            result_acks,
            pings,
            closed,
            is_closed,
        }
    }

    /// Ids the relay has acknowledged results for, in order.
    fn result_acks(&self) -> Vec<String> {
        self.result_acks.lock().unwrap().clone()
    }

    fn no_ack(&self) {
        self.auto_ack.store(false, Ordering::SeqCst);
    }

    pub(crate) async fn next(&mut self) -> ToConnector {
        within(self.frames.recv()).await.expect("device frame")
    }

    pub(crate) async fn next_call(&mut self) -> Call {
        match self.next().await {
            ToConnector::Call(c) => c,
            other => panic!("expected a call, got {other:?}"),
        }
    }

    pub(crate) fn send(&self, f: ToRelay) {
        self.out.send(f).unwrap();
    }

    pub(crate) fn reply(&self, call_id: &str, text: &str) {
        self.send(ToRelay::Result(CallResult {
            call_id: call_id.into(),
            content: json!([{"type": "text", "text": text}]),
            is_error: false,
            truncated: false,
        }));
    }

    pub(crate) async fn wait_closed(&self) {
        within(async {
            while !self.is_closed.load(Ordering::SeqCst) {
                let _ =
                    tokio::time::timeout(Duration::from_millis(50), self.closed.notified()).await;
            }
        })
        .await
    }
}

pub(crate) fn call_body(id: Value, tool: &str, args: Value) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "method": "tools/call",
           "params": {"name": tool, "arguments": args}})
}

/// Starts a tools/call in the background.
pub(crate) fn spawn_rpc(
    h: &Arc<Harness>,
    device: &str,
    sub: &str,
    session: &str,
    body: Value,
) -> tokio::task::JoinHandle<Reply> {
    let (h, device, sub, session) = (
        h.clone(),
        device.to_string(),
        sub.to_string(),
        session.to_string(),
    );
    tokio::spawn(async move { h.rpc(&device, &sub, Some(&session), body).await })
}

// ---------------------------------------------------------------- the tests

#[tokio::test]
async fn healthz_ok() {
    let h = harness().await;
    let r = h.get("/healthz").await;
    assert_eq!((r.status, r.body.as_str()), (StatusCode::OK, "ok"));
}

#[tokio::test]
async fn get_and_delete_get_405() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    for method in ["GET", "DELETE"] {
        let r = h
            .send(
                method,
                &format!("/mcp/d/{device}"),
                &h.mcp_headers(ALICE, None),
                "",
            )
            .await;
        assert_eq!(r.status, StatusCode::METHOD_NOT_ALLOWED, "{method}");
    }
}

#[tokio::test]
async fn bare_prm_names_the_relay() {
    let h = harness().await;
    let r = h.get("/.well-known/oauth-protected-resource").await;
    assert_eq!(r.status, StatusCode::OK);
    let m = r.json();
    assert_eq!(m["resource"], PUBLIC_URL);
    assert_eq!(m["authorization_servers"], json!([ISSUER]));

    // The per-device document names that device's URL. It is served for any
    // well-formed id, so it says nothing about which devices exist.
    let r = h
        .get("/.well-known/oauth-protected-resource/mcp/d/abc-123")
        .await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.json()["resource"], format!("{PUBLIC_URL}/mcp/d/abc-123"));
    assert_eq!(
        r.json()["scopes_supported"][2],
        format!("urn:zitadel:iam:org:project:id:{PROJECT_ID}:aud")
    );
}

#[tokio::test]
async fn mcp_requires_token_with_www_authenticate() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let path = format!("/mcp/d/{device}");
    let metadata = format!("{PUBLIC_URL}/.well-known/oauth-protected-resource/mcp/d/{device}");
    let body = json!({"jsonrpc": "2.0", "id": 1, "method": "initialize"}).to_string();

    let r = h
        .send("POST", &path, &[("accept", ACCEPT.into())], &body)
        .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
    assert_eq!(
        r.header("www-authenticate").unwrap(),
        format!("Bearer resource_metadata=\"{metadata}\"")
    );

    let r = h
        .send(
            "POST",
            &path,
            &[
                ("authorization", "Bearer a.b.c".into()),
                ("accept", ACCEPT.into()),
            ],
            &body,
        )
        .await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
    let challenge = r.header("www-authenticate").unwrap();
    assert!(challenge.contains("error=\"invalid_token\""), "{challenge}");
    assert!(
        challenge.contains(&format!("resource_metadata=\"{metadata}\"")),
        "{challenge}"
    );

    // The connector's token is for another client: refused on /mcp.
    let r = h
        .send(
            "POST",
            &path,
            &[
                (
                    "authorization",
                    format!("Bearer {}", h.connector_token(ALICE)),
                ),
                ("accept", ACCEPT.into()),
            ],
            &body,
        )
        .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn mcp_rejects_other_users_device_as_404() {
    let h = harness().await;
    let (bobs, _) = h.new_device(BOB).await;
    let init = json!({"jsonrpc": "2.0", "id": 1, "method": "initialize"});
    let theirs = h.rpc(&bobs, ALICE, None, init.clone()).await;
    let missing = h.rpc("no-such-device", ALICE, None, init.clone()).await;
    assert_eq!(theirs.status, StatusCode::NOT_FOUND);
    // Indistinguishable from a device that does not exist.
    assert_eq!(
        (missing.status, &missing.body),
        (theirs.status, &theirs.body)
    );
    // The owner gets in.
    assert_eq!(h.rpc(&bobs, BOB, None, init).await.status, StatusCode::OK);

    // A session opened on one device does not work on another.
    let (alices, _) = h.new_device(ALICE).await;
    let s = h.session(&alices, ALICE).await;
    let bob_session_on_alice = h
        .rpc(
            &bobs,
            BOB,
            Some(&s),
            json!({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
        )
        .await;
    assert_eq!(bob_session_on_alice.status, StatusCode::NOT_FOUND);

    // Nor on another device of the same person (P2 allows several; P1's
    // registration does not, so the record goes straight into the store).
    h.store
        .insert_device(&NewDevice {
            device_id: "alices-second".into(),
            owner_sub: ALICE.into(),
            name: "Second".into(),
            public_key_ed25519: [9; 32],
        })
        .await
        .unwrap();
    let r = h
        .rpc(
            "alices-second",
            ALICE,
            Some(&s),
            json!({"jsonrpc": "2.0", "id": 3, "method": "tools/list"}),
        )
        .await;
    assert_eq!(r.status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn server_discover_is_answered() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let r = h
        .rpc(
            &device,
            ALICE,
            None,
            json!({"jsonrpc": "2.0", "id": "d", "method": "server/discover"}),
        )
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(
        r.header("mcp-session-id"),
        None,
        "discover starts no session"
    );
    let res = &r.json()["result"];
    assert_eq!(res["serverInfo"]["name"], SERVER_NAME);
    assert_eq!(res["serverInfo"]["version"], env!("CARGO_PKG_VERSION"));
    assert_eq!(
        res["capabilities"],
        json!({"tools": {"listChanged": false}})
    );
    // Discover is the stateless revision's request: it lists only the
    // versions served that way (older ones are reached through initialize),
    // with the fields that revision requires on a result.
    assert_eq!(res["supportedVersions"], json!(MODERN_VERSIONS));
    assert_eq!(res["resultType"], "complete");
    assert!(res["ttlMs"].as_u64().is_some(), "{res}");
    assert_eq!(res["cacheScope"], "public");
    assert_eq!(
        res["_meta"]["io.modelcontextprotocol/serverInfo"],
        res["serverInfo"]
    );

    // initialize describes the server the same way.
    let r = h
        .rpc(
            &device,
            ALICE,
            None,
            json!({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                                          "params": {"protocolVersion": "1999-01-01"}}),
        )
        .await;
    let init = &r.json()["result"];
    assert_eq!(init["serverInfo"], res["serverInfo"]);
    assert_eq!(init["capabilities"], res["capabilities"]);
    assert_eq!(init["protocolVersion"], LEGACY_VERSIONS[0]);
    let id = r.header("mcp-session-id").unwrap();
    assert_eq!(id.len(), 32);
    assert!(id.bytes().all(|c| c.is_ascii_hexdigit()));
}

#[tokio::test]
async fn unknown_session_gets_404() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let list = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"});
    let r = h
        .rpc(
            &device,
            ALICE,
            Some("0123456789abcdef0123456789abcdef"),
            list.clone(),
        )
        .await;
    assert_eq!(r.status, StatusCode::NOT_FOUND);
    let r = h.rpc(&device, ALICE, None, list.clone()).await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST);
    // A real session works; it is bound to the subject that opened it.
    let s = h.session(&device, ALICE).await;
    let r = h.rpc(&device, ALICE, Some(&s), list.clone()).await;
    assert_eq!(r.status, StatusCode::OK);
    // Offline: no device tools, no error. The relay's own tool is still
    // listed (a request parked before the device went away can be fetched).
    let names: Vec<Value> = r.json()["result"]["tools"]
        .as_array()
        .unwrap()
        .iter()
        .map(|t| t["name"].clone())
        .collect();
    assert_eq!(names, [json!("check_request")]);
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            json!({"jsonrpc": "2.0", "id": 2, "method": "ping"}),
        )
        .await;
    assert_eq!(r.json()["result"], json!({"resultType": "complete"}));
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            json!({"jsonrpc": "2.0", "method": "notifications/initialized"}),
        )
        .await;
    assert_eq!(r.status, StatusCode::ACCEPTED);
}

#[tokio::test]
async fn register_device_returns_mcp_url() {
    let h = harness().await;
    let key = ed25519();
    let r = h.register(ALICE, &key).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    let id = r.json()["device_id"].as_str().unwrap().to_string();
    assert_eq!(id.len(), 36);
    assert_eq!(&id[14..15], "4", "uuid v4: {id}");
    assert_eq!(r.json()["mcp_url"], format!("{PUBLIC_URL}/mcp/d/{id}"));
    let mut expected_key = [0u8; 32];
    expected_key.copy_from_slice(key.public_key().as_ref());
    let stored = h.store.device(&id).await.unwrap().expect("stored");
    assert_eq!(
        (
            stored.device_id.as_str(),
            stored.owner_sub.as_str(),
            stored.name.as_str(),
            stored.public_key_ed25519,
            stored.revoked
        ),
        (id.as_str(), ALICE, "My Mac", expected_key, false)
    );

    // Bad bodies and the wrong client are refused.
    let auth = (
        "authorization",
        format!("Bearer {}", h.connector_token(ALICE)),
    );
    for bad in [
        "not json".to_string(),
        json!({"public_key": b64(&[1u8; 31])}).to_string(),
        json!({"public_key": "!!!"}).to_string(),
        json!({}).to_string(),
    ] {
        let r = h
            .send("POST", "/devices", std::slice::from_ref(&auth), &bad)
            .await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{bad}");
    }
    let r = h
        .send(
            "POST",
            "/devices",
            &[("authorization", format!("Bearer {}", h.mcp_token(ALICE)))],
            &json!({"public_key": b64(key.public_key().as_ref())}).to_string(),
        )
        .await;
    assert_eq!(r.status, StatusCode::FORBIDDEN);
    let r = h.send("POST", "/devices", &[], "{}").await;
    assert_eq!(r.status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn reregister_kicks_old_session() {
    let h = harness().await;
    let (device, old_key) = h.new_device(ALICE).await;
    let fake = h.connect(ALICE, &device, &old_key, vec![tool("a")]).await;

    let new_key = ed25519();
    let r = h.reregister(ALICE, &device, &new_key).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.json()["device_id"], device.as_str(), "same id, new key");
    fake.wait_closed().await;

    // The old key no longer gets in; the new one does.
    let token = h.connector_token(ALICE);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &old_key,
        &token,
        now_secs(),
        vec![],
    )))
    .await
    .unwrap();
    assert!(matches!(
        next_frame(&mut ws).await,
        Some(ToConnector::Reject { .. })
    ));
    h.connect(ALICE, &device, &new_key, vec![]).await;
}

#[tokio::test]
async fn tools_list_reflects_hello_tools() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let fake = h
        .connect(
            ALICE,
            &device,
            &key,
            vec![tool("read_file"), tool("list_directory")],
        )
        .await;
    let s = h.session(&device, ALICE).await;
    let names = |r: Reply| -> Vec<String> {
        r.json()["result"]["tools"]
            .as_array()
            .unwrap()
            .iter()
            .map(|t| t["name"].as_str().unwrap().to_string())
            .collect()
    };
    let list = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"});
    let r = h.rpc(&device, ALICE, Some(&s), list.clone()).await;
    assert_eq!(
        r.json()["result"]["tools"][0]["inputSchema"],
        json!({"type": "object"})
    );
    // The relay's own tool follows the device's.
    assert_eq!(
        names(r),
        vec!["read_file", "list_directory", "check_request"]
    );

    // tools_changed: the next tools/list sees it.
    fake.send(ToRelay::ToolsChanged {
        tools: vec![tool("write_file")],
    });
    within(async {
        loop {
            if names(h.rpc(&device, ALICE, Some(&s), list.clone()).await)
                == vec!["write_file", "check_request"]
            {
                break;
            }
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;
}

#[tokio::test]
async fn connect_rejects_bad_signature() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let token = h.connector_token(ALICE);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &ed25519(),
        &token,
        now_secs(),
        vec![],
    )))
    .await
    .unwrap();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => assert!(reason.contains("signature"), "{reason}"),
        other => panic!("expected reject, got {other:?}"),
    }
    assert!(next_frame(&mut ws).await.is_none(), "closed after reject");

    // A signature made for a different token does not verify either.
    let (bobs, bobs_key) = h.new_device(BOB).await;
    let bob_token = h.connector_token(BOB);
    let mut ws = h.ws(&bob_token).await.unwrap();
    ws.send(Message::Text(hello(
        &bobs,
        &bobs_key,
        &format!("{bob_token}x"),
        now_secs(),
        vec![],
    )))
    .await
    .unwrap();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => assert!(reason.contains("signature"), "{reason}"),
        other => panic!("expected reject, got {other:?}"),
    }

    // Someone else's device: refused, even with that device's own key.
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &bobs,
        &bobs_key,
        &token,
        now_secs(),
        vec![],
    )))
    .await
    .unwrap();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => {
            assert!(reason.contains("not registered"), "{reason}")
        }
        other => panic!("expected reject, got {other:?}"),
    }
}

#[tokio::test]
async fn connect_rejects_stale_ts() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let token = h.connector_token(ALICE);
    for ts in [now_secs() - 120, now_secs() + 120] {
        let mut ws = h.ws(&token).await.unwrap();
        ws.send(Message::Text(hello(&device, &key, &token, ts, vec![])))
            .await
            .unwrap();
        match next_frame(&mut ws).await {
            Some(ToConnector::Reject { reason }) => assert!(reason.contains("clock"), "{reason}"),
            other => panic!("expected reject, got {other:?}"),
        }
    }
    // Within a minute is fine.
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &key,
        &token,
        now_secs() - 30,
        vec![],
    )))
    .await
    .unwrap();
    assert!(matches!(
        next_frame(&mut ws).await,
        Some(ToConnector::Welcome { .. })
    ));
}

#[tokio::test]
async fn connect_rejects_token_for_another_client() {
    let h = harness().await;
    match h.ws(&h.mcp_token(ALICE)).await {
        Err(tokio_tungstenite::tungstenite::Error::Http(resp)) => {
            assert_eq!(resp.status(), StatusCode::FORBIDDEN)
        }
        Err(e) => panic!("expected an HTTP refusal, got {e}"),
        Ok(_) => panic!("an AI app's token must not open /connect"),
    }
    match h.ws("not-a-token").await {
        Err(tokio_tungstenite::tungstenite::Error::Http(resp)) => {
            assert_eq!(resp.status(), StatusCode::UNAUTHORIZED)
        }
        _ => panic!("expected 401"),
    }
}

#[tokio::test]
async fn connect_rejects_a_wrong_first_frame_and_old_protocol() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let token = h.connector_token(ALICE);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(encode(&ToRelay::Ping { n: 1 }).unwrap()))
        .await
        .unwrap();
    assert!(matches!(
        next_frame(&mut ws).await,
        Some(ToConnector::Reject { .. })
    ));

    let mut frame: Value =
        serde_json::from_str(&hello(&device, &key, &token, now_secs(), vec![])).unwrap();
    frame["protocol"] = json!(1);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(frame.to_string())).await.unwrap();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => assert!(reason.contains("protocol"), "{reason}"),
        other => panic!("expected reject, got {other:?}"),
    }
}

#[tokio::test]
async fn connect_rejects_when_no_hello_arrives() {
    let h = harness_with(Timing {
        hello_timeout: Duration::from_millis(200),
        ..Timing::default()
    })
    .await;
    let mut ws = h.ws(&h.connector_token(ALICE)).await.unwrap();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => assert!(reason.contains("hello"), "{reason}"),
        other => panic!("expected reject, got {other:?}"),
    }
}

#[tokio::test]
async fn call_reaches_the_device_and_answers() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(5), "read_file", json!({"path": "/tmp/x"})),
    );
    let call = fake.next_call().await;
    assert_eq!(
        (call.tool.as_str(), &call.arguments),
        ("read_file", &json!({"path": "/tmp/x"}))
    );
    // What is left of the call budget when the frame is written, less the
    // 6 s allowed for it to arrive: a little under 84 s, never over.
    assert!(
        (79_000..=84_000).contains(&call.deadline_ms),
        "{}",
        call.deadline_ms
    );
    assert_eq!(call.call_id.len(), 32);
    fake.reply(&call.call_id, "contents");
    let r = within(pending).await.unwrap();
    assert_eq!(r.json()["id"], 5);
    assert_eq!(r.json()["result"]["content"][0]["text"], "contents");
    assert_eq!(r.json()["result"]["isError"], false);

    // Offline: a tool result with the error, not a protocol error.
    drop(fake);
    let (other, _) = h.new_device(BOB).await;
    let s = h.session(&other, BOB).await;
    let r = h
        .rpc(
            &other,
            BOB,
            Some(&s),
            call_body(json!(6), "read_file", json!({})),
        )
        .await;
    assert_eq!(r.json()["result"]["isError"], true);
    assert_eq!(
        r.json()["result"]["content"][0]["text"],
        offline_said("My Mac", "never")
    );
}

/// The words for a call to a computer that is not connected.
fn offline_said(name: &str, last_seen: &str) -> String {
    format!(
        "Your computer \"{name}\" is offline (last seen {last_seen}). \
         It may be asleep, shut down or off the network."
    )
}

/// The activity rows for `sub`, once there are `n` of them (they are written
/// in the background, after the call has answered).
async fn activity_when(h: &Harness, sub: &str, n: usize) -> Vec<crate::store::ActivityRow> {
    within(async {
        loop {
            let rows = h.store.activity_of(sub, None, 100).await.unwrap();
            if rows.len() >= n {
                return rows;
            }
            tokio::time::sleep(Duration::from_millis(10)).await;
        }
    })
    .await
}

/// The relay keeps no content (spec 7.2): the row says which tool, how big,
/// how long and how it went, and no column can hold what was asked or said.
#[tokio::test]
async fn activity_row_written_without_content() {
    const MARKER: &str = "SECRET-MARKER-9f3a";
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let s = h.session(&device, ALICE).await;
    let args = json!({"path": format!("/tmp/{MARKER}")});
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(5), "read_file", args.clone()),
    );
    let call = fake.next_call().await;
    fake.reply(&call.call_id, &format!("the file says {MARKER}"));
    let r = within(pending).await.unwrap();
    assert!(text_of(&r).contains(MARKER), "the person gets the result");

    let rows = activity_when(&h, ALICE, 1).await;
    assert_eq!(rows.len(), 1);
    let row = &rows[0];
    assert_eq!(row.owner_sub, ALICE);
    assert_eq!(row.device_id, device);
    assert_eq!(row.client_id, MCP_CLIENT);
    assert_eq!(row.tool, "read_file");
    assert_eq!(row.outcome, "ok");
    assert_eq!(row.arg_bytes, Some(args.to_string().len() as u32));
    let reply = json!([{"type": "text", "text": format!("the file says {MARKER}")}]);
    assert_eq!(row.result_bytes, Some(reply.to_string().len() as u32));
    assert!(row.duration_ms.is_some());
    // Nothing a person said or got back is in the row, or in the log.
    assert!(!format!("{row:?}").contains(MARKER), "{row:?}");
    assert!(!h.logs().contains(MARKER), "the log holds content");

    // Another person never sees it.
    assert!(h
        .store
        .activity_of(BOB, None, 100)
        .await
        .unwrap()
        .is_empty());
}

/// Every call is recorded, a refusal and an offline computer included.
#[tokio::test]
async fn every_call_is_recorded_whatever_its_outcome() {
    let h = Arc::new(harness().await);
    let (device, _key) = h.new_device(ALICE).await;
    let s = h.session(&device, ALICE).await;
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(1), "read_file", json!({})),
        )
        .await;
    assert!(error_text(&r).contains("is offline"));
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(2), CHECK_REQUEST_NAME, json!({"request_id": "nope"})),
        )
        .await;
    assert_eq!(r.json()["result"]["isError"], true);

    let rows = activity_when(&h, ALICE, 2).await;
    let mut seen: Vec<(String, String)> = rows
        .iter()
        .map(|r| (r.tool.clone(), r.outcome.clone()))
        .collect();
    seen.sort();
    assert_eq!(
        seen,
        [
            ("check_request".to_string(), "unknown_request".to_string()),
            ("read_file".to_string(), "offline".to_string()),
        ]
    );
}

const CHECK_REQUEST_NAME: &str = crate::mcp::CHECK_REQUEST;

/// A call is never failed by its own log line: the person gets the result,
/// the failed write is logged, and nothing is kept.
#[tokio::test]
async fn activity_write_failure_does_not_fail_call() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let s = h.session(&device, ALICE).await;
    h.store
        .fail_activity_writes_with(Some(StoreError::Unavailable));
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(5), "read_file", json!({})),
    );
    let call = fake.next_call().await;
    fake.reply(&call.call_id, "contents");
    let r = within(pending).await.unwrap();
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(r.json()["result"]["isError"], false, "{}", r.body);
    assert_eq!(text_of(&r), "contents");

    until(|| h.logs().contains("\"activity_write_failed\"")).await;
    assert!(h
        .store
        .activity_of(ALICE, None, 10)
        .await
        .unwrap()
        .is_empty());

    // The database is writable again: the next call is recorded.
    h.store.fail_activity_writes_with(None);
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(6), "read_file", json!({"again": 1})),
    );
    let call = fake.next_call().await;
    fake.reply(&call.call_id, "contents");
    within(pending).await.unwrap();
    assert_eq!(activity_when(&h, ALICE, 1).await.len(), 1);
}

#[tokio::test]
async fn offline_message_names_device_and_last_seen() {
    let h = harness().await;
    let key = ed25519();
    let r = h.register_with(ALICE, &key, Some("Studio Mac"), None).await;
    let device = r.json()["device_id"].as_str().unwrap().to_string();
    let s = h.session(&device, ALICE).await;
    let ask = |id: u64| {
        h.rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(id), "read_file", json!({"n": id})),
        )
    };

    // Never connected.
    assert_eq!(
        error_text(&ask(1).await),
        offline_said("Studio Mac", "never")
    );

    // Seen at various times before now. Each on a computer of its own:
    // "last seen" never moves back, so one computer cannot be set to a
    // later and then an earlier time.
    let now = SystemTime::now();
    for (secs, said) in [
        (5, "just now"),
        (60, "1 minute ago"),
        (7 * 60 + 30, "7 minutes ago"),
        (3600, "1 hour ago"),
        (3 * 3600 + 120, "3 hours ago"),
        (24 * 3600, "1 day ago"),
        (4 * 24 * 3600 + 3600, "4 days ago"),
    ] {
        let who = format!("person-{secs}");
        let r = h
            .register_with(&who, &ed25519(), Some("Studio Mac"), None)
            .await;
        let dev = r.json()["device_id"].as_str().unwrap().to_string();
        let sess = h.session(&dev, &who).await;
        h.store
            .touch_seen(&dev, now - Duration::from_secs(secs))
            .await
            .unwrap();
        let r = h
            .rpc(
                &dev,
                &who,
                Some(&sess),
                call_body(json!(1), "read_file", json!({})),
            )
            .await;
        assert_eq!(
            error_text(&r),
            offline_said("Studio Mac", said),
            "{secs} s ago"
        );
    }

    // It says which computer, so a second one has its own words.
    let other = h
        .register_with(ALICE, &ed25519(), Some("Laptop"), None)
        .await;
    let other = other.json()["device_id"].as_str().unwrap().to_string();
    let s2 = h.session(&other, ALICE).await;
    let r = h
        .rpc(
            &other,
            ALICE,
            Some(&s2),
            call_body(json!(1), "read_file", json!({})),
        )
        .await;
    assert_eq!(error_text(&r), offline_said("Laptop", "never"));

    // Plain words that end with what to do or what may be going on.
    let said = error_text(&ask(99_999).await);
    assert!(said.ends_with("It may be asleep, shut down or off the network."));
}

#[test]
fn how_long_ago_is_said_the_way_a_person_would() {
    let now = SystemTime::now();
    let at = |secs: u64| Some(now - Duration::from_secs(secs));
    assert_eq!(crate::mcp::ago(None, now), "never");
    for (secs, said) in [
        (0, "just now"),
        (59, "just now"),
        (60, "1 minute ago"),
        (119, "1 minute ago"),
        (120, "2 minutes ago"),
        (3599, "59 minutes ago"),
        (3600, "1 hour ago"),
        (86_399, "23 hours ago"),
        (86_400, "1 day ago"),
        (30 * 86_400, "30 days ago"),
    ] {
        assert_eq!(crate::mcp::ago(at(secs), now), said, "{secs} s");
    }
    // A last-seen in the future (a clock that stepped back) is "just now".
    assert_eq!(
        crate::mcp::ago(Some(now + Duration::from_secs(90)), now),
        "just now"
    );
}

/// 20 calls at once are fine, the 21st is refused in plain words and recorded
/// as such, and it is per person: someone else is not held up.
#[tokio::test]
async fn twenty_first_burst_call_is_rate_limited() {
    // The same burst, but refilling one call a minute so the test does not
    // depend on how fast it runs.
    let h = harness_with(Timing {
        calls_per_minute: 1,
        ..Timing::default()
    })
    .await;
    assert_eq!(Timing::default().calls_per_minute, 60);
    assert_eq!(Timing::default().rate_burst, 20);
    let (device, _key) = h.new_device(ALICE).await;
    let s = h.session(&device, ALICE).await;
    for i in 1..=20u64 {
        let r = h
            .rpc(
                &device,
                ALICE,
                Some(&s),
                call_body(json!(i), "read_file", json!({"i": i})),
            )
            .await;
        assert!(
            error_text(&r).contains("is offline"),
            "call {i}: {}",
            r.body
        );
    }
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(21), "read_file", json!({"i": 21})),
        )
        .await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(
        error_text(&r),
        "Too many requests from your account; wait a minute and try again."
    );
    // Still refused, not a protocol error, and the session is fine.
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            json!({"jsonrpc": "2.0", "id": 22, "method": "tools/list"}),
        )
        .await;
    assert!(r.json()["result"]["tools"].is_array(), "{}", r.body);

    // Recorded as such.
    let rows = activity_when(&h, ALICE, 21).await;
    assert_eq!(
        rows.iter().filter(|r| r.outcome == "rate_limited").count(),
        1
    );
    assert_eq!(rows.iter().filter(|r| r.outcome == "offline").count(), 20);

    // Bob has his own allowance.
    let (bobs, _k) = h.new_device(BOB).await;
    let sb = h.session(&bobs, BOB).await;
    let r = h
        .rpc(
            &bobs,
            BOB,
            Some(&sb),
            call_body(json!(1), "read_file", json!({})),
        )
        .await;
    assert!(error_text(&r).contains("is offline"), "{}", r.body);
}

/// An AI app polling `check_request` while a person decides must not use up
/// its own allowance: polls are recorded but spend nothing.
#[tokio::test]
async fn polling_check_request_does_not_spend_the_allowance() {
    let h = harness_with(Timing {
        calls_per_minute: 1,
        ..Timing::default()
    })
    .await;
    let (device, _key) = h.new_device(ALICE).await;
    for i in 1..=30u64 {
        let r = mcp_call(&h, &device, ALICE, check_body(i, "r_000000000000000a")).await;
        assert!(
            !mcp_text(&r).contains("Too many requests"),
            "poll {i} was refused: {r}"
        );
    }
    // A fresh call afterwards still works: the 30 polls spent nothing.
    let r = mcp_call(
        &h,
        &device,
        ALICE,
        call_body(json!(100), "read_file", json!({})),
    )
    .await;
    assert!(mcp_text(&r).contains("is offline"), "{r}");
    // Every poll is still a recorded call.
    let rows = activity_when(&h, ALICE, 31).await;
    assert_eq!(
        rows.iter().filter(|r| r.tool == "check_request").count(),
        30
    );
    assert!(rows.iter().all(|r| r.outcome != "rate_limited"));
}

/// Asks the MCP layer directly (no HTTP, no token to sign: for tests that
/// make many calls).
async fn mcp_call(h: &Harness, device: &str, sub: &str, body: Value) -> Value {
    let caller = Caller {
        subject: sub.to_string(),
        client_id: MCP_CLIENT.to_string(),
    };
    h.app
        .mcp
        .handle(&body, device, &caller, None)
        .await
        .expect("an answer")
}

fn mcp_text(v: &Value) -> String {
    v["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_else(|| panic!("no text: {v}"))
        .to_string()
}

/// A retry that joins a call that is already running starts nothing, so it
/// spends nothing either (and is not refused when the allowance is used up);
/// the call it joined spent one place when it began.
#[tokio::test]
async fn a_retry_that_rejoins_an_open_call_does_not_spend_the_allowance() {
    let h = Arc::new(
        harness_with(Timing {
            calls_per_minute: 1,
            rate_burst: 1,
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("start_process")])
        .await;
    let s = h.session(&device, ALICE).await;
    let body = |id: u64| call_body(json!(id), "start_process", json!({"command": "ls"}));
    let first = spawn_rpc(&h, &device, ALICE, &s, body(1));
    let call = fake.next_call().await;
    // Two retries while the first is open: the one place is already spent.
    let second = spawn_rpc(&h, &device, ALICE, &s, body(2));
    let third = spawn_rpc(&h, &device, ALICE, &s, body(3));
    tokio::time::sleep(Duration::from_millis(100)).await;
    fake.reply(&call.call_id, "one answer");
    for r in [
        within(first).await.unwrap(),
        within(second).await.unwrap(),
        within(third).await.unwrap(),
    ] {
        assert_eq!(text_of(&r), "one answer", "{}", r.body);
    }
    // The one place was spent by the call that started, so a different call
    // is refused: the retries did not hand anything back or take more.
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(4), "start_process", json!({"command": "pwd"})),
        )
        .await;
    assert!(error_text(&r).contains("Too many requests"), "{}", r.body);
    // All three were recorded.
    let rows = activity_when(&h, ALICE, 4).await;
    assert_eq!(
        rows.iter().filter(|r| r.outcome == "rate_limited").count(),
        1
    );
}

/// A database that has stopped answering must not let activity writes pile
/// up: past 64 in flight a row is dropped and logged, calls are unaffected,
/// and writing goes on once the database is back.
#[tokio::test]
async fn a_stalled_database_cannot_pile_up_activity_writes() {
    let h = harness_with(Timing {
        calls_per_minute: 6000,
        rate_burst: 1000,
        ..Timing::default()
    })
    .await;
    let (device, _key) = h.new_device(ALICE).await;
    h.store.stall_activity_writes(true);
    for i in 1..=70u64 {
        let r = mcp_call(
            &h,
            &device,
            ALICE,
            call_body(json!(i), "read_file", json!({"i": i})),
        )
        .await;
        assert!(mcp_text(&r).contains("is offline"), "call {i}: {r}");
    }
    let dropped = || h.logs().matches("\"activity_write_dropped\"").count();
    assert_eq!(dropped(), 6, "64 writes wait, the other 6 are dropped");
    assert!(h
        .store
        .activity_of(ALICE, None, 100)
        .await
        .unwrap()
        .is_empty());

    // The database answers again: the 64 that waited are written, no more.
    h.store.stall_activity_writes(false);
    activity_when(&h, ALICE, 64).await;
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert_eq!(
        h.store.activity_of(ALICE, None, 100).await.unwrap().len(),
        64
    );
    // And the places came back: the next call is recorded.
    let r = mcp_call(
        &h,
        &device,
        ALICE,
        call_body(json!(71), "read_file", json!({"i": 71})),
    )
    .await;
    assert!(mcp_text(&r).contains("is offline"));
    activity_when(&h, ALICE, 65).await;
    assert_eq!(dropped(), 6);
}

/// "Last seen" is kept up to date: when the computer connects, while it stays
/// connected, and when it goes.
#[tokio::test]
async fn last_seen_is_kept_up_to_date() {
    let h = harness_with(Timing {
        seen_every: Duration::from_millis(40),
        ..Timing::default()
    })
    .await;
    let (device, key) = h.new_device(ALICE).await;
    let last_seen = || async { h.store.device(&device).await.unwrap().unwrap().last_seen };
    assert_eq!(last_seen().await, None);

    let fake = h.connect(ALICE, &device, &key, vec![]).await;
    // On connecting.
    within(async {
        while last_seen().await.is_none() {
            tokio::time::sleep(Duration::from_millis(5)).await
        }
    })
    .await;
    // Then again while it stays connected.
    let old = SystemTime::now() - Duration::from_secs(3600);
    h.store.touch_seen(&device, old).await.unwrap();
    within(async {
        while last_seen().await == Some(old) {
            tokio::time::sleep(Duration::from_millis(5)).await
        }
    })
    .await;
    drop(fake);
}

#[tokio::test]
async fn last_seen_is_set_on_connect_and_on_disconnect() {
    // The periodic update is five minutes here: only the connect and the
    // disconnect can have touched it.
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let last_seen = || async { h.store.device(&device).await.unwrap().unwrap().last_seen };
    let fake = h.connect(ALICE, &device, &key, vec![]).await;
    within(async {
        while last_seen().await.is_none() {
            tokio::time::sleep(Duration::from_millis(5)).await
        }
    })
    .await;

    let old = SystemTime::now() - Duration::from_secs(3600);
    h.store.touch_seen(&device, old).await.unwrap();
    drop(fake);
    within(async {
        while last_seen().await == Some(old) {
            tokio::time::sleep(Duration::from_millis(5)).await
        }
    })
    .await;
    assert!(last_seen().await.unwrap() > old);
}

/// A request in the stateless MCP revision: the version in `_meta` and,
/// unless `header` overrides it (`Some(None)` leaves it out), in the
/// `MCP-Protocol-Version` header. `session` is sent as-is, to show it is
/// ignored.
fn modern(mut body: Value, version: &str) -> Value {
    body["params"]["_meta"] = json!({
        "io.modelcontextprotocol/protocolVersion": version,
        "io.modelcontextprotocol/clientCapabilities": {},
        "io.modelcontextprotocol/clientInfo": {"name": "test", "version": "0"},
    });
    body
}

impl Harness {
    async fn modern_rpc(
        &self,
        device: &str,
        sub: &str,
        header: Option<Option<&str>>,
        session: Option<&str>,
        body: Value,
    ) -> Reply {
        let version = body["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"]
            .as_str()
            .map(String::from);
        let mut headers = self.mcp_headers(sub, session);
        let header = match header {
            Some(h) => h.map(String::from),
            None => version,
        };
        if let Some(v) = header {
            headers.push(("mcp-protocol-version", v));
        }
        self.send(
            "POST",
            &format!("/mcp/d/{device}"),
            &headers,
            &body.to_string(),
        )
        .await
    }
}

// Claude asks `server/discover`, sees 2026-07-28, and from then on sends each
// request on its own: no initialize, no session (MCP 2026-07-28, streamable
// HTTP). Live, the relay refused every one with "Mcp-Session-Id header
// required" and Claude reported the server broken.
#[tokio::test]
async fn modern_requests_need_no_session() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let v = MODERN_VERSIONS[0];

    let list = modern(
        json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}),
        v,
    );
    let r = h.modern_rpc(&device, ALICE, None, None, list.clone()).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(r.header("mcp-session-id"), None, "mints no session");
    let res = &r.json()["result"];
    assert_eq!(res["tools"][0]["name"], "read_file");
    assert_eq!(res["resultType"], "complete");
    // The list is this person's device's: never shared, and it can change
    // whenever the device reconnects.
    assert_eq!(res["cacheScope"], "private");
    assert_eq!(res["ttlMs"], 0);

    // A session id from an older client is ignored, not looked up.
    let r = h
        .modern_rpc(&device, ALICE, None, Some("not-a-session"), list)
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);

    // A tool call goes through the same way.
    let h2 = h.clone();
    let d2 = device.clone();
    let pending = tokio::spawn(async move {
        h2.modern_rpc(
            &d2,
            ALICE,
            None,
            None,
            modern(call_body(json!(7), "read_file", json!({"path": "/x"})), v),
        )
        .await
    });
    let call = fake.next_call().await;
    assert_eq!(call.tool, "read_file");
    fake.reply(&call.call_id, "contents");
    let r = within(pending).await.unwrap();
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(r.json()["result"]["content"][0]["text"], "contents");
    assert_eq!(r.json()["result"]["resultType"], "complete");

    // An older-style request still needs its session.
    let r = h
        .rpc(
            &device,
            ALICE,
            None,
            json!({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
        )
        .await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST, "{}", r.body);
}

// The stateless revision answers an unknown method with HTTP 404 (and
// -32601), so a client can tell "not here" from a server that misunderstood.
#[tokio::test]
async fn modern_unknown_method_is_404() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let r = h
        .modern_rpc(
            &device,
            ALICE,
            None,
            None,
            modern(
                json!({"jsonrpc": "2.0", "id": 1, "method": "nope/never"}),
                MODERN_VERSIONS[0],
            ),
        )
        .await;
    assert_eq!(r.status, StatusCode::NOT_FOUND, "{}", r.body);
    assert_eq!(r.json()["error"]["code"], -32601);

    // An older-style session keeps the 200 it always had.
    let s = h.session(&device, ALICE).await;
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            json!({"jsonrpc": "2.0", "id": 2, "method": "nope/never"}),
        )
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(r.json()["error"]["code"], -32601);
}

#[tokio::test]
async fn modern_header_must_match_meta() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let list = modern(
        json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}),
        MODERN_VERSIONS[0],
    );
    let r = h
        .modern_rpc(&device, ALICE, Some(Some("2025-11-25")), None, list)
        .await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST, "{}", r.body);
    assert_eq!(r.json()["error"]["code"], -32020);
    assert_eq!(r.json()["id"], 1);

    // The header naming the new revision with no `_meta` is a mismatch too.
    let r = h
        .modern_rpc(
            &device,
            ALICE,
            Some(Some(MODERN_VERSIONS[0])),
            None,
            json!({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
        )
        .await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST, "{}", r.body);
    assert_eq!(r.json()["error"]["code"], -32020);
}

#[tokio::test]
async fn modern_unknown_version_is_refused_with_the_supported_list() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let r = h
        .modern_rpc(
            &device,
            ALICE,
            None,
            None,
            modern(
                json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}),
                "2099-01-01",
            ),
        )
        .await;
    assert_eq!(r.status, StatusCode::BAD_REQUEST, "{}", r.body);
    assert_eq!(r.json()["error"]["code"], -32022);
    assert_eq!(
        r.json()["error"]["data"]["supported"],
        json!(MODERN_VERSIONS)
    );
}

#[tokio::test]
async fn cancelled_notification_still_cancels() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("start_process")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(7), "start_process", json!({})),
    );
    let call = fake.next_call().await;
    // With its dialog open, as the real thing would be: parking is for a
    // request that goes away, not one the AI app cancels.
    fake.send(ToRelay::Pending {
        call_id: call.call_id.clone(),
    });
    let r = h
        .rpc(&device, ALICE, Some(&s), json!({"jsonrpc": "2.0", "method": "notifications/cancelled",
                                              "params": {"requestId": 7, "reason": "user stopped it"}}))
        .await;
    assert_eq!(r.status, StatusCode::ACCEPTED);
    assert_eq!(
        fake.next().await,
        ToConnector::Cancel {
            call_id: call.call_id
        }
    );
    // The cancelled request is answered (so the HTTP request ends), as an error.
    let r = within(pending).await.unwrap();
    assert!(r.json()["error"].is_object(), "{}", r.body);
    until(|| h.logs().contains("\"outcome\":\"cancelled\"")).await;
    // Nothing is left to rejoin: the same call again starts a new one.
    let again = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(8), "start_process", json!({})),
    );
    let call2 = fake.next_call().await;
    fake.reply(&call2.call_id, "fresh");
    assert_eq!(
        within(again).await.unwrap().json()["result"]["content"][0]["text"],
        "fresh"
    );
}

// --------------------------------------------- approvals that outlive the app

/// Timing for the approval tests: the 10 s / 120 s / 300 s of production, a
/// few hundred milliseconds here.
fn approval_timing() -> Timing {
    Timing {
        approval_reply: Duration::from_millis(300),
        rejoin_window: Duration::from_secs(30),
        parked_result: Duration::from_secs(30),
        ..Timing::default()
    }
}

fn text_of(r: &Reply) -> String {
    r.json()["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_else(|| panic!("no text: {}", r.body))
        .to_string()
}

/// The request id inside a waiting reply, checking the text around it. The
/// computer is named by its name, "My Mac" for one registered without one.
fn waiting_id(r: &Reply, _device: &str) -> String {
    waiting_id_named(r, "My Mac")
}

fn waiting_id_named(r: &Reply, name: &str) -> String {
    let v = r.json();
    assert_eq!(v["result"]["isError"], false, "{}", r.body);
    let text = text_of(r);
    let id = text
        .split("request_id \"")
        .nth(1)
        .and_then(|t| t.split('"').next())
        .unwrap_or_else(|| panic!("no request id in {text}"))
        .to_string();
    assert_eq!(
        text,
        format!(
            "Waiting for you to allow this on \"{name}\". Call check_request with \
             request_id \"{id}\" to get the result. The request is cancelled if nobody \
             answers within 60 seconds."
        )
    );
    assert!(
        id.len() == 18
            && id.starts_with("r_")
            && id[2..]
                .bytes()
                .all(|c| matches!(c, b'0'..=b'9' | b'a'..=b'f')),
        "{id}"
    );
    id
}

fn check_body(rpc_id: u64, request_id: &str) -> Value {
    call_body(
        json!(rpc_id),
        "check_request",
        json!({"request_id": request_id}),
    )
}

const UNKNOWN: &str = "That request has finished or expired. Send the original request again.";

/// A device with `start_process`, an AI session, and a harness with the
/// approval timing.
async fn approval_setup() -> (Arc<Harness>, String, FakeDevice, String) {
    let h = Arc::new(harness_with(approval_timing()).await);
    let (device, key) = h.new_device(ALICE).await;
    let fake = h
        .connect(ALICE, &device, &key, vec![tool("start_process")])
        .await;
    let s = h.session(&device, ALICE).await;
    (h, device, fake, s)
}

#[tokio::test]
async fn slow_approval_returns_waiting_then_result() {
    let (h, device, mut fake, s) = approval_setup().await;
    let args = json!({"command": "ls"});
    let started = Instant::now();
    let first = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(1), "start_process", args),
    );
    let call = fake.next_call().await;
    // The dialog opens on the Mac, and the person takes their time.
    fake.send(ToRelay::Pending {
        call_id: call.call_id.clone(),
    });
    let r = within(first).await.unwrap();
    let id = waiting_id(&r, &device);
    assert!(
        started.elapsed() >= Duration::from_millis(300),
        "answered before the approval reply time: {:?}",
        started.elapsed()
    );
    until(|| h.logs().contains("\"outcome\":\"waiting_approval\"")).await;
    // Still waiting: `check_request` waits its turn, then says so again.
    let r = h.rpc(&device, ALICE, Some(&s), check_body(2, &id)).await;
    assert_eq!(waiting_id(&r, &device), id);
    // The person allows it, after the AI app would have given up (3x here).
    tokio::time::sleep(Duration::from_millis(300)).await;
    fake.reply(&call.call_id, "the real result");
    let r = h.rpc(&device, ALICE, Some(&s), check_body(3, &id)).await;
    assert_eq!(r.json()["result"]["isError"], false, "{}", r.body);
    assert_eq!(text_of(&r), "the real result");
    // Nothing told the device to stop it, and it ran once.
    assert!(
        tokio::time::timeout(Duration::from_millis(200), fake.frames.recv())
            .await
            .is_err()
    );
    // The result can be fetched again until it expires.
    let r = h.rpc(&device, ALICE, Some(&s), check_body(4, &id)).await;
    assert_eq!(text_of(&r), "the real result");
}

#[tokio::test]
async fn a_call_with_no_dialog_is_not_answered_waiting() {
    // `Pending` is what says a person is being asked: a slow call without
    // one just takes as long as it takes.
    let (h, device, mut fake, s) = approval_setup().await;
    let first = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(1), "start_process", json!({"command": "sleep"})),
    );
    let call = fake.next_call().await;
    tokio::time::sleep(Duration::from_millis(700)).await;
    assert!(!first.is_finished(), "answered a call that had no dialog");
    fake.reply(&call.call_id, "done at last");
    assert_eq!(text_of(&within(first).await.unwrap()), "done at last");
}

#[tokio::test]
async fn retry_rejoins_the_open_dialog() {
    let (h, device, mut fake, s) = approval_setup().await;
    let args = json!({"command": "ls", "options": {"b": 1, "a": 2}});
    let first = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(1), "start_process", args),
    );
    let call = fake.next_call().await;
    fake.send(ToRelay::Pending {
        call_id: call.call_id.clone(),
    });
    // The AI app's retry: the same call, new request id, keys in another order.
    let again = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(
            json!(2),
            "start_process",
            json!({"options": {"a": 2, "b": 1}, "command": "ls"}),
        ),
    );
    // Both are told the call is waiting, by the same id...
    let (r1, r2) = (within(first).await.unwrap(), within(again).await.unwrap());
    assert_eq!(waiting_id(&r1, &device), waiting_id(&r2, &device));
    // ...and one more retry still finds it (the one dialog is still open).
    let third = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(
            json!(3),
            "start_process",
            json!({"command": "ls", "options": {"a": 2, "b": 1}}),
        ),
    );
    let r3 = within(third).await.unwrap();
    assert_eq!(waiting_id(&r3, &device), waiting_id(&r1, &device));
    // The person allows it: the device saw exactly one call.
    fake.reply(&call.call_id, "listed");
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            check_body(4, &waiting_id(&r1, &device)),
        )
        .await;
    assert_eq!(text_of(&r), "listed");
    assert!(
        tokio::time::timeout(Duration::from_millis(300), fake.frames.recv())
            .await
            .is_err(),
        "a second call reached the device"
    );
    assert!(
        h.logs().contains("\"outcome\":\"rejoined\""),
        "{}",
        h.logs()
    );
}

#[tokio::test]
async fn a_retry_while_the_first_request_is_still_open_joins_it() {
    // The retry arrives before the dialog is even reported open.
    let (h, device, mut fake, s) = approval_setup().await;
    let body = |id: u64| call_body(json!(id), "start_process", json!({"command": "ls"}));
    let first = spawn_rpc(&h, &device, ALICE, &s, body(1));
    let call = fake.next_call().await;
    let second = spawn_rpc(&h, &device, ALICE, &s, body(2));
    tokio::time::sleep(Duration::from_millis(100)).await;
    fake.reply(&call.call_id, "one answer");
    for r in [within(first).await.unwrap(), within(second).await.unwrap()] {
        assert_eq!(text_of(&r), "one answer");
    }
    assert!(
        tokio::time::timeout(Duration::from_millis(200), fake.frames.recv())
            .await
            .is_err(),
        "a second call reached the device"
    );
}

#[tokio::test]
async fn modern_retry_rejoins_the_open_call() {
    // The stateless revision has no session and so no request-id check:
    // joining is what stops its retries starting a second call.
    let (h, device, mut fake, _s) = approval_setup().await;
    let v = MODERN_VERSIONS[0];
    let send = |id: u64| {
        let (h, device) = (h.clone(), device.clone());
        tokio::spawn(async move {
            h.modern_rpc(
                &device,
                ALICE,
                None,
                None,
                modern(
                    call_body(json!(id), "start_process", json!({"command": "ls"})),
                    v,
                ),
            )
            .await
        })
    };
    let first = send(1);
    let call = fake.next_call().await;
    fake.send(ToRelay::Pending {
        call_id: call.call_id.clone(),
    });
    let second = send(2);
    let (r1, r2) = (within(first).await.unwrap(), within(second).await.unwrap());
    assert_eq!(waiting_id(&r1, &device), waiting_id(&r2, &device));
    fake.reply(&call.call_id, "listed");
    let r = h
        .modern_rpc(
            &device,
            ALICE,
            None,
            None,
            modern(check_body(3, &waiting_id(&r1, &device)), v),
        )
        .await;
    assert_eq!(text_of(&r), "listed");
    assert!(
        tokio::time::timeout(Duration::from_millis(200), fake.frames.recv())
            .await
            .is_err()
    );
}

#[tokio::test]
async fn client_timeout_parks_instead_of_cancelling() {
    let (h, device, mut fake, s) = approval_setup().await;
    let body = |id: u64| call_body(json!(id), "start_process", json!({"command": "ls"}));
    let first = spawn_rpc(&h, &device, ALICE, &s, body(1));
    let call = fake.next_call().await;
    fake.send(ToRelay::Pending {
        call_id: call.call_id.clone(),
    });
    // The AI app gives up: its connection closes.
    first.abort();
    until(|| h.logs().contains("\"outcome\":\"parked\"")).await;
    // The dialog is not touched.
    assert!(
        tokio::time::timeout(Duration::from_millis(400), fake.frames.recv())
            .await
            .is_err(),
        "the device was sent something"
    );
    // The retry finds the same call, and gets its result.
    let retry = spawn_rpc(&h, &device, ALICE, &s, body(2));
    tokio::time::sleep(Duration::from_millis(100)).await;
    fake.reply(&call.call_id, "allowed and ran");
    assert_eq!(text_of(&within(retry).await.unwrap()), "allowed and ran");
    assert!(
        tokio::time::timeout(Duration::from_millis(200), fake.frames.recv())
            .await
            .is_err(),
        "a second call reached the device"
    );
}

#[tokio::test]
async fn an_answer_that_arrives_after_the_request_went_is_kept_for_the_retry() {
    let (h, device, mut fake, s) = approval_setup().await;
    let body = |id: u64| call_body(json!(id), "start_process", json!({"command": "rm x"}));
    let first = spawn_rpc(&h, &device, ALICE, &s, body(1));
    let call = fake.next_call().await;
    first.abort();
    until(|| h.logs().contains("\"outcome\":\"parked\"")).await;
    // The person allows it, and it runs, with nobody on the line.
    fake.reply(&call.call_id, "removed x");
    until(|| fake.result_acks().len() == 1).await;
    // The retry gets that result; it does not run `rm x` a second time.
    let retry = h.rpc(&device, ALICE, Some(&s), body(2)).await;
    assert_eq!(text_of(&retry), "removed x");
    assert!(
        tokio::time::timeout(Duration::from_millis(200), fake.frames.recv())
            .await
            .is_err(),
        "a second call reached the device"
    );
}

#[tokio::test]
async fn delivered_call_is_never_reused() {
    let (h, device, mut fake, s) = approval_setup().await;
    let body = |id: u64| call_body(json!(id), "start_process", json!({"command": "date"}));
    // A call that completes and is delivered.
    let first = spawn_rpc(&h, &device, ALICE, &s, body(1));
    let call1 = fake.next_call().await;
    fake.reply(&call1.call_id, "10:00");
    assert_eq!(text_of(&within(first).await.unwrap()), "10:00");
    // The same call again is a new call, with its own answer.
    let second = spawn_rpc(&h, &device, ALICE, &s, body(2));
    let call2 = fake.next_call().await;
    assert_ne!(call1.call_id, call2.call_id);
    fake.reply(&call2.call_id, "10:05");
    assert_eq!(text_of(&within(second).await.unwrap()), "10:05");

    // The same after a parked one: its result is handed over by a retry (and
    // still fetchable by id), but never given to a later, separate call.
    let third = spawn_rpc(&h, &device, ALICE, &s, body(3));
    let call3 = fake.next_call().await;
    fake.send(ToRelay::Pending {
        call_id: call3.call_id.clone(),
    });
    let id = waiting_id(&within(third).await.unwrap(), &device);
    fake.reply(&call3.call_id, "10:10");
    let got = h.rpc(&device, ALICE, Some(&s), check_body(4, &id)).await;
    assert_eq!(text_of(&got), "10:10");
    let fourth = spawn_rpc(&h, &device, ALICE, &s, body(5));
    let call4 = fake.next_call().await;
    assert_ne!(call3.call_id, call4.call_id);
    fake.reply(&call4.call_id, "10:15");
    assert_eq!(text_of(&within(fourth).await.unwrap()), "10:15");
}

/// The server's end of a connection, whose writes fail once `dead` is set
/// while reads carry on: a socket the AI app has left that the relay has
/// not yet noticed is gone.
struct DeadAfter {
    inner: tokio::io::DuplexStream,
    dead: Arc<AtomicBool>,
}

impl tokio::io::AsyncRead for DeadAfter {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_read(cx, buf)
    }
}

impl tokio::io::AsyncWrite for DeadAfter {
    fn poll_write(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        if self.dead.load(Ordering::SeqCst) {
            return std::task::Poll::Ready(Err(std::io::ErrorKind::BrokenPipe.into()));
        }
        std::pin::Pin::new(&mut self.inner).poll_write(cx, buf)
    }

    fn poll_flush(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        if self.dead.load(Ordering::SeqCst) {
            return std::task::Poll::Ready(Err(std::io::ErrorKind::BrokenPipe.into()));
        }
        std::pin::Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

/// A command must never run twice. The result is counted as handed to the AI
/// app only once the response carrying it has been written out: here the
/// relay produces the response and hands its body to hyper, whose write then
/// fails because the app's socket is dead. The app's retry must get the
/// stored result, not start the command again.
#[tokio::test]
async fn result_lost_on_a_dead_socket_stays_rejoinable() {
    let (h, device, mut fake, s) = approval_setup().await;
    let args = json!({"command": "rm important"});
    // The first request, on a connection the test can kill.
    let (client, server) = tokio::io::duplex(256 * 1024);
    let dead = Arc::new(AtomicBool::new(false));
    tokio::spawn(serve_stream(
        h.app.clone(),
        DeadAfter {
            inner: server,
            dead: dead.clone(),
        },
    ));
    let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(client))
        .await
        .unwrap();
    let conn = tokio::spawn(conn);
    let mut req = Request::builder()
        .method("POST")
        .uri(format!("/mcp/d/{device}"))
        .header(header::HOST, "relay.example.test");
    for (k, v) in h.mcp_headers(ALICE, Some(&s)) {
        req = req.header(k, v);
    }
    let body = call_body(json!(1), "start_process", args.clone()).to_string();
    let first = tokio::spawn(async move {
        sender
            .send_request(req.body(Full::new(Bytes::from(body))).unwrap())
            .await
            .map(|_| ())
    });
    let call = fake.next_call().await;
    // The socket dies with the call running; then the command finishes.
    dead.store(true, Ordering::SeqCst);
    fake.reply(&call.call_id, "removed important");
    until(|| h.logs().contains("\"outcome\":\"ok\"")).await;
    // The relay's answer never got out.
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(!first.is_finished() || first.await.unwrap().is_err());
    conn.abort();
    // The retry gets the stored result; the command is not started again.
    let retry = within(h.rpc(
        &device,
        ALICE,
        Some(&s),
        call_body(json!(2), "start_process", args.clone()),
    ))
    .await;
    assert_eq!(text_of(&retry), "removed important");
    assert!(
        tokio::time::timeout(Duration::from_millis(300), fake.frames.recv())
            .await
            .is_err(),
        "a second call reached the device"
    );
    // That answer was written out, so it is handed over for good: the same
    // call again is a new call.
    let third = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(3), "start_process", args),
    );
    let call3 = fake.next_call().await;
    assert_ne!(call.call_id, call3.call_id);
    fake.reply(&call3.call_id, "removed again");
    assert_eq!(text_of(&within(third).await.unwrap()), "removed again");
}

#[tokio::test]
async fn other_persons_request_id_is_unknown() {
    let h = Arc::new(harness_with(approval_timing()).await);
    let (alice_dev, akey) = h.new_device(ALICE).await;
    let (bob_dev, _bkey) = h.new_device(BOB).await;
    let mut fake = h
        .connect(ALICE, &alice_dev, &akey, vec![tool("start_process")])
        .await;
    let (sa, sb) = (
        h.session(&alice_dev, ALICE).await,
        h.session(&bob_dev, BOB).await,
    );
    let first = spawn_rpc(
        &h,
        &alice_dev,
        ALICE,
        &sa,
        call_body(json!(1), "start_process", json!({"command": "ls"})),
    );
    let call = fake.next_call().await;
    fake.send(ToRelay::Pending {
        call_id: call.call_id.clone(),
    });
    let id = waiting_id(&within(first).await.unwrap(), &alice_dev);

    let bobs = h.rpc(&bob_dev, BOB, Some(&sb), check_body(2, &id)).await;
    let made_up = h
        .rpc(
            &bob_dev,
            BOB,
            Some(&sb),
            check_body(2, "r_0123456789abcdef"),
        )
        .await;
    assert_eq!(text_of(&bobs), UNKNOWN);
    // Byte for byte the same as for an id that never existed.
    assert_eq!(bobs.body, made_up.body);
    assert_eq!(bobs.status, made_up.status);
    // Bob asking on Alice's endpoint is refused the way every other person is.
    let r = h.rpc(&alice_dev, BOB, Some(&sb), check_body(3, &id)).await;
    assert_eq!(r.status, StatusCode::NOT_FOUND, "{}", r.body);
    // Bob's try took nothing: Alice still gets her result.
    fake.reply(&call.call_id, "alice's listing");
    let r = h
        .rpc(&alice_dev, ALICE, Some(&sa), check_body(4, &id))
        .await;
    assert_eq!(text_of(&r), "alice's listing");
}

#[tokio::test]
async fn parked_result_is_dropped_after_300s() {
    // 300 s in production; 400 ms here.
    let h = Arc::new(
        harness_with(Timing {
            approval_reply: Duration::from_millis(100),
            parked_result: Duration::from_millis(400),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("start_process")])
        .await;
    let s = h.session(&device, ALICE).await;
    let first = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(1), "start_process", json!({"command": "ls"})),
    );
    let call = fake.next_call().await;
    fake.send(ToRelay::Pending {
        call_id: call.call_id.clone(),
    });
    let id = waiting_id(&within(first).await.unwrap(), &device);
    fake.reply(&call.call_id, "late");
    until(|| fake.result_acks().len() == 1).await;
    // Inside the time it is kept...
    let r = h.rpc(&device, ALICE, Some(&s), check_body(2, &id)).await;
    assert_eq!(text_of(&r), "late");
    // ...and gone after it.
    tokio::time::sleep(Duration::from_millis(700)).await;
    let r = h.rpc(&device, ALICE, Some(&s), check_body(3, &id)).await;
    assert_eq!(text_of(&r), UNKNOWN);
    assert_eq!(r.json()["result"]["isError"], true);
}

#[tokio::test]
async fn a_call_that_failed_is_not_handed_to_a_retry_as_its_answer() {
    // The device went away mid-call and the AI app's request with it: the
    // failure is waiting for nobody, so the retry makes a fresh attempt.
    let h = Arc::new(
        harness_with(Timing {
            reconnect_grace: Duration::from_millis(100),
            ..approval_timing()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("start_process")])
        .await;
    let s = h.session(&device, ALICE).await;
    let body = |id: u64| call_body(json!(id), "start_process", json!({"command": "ls"}));
    let first = spawn_rpc(&h, &device, ALICE, &s, body(1));
    fake.next_call().await;
    first.abort();
    drop(fake);
    until(|| !h.app.registry.in_flight(&device)).await;
    tokio::time::sleep(Duration::from_millis(400)).await;
    let mut fake2 = h
        .connect(ALICE, &device, &key, vec![tool("start_process")])
        .await;
    let retry = spawn_rpc(&h, &device, ALICE, &s, body(2));
    // (The relay's overdue `Cancel` for the first attempt comes first.)
    let call = loop {
        if let ToConnector::Call(c) = fake2.next().await {
            break c;
        }
    };
    fake2.reply(&call.call_id, "second try");
    assert_eq!(text_of(&within(retry).await.unwrap()), "second try");
}

#[tokio::test]
async fn check_request_is_listed_and_replaces_a_device_tool_of_that_name() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let _fake = h
        .connect(
            ALICE,
            &device,
            &key,
            vec![tool("read_file"), tool("check_request")],
        )
        .await;
    let s = h.session(&device, ALICE).await;
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}),
        )
        .await;
    let tools = r.json()["result"]["tools"].as_array().unwrap().clone();
    let names: Vec<&str> = tools.iter().map(|t| t["name"].as_str().unwrap()).collect();
    // The device's own `check_request` is gone; the relay's is the only one.
    assert_eq!(names, ["read_file", "check_request"]);
    let ours = &tools[1];
    assert_eq!(
        ours["description"],
        "Get the result of a request that was waiting for approval on the computer."
    );
    assert_eq!(ours["inputSchema"]["required"], json!(["request_id"]));
    assert_eq!(
        ours["inputSchema"]["properties"]["request_id"]["type"],
        "string"
    );
    let dropped = h
        .logs()
        .lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap())
        .find(|v| v["event"] == "tool_dropped")
        .expect("the drop is logged");
    assert_eq!(dropped["tool"], "check_request");
    assert_eq!(dropped["device_id"], device.as_str());
    // A device without the name logs nothing of the kind.
    let (device2, key2) = h.new_device(BOB).await;
    let _f2 = h
        .connect(BOB, &device2, &key2, vec![tool("read_file")])
        .await;
    let s2 = h.session(&device2, BOB).await;
    let before = h.logs().matches("tool_dropped").count();
    h.rpc(
        &device2,
        BOB,
        Some(&s2),
        json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"}),
    )
    .await;
    assert_eq!(h.logs().matches("tool_dropped").count(), before);
}

#[tokio::test]
async fn check_request_never_reaches_the_device_and_needs_an_id() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("check_request")])
        .await;
    let s = h.session(&device, ALICE).await;
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            check_body(1, "r_ffffffffffffffff"),
        )
        .await;
    assert_eq!(text_of(&r), UNKNOWN);
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(2), "check_request", json!({})),
        )
        .await;
    assert_eq!(r.json()["error"]["code"], -32602, "{}", r.body);
    assert!(fake.frames.try_recv().is_err());
}

#[tokio::test]
async fn cancel_only_affects_own_session() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    let (s1, s2) = (
        h.session(&device, ALICE).await,
        h.session(&device, ALICE).await,
    );
    assert_ne!(s1, s2);
    // Two chats, the same JSON-RPC id.
    let one = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s1,
        call_body(json!(1), "t", json!({"who": "one"})),
    );
    let first = fake.next_call().await;
    let two = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s2,
        call_body(json!(1), "t", json!({"who": "two"})),
    );
    let second = fake.next_call().await;
    assert_eq!(first.arguments["who"], "one");
    assert_eq!(second.arguments["who"], "two");
    assert_ne!(first.call_id, second.call_id);

    h.rpc(
        &device,
        ALICE,
        Some(&s1),
        json!({"jsonrpc": "2.0", "method": "notifications/cancelled",
                                            "params": {"requestId": 1}}),
    )
    .await;
    assert_eq!(
        fake.next().await,
        ToConnector::Cancel {
            call_id: first.call_id
        }
    );
    within(one).await.unwrap();

    // The other chat's call is still running and gets its answer.
    fake.reply(&second.call_id, "still here");
    let r = within(two).await.unwrap();
    assert_eq!(r.json()["result"]["content"][0]["text"], "still here");
    assert!(
        fake.frames.try_recv().is_err(),
        "no cancel went to the second call"
    );

    // A cancel naming an id that is not running in this session does nothing.
    h.rpc(
        &device,
        ALICE,
        Some(&s2),
        json!({"jsonrpc": "2.0", "method": "notifications/cancelled",
                                            "params": {"requestId": 99}}),
    )
    .await;
}

#[tokio::test]
async fn silent_drop_mid_call_fails_within_seconds() {
    // In-call pings every 200 ms instead of 2 s, so three missed pings take
    // under a second. Idle pings stay at 20 s: only the in-call interval can
    // end this call quickly (three missed idle pings would take a minute).
    let h = Arc::new(
        harness_with(Timing {
            in_call_ping: Duration::from_millis(200),
            // The call is held this long after the link is found dead.
            reconnect_grace: Duration::from_millis(200),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(&h, &device, ALICE, &s, call_body(json!(1), "t", json!({})));
    fake.next_call().await;
    // The network goes quiet: the socket stays open but nothing answers.
    fake.answer_pings.store(false, Ordering::SeqCst);
    let started = Instant::now();
    let r = within(pending).await.unwrap();
    assert_eq!(r.json()["result"]["isError"], true);
    assert_eq!(
        r.json()["result"]["content"][0]["text"],
        "Your computer disconnected. The command may already have run; check before trying again."
    );
    // Generous for a loaded runner; the idle path would need 60 s.
    assert!(
        started.elapsed() < Duration::from_secs(10),
        "{:?}",
        started.elapsed()
    );
    fake.wait_closed().await;
}

#[tokio::test]
async fn connector_pings_are_answered() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![]).await;
    fake.send(ToRelay::Ping { n: 42 });
    assert_eq!(fake.next().await, ToConnector::Pong { n: 42 });
}

#[tokio::test]
async fn logs_never_contain_arguments_outputs_or_tokens() {
    let h = Arc::new(
        harness_with(Timing {
            approval_reply: Duration::from_millis(200),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(
            ALICE,
            &device,
            &key,
            vec![tool("read_file"), tool("start_process")],
        )
        .await;
    let s = h.session(&device, ALICE).await;
    let mcp_token = h.mcp_token(ALICE);
    let headers = vec![
        ("authorization", format!("Bearer {mcp_token}")),
        ("accept", ACCEPT.to_string()),
        ("mcp-session-id", s.clone()),
    ];
    let body = call_body(
        json!(3),
        "read_file",
        json!({"path": "SECRET-ARGUMENT-MARKER"}),
    )
    .to_string();
    let path = format!("/mcp/d/{device}");
    let pending = {
        let h = h.clone();
        tokio::spawn(async move { h.send("POST", &path, &headers, &body).await })
    };
    let call = fake.next_call().await;
    fake.reply(&call.call_id, "SECRET-OUTPUT-MARKER");
    let r = within(pending).await.unwrap();
    assert_eq!(
        r.json()["result"]["content"][0]["text"],
        "SECRET-OUTPUT-MARKER"
    );
    // A call that waits for approval, and `check_request` fetching its
    // result: the arguments, the output and the request id stay out of the
    // log too, and the fetch is logged as `check_request`.
    let waiting = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(
            json!(4),
            "start_process",
            json!({"command": "SECRET-COMMAND-MARKER"}),
        ),
    );
    let call = fake.next_call().await;
    fake.send(ToRelay::Pending {
        call_id: call.call_id.clone(),
    });
    let request_id = waiting_id(&within(waiting).await.unwrap(), &device);
    fake.reply(&call.call_id, "SECRET-LATE-OUTPUT-MARKER");
    let fetched = h
        .rpc(&device, ALICE, Some(&s), check_body(5, &request_id))
        .await;
    assert_eq!(text_of(&fetched), "SECRET-LATE-OUTPUT-MARKER");
    // A refused token is not logged either.
    let bad = format!("{mcp_token}tampered");
    h.send(
        "POST",
        &format!("/mcp/d/{device}"),
        &[("authorization", format!("Bearer {bad}"))],
        "{}",
    )
    .await;

    let logs = h.logs();
    for secret in [
        "SECRET-ARGUMENT-MARKER",
        "SECRET-OUTPUT-MARKER",
        "SECRET-COMMAND-MARKER",
        "SECRET-LATE-OUTPUT-MARKER",
        request_id.as_str(),
        &mcp_token,
        &bad,
        &s,
    ] {
        assert!(!logs.contains(secret), "log leaked {secret:?}:\n{logs}");
    }
    // Every connector token and its signature stay out too.
    for line in h.logs.lock().unwrap().iter() {
        assert!(
            !line.contains("eyJ"),
            "a JWT-looking string reached the log: {line}"
        );
    }
    // The one line per call is there, with sizes and outcome.
    let call_line: Value = logs
        .lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap())
        .find(|v| v["event"] == "call")
        .expect("a call line");
    assert_eq!(call_line["device_id"], device.as_str());
    assert_eq!(call_line["client_id"], MCP_CLIENT);
    assert_eq!(call_line["tool"], "read_file");
    assert_eq!(call_line["outcome"], "ok");
    assert_eq!(
        call_line["arg_bytes"],
        json!({"path": "SECRET-ARGUMENT-MARKER"}).to_string().len()
    );
    assert!(call_line["result_bytes"].as_u64().unwrap() > 0);
    assert!(call_line["duration_ms"].is_u64());
    // The waiting reply and the fetch each have their line.
    let lines: Vec<Value> = logs
        .lines()
        .map(|l| serde_json::from_str::<Value>(l).unwrap())
        .filter(|v| v["event"] == "call")
        .collect();
    let line_for = |tool: &str, outcome: &str| {
        lines
            .iter()
            .find(|v| v["tool"] == tool && v["outcome"] == outcome)
            .unwrap_or_else(|| panic!("no {tool}/{outcome} line in {logs}"))
    };
    assert!(
        line_for("start_process", "waiting_approval")["arg_bytes"]
            .as_u64()
            .unwrap()
            > 0
    );
    let check = line_for("check_request", "ok");
    assert_eq!(check["device_id"], device.as_str());
    assert_eq!(check["client_id"], MCP_CLIENT);
    assert!(check["result_bytes"].as_u64().unwrap() > 0);
}

#[test]
fn pings_every_tick_in_a_call_and_every_idle_interval_otherwise() {
    // Production: 2 s ticks, idle every 10th (20 s).
    assert!(ping_due(1, true, 10));
    assert!(!ping_due(1, false, 10));
    assert!(!ping_due(9, false, 10));
    assert!(ping_due(10, false, 10));
}

#[test]
fn production_timing_matches_the_spec() {
    let t = Timing::default();
    assert_eq!(t.hello_timeout, Duration::from_secs(10));
    assert_eq!(
        t.idle_ping,
        Duration::from_secs(vitruvian_relay_protocol::PING_SECS)
    );
    assert_eq!(
        t.in_call_ping,
        Duration::from_secs(vitruvian_relay_protocol::IN_CALL_PING_SECS)
    );
    assert_eq!(
        t.max_missed_pings,
        vitruvian_relay_protocol::MAX_MISSED_PINGS
    );
    assert_eq!(t.call_budget, Duration::from_secs(90));
    assert_eq!(
        t.ack_timeout,
        Duration::from_secs(vitruvian_relay_protocol::ACK_SECS)
    );
    assert_eq!(
        t.reconnect_grace,
        Duration::from_secs(vitruvian_relay_protocol::RECONNECT_GRACE_SECS)
    );
    assert_eq!(t.reconnect_grace, Duration::from_secs(10));
    // The AI app gives up on a call at about 15 s; the relay answers at 10.
    assert_eq!(t.approval_reply, Duration::from_secs(10));
    assert_eq!(
        t.approval_reply,
        Duration::from_secs(vitruvian_relay_protocol::APPROVAL_REPLY_SECS)
    );
    assert_eq!(t.rejoin_window, Duration::from_secs(120));
    assert_eq!(
        t.rejoin_window,
        Duration::from_secs(vitruvian_relay_protocol::REJOIN_WINDOW_SECS)
    );
    assert_eq!(t.parked_result, Duration::from_secs(300));
    assert_eq!(
        t.parked_result,
        Duration::from_secs(vitruvian_relay_protocol::PARKED_RESULT_SECS)
    );
    assert_eq!(t.max_clock_skew_secs, 60);
    assert_eq!(t.send_timeout, Duration::from_secs(30));
    assert_eq!(t.transit_margin, Duration::from_secs(6));
    assert_eq!(t.first_header_timeout, Duration::from_secs(10));
    assert_eq!(t.header_read_timeout, Duration::from_secs(75));
    assert_eq!(t.body_timeout, Duration::from_secs(30));
    assert_eq!(t.max_connection_lifetime, Duration::from_secs(12 * 60 * 60));
    let now = (t.clock)();
    assert!(now.abs_diff(now_secs()) <= 5, "the clock is the wall clock");
}

// ------------------------------------------------------- fix round 1 tests

#[tokio::test]
async fn reregister_during_hello_gap_ends_old_key_connection() {
    let h = harness().await;
    let (device, old_key) = h.new_device(ALICE).await;
    // Pause the connection after its hello is checked, before it registers.
    let (reached, release) = (
        Arc::new(tokio::sync::Notify::new()),
        Arc::new(tokio::sync::Notify::new()),
    );
    *h.app.after_hello.lock().unwrap() = Some((reached.clone(), release.clone()));
    let token = h.connector_token(ALICE);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &old_key,
        &token,
        now_secs(),
        vec![tool("a")],
    )))
    .await
    .unwrap();
    within(reached.notified()).await;
    // The key changes in the gap; there is nothing to kick yet.
    *h.app.after_hello.lock().unwrap() = None;
    assert_eq!(
        h.reregister(ALICE, &device, &ed25519()).await.status,
        StatusCode::OK
    );
    release.notify_one();
    // The old-key connection must end, whatever it saw first.
    loop {
        match next_frame(&mut ws).await {
            None => break,
            Some(ToConnector::Welcome { .. }) | Some(ToConnector::Reject { .. }) => {}
            Some(other) => panic!("unexpected {other:?}"),
        }
    }
    within(async {
        while h.app.registry.tools(&device).is_some() {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;
}

#[test]
fn in_call_drop_trips_three_intervals_after_the_call_starts() {
    // Production: 2 s ticks, idle ping every 10th tick.
    let mut l = Liveness::new(10, 3);
    // The call goes out: a ping at once, so the count starts with the call.
    assert_eq!(l.call_started(), Beat::Ping(1));
    assert_eq!(l.tick(true), Beat::Ping(2)); // 2 s: ping 1 unanswered
    assert_eq!(l.tick(true), Beat::Ping(3)); // 4 s
    assert_eq!(l.tick(true), Beat::Dead(3)); // 6 s: ping 3's window has passed
}

#[test]
fn idle_drop_trips_after_three_unanswered_pings() {
    let mut l = Liveness::new(10, 3);
    let mut beats = Vec::new();
    for tick in 1..=30 {
        match l.tick(false) {
            Beat::Nothing => {}
            b => beats.push((tick, b)),
        }
        if matches!(beats.last(), Some((_, Beat::Dead(_)))) {
            break;
        }
    }
    // Pings at 20 s, 40 s, 60 s; dead when the third's reply window ends
    // (62 s), not one whole idle interval later.
    assert_eq!(
        beats,
        vec![
            (10, Beat::Ping(1)),
            (20, Beat::Ping(2)),
            (30, Beat::Ping(3))
        ]
    );
    assert_eq!(l.tick(false), Beat::Dead(3), "62 s");
}

#[test]
fn an_answered_ping_keeps_the_link_alive() {
    let mut l = Liveness::new(10, 3);
    for _ in 0..100 {
        if let Beat::Ping(_) = l.tick(true) {
            l.heard();
        }
        assert_ne!(l.tick(true), Beat::Dead(3));
        l.heard();
    }
    // A call starting while a ping is already out does not send another.
    let mut l = Liveness::new(10, 3);
    assert_eq!(l.call_started(), Beat::Ping(1));
    assert_eq!(l.call_started(), Beat::Nothing);
}

#[tokio::test]
async fn slow_headers_are_cut_off() {
    // The first request gets the short limit even though the idle limit
    // (hyper's header timer) is long.
    let h = harness_with(Timing {
        first_header_timeout: Duration::from_millis(200),
        header_read_timeout: Duration::from_secs(60),
        ..Timing::default()
    })
    .await;
    // Headers never finish; the server must not wait forever.
    let t = Instant::now();
    let got = h.raw(b"POST /devices HTTP/1.1\r\nHost: relay\r\n").await;
    assert!(got.is_empty() || got.starts_with("HTTP/1.1 408"), "{got:?}");
    assert!(t.elapsed() < Duration::from_secs(5), "{:?}", t.elapsed());
}

/// Final review M4: a kept-alive connection idle between requests is not
/// closed after the first request's short header limit (a proxy reuses its
/// pooled connections).
#[tokio::test]
async fn an_idle_kept_alive_connection_outlives_the_first_header_limit() {
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    let h = harness_with(Timing {
        first_header_timeout: Duration::from_millis(200),
        header_read_timeout: Duration::from_secs(5),
        ..Timing::default()
    })
    .await;
    let mut stream = tokio::net::TcpStream::connect(h.addr).await.unwrap();
    async fn healthz(stream: &mut tokio::net::TcpStream) -> String {
        stream
            .write_all(b"GET /healthz HTTP/1.1\r\nHost: relay\r\n\r\n")
            .await
            .unwrap();
        let mut got = Vec::new();
        let mut buf = [0u8; 1024];
        within(async {
            while !String::from_utf8_lossy(&got).ends_with("ok") {
                let n = stream.read(&mut buf).await.unwrap();
                assert!(n > 0, "closed: {}", String::from_utf8_lossy(&got));
                got.extend_from_slice(&buf[..n]);
            }
        })
        .await;
        String::from_utf8_lossy(&got).into_owned()
    }
    assert!(healthz(&mut stream).await.starts_with("HTTP/1.1 200"));
    // Idle for five first-header limits.
    tokio::time::sleep(Duration::from_millis(1000)).await;
    assert!(healthz(&mut stream).await.starts_with("HTTP/1.1 200"));
}

#[test]
fn the_first_head_ends_at_the_blank_line_even_split_across_reads() {
    // Drive FirstHead's matcher through reads that split "\r\n\r\n".
    let rt = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    rt.block_on(async {
        use tokio::io::AsyncReadExt;
        let (client, server) = tokio::io::duplex(64);
        let mut head = FirstHead::new(server, Duration::from_millis(300));
        let writer = tokio::spawn(async move {
            use tokio::io::AsyncWriteExt;
            let mut client = client;
            for part in [&b"GET / HTTP/1.1\r"[..], b"\nHost: x\r\n\r", b"\n"] {
                client.write_all(part).await.unwrap();
                tokio::time::sleep(Duration::from_millis(50)).await;
            }
            // Past the limit, after the head: still readable.
            tokio::time::sleep(Duration::from_millis(400)).await;
            client.write_all(b"body").await.unwrap();
            client
        });
        let mut got = Vec::new();
        let mut buf = [0u8; 64];
        while !got.ends_with(b"body") {
            let n = head
                .read(&mut buf)
                .await
                .expect("no time-out after the head");
            got.extend_from_slice(&buf[..n]);
        }
        let _client = writer.await.unwrap();
    });
}

#[tokio::test]
async fn slow_body_gets_408() {
    let h = harness_with(Timing {
        body_timeout: Duration::from_millis(200),
        ..Timing::default()
    })
    .await;
    let req = format!(
        "POST /devices HTTP/1.1\r\nHost: relay\r\nAuthorization: Bearer {}\r\nContent-Length: 100\r\n\r\n{{\"public",
        h.connector_token(ALICE)
    );
    let got = h.raw(req.as_bytes()).await;
    assert!(got.starts_with("HTTP/1.1 408"), "{got:?}");
}

#[tokio::test]
async fn body_errors_other_than_size_get_400() {
    let h = harness().await;
    let auth = format!("Authorization: Bearer {}\r\n", h.connector_token(ALICE));
    let broken = format!(
        "POST /devices HTTP/1.1\r\nHost: relay\r\n{auth}Transfer-Encoding: chunked\r\n\r\nzz\r\n"
    );
    let got = h.raw(broken.as_bytes()).await;
    assert!(got.starts_with("HTTP/1.1 400"), "{got:?}");
    // Too big is still 413.
    let big = "x".repeat(MAX_DEVICES_BODY_BYTES + 1);
    let r = h
        .send(
            "POST",
            "/devices",
            &[(
                "authorization",
                format!("Bearer {}", h.connector_token(ALICE)),
            )],
            &big,
        )
        .await;
    assert_eq!(r.status, StatusCode::PAYLOAD_TOO_LARGE);
}

#[tokio::test]
async fn one_person_cannot_evict_anothers_sessions() {
    let h = harness().await;
    let (alices, _) = h.new_device(ALICE).await;
    let (bobs, _) = h.new_device(BOB).await;
    let bob_session = h.session(&bobs, BOB).await;
    let first = h.session(&alices, ALICE).await;
    let mut last = first.clone();
    for _ in 0..MAX_SESSIONS_PER_SUBJECT {
        last = h.session(&alices, ALICE).await;
    }
    let list = json!({"jsonrpc": "2.0", "id": 1, "method": "tools/list"});
    assert_eq!(
        h.rpc(&bobs, BOB, Some(&bob_session), list.clone())
            .await
            .status,
        StatusCode::OK
    );
    // Alice's own oldest session made room for her newest.
    assert_eq!(
        h.rpc(&alices, ALICE, Some(&first), list.clone())
            .await
            .status,
        StatusCode::NOT_FOUND
    );
    assert_eq!(
        h.rpc(&alices, ALICE, Some(&last), list).await.status,
        StatusCode::OK
    );
}

#[test]
fn token_exp_reads_the_claim() {
    let t = mint_exp(&rsa_key(), CONNECTOR_CLIENT, ALICE, 1_900_000_000);
    assert_eq!(token_exp(&t), Some(1_900_000_000));
    assert_eq!(token_exp("not.a.jwt"), None);
    assert_eq!(token_exp("garbage"), None);
}

async fn close_reason<S>(ws: &mut tokio_tungstenite::WebSocketStream<S>) -> Option<String>
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    loop {
        match within(ws.next()).await {
            Some(Ok(Message::Close(f))) => return f.map(|f| f.reason.into_owned()),
            Some(Ok(_)) => {}
            Some(Err(_)) | None => return None,
        }
    }
}

#[tokio::test]
async fn connection_closes_when_the_token_expires() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let token = mint_exp(&h.rsa, CONNECTOR_CLIENT, ALICE, now_secs() + 2);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &key,
        &token,
        now_secs(),
        vec![],
    )))
    .await
    .unwrap();
    assert!(matches!(
        next_frame(&mut ws).await,
        Some(ToConnector::Welcome { .. })
    ));
    let reason = close_reason(&mut ws)
        .await
        .expect("a close frame with a reason");
    assert!(reason.contains("expired"), "{reason}");
    assert!(h.app.registry.tools(&device).is_none());

    // Already past its exp (the checker allows some clock skew): refused.
    let token = mint_exp(&h.rsa, CONNECTOR_CLIENT, ALICE, now_secs() - 5);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &key,
        &token,
        now_secs(),
        vec![],
    )))
    .await
    .unwrap();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => assert!(reason.contains("expired"), "{reason}"),
        other => panic!("expected reject, got {other:?}"),
    }
}

#[tokio::test]
async fn connect_requires_websocket_version_13() {
    let h = harness().await;
    let auth = format!("Authorization: Bearer {}\r\n", h.connector_token(ALICE));
    for version in ["Sec-WebSocket-Version: 8\r\n", ""] {
        let req = format!(
            "GET /connect HTTP/1.1\r\nHost: relay\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n\
             Sec-WebSocket-Key: {nonce}\r\n{version}{auth}\r\n",
            nonce = b64(b"a 16-byte nonce!")
        );
        let got = h.raw(req.as_bytes()).await;
        assert!(got.starts_with("HTTP/1.1 400"), "{version:?}: {got:?}");
    }
}

// ------------------------------------------------------- fix round 2 tests

#[tokio::test]
async fn stale_key_hello_in_the_gap_does_not_displace_the_new_connection() {
    let h = harness().await;
    let (device, old_key) = h.new_device(ALICE).await;
    // A connection with the old key passes its hello check, then stalls.
    let (reached, release) = (
        Arc::new(tokio::sync::Notify::new()),
        Arc::new(tokio::sync::Notify::new()),
    );
    *h.app.after_hello.lock().unwrap() = Some((reached.clone(), release.clone()));
    let token = h.connector_token(ALICE);
    let mut stale = h.ws(&token).await.unwrap();
    stale
        .send(Message::Text(hello(
            &device,
            &old_key,
            &token,
            now_secs(),
            vec![tool("old")],
        )))
        .await
        .unwrap();
    within(reached.notified()).await;
    *h.app.after_hello.lock().unwrap() = None;
    // Meanwhile the device is registered again and connects with its new key.
    let new_key = ed25519();
    assert_eq!(
        h.reregister(ALICE, &device, &new_key).await.status,
        StatusCode::OK
    );
    let fresh = h.connect(ALICE, &device, &new_key, vec![tool("new")]).await;
    release.notify_one();
    // The stale connection ends without ever taking the device's place,
    // and is never told "welcome" first (final-wave item 4a).
    let mut frames = Vec::new();
    while let Some(f) = next_frame(&mut stale).await {
        frames.push(f);
    }
    assert!(
        matches!(frames.as_slice(), [ToConnector::Reject { .. }]),
        "{frames:?}"
    );
    assert_eq!(h.app.registry.tools(&device), Some(vec![tool("new")]));
    assert!(!fresh.is_closed.load(Ordering::SeqCst));
}

#[tokio::test]
async fn frames_without_pongs_keep_a_call_alive() {
    // 200 ms in-call pings: three missed would end the link in ~600 ms.
    let h = Arc::new(
        harness_with(Timing {
            in_call_ping: Duration::from_millis(200),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(&h, &device, ALICE, &s, call_body(json!(1), "t", json!({})));
    let call = fake.next_call().await;
    fake.answer_pings.store(false, Ordering::SeqCst);
    // No pongs for 1.5 s, but other frames keep coming.
    for _ in 0..15 {
        fake.send(ToRelay::ToolsChanged {
            tools: vec![tool("t")],
        });
        tokio::time::sleep(Duration::from_millis(100)).await;
    }
    fake.reply(&call.call_id, "done");
    let r = within(pending).await.unwrap();
    assert_eq!(
        r.json()["result"]["content"][0]["text"],
        "done",
        "{}",
        r.body
    );
}

/// Writes at most `chunk` bytes, then waits `pause`: a slow uplink.
struct Throttled {
    inner: tokio::net::TcpStream,
    chunk: usize,
    pause: Duration,
    sleep: Option<std::pin::Pin<Box<tokio::time::Sleep>>>,
}

impl tokio::io::AsyncRead for Throttled {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_read(cx, buf)
    }
}

impl tokio::io::AsyncWrite for Throttled {
    fn poll_write(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buf: &[u8],
    ) -> std::task::Poll<std::io::Result<usize>> {
        use std::future::Future;
        use std::task::Poll;
        if let Some(sleep) = self.sleep.as_mut() {
            if sleep.as_mut().poll(cx).is_pending() {
                return Poll::Pending;
            }
            self.sleep = None;
        }
        let n = buf.len().min(self.chunk);
        let r = std::pin::Pin::new(&mut self.inner).poll_write(cx, &buf[..n]);
        if let Poll::Ready(Ok(w)) = &r {
            if *w > 0 {
                let pause = self.pause;
                self.sleep = Some(Box::pin(tokio::time::sleep(pause)));
            }
        }
        r
    }

    fn poll_flush(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_flush(cx)
    }

    fn poll_shutdown(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        std::pin::Pin::new(&mut self.inner).poll_shutdown(cx)
    }
}

#[tokio::test]
async fn a_slow_large_result_is_not_dropped_mid_upload() {
    let h = Arc::new(
        harness_with(Timing {
            in_call_ping: Duration::from_millis(200),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    // 64 KiB per 100 ms: a 1 MiB result takes about 1.6 s, well past the
    // 600 ms in which three missed pings would end the link, and the device
    // answers no pings while it uploads.
    let stream = Throttled {
        inner: tokio::net::TcpStream::connect(h.addr).await.unwrap(),
        chunk: 64 * 1024,
        pause: Duration::from_millis(100),
        sleep: None,
    };
    let mut fake = h
        .connect_on(stream, ALICE, &device, &key, vec![tool("t")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(&h, &device, ALICE, &s, call_body(json!(1), "t", json!({})));
    let call = fake.next_call().await;
    fake.answer_pings.store(false, Ordering::SeqCst);
    let big = "x".repeat(1024 * 1024);
    fake.reply(&call.call_id, &big);
    let r = within(pending).await.unwrap();
    assert_eq!(
        r.json()["result"]["isError"],
        false,
        "{}",
        &r.body[..r.body.len().min(300)]
    );
    assert_eq!(
        r.json()["result"]["content"][0]["text"]
            .as_str()
            .unwrap()
            .len(),
        big.len()
    );
}

#[tokio::test]
async fn connect_refuses_a_token_without_exp() {
    let h = harness().await;
    let token = mint_claims(&h.rsa, CONNECTOR_CLIENT, ALICE, None);
    match h.ws(&token).await {
        Err(tokio_tungstenite::tungstenite::Error::Http(resp)) => {
            assert_eq!(resp.status(), StatusCode::UNAUTHORIZED);
            let challenge = resp.headers()["www-authenticate"]
                .to_str()
                .unwrap()
                .to_string();
            assert!(challenge.contains("exp"), "{challenge}");
        }
        Err(e) => panic!("expected an HTTP refusal, got {e}"),
        Ok(_) => panic!("a token with no exp must not open /connect"),
    }
}

#[tokio::test]
async fn connection_closes_at_the_lifetime_cap() {
    let h = harness_with(Timing {
        max_connection_lifetime: Duration::from_millis(500),
        ..Timing::default()
    })
    .await;
    let (device, key) = h.new_device(ALICE).await;
    // A token good for a long time: the cap still applies.
    let token = mint_exp(&h.rsa, CONNECTOR_CLIENT, ALICE, now_secs() + 24 * 60 * 60);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &key,
        &token,
        now_secs(),
        vec![],
    )))
    .await
    .unwrap();
    assert!(matches!(
        next_frame(&mut ws).await,
        Some(ToConnector::Welcome { .. })
    ));
    let reason = close_reason(&mut ws)
        .await
        .expect("a close frame with a reason");
    assert!(reason.contains("lifetime"), "{reason}");
    assert!(h.app.registry.tools(&device).is_none());
}

// ------------------------------------------- calls that waited to be sent

/// Makes the next session that takes a frame off its queue stop there, the
/// frame not yet sent, as a peer that has stopped reading does. Wait for
/// `reached`, then call `let_go` to let the session carry on (later frames
/// are not held).
struct HeldSends {
    reached: Arc<tokio::sync::Notify>,
    release: Arc<tokio::sync::Notify>,
}

fn hold_sends(h: &Harness) -> HeldSends {
    let held = HeldSends {
        reached: Arc::new(tokio::sync::Notify::new()),
        release: Arc::new(tokio::sync::Notify::new()),
    };
    *h.app.hold_sends.lock().unwrap() = Some((held.reached.clone(), held.release.clone()));
    held
}

impl HeldSends {
    fn let_go(&self, h: &Harness) {
        *h.app.hold_sends.lock().unwrap() = None;
        self.release.notify_one();
    }
}

pub(crate) fn error_text(r: &Reply) -> String {
    assert_eq!(r.json()["result"]["isError"], true, "{}", r.body);
    r.json()["result"]["content"][0]["text"]
        .as_str()
        .unwrap()
        .to_string()
}

#[test]
fn the_margin_for_a_call_grows_with_its_size() {
    let transit = Duration::from_secs(6);
    assert_eq!(call_margin(transit, 0), transit);
    assert_eq!(
        call_margin(transit, 640),
        transit + Duration::from_millis(10)
    );
    // The largest frame at the slowest link the connector also allows for.
    assert_eq!(
        call_margin(transit, MAX_FRAME_BYTES),
        transit + Duration::from_millis(65_536)
    );
}

#[tokio::test]
async fn a_call_given_up_on_while_it_waited_to_be_sent_never_reaches_the_device() {
    let h = Arc::new(
        harness_with(Timing {
            call_budget: Duration::from_millis(800),
            transit_margin: Duration::from_millis(50),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    let s = h.session(&device, ALICE).await;

    // The session has the call in hand but cannot send it yet.
    let held = hold_sends(&h);
    let pending = spawn_rpc(&h, &device, ALICE, &s, call_body(json!(1), "t", json!({})));
    within(held.reached.notified()).await;
    // The relay gives up on it: the AI app is told so.
    let r = within(pending).await.unwrap();
    assert_eq!(error_text(&r), "The command took too long.");
    assert!(!h.app.registry.in_flight(&device));

    // The send goes through at last. The cancel was queued behind the call,
    // so if the cancel is the first thing the device gets, the call was
    // never sent.
    held.let_go(&h);
    match fake.next().await {
        ToConnector::Cancel { .. } => {}
        other => panic!("the device got {other:?}"),
    }
    // No call was started on the link, so the relay did not begin its
    // in-call pings, and the device has no call to expect them for.
    assert_eq!(fake.pings.load(Ordering::SeqCst), 0);
    assert!(fake.frames.try_recv().is_err());
}

#[tokio::test]
async fn a_call_that_waited_to_be_sent_carries_only_the_time_left_less_the_margin() {
    let h = Arc::new(
        harness_with(Timing {
            call_budget: Duration::from_secs(10),
            transit_margin: Duration::from_secs(2),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    let s = h.session(&device, ALICE).await;
    let held = hold_sends(&h);
    let pending = spawn_rpc(&h, &device, ALICE, &s, call_body(json!(1), "t", json!({})));
    within(held.reached.notified()).await;
    tokio::time::sleep(Duration::from_millis(500)).await;
    held.let_go(&h);
    let call = fake.next_call().await;
    // 10 s, less the 0.5 s it waited, less the 2 s margin. The lower bound
    // only allows for a slow machine.
    assert!(
        (2_500..=7_500).contains(&call.deadline_ms),
        "{}",
        call.deadline_ms
    );
    fake.reply(&call.call_id, "ok");
    let r = within(pending).await.unwrap();
    assert_eq!(r.json()["result"]["isError"], false);
}

#[tokio::test]
async fn a_call_with_no_more_than_the_margin_left_is_failed_instead_of_sent() {
    let h = Arc::new(
        harness_with(Timing {
            call_budget: Duration::from_secs(10),
            transit_margin: Duration::from_secs(60),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    let s = h.session(&device, ALICE).await;
    let started = Instant::now();
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(1), "t", json!({})),
        )
        .await;
    assert_eq!(error_text(&r), "The command took too long.");
    // At once, not after the 10 s budget; and nothing was sent, not even a
    // cancel (there is nothing at the device to stop).
    assert!(started.elapsed() < Duration::from_secs(5));
    assert!(!h.app.registry.in_flight(&device));
    tokio::time::sleep(Duration::from_millis(200)).await;
    assert!(fake.frames.try_recv().is_err());
}

#[tokio::test]
async fn a_reregistered_device_never_gets_the_calls_still_queued_for_its_old_connection() {
    let h = Arc::new(harness().await);
    let (device, old_key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &old_key, vec![tool("t")]).await;
    let s = h.session(&device, ALICE).await;

    let held = hold_sends(&h);
    let pending = spawn_rpc(&h, &device, ALICE, &s, call_body(json!(1), "t", json!({})));
    within(held.reached.notified()).await;
    // The device is registered again: the relay fails the call.
    assert_eq!(
        h.reregister(ALICE, &device, &ed25519()).await.status,
        StatusCode::OK
    );
    let r = within(pending).await.unwrap();
    assert_eq!(
        error_text(&r),
        "Your computer disconnected. The command may already have run; check before trying again."
    );

    // The old connection gets to send again. It must close without handing
    // over the call the relay has already failed.
    held.let_go(&h);
    fake.wait_closed().await;
    if let Ok(f) = fake.frames.try_recv() {
        panic!("the old connection got {f:?}");
    }
}

#[tokio::test]
async fn a_connection_closed_for_a_lost_cancel_sends_nothing_that_was_queued() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    // Cancels wait 100 ms for room here, not 2 s.
    let reg = h.app.registry.cancel_waiting(Duration::from_millis(100));
    let spawn_call = |n: usize| {
        let (reg, device) = (reg.clone(), device.clone());
        tokio::spawn(async move {
            let call = Call {
                call_id: format!("c{n}"),
                tool: "t".into(),
                arguments: json!({}),
                deadline_ms: 500,
            };
            reg.call(&device, call).await
        })
    };

    // One call in the session's hand, unsent, and the queue full behind it:
    // when the relay gives up on them, no cancel can be queued.
    let held = hold_sends(&h);
    let mut calls = vec![spawn_call(0)];
    within(held.reached.notified()).await;
    calls.extend((1..=CONNECTION_QUEUE).map(spawn_call));
    for c in calls {
        assert!(within(c).await.unwrap().is_err());
    }
    // So the relay closes the connection.
    within(async {
        while h.app.registry.tools(&device).is_some() {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;

    // The stalled send comes back: the session ends at once and the device
    // gets none of what was queued.
    held.let_go(&h);
    fake.wait_closed().await;
    if let Ok(f) = fake.frames.try_recv() {
        panic!("the device got {f:?}");
    }
    within(async {
        while !h.logs().contains("closed: a cancel could not be queued") {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;
}

#[tokio::test]
async fn a_call_frame_that_cannot_be_written_within_its_margin_drops_the_link() {
    let h = harness_with(Timing {
        transit_margin: Duration::from_millis(200),
        ..Timing::default()
    })
    .await;
    let (device, key) = h.new_device(ALICE).await;
    // A session on a pipe that holds 1 KiB: once the device stops reading,
    // a larger frame cannot be written.
    let (client_io, server_io) = tokio::io::duplex(1024);
    let token = h.connector_token(ALICE);
    let (app, hash) = (h.app.clone(), token_hash(&token));
    tokio::spawn(async move {
        let ws = WebSocketStream::from_raw_socket(server_io, Role::Server, Some(ws_config())).await;
        let caller = Caller {
            subject: ALICE.into(),
            client_id: CONNECTOR_CLIENT.into(),
        };
        run_connection(app, ws, caller, hash, None, Arc::default()).await;
    });
    let mut ws = WebSocketStream::from_raw_socket(client_io, Role::Client, None).await;
    ws.send(Message::Text(hello(
        &device,
        &key,
        &token,
        now_secs(),
        vec![tool("t")],
    )))
    .await
    .unwrap();
    assert!(matches!(
        next_frame(&mut ws).await,
        Some(ToConnector::Welcome { .. })
    ));

    // The device reads nothing more. A 16 KiB call may take the 200 ms
    // margin plus 16 KiB at 64 bytes/ms (about 0.25 s) to arrive; after
    // that the device's deadline would end later than the relay's, so the
    // link goes, long before the 30 s any other frame is allowed.
    let s = h.session(&device, ALICE).await;
    let started = Instant::now();
    let args = json!({"data": "x".repeat(16 * 1024)});
    let r = within(h.rpc(&device, ALICE, Some(&s), call_body(json!(1), "t", args))).await;
    assert_eq!(
        error_text(&r),
        "Your computer disconnected. The command may already have run; check before trying again."
    );
    assert!(started.elapsed() >= Duration::from_millis(400));
    // (The session logs its reason once its socket is closed.)
    drop(ws);
    within(async {
        while !h.logs().contains("send stalled") {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;
}

// ------------------------------------------------ p2 task 2: receipt handshake

#[tokio::test]
async fn call_without_ack_fails_not_received() {
    let h = Arc::new(
        harness_with(Timing {
            ack_timeout: Duration::from_millis(200),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    fake.no_ack();
    let s = h.session(&device, ALICE).await;

    let started = Instant::now();
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(1), "read_file", json!({"path": "/tmp/x"})),
    );
    let call = fake.next_call().await;

    let r = within(pending).await.unwrap();
    assert_eq!(
        error_text(&r),
        "Your computer didn't answer in time; try again."
    );
    assert!(started.elapsed() < Duration::from_secs(5));
    assert_eq!(
        fake.next().await,
        ToConnector::Cancel {
            call_id: call.call_id.clone(),
        }
    );
    assert!(!h.app.registry.in_flight(&device));
    assert!(fake.starts.lock().unwrap().is_empty());
    within(async {
        while !h.logs().contains("\"outcome\":\"not_received\"") {
            tokio::time::sleep(Duration::from_millis(20)).await;
        }
    })
    .await;

    // A late ack after the relay gave up must never trigger Start.
    fake.send(ToRelay::Ack {
        call_id: call.call_id,
    });
    tokio::time::sleep(Duration::from_millis(100)).await;
    assert!(fake.frames.try_recv().is_err());
    assert!(fake.starts.lock().unwrap().is_empty());
}

#[tokio::test]
async fn ack_triggers_start_and_delivers_result() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    fake.no_ack();
    let s = h.session(&device, ALICE).await;

    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(2), "read_file", json!({"path": "/tmp/y"})),
    );
    let call = fake.next_call().await;
    fake.send(ToRelay::Ack {
        call_id: call.call_id.clone(),
    });
    assert_eq!(
        fake.next().await,
        ToConnector::Start {
            call_id: call.call_id.clone(),
        }
    );
    assert_eq!(*fake.starts.lock().unwrap(), vec![call.call_id.clone()]);
    fake.reply(&call.call_id, "ok");
    let r = within(pending).await.unwrap();
    assert_eq!(r.json()["result"]["isError"], false);
    assert_eq!(r.json()["result"]["content"][0]["text"], "ok");
}

#[tokio::test]
async fn an_accepted_result_is_acknowledged() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(2), "read_file", json!({"path": "/tmp/y"})),
    );
    let call = fake.next_call().await;
    fake.reply(&call.call_id, "ok");
    within(pending).await.unwrap();
    until(|| fake.result_acks() == [call.call_id.clone()]).await;
}

#[tokio::test]
async fn repeated_result_for_finished_call_is_acked() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(2), "read_file", json!({"path": "/tmp/y"})),
    );
    let call = fake.next_call().await;
    fake.reply(&call.call_id, "ok");
    let first = within(pending).await.unwrap();
    until(|| fake.result_acks().len() == 1).await;
    // The connector never saw that ack and sends the result again: nobody
    // waits for it now, but it is acknowledged so the connector stops.
    fake.reply(&call.call_id, "ok");
    until(|| fake.result_acks().len() == 2).await;
    assert_eq!(fake.result_acks(), [call.call_id.clone(), call.call_id]);
    assert_eq!(first.json()["result"]["content"][0]["text"], "ok");
}

#[tokio::test]
async fn result_after_grace_is_delivered_when_device_reconnected() {
    let h = Arc::new(
        harness_with(Timing {
            reconnect_grace: Duration::from_millis(300),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(2), "read_file", json!({"path": "/tmp/y"})),
    );
    let call = fake.next_call().await;
    // The link resets; the device is back at once, and runs the command for
    // well over the grace period.
    drop(fake);
    until(|| !h.app.registry.in_flight(&device)).await;
    let mut fake2 = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    tokio::time::sleep(Duration::from_millis(800)).await;
    assert!(!pending.is_finished(), "the call failed after the grace");
    fake2.reply(&call.call_id, "late but real");
    let r = within(pending).await.unwrap();
    assert_eq!(r.json()["result"]["isError"], false);
    assert_eq!(r.json()["result"]["content"][0]["text"], "late but real");
    // Nothing told the device to stop it.
    assert!(fake2.frames.try_recv().is_err());
}

#[tokio::test]
async fn dialog_open_after_reconnect_is_cancelled_when_relay_gives_up() {
    let h = Arc::new(
        harness_with(Timing {
            reconnect_grace: Duration::from_millis(300),
            call_budget: Duration::from_millis(1500),
            transit_margin: Duration::from_millis(100),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("start_process")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(2), "start_process", json!({"command": "ls"})),
    );
    let call = fake.next_call().await;
    drop(fake);
    until(|| !h.app.registry.in_flight(&device)).await;
    // Back within the grace, with its dialog still open; nobody answers it.
    let mut fake2 = h
        .connect(ALICE, &device, &key, vec![tool("start_process")])
        .await;
    // The relay's deadline passes (after the grace): the AI is told, and the
    // device is told to close the dialog on the connection it has now.
    let r = within(pending).await.unwrap();
    assert_eq!(error_text(&r), "The command took too long.");
    assert_eq!(
        fake2.next().await,
        ToConnector::Cancel {
            call_id: call.call_id
        }
    );
}

#[tokio::test]
async fn a_result_over_a_new_connection_reaches_a_call_held_across_a_drop() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(2), "read_file", json!({"path": "/tmp/y"})),
    );
    let call = fake.next_call().await;
    // The link drops with the call running on the device.
    drop(fake);
    until(|| !h.app.registry.in_flight(&device)).await;
    let fake2 = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    fake2.reply(&call.call_id, "survived");
    let r = within(pending).await.unwrap();
    assert_eq!(r.json()["result"]["isError"], false);
    assert_eq!(r.json()["result"]["content"][0]["text"], "survived");
    until(|| fake2.result_acks() == [call.call_id.clone()]).await;
}

#[tokio::test]
async fn a_call_held_across_a_drop_fails_when_the_device_stays_away() {
    let h = Arc::new(
        harness_with(Timing {
            reconnect_grace: Duration::from_millis(300),
            ..Timing::default()
        })
        .await,
    );
    let (device, key) = h.new_device(ALICE).await;
    let mut fake = h
        .connect(ALICE, &device, &key, vec![tool("read_file")])
        .await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &device,
        ALICE,
        &s,
        call_body(json!(2), "read_file", json!({"path": "/tmp/y"})),
    );
    fake.next_call().await;
    let dropped = Instant::now();
    drop(fake);
    let r = within(pending).await.unwrap();
    assert_eq!(
        error_text(&r),
        "Your computer disconnected. The command may already have run; check before trying again."
    );
    assert!(dropped.elapsed() >= Duration::from_millis(300));
}

#[tokio::test]
async fn v1_hello_is_rejected_with_update_message() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let token = h.connector_token(ALICE);
    let mut frame: Value =
        serde_json::from_str(&hello(&device, &key, &token, now_secs(), vec![])).unwrap();
    frame["protocol"] = json!(1);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(frame.to_string())).await.unwrap();
    assert_eq!(
        next_frame(&mut ws).await,
        Some(ToConnector::Reject {
            reason: "Update vrelay: this relay needs protocol 2.".into(),
        })
    );
    assert!(next_frame(&mut ws).await.is_none());
}

/// The database not answering is said plainly, on every path that needs it,
/// and the relay works again the moment it answers (with a unit-test store;
/// the real database being cut is `tests/database_down.rs`).
#[tokio::test]
async fn a_database_that_is_down_gets_a_plain_message_then_recovers() {
    const MESSAGE: &str = "The relay is having trouble right now; try again in a minute.";
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let s = h.session(&device, ALICE).await;
    h.store.fail_with(Some(StoreError::Unavailable));

    // A call: an ordinary tool result that says what to do, and logs why.
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(5), "read_file", json!({"path": "/top/secret"})),
        )
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(r.json()["id"], 5);
    assert_eq!(r.json()["result"]["isError"], true);
    assert_eq!(r.json()["result"]["content"][0]["text"], MESSAGE);
    let logs = h.logs();
    assert!(logs.contains("\"outcome\":\"store_unavailable\""), "{logs}");
    assert!(logs.contains("\"tool\":\"read_file\""), "{logs}");
    assert!(!logs.contains("/top/secret"), "arguments reached the log");

    // Another method has no tool result to carry it: a 503 with the words.
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            json!({"jsonrpc": "2.0", "id": 6, "method": "tools/list"}),
        )
        .await;
    assert_eq!(r.status, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(r.body, MESSAGE);

    // Registering: the same.
    let r = h.register(ALICE, &ed25519()).await;
    assert_eq!(r.status, StatusCode::SERVICE_UNAVAILABLE);
    assert_eq!(r.body, MESSAGE);

    // A device connecting is told, in words the connector shows.
    let token = h.connector_token(ALICE);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &key,
        &token,
        now_secs(),
        vec![],
    )))
    .await
    .unwrap();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => assert_eq!(reason, MESSAGE),
        other => panic!("expected reject, got {other:?}"),
    }

    // The database is back: the next call is an ordinary one (no computer
    // is connected, so it says so).
    h.store.fail_with(None);
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            call_body(json!(7), "read_file", json!({})),
        )
        .await;
    assert_eq!(r.json()["result"]["isError"], true);
    assert_eq!(
        r.json()["result"]["content"][0]["text"],
        offline_said("My Mac", "never")
    );
    assert_eq!(h.register(ALICE, &ed25519()).await.status, StatusCode::OK);
}

/// A person who already has the most devices is told what to do.
#[tokio::test]
async fn registering_when_the_store_refuses_says_what_to_do() {
    let h = harness().await;
    h.store.fail_with(Some(StoreError::TooManyDevices));
    let r = h.register(ALICE, &ed25519()).await;
    assert_eq!(r.status, StatusCode::CONFLICT);
    assert!(r.body.contains("Remove one"), "{}", r.body);
    h.store.fail_with(Some(StoreError::DuplicateId));
    let r = h.register(ALICE, &ed25519()).await;
    assert_eq!(r.status, StatusCode::CONFLICT);
    assert!(r.body.contains("Register it again"), "{}", r.body);
}

/// The relay remembers a key change only as long as a `/connect` could still
/// be in flight, so the map does not grow with every device ever changed.
#[tokio::test]
async fn key_changes_are_forgotten_after_their_memory() {
    let h = harness_with(Timing {
        key_change_memory: Duration::from_millis(50),
        ..Timing::default()
    })
    .await;
    let before = h.app.key_generation();
    h.app.key_changed("a");
    assert!(h.app.key_changed_since("a", before));
    assert!(!h.app.key_changed_since("a", h.app.key_generation()));
    assert!(!h.app.key_changed_since("other", before));

    tokio::time::sleep(Duration::from_millis(120)).await;
    h.app.key_changed("b");
    let remembered: Vec<String> = h.app.key_changes.lock().unwrap().keys().cloned().collect();
    assert_eq!(remembered, ["b"], "a was forgotten, b is remembered");

    // Many devices over a long time never accumulate.
    for i in 0..200 {
        h.app.key_changed(&format!("d{i}"));
        tokio::time::sleep(Duration::from_millis(1)).await;
    }
    tokio::time::sleep(Duration::from_millis(120)).await;
    h.app.key_changed("last");
    assert_eq!(h.app.key_changes.lock().unwrap().len(), 1);
}

// ------------------------------------------- several computers, and the role

const FIVE_COMPUTERS: &str =
    "You already have 5 computers connected. Remove one in the dashboard first.";

/// Everything about a reply that a caller could tell apart, except the
/// `date` header (a second can tick over between two requests).
fn fingerprint(r: &Reply) -> (StatusCode, String, Vec<(String, String)>) {
    let mut headers: Vec<(String, String)> = r
        .headers
        .iter()
        .filter(|(k, _)| *k != header::DATE)
        .map(|(k, v)| (k.to_string(), v.to_str().unwrap().to_string()))
        .collect();
    headers.sort();
    (r.status, r.body.clone(), headers)
}

async fn names_of(h: &Harness, sub: &str) -> Vec<(String, String)> {
    let mut v: Vec<(String, String)> = h
        .store
        .devices_of(sub)
        .await
        .unwrap()
        .into_iter()
        .map(|d| (d.device_id, d.name))
        .collect();
    v.sort();
    v
}

#[tokio::test]
async fn second_device_gets_its_own_id_and_url() {
    let h = Arc::new(harness().await);
    let (first, first_key) = h.new_device(ALICE).await;
    let second_key = ed25519();
    let r = h
        .register_with(ALICE, &second_key, Some("Studio Mac"), None)
        .await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    let second = r.json()["device_id"].as_str().unwrap().to_string();
    assert_ne!(first, second, "a new computer is a new device");
    assert_eq!(r.json()["mcp_url"], format!("{PUBLIC_URL}/mcp/d/{second}"));

    // Both are hers, each with its own name and key.
    let mut expected = vec![
        (first.clone(), "My Mac".to_string()),
        (second.clone(), "Studio Mac".to_string()),
    ];
    expected.sort();
    assert_eq!(names_of(&h, ALICE).await, expected);
    let stored = h.store.device(&second).await.unwrap().unwrap();
    assert_eq!(
        &stored.public_key_ed25519[..],
        second_key.public_key().as_ref()
    );

    // Both can be connected at once, and each URL reaches its own computer.
    let mut a = h
        .connect(ALICE, &first, &first_key, vec![tool("one")])
        .await;
    let mut b = h
        .connect(ALICE, &second, &second_key, vec![tool("two")])
        .await;
    let sa = h.session(&first, ALICE).await;
    let sb = h.session(&second, ALICE).await;
    let pending = spawn_rpc(
        &h,
        &second,
        ALICE,
        &sb,
        call_body(json!(1), "two", json!({})),
    );
    let call = b.next_call().await;
    b.reply(&call.call_id, "from the studio");
    let r = within(pending).await.unwrap();
    assert_eq!(r.json()["result"]["content"][0]["text"], "from the studio");
    let pending = spawn_rpc(
        &h,
        &first,
        ALICE,
        &sa,
        call_body(json!(1), "one", json!({})),
    );
    let call = a.next_call().await;
    a.reply(&call.call_id, "from the first");
    let r = within(pending).await.unwrap();
    assert_eq!(r.json()["result"]["content"][0]["text"], "from the first");
    assert!(a.frames.try_recv().is_err() && b.frames.try_recv().is_err());

    // Another person's registrations are their own.
    let (bobs, _) = h.new_device(BOB).await;
    assert_eq!(names_of(&h, BOB).await.len(), 1);
    assert_ne!(bobs, first);
    assert_eq!(names_of(&h, ALICE).await.len(), 2);
}

#[tokio::test]
async fn relogin_with_device_id_keeps_the_id() {
    let h = harness().await;
    let (device, old_key) = h.new_device(ALICE).await;
    let fake = h.connect(ALICE, &device, &old_key, vec![tool("a")]).await;

    // Signing in again on that computer: same id, same URL, the key is
    // replaced, the old link ends, and nothing new is made.
    let new_key = ed25519();
    let r = h.reregister(ALICE, &device, &new_key).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(r.json()["device_id"], device.as_str());
    assert_eq!(r.json()["mcp_url"], format!("{PUBLIC_URL}/mcp/d/{device}"));
    fake.wait_closed().await;
    assert_eq!(
        names_of(&h, ALICE).await,
        [(device.clone(), "My Mac".to_string())],
        "no name sent, so the name stays"
    );
    let stored = h.store.device(&device).await.unwrap().unwrap();
    assert_eq!(
        &stored.public_key_ed25519[..],
        new_key.public_key().as_ref()
    );
    h.connect(ALICE, &device, &new_key, vec![]).await;

    // A name sent with it is only what a new computer would be called: this
    // one keeps the name it has (the person may have changed it in the
    // dashboard).
    let r = h
        .register_with(ALICE, &new_key, Some("Studio Mac"), Some(&device))
        .await;
    assert_eq!(r.json()["device_id"], device.as_str());
    assert_eq!(
        names_of(&h, ALICE).await,
        [(device.clone(), "My Mac".to_string())]
    );
    // Asking for the rename (`vrelay login --name`) changes it.
    let body = json!({"public_key": b64(new_key.public_key().as_ref()),
                      "name": "Desk Mac", "device_id": device, "rename": true});
    let r = h.register_body(ALICE, &body.to_string()).await;
    assert_eq!(r.json()["device_id"], device.as_str());
    assert_eq!(
        names_of(&h, ALICE).await,
        [(device.clone(), "Desk Mac".to_string())]
    );

    // An id that is not hers (someone else's, one nobody has, or one she
    // removed) gets her a new device. It never touches the other one, and
    // the answer does not say which of those it was.
    let (bobs, bobs_key) = h.new_device(BOB).await;
    let bobs_fake = h.connect(BOB, &bobs, &bobs_key, vec![tool("b")]).await;
    let nobody = "00000000-0000-4000-8000-000000000000".to_string();
    assert!(h.app.revoke(ALICE, &device).await.unwrap());
    let mut made = Vec::new();
    for not_hers in [&bobs, &nobody, &device] {
        // The name sent is what the new computer is called: a stale id loses
        // nothing.
        let r = h
            .register_with(ALICE, &ed25519(), Some("Studio Mac"), Some(not_hers))
            .await;
        assert_eq!(r.status, StatusCode::OK, "{}", r.body);
        let id = r.json()["device_id"].as_str().unwrap().to_string();
        assert_ne!(&id, not_hers);
        assert_eq!(
            h.store.device(&id).await.unwrap().unwrap().name,
            "Studio Mac"
        );
        assert_eq!(r.json()["mcp_url"], format!("{PUBLIC_URL}/mcp/d/{id}"));
        made.push(id);
    }
    assert_eq!(names_of(&h, ALICE).await.len(), 3);
    let bobs_record = h.store.device(&bobs).await.unwrap().unwrap();
    assert_eq!(
        (
            &bobs_record.owner_sub[..],
            &bobs_record.public_key_ed25519[..]
        ),
        (BOB, bobs_key.public_key().as_ref()),
        "Bob's device is untouched"
    );
    assert!(
        !bobs_fake.is_closed.load(Ordering::SeqCst),
        "and still linked"
    );

    // Something that is not an id at all, or a name that is not text, is
    // a request the person can fix.
    for bad in [
        json!({"public_key": b64(&[1u8; 32]), "device_id": 7}),
        json!({"public_key": b64(&[1u8; 32]), "name": ["x"]}),
    ] {
        let r = h.register_body(ALICE, &bad.to_string()).await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{bad}");
    }
}

#[tokio::test]
async fn sixth_device_is_refused() {
    let h = harness().await;
    for i in 0..5 {
        let r = h
            .register_with(ALICE, &ed25519(), Some(&format!("Mac {i}")), None)
            .await;
        assert_eq!(r.status, StatusCode::OK, "{i}: {}", r.body);
    }
    let r = h
        .register_with(ALICE, &ed25519(), Some("One too many"), None)
        .await;
    assert_eq!(r.status, StatusCode::CONFLICT, "{}", r.body);
    assert_eq!(r.header("content-type").unwrap(), "application/json");
    assert_eq!(r.json(), json!({ "error": FIVE_COMPUTERS }));
    assert_eq!(names_of(&h, ALICE).await.len(), 5, "nothing was added");

    // The limit is per person.
    assert_eq!(h.register(BOB, &ed25519()).await.status, StatusCode::OK);

    // Signing in again on a computer she already has is not a sixth.
    let ids: Vec<String> = names_of(&h, ALICE).await.into_iter().map(|d| d.0).collect();
    let r = h.reregister(ALICE, &ids[0], &ed25519()).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(r.json()["device_id"], ids[0].as_str());

    // Removing one makes room.
    assert!(h.app.revoke(ALICE, &ids[1]).await.unwrap());
    let r = h.register(ALICE, &ed25519()).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
    assert_eq!(names_of(&h, ALICE).await.len(), 5);
}

#[tokio::test]
async fn name_is_trimmed_and_capped() {
    let h = harness().await;
    let long_with_space_at_the_cut = format!("{} tail", "b".repeat(63));
    let cases: Vec<(String, String)> = vec![
        ("  Work Mac  ".into(), "Work Mac".into()),
        ("Home\u{7}\nMac\t\u{0}".into(), "HomeMac".into()),
        ("a".repeat(100), "a".repeat(64)),
        // Characters, not bytes: 70 two-byte letters are cut to 64 letters.
        ("é".repeat(70), "é".repeat(64)),
        // A cut that lands after a space leaves no trailing space.
        (long_with_space_at_the_cut, "b".repeat(63)),
        ("a".repeat(64), "a".repeat(64)),
    ];
    for (i, (sent, stored)) in cases.iter().enumerate() {
        // A different person each time, so the five-computer limit is not
        // what is being tried.
        let sub = format!("person-{i}");
        let r = h.register_with(&sub, &ed25519(), Some(sent), None).await;
        assert_eq!(r.status, StatusCode::OK, "{sent:?}: {}", r.body);
        let id = r.json()["device_id"].as_str().unwrap().to_string();
        let name = h.store.device(&id).await.unwrap().unwrap().name;
        assert_eq!(&name, stored, "sent {sent:?}");
        assert!(name.chars().count() <= 64);
    }

    // A name that is nothing once cleaned is a request she can fix, and
    // nothing is registered.
    for blank in ["", "   ", "\u{7}\n"] {
        let r = h
            .register_with("person-blank", &ed25519(), Some(blank), None)
            .await;
        assert_eq!(r.status, StatusCode::BAD_REQUEST, "{blank:?}");
        let said = r.json()["error"].as_str().unwrap().to_string();
        assert!(said.contains("name") && said.contains("64"), "{said}");
    }
    assert!(names_of(&h, "person-blank").await.is_empty());

    // The same cleaning when a name comes with a re-login.
    let (device, key) = h.new_device("person-rename").await;
    let body = json!({"public_key": b64(key.public_key().as_ref()),
                      "name": "  New\u{7} name ", "device_id": device, "rename": true});
    let r = h.register_body("person-rename", &body.to_string()).await;
    assert_eq!(r.status, StatusCode::OK);
    assert_eq!(
        names_of(&h, "person-rename").await,
        [(device, "New name".to_string())]
    );
}

/// What the relay says to a connector whose hello names `device`, signed with
/// `key`, under `who`'s token.
async fn reject_for(h: &Harness, who: &str, device: &str, key: &Ed25519KeyPair) -> String {
    reject_for_at(h, who, device, key, now_secs()).await
}

/// The same, with the hello stamped `ts`.
async fn reject_for_at(
    h: &Harness,
    who: &str,
    device: &str,
    key: &Ed25519KeyPair,
    ts: u64,
) -> String {
    let token = h.connector_token(who);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(device, key, &token, ts, vec![])))
        .await
        .unwrap();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => reason,
        other => panic!("expected reject, got {other:?}"),
    }
}

#[tokio::test]
async fn revoke_closes_live_link() {
    let h = Arc::new(harness().await);
    let (device, key) = h.new_device(ALICE).await;
    let (other, other_key) = h.new_device(ALICE).await;
    let mut fake = h.connect(ALICE, &device, &key, vec![tool("t")]).await;
    let other_fake = h.connect(ALICE, &other, &other_key, vec![tool("t")]).await;
    let s = h.session(&device, ALICE).await;
    let pending = spawn_rpc(&h, &device, ALICE, &s, call_body(json!(1), "t", json!({})));
    fake.next_call().await;

    // Someone else cannot remove it, and removing twice is not an error.
    assert!(!h.app.revoke(BOB, &device).await.unwrap());
    assert!(h.store.device(&device).await.unwrap().is_some());
    assert!(!fake.is_closed.load(Ordering::SeqCst));

    assert!(h.app.revoke(ALICE, &device).await.unwrap());
    assert!(!h.app.revoke(ALICE, &device).await.unwrap());

    // The call in flight fails with the plain words, the link closes.
    let r = within(pending).await.unwrap();
    assert_eq!(
        error_text(&r),
        "This computer was removed from your account."
    );
    fake.wait_closed().await;
    assert!(h.app.registry.tools(&device).is_none());

    // The removed computer, signing its hello with its own key, is told what
    // happened and what to do.
    let told = reject_for(&h, ALICE, &device, &key).await;
    assert_eq!(told, REMOVED_DEVICE);
    assert!(
        told.contains("removed") && told.contains("vrelay login"),
        "{told}"
    );

    // Anyone else asking about that id gets exactly what a device that never
    // existed gets: a bad signature, or another person holding Alice's real
    // key (and so signing correctly) under their own token.
    let never = "00000000-0000-4000-8000-000000000000";
    let unknown = reject_for(&h, ALICE, never, &ed25519()).await;
    assert_ne!(unknown, told);
    assert!(unknown.contains("vrelay login"), "{unknown}");
    assert_eq!(
        reject_for(&h, ALICE, &device, &ed25519()).await,
        unknown,
        "a bad signature does not learn it was removed"
    );
    assert_eq!(
        reject_for(&h, BOB, &device, &key).await,
        unknown,
        "someone else's removed device looks like one that never existed"
    );

    // Her AI app's URL for it is gone too, session or not.
    let r = h
        .rpc(
            &device,
            ALICE,
            Some(&s),
            json!({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
        )
        .await;
    assert_eq!(r.status, StatusCode::NOT_FOUND);

    // Her other computer never noticed.
    assert!(!other_fake.is_closed.load(Ordering::SeqCst));
    assert!(h.app.registry.tools(&other).is_some());
}

/// Task 8 review: the word "removed" is for the computer itself, now. A hello
/// signed with a removed computer's key but stamped far from the relay's clock
/// is a replay (or a clock that is wrong), and is answered like any unknown
/// computer, exactly as a hello for a computer that is still registered would
/// be refused for its timestamp.
#[tokio::test]
async fn removed_is_not_told_to_a_stale_hello() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    assert!(h.app.revoke(ALICE, &device).await.unwrap());

    let now = now_secs();
    let fresh = reject_for_at(&h, ALICE, &device, &key, now).await;
    assert_eq!(fresh, REMOVED_DEVICE);

    let never = "00000000-0000-4000-8000-000000000000";
    let unknown = reject_for(&h, ALICE, never, &ed25519()).await;
    assert_eq!(unknown, UNKNOWN_DEVICE);
    let skew = h.app.timing.max_clock_skew_secs;
    for (label, ts) in [
        ("an hour old", now - 3600),
        ("an hour ahead", now + 3600),
        ("just past the limit", now - skew - 5),
    ] {
        assert_eq!(
            reject_for_at(&h, ALICE, &device, &key, ts).await,
            unknown,
            "a correctly signed hello that is {label} must not learn it was removed"
        );
    }
    // Just inside the limit still counts as now.
    assert_eq!(
        reject_for_at(&h, ALICE, &device, &key, now - skew + 5).await,
        REMOVED_DEVICE
    );
}

/// A `/connect` that read the device before it was removed must not register
/// after it (the same gap `reregister_during_hello_gap_ends_old_key_connection`
/// covers for a new key).
#[tokio::test]
async fn connect_racing_a_revoke_cannot_register() {
    let h = harness().await;
    let (device, key) = h.new_device(ALICE).await;
    let (reached, release) = (
        Arc::new(tokio::sync::Notify::new()),
        Arc::new(tokio::sync::Notify::new()),
    );
    *h.app.after_hello.lock().unwrap() = Some((reached.clone(), release.clone()));
    let token = h.connector_token(ALICE);
    let mut ws = h.ws(&token).await.unwrap();
    ws.send(Message::Text(hello(
        &device,
        &key,
        &token,
        now_secs(),
        vec![tool("a")],
    )))
    .await
    .unwrap();
    within(reached.notified()).await;
    *h.app.after_hello.lock().unwrap() = None;
    // Removed in the gap: there is no link to close yet.
    assert!(h.app.revoke(ALICE, &device).await.unwrap());
    release.notify_one();
    match next_frame(&mut ws).await {
        Some(ToConnector::Reject { reason }) => {
            assert_eq!(reason, REMOVED_DEVICE)
        }
        other => panic!("expected reject, got {other:?}"),
    }
    assert!(next_frame(&mut ws).await.is_none(), "closed after reject");
    assert!(h.app.registry.tools(&device).is_none(), "never registered");
}

#[tokio::test]
async fn token_without_role_is_refused() {
    let h = harness().await;
    let (device, _) = h.new_device(ALICE).await;
    let uninvited =
        |client: &str| mint_with_role(&h.rsa, client, ALICE, Some(now_secs() + 600), None);
    let other_role = |client: &str| {
        mint_with_role(
            &h.rsa,
            client,
            ALICE,
            Some(now_secs() + 600),
            Some("someone-else"),
        )
    };

    for (label, token) in [
        ("no role", uninvited(CONNECTOR_CLIENT)),
        ("another role", other_role(CONNECTOR_CLIENT)),
    ] {
        let r = h
            .send(
                "POST",
                "/devices",
                &[("authorization", format!("Bearer {token}"))],
                &json!({"public_key": b64(&[1u8; 32])}).to_string(),
            )
            .await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "{label}: {}", r.body);
        let challenge = r.header("www-authenticate").unwrap();
        assert!(challenge.contains("insufficient_scope"), "{challenge}");
        assert!(challenge.contains("relay-user"), "{challenge}");
        assert!(!challenge.contains("resource_metadata"), "{challenge}");
    }
    assert_eq!(names_of(&h, ALICE).await.len(), 1, "nothing was registered");

    // On the AI app's side too.
    for token in [uninvited(MCP_CLIENT), other_role(MCP_CLIENT)] {
        let r = h
            .send(
                "POST",
                &format!("/mcp/d/{device}"),
                &[
                    ("authorization", format!("Bearer {token}")),
                    ("accept", ACCEPT.into()),
                ],
                &json!({"jsonrpc": "2.0", "id": 1, "method": "initialize"}).to_string(),
            )
            .await;
        assert_eq!(r.status, StatusCode::FORBIDDEN, "{}", r.body);
    }

    // And on the connector's socket.
    match h.ws(&uninvited(CONNECTOR_CLIENT)).await {
        Err(tokio_tungstenite::tungstenite::Error::Http(resp)) => {
            assert_eq!(resp.status(), StatusCode::FORBIDDEN)
        }
        other => panic!("expected a 403, got {:?}", other.map(|_| "a socket")),
    }

    // Each refusal is logged with its reason, and never with who it was.
    let logs = h.logs();
    for route in ["devices", "mcp", "connect"] {
        assert!(
            logs.lines().any(|l| l.contains("auth_refused")
                && l.contains(&format!("\"route\":\"{route}\""))
                && l.contains("\"code\":\"role_missing\"")),
            "{route}: {logs}"
        );
    }
    assert!(!logs.contains(ALICE), "{logs}");

    // A person who holds the role is let in with no list naming them.
    let key = ed25519();
    let r = h.register("a-person-nobody-listed", &key).await;
    assert_eq!(r.status, StatusCode::OK, "{}", r.body);
}

#[tokio::test]
async fn owned_device_is_the_one_ownership_check() {
    let h = harness().await;
    let (mine, _) = h.new_device(ALICE).await;
    let (bobs, _) = h.new_device(BOB).await;
    let own = h.app.owned_device(ALICE, &mine).await.unwrap();
    assert_eq!(own.map(|d| d.device_id), Some(mine.clone()));
    assert_eq!(h.app.owned_device(ALICE, &bobs).await, Ok(None));
    assert_eq!(h.app.owned_device(ALICE, "no-such-device").await, Ok(None));
    assert!(h.app.revoke(ALICE, &mine).await.unwrap());
    assert_eq!(h.app.owned_device(ALICE, &mine).await, Ok(None));
    h.store.fail_with(Some(StoreError::Unavailable));
    assert_eq!(
        h.app.owned_device(ALICE, &bobs).await,
        Err(StoreError::Unavailable)
    );
}

/// Every route that names a device answers for someone else's exactly as it
/// does for one that does not exist: status, body and headers.
#[tokio::test]
async fn someone_elses_device_looks_like_a_missing_one() {
    let h = harness().await;
    let (bobs, bobs_key) = h.new_device(BOB).await;
    let _bob_fake = h.connect(BOB, &bobs, &bobs_key, vec![tool("t")]).await;
    let missing = "00000000-0000-4000-8000-000000000000";

    for body in [
        json!({"jsonrpc": "2.0", "id": 1, "method": "initialize",
               "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                          "clientInfo": {"name": "test", "version": "0"}}}),
        json!({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}),
        call_body(json!(3), "t", json!({})),
    ] {
        let theirs = h.rpc(&bobs, ALICE, None, body.clone()).await;
        let nobodys = h.rpc(missing, ALICE, None, body.clone()).await;
        assert_eq!(theirs.status, StatusCode::NOT_FOUND, "{body}");
        assert_eq!(fingerprint(&theirs), fingerprint(&nobodys), "{body}");
    }

    // The connector's socket: the same refusal.
    let token = h.connector_token(ALICE);
    let mut reasons = Vec::new();
    for (id, key) in [(bobs.as_str(), &bobs_key), (missing, &ed25519())] {
        let mut ws = h.ws(&token).await.unwrap();
        ws.send(Message::Text(hello(id, key, &token, now_secs(), vec![])))
            .await
            .unwrap();
        match next_frame(&mut ws).await {
            Some(ToConnector::Reject { reason }) => reasons.push(reason),
            other => panic!("expected reject, got {other:?}"),
        }
    }
    assert_eq!(reasons[0], reasons[1]);
}
