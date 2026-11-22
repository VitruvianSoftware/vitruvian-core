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

//! What the tests that run the whole relay over HTTP share: a throwaway key
//! the relay trusts, tokens signed with it, a stand-in for the identity
//! service (its key set and its token endpoint), one HTTP request on a new
//! connection, a fake connector on a real WebSocket, and a relay on a loopback
//! port with its store in the itest Postgres.

#![allow(dead_code)]

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::SocketAddr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use bytes::Bytes;
use futures_util::{SinkExt, StreamExt};
use http_body_util::{BodyExt, Full};
use hyper_util::rt::TokioIo;
use ring::rand::SystemRandom;
use ring::signature::{Ed25519KeyPair, KeyPair, RsaKeyPair, RSA_PKCS1_SHA256};
use serde_json::{json, Value};
use tokio::net::{TcpListener, TcpStream};
use tokio::sync::mpsc;
use tokio_tungstenite::tungstenite::client::IntoClientRequest;
use tokio_tungstenite::tungstenite::Message;
use vitruvian_mcp_auth::{verifier_requiring_role, VerifierConfig};
use vitruvian_relay::config::Settings;
use vitruvian_relay::http::{serve, App, Timing};
use vitruvian_relay::store::PgStore;
use vitruvian_relay::LogSink;
use vitruvian_relay_protocol::{
    decode_to_connector, encode, hello_message, Hello, ToConnector, ToRelay, ToolDef, PROTOCOL,
};

pub const PUBLIC_URL: &str = "https://relay.example.test";
pub const ISSUER: &str = "https://auth.example.test";
pub const PROJECT_ID: &str = "123456789";
pub const MCP_CLIENT: &str = "claude-client";
pub const CONNECTOR_CLIENT: &str = "connector-client";
pub const DASHBOARD_CLIENT: &str = "dashboard-client";
pub const ALICE: &str = "alice";
pub const BOB: &str = "bob";
/// The Zitadel role that lets a person in.
pub const ROLE: &str = "relay-user";

/// The longest any one step may take before a test gives up. Only a failing
/// test waits this long.
pub const WAIT: Duration = Duration::from_secs(20);

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

pub fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap()
        .as_secs()
}

pub fn b64url(bytes: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes)
}

pub fn b64(bytes: &[u8]) -> String {
    base64::engine::general_purpose::STANDARD.encode(bytes)
}

pub fn rsa_key() -> Arc<RsaKeyPair> {
    let der = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(TEST_RSA_KEY)
        .unwrap();
    Arc::new(RsaKeyPair::from_pkcs8(&der).unwrap())
}

pub fn jwks(pair: &RsaKeyPair) -> Value {
    let public: ring::signature::RsaPublicKeyComponents<Vec<u8>> = pair.public().into();
    json!({"keys": [{
        "kty": "RSA", "kid": "k1", "alg": "RS256", "use": "sig",
        "n": b64url(&public.n), "e": b64url(&public.e),
    }]})
}

/// A token for `sub` (who holds the `relay-user` role), issued to `client_id`,
/// good for ten minutes.
pub fn mint(pair: &RsaKeyPair, client_id: &str, sub: &str) -> String {
    let header = b64url(json!({"alg": "RS256", "kid": "k1"}).to_string().as_bytes());
    let claims = json!({
        "iss": ISSUER, "aud": [PROJECT_ID], "sub": sub, "client_id": client_id,
        "iat": now_secs(), "exp": now_secs() + 600,
        format!("urn:zitadel:iam:org:project:{PROJECT_ID}:roles"):
            { ROLE: { "org-1": "example.test" } },
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
pub fn start_jwks_server(body: String) -> String {
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

/// A stand-in for the identity service's token endpoint: answers every
/// sign-in code exchange with the access token the test last gave it.
pub struct TokenServer {
    pub url: String,
    answer: Arc<Mutex<String>>,
}

impl TokenServer {
    pub fn give_token(&self, access_token: &str) {
        *self.answer.lock().unwrap() =
            json!({"access_token": access_token, "token_type": "Bearer", "expires_in": 3600})
                .to_string();
    }
}

pub fn start_token_server() -> TokenServer {
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let url = format!("http://{}/oauth/v2/token", listener.local_addr().unwrap());
    let answer = Arc::new(Mutex::new(json!({"error": "invalid_grant"}).to_string()));
    let reply = answer.clone();
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
            let mut form = vec![0u8; length];
            std::io::Read::read_exact(&mut reader, &mut form).unwrap();
            let text = reply.lock().unwrap().clone();
            let status = if text.contains("access_token") {
                200
            } else {
                400
            };
            let _ = write!(
                stream,
                "HTTP/1.1 {status} X\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{text}",
                text.len()
            );
        }
    });
    TokenServer { url, answer }
}

pub struct Reply {
    pub status: u16,
    pub headers: http::HeaderMap,
    pub body: String,
}

impl Reply {
    pub fn json(&self) -> Value {
        serde_json::from_str(&self.body).unwrap_or_else(|_| panic!("not JSON: {}", self.body))
    }

    pub fn header(&self, name: &str) -> Option<String> {
        self.headers
            .get(name)
            .map(|v| v.to_str().unwrap().to_string())
    }

    /// The MCP session id a reply handed out.
    pub fn session(&self) -> Option<String> {
        self.header("mcp-session-id")
    }
}

/// One HTTP request on a new connection.
pub async fn send(
    addr: SocketAddr,
    method: &str,
    path: &str,
    headers: &[(&str, String)],
    body: &str,
) -> Reply {
    let stream = TcpStream::connect(addr).await.unwrap();
    let (mut sender, conn) = hyper::client::conn::http1::handshake(TokioIo::new(stream))
        .await
        .unwrap();
    let conn = tokio::spawn(conn);
    let mut req = http::Request::builder()
        .method(method)
        .uri(path)
        .header("host", "relay.example.test");
    for (k, v) in headers {
        req = req.header(*k, v);
    }
    let resp = sender
        .send_request(req.body(Full::new(Bytes::from(body.to_string()))).unwrap())
        .await
        .unwrap();
    let status = resp.status().as_u16();
    let headers = resp.headers().clone();
    let body = resp.into_body().collect().await.unwrap().to_bytes();
    conn.abort();
    Reply {
        status,
        headers,
        body: String::from_utf8_lossy(&body).into_owned(),
    }
}

/// A JSON `POST` with a bearer token, as an AI app or the connector sends it.
pub async fn post(
    addr: SocketAddr,
    path: &str,
    token: &str,
    session: Option<&str>,
    body: Value,
) -> Reply {
    let mut headers = vec![
        ("authorization", format!("Bearer {token}")),
        ("content-type", "application/json".to_string()),
        ("accept", "application/json, text/event-stream".to_string()),
    ];
    if let Some(s) = session {
        headers.push(("mcp-session-id", s.to_string()));
    }
    send(addr, "POST", path, &headers, &body.to_string()).await
}

pub struct Relay {
    pub addr: SocketAddr,
    pub app: Arc<App>,
    pub rsa: Arc<RsaKeyPair>,
    pub logs: Arc<Mutex<Vec<String>>>,
    pub tokens: TokenServer,
    pub server: tokio::task::JoinHandle<()>,
}

/// A relay whose store is Postgres at `database_url`.
pub async fn start_relay(database_url: &str) -> Relay {
    start_relay_with(database_url, Timing::default()).await
}

pub async fn start_relay_with(database_url: &str, timing: Timing) -> Relay {
    let rsa = rsa_key();
    let jwks_uri = start_jwks_server(jwks(&rsa).to_string());
    let tokens = start_token_server();
    let env: HashMap<&str, String> = [
        ("PUBLIC_URL", PUBLIC_URL.to_string()),
        ("ISSUER", ISSUER.to_string()),
        ("PROJECT_ID", PROJECT_ID.to_string()),
        ("MCP_CLIENT_IDS", MCP_CLIENT.to_string()),
        ("CONNECTOR_CLIENT_ID", CONNECTOR_CLIENT.to_string()),
        ("DASHBOARD_CLIENT_ID", DASHBOARD_CLIENT.to_string()),
        ("MCP_CLIENT_LABELS", format!("Claude={MCP_CLIENT}")),
        ("DATABASE_URL", database_url.to_string()),
        ("JWKS_URI", jwks_uri.clone()),
        ("TOKEN_URI", tokens.url.clone()),
    ]
    .into_iter()
    .collect();
    let settings = Settings::from_lookup(|k| env.get(k).cloned()).unwrap();
    let required_role = settings.required_role.clone();
    let verifier_for = |ids: Vec<String>| {
        verifier_requiring_role(
            VerifierConfig {
                issuer: ISSUER.into(),
                project_id: PROJECT_ID.into(),
                allowed_client_ids: ids,
                allowed_subjects: Vec::new(),
                jwks_uri: Some(jwks_uri.clone()),
                user_agent: "vitruvian-relay-itest".into(),
            },
            required_role.clone(),
        )
        .unwrap()
    };
    let logs = Arc::new(Mutex::new(Vec::new()));
    let sink_logs = logs.clone();
    let sink: LogSink = Arc::new(move |line| sink_logs.lock().unwrap().push(line.to_string()));
    let store = PgStore::connect(settings.database_url.expose(), None, sink.clone())
        .await
        .expect("the relay's store connects");
    let app = App::new(
        settings,
        verifier_for(vec![MCP_CLIENT.into()]),
        verifier_for(vec![CONNECTOR_CLIENT.into()]),
        verifier_for(vec![DASHBOARD_CLIENT.into()]),
        Arc::new(store),
        timing,
        sink,
    );
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    let server = tokio::spawn(serve(listener, app.clone()));
    Relay {
        addr,
        app,
        rsa,
        logs,
        tokens,
        server,
    }
}

impl Relay {
    pub fn logs(&self) -> String {
        self.logs.lock().unwrap().join("\n")
    }

    pub fn mcp_token(&self, sub: &str) -> String {
        mint(&self.rsa, MCP_CLIENT, sub)
    }

    pub fn connector_token(&self, sub: &str) -> String {
        mint(&self.rsa, CONNECTOR_CLIENT, sub)
    }

    pub fn dashboard_token(&self, sub: &str) -> String {
        mint(&self.rsa, DASHBOARD_CLIENT, sub)
    }

    /// `POST /devices` as the connector does, with whatever body the test
    /// chooses.
    pub async fn register_body(&self, sub: &str, body: Value) -> Reply {
        post(
            self.addr,
            "/devices",
            &self.connector_token(sub),
            None,
            body,
        )
        .await
    }

    /// Registers a computer for `sub`; its id.
    pub async fn register(&self, sub: &str, key: &Ed25519KeyPair, name: &str) -> String {
        let r = self
            .register_body(
                sub,
                json!({"public_key": b64(key.public_key().as_ref()), "name": name}),
            )
            .await;
        assert_eq!(r.status, 200, "{}", r.body);
        r.json()["device_id"].as_str().unwrap().to_string()
    }

    /// An AI app's request for `sub` on `device`'s endpoint.
    pub async fn rpc(&self, sub: &str, device: &str, session: Option<&str>, body: Value) -> Reply {
        post(
            self.addr,
            &format!("/mcp/d/{device}"),
            &self.mcp_token(sub),
            session,
            body,
        )
        .await
    }

    /// `initialize` as `sub` on `device`, and the session id it handed out.
    pub async fn session(&self, sub: &str, device: &str) -> String {
        let r = self.rpc(sub, device, None, initialize_body()).await;
        assert_eq!(r.status, 200, "{}", r.body);
        r.session().expect("a session id")
    }
}

pub fn initialize_body() -> Value {
    json!({"jsonrpc": "2.0", "id": 0, "method": "initialize",
           "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                      "clientInfo": {"name": "itest", "version": "0"}}})
}

pub fn call_body(id: u64, tool: &str, args: Value) -> Value {
    json!({"jsonrpc": "2.0", "id": id, "method": "tools/call",
           "params": {"name": tool, "arguments": args}})
}

pub fn ed25519() -> Ed25519KeyPair {
    let doc = Ed25519KeyPair::generate_pkcs8(&SystemRandom::new()).unwrap();
    Ed25519KeyPair::from_pkcs8(doc.as_ref()).unwrap()
}

pub fn tool(name: &str) -> ToolDef {
    ToolDef {
        name: name.into(),
        description: format!("the {name} tool"),
        input_schema: json!({"type": "object"}),
    }
}

// ------------------------------------------------------------ a connector

type Ws = tokio_tungstenite::WebSocketStream<TcpStream>;

fn token_hash(token: &str) -> String {
    vitruvian_relay::hex(ring::digest::digest(&ring::digest::SHA256, token.as_bytes()).as_ref())
}

/// What a connector sends first: signed with `key`, for `token`.
pub fn hello(device: &str, key: &Ed25519KeyPair, token: &str, tools: Vec<ToolDef>) -> String {
    let ts = now_secs();
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

/// The next frame the relay sends, `None` once it has closed.
pub async fn next_frame(ws: &mut Ws) -> Option<ToConnector> {
    tokio::time::timeout(WAIT, async {
        loop {
            match ws.next().await? {
                Ok(Message::Text(t)) => return Some(decode_to_connector(&t).unwrap()),
                Ok(Message::Close(_)) | Err(_) => return None,
                Ok(_) => {}
            }
        }
    })
    .await
    .expect("the relay sent nothing in time")
}

impl Relay {
    /// Opens `/connect` with `token` and sends `hello_text` as the first
    /// frame; what the relay answers.
    pub async fn say_hello(&self, token: &str, hello_text: String) -> Option<ToConnector> {
        let stream = TcpStream::connect(self.addr).await.unwrap();
        let mut req = format!("ws://{}/connect", self.addr)
            .into_client_request()
            .unwrap();
        req.headers_mut().insert(
            http::header::AUTHORIZATION,
            format!("Bearer {token}").parse().unwrap(),
        );
        let (mut ws, _) = tokio_tungstenite::client_async(req, stream)
            .await
            .expect("the upgrade to /connect");
        ws.send(Message::Text(hello_text)).await.unwrap();
        next_frame(&mut ws).await
    }

    /// Connects `device` as its own computer and waits for the welcome.
    pub async fn connect(
        &self,
        sub: &str,
        device: &str,
        key: &Ed25519KeyPair,
        tools: Vec<ToolDef>,
    ) -> FakeDevice {
        let token = self.connector_token(sub);
        let stream = TcpStream::connect(self.addr).await.unwrap();
        let mut req = format!("ws://{}/connect", self.addr)
            .into_client_request()
            .unwrap();
        req.headers_mut().insert(
            http::header::AUTHORIZATION,
            format!("Bearer {token}").parse().unwrap(),
        );
        let (mut ws, _) = tokio_tungstenite::client_async(req, stream)
            .await
            .expect("the upgrade to /connect");
        ws.send(Message::Text(hello(device, key, &token, tools)))
            .await
            .unwrap();
        match next_frame(&mut ws).await {
            Some(ToConnector::Welcome { device_id }) => assert_eq!(device_id, device),
            other => panic!("expected welcome, got {other:?}"),
        }
        FakeDevice::spawn(ws)
    }
}

/// A connector on a real WebSocket: answers pings and acknowledges calls,
/// hands the calls to the test, and sends what the test gives it.
pub struct FakeDevice {
    calls: mpsc::UnboundedReceiver<vitruvian_relay_protocol::Call>,
    out: mpsc::UnboundedSender<ToRelay>,
    closed: Arc<AtomicBool>,
}

impl FakeDevice {
    fn spawn(ws: Ws) -> Self {
        let (calls_tx, calls) = mpsc::unbounded_channel();
        let (out, mut out_rx) = mpsc::unbounded_channel::<ToRelay>();
        let closed = Arc::new(AtomicBool::new(false));
        let closed2 = closed.clone();
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
                                let pong = encode(&ToRelay::Pong { n }).unwrap();
                                let _ = sink.send(Message::Text(pong)).await;
                            }
                            ToConnector::Call(c) => {
                                let ack = encode(&ToRelay::Ack { call_id: c.call_id.clone() }).unwrap();
                                let _ = sink.send(Message::Text(ack)).await;
                                let _ = calls_tx.send(c);
                            }
                            _ => {}
                        },
                        Some(Ok(Message::Close(_))) | Some(Err(_)) | None => break,
                        Some(Ok(_)) => {}
                    },
                }
            }
            closed2.store(true, Ordering::SeqCst);
        });
        FakeDevice { calls, out, closed }
    }

    /// The next call the relay sends this computer.
    pub async fn next_call(&mut self) -> vitruvian_relay_protocol::Call {
        tokio::time::timeout(WAIT, self.calls.recv())
            .await
            .expect("no call reached the computer in time")
            .expect("the computer's link closed")
    }

    /// True if no call reaches this computer within `for_`.
    pub async fn gets_no_call(&mut self, for_: Duration) -> bool {
        tokio::time::timeout(for_, self.calls.recv()).await.is_err()
    }

    pub fn send(&self, f: ToRelay) {
        let _ = self.out.send(f);
    }

    /// An approval dialog opened for this call.
    pub fn pending(&self, call_id: &str) {
        self.send(ToRelay::Pending {
            call_id: call_id.into(),
        });
    }

    pub fn reply(&self, call_id: &str, text: &str) {
        self.send(ToRelay::Result(vitruvian_relay_protocol::CallResult {
            call_id: call_id.into(),
            content: json!([{"type": "text", "text": text}]),
            is_error: false,
            truncated: false,
        }));
    }

    pub fn is_closed(&self) -> bool {
        self.closed.load(Ordering::SeqCst)
    }
}
