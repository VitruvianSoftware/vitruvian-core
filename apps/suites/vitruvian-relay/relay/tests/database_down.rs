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

//! The database going away and coming back, with the whole relay over HTTP and
//! a real PostgreSQL behind it (a `service_test`, `:database_down_test`).
//!
//! rules_itest cannot stop the Postgres service mid-test, so a small TCP proxy
//! (`pg_support::Proxy`) sits between the relay's store and the database.
//! Cutting the proxy is the database going down; opening it again is the
//! database coming back.

mod pg_support;

use std::collections::HashMap;
use std::io::{BufRead, BufReader, Write};
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::Engine as _;
use bytes::Bytes;
use http_body_util::{BodyExt, Full};
use hyper_util::rt::TokioIo;
use pg_support::{fresh_database, postgres_port, Mode, Proxy};
use ring::rand::SystemRandom;
use ring::signature::{RsaKeyPair, RSA_PKCS1_SHA256};
use serde_json::{json, Value};
use tokio::net::{TcpListener, TcpStream};
use vitruvian_mcp_auth::{verifier, VerifierConfig};
use vitruvian_relay::config::Settings;
use vitruvian_relay::http::{serve, App, Timing};
use vitruvian_relay::store::PgStore;
use vitruvian_relay::LogSink;

const PUBLIC_URL: &str = "https://relay.example.test";
const ISSUER: &str = "https://auth.example.test";
const PROJECT_ID: &str = "123456789";
const MCP_CLIENT: &str = "claude-client";
const CONNECTOR_CLIENT: &str = "connector-client";
const ALICE: &str = "alice";

/// What a person is told (spec: the store being down).
const MESSAGE: &str = "The relay is having trouble right now; try again in a minute.";

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

fn mint(pair: &RsaKeyPair, client_id: &str) -> String {
    let header = b64url(json!({"alg": "RS256", "kid": "k1"}).to_string().as_bytes());
    let claims = json!({
        "iss": ISSUER, "aud": [PROJECT_ID], "sub": ALICE, "client_id": client_id,
        "iat": now_secs(), "exp": now_secs() + 600,
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

struct Relay {
    addr: SocketAddr,
    rsa: Arc<RsaKeyPair>,
    logs: Arc<Mutex<Vec<String>>>,
}

/// A relay whose store is Postgres at `database_url`.
async fn start_relay(database_url: &str) -> Relay {
    let rsa = rsa_key();
    let jwks_uri = start_jwks_server(jwks(&rsa).to_string());
    let env: HashMap<&str, String> = [
        ("PUBLIC_URL", PUBLIC_URL.to_string()),
        ("ISSUER", ISSUER.to_string()),
        ("PROJECT_ID", PROJECT_ID.to_string()),
        ("MCP_CLIENT_IDS", MCP_CLIENT.to_string()),
        ("CONNECTOR_CLIENT_ID", CONNECTOR_CLIENT.to_string()),
        ("ALLOWED_SUBJECTS", ALICE.to_string()),
        ("DATABASE_URL", database_url.to_string()),
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
            user_agent: "vitruvian-relay-database-down".into(),
        })
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
        Arc::new(store),
        Timing::default(),
        sink,
    );
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let addr = listener.local_addr().unwrap();
    tokio::spawn(serve(listener, app));
    Relay { addr, rsa, logs }
}

impl Relay {
    fn logs(&self) -> String {
        self.logs.lock().unwrap().join("\n")
    }

    /// `POST /devices` as the connector does.
    async fn register(&self, key_byte: u8) -> Reply {
        let token = mint(&self.rsa, CONNECTOR_CLIENT);
        let key = base64::engine::general_purpose::STANDARD.encode([key_byte; 32]);
        post(
            self.addr,
            "/devices",
            &token,
            None,
            json!({"public_key": key}),
        )
        .await
    }

    /// An AI app's session on `device`: its path and session id.
    async fn open_session(&self, device: &str) -> (String, String) {
        let path = format!("/mcp/d/{device}");
        let r = post(
            self.addr,
            &path,
            &mint(&self.rsa, MCP_CLIENT),
            None,
            json!({"jsonrpc": "2.0", "id": 0, "method": "initialize",
                   "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                              "clientInfo": {"name": "down", "version": "0"}}}),
        )
        .await;
        assert_eq!(r.status, 200, "{}", r.body);
        (path, r.session.expect("a session id"))
    }

    async fn tools_call(&self, path: &str, session: &str, id: u64) -> Reply {
        post(
            self.addr,
            path,
            &mint(&self.rsa, MCP_CLIENT),
            Some(session),
            json!({"jsonrpc": "2.0", "id": id, "method": "tools/call",
                   "params": {"name": "read_file", "arguments": {"path": "/top/secret"}}}),
        )
        .await
    }
}

fn text_of(r: &Reply) -> String {
    r.json()["result"]["content"][0]["text"]
        .as_str()
        .unwrap_or_default()
        .to_string()
}

/// With the database up and a device registered, a call reaches the device
/// lookup and answers (no computer is connected, so it says so).
async fn assert_calls_work(relay: &Relay, path: &str, session: &str, id: u64) {
    let r = relay.tools_call(path, session, id).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(text_of(&r), "Your computer is offline.", "{}", r.body);
}

/// How long the relay may take to say the database is down: the store's own
/// limit is 5 s (connect and query), and a cut road answers at once.
const WITHIN: Duration = Duration::from_secs(5);

#[tokio::test(flavor = "multi_thread")]
async fn database_down_fails_clearly_then_recovers() {
    let db = fresh_database().await;
    let proxy = Proxy::start(postgres_port()).await;
    let relay = start_relay(&db.url_at(proxy.port)).await;

    let r = relay.register(1).await;
    assert_eq!(r.status, 200, "{}", r.body);
    let device = r.json()["device_id"].as_str().unwrap().to_string();
    let (path, session) = relay.open_session(&device).await;
    assert_calls_work(&relay, &path, &session, 1).await;

    // The database stops.
    proxy.set(Mode::Down);

    let started = Instant::now();
    let r = relay.tools_call(&path, &session, 2).await;
    assert!(started.elapsed() < WITHIN, "took {:?}", started.elapsed());
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(r.json()["result"]["isError"], true);
    assert_eq!(text_of(&r), MESSAGE);

    let started = Instant::now();
    let r = relay.register(2).await;
    assert!(started.elapsed() < WITHIN, "took {:?}", started.elapsed());
    assert_eq!(r.status, 503, "{}", r.body);
    assert_eq!(r.body, MESSAGE);

    let logs = relay.logs();
    assert!(logs.contains("\"outcome\":\"store_unavailable\""), "{logs}");
    assert!(!logs.contains("/top/secret"), "arguments reached the log");

    // The database is back: the very next call works, with the same session.
    proxy.set(Mode::Open);
    assert_calls_work(&relay, &path, &session, 3).await;
    let r = relay.register(3).await;
    assert_eq!(r.status, 200, "{}", r.body);
    assert_eq!(
        r.json()["device_id"],
        device,
        "registering again keeps the device"
    );
}

/// The road is up but nothing comes back (a database that hangs, not one that
/// is gone): the store's 5 s limit turns that into the same message.
#[tokio::test(flavor = "multi_thread")]
async fn a_silent_database_gets_the_same_message_after_the_limit() {
    let db = fresh_database().await;
    let proxy = Proxy::start(postgres_port()).await;
    let relay = start_relay(&db.url_at(proxy.port)).await;
    let r = relay.register(1).await;
    let device = r.json()["device_id"].as_str().unwrap().to_string();
    let (path, session) = relay.open_session(&device).await;

    proxy.set(Mode::Silent);
    let started = Instant::now();
    let r = relay.tools_call(&path, &session, 2).await;
    let took = started.elapsed();
    assert_eq!(text_of(&r), MESSAGE, "{}", r.body);
    // It waited for the limit rather than answering at once, and not longer
    // than it (one limit for the whole step, with a second of slack for a
    // loaded machine).
    assert!(
        took >= Duration::from_secs(4) && took < Duration::from_secs(6),
        "took {took:?}"
    );

    proxy.set(Mode::Open);
    assert_calls_work(&relay, &path, &session, 3).await;
}

/// The 5 s limit covers getting a connection AND the query together. Here each
/// answer from the database is 3 s late, so getting a connection (the pool
/// checks an idle one first) takes about 3 s and the query another 3 s: each is
/// under 5 s alone, together they are not. The person must still hear within
/// one limit, not after two.
#[tokio::test(flavor = "multi_thread")]
async fn a_slow_database_is_given_one_limit_in_all_not_one_per_step() {
    let db = fresh_database().await;
    let proxy = Proxy::start(postgres_port()).await;
    let relay = start_relay(&db.url_at(proxy.port)).await;
    let r = relay.register(1).await;
    let device = r.json()["device_id"].as_str().unwrap().to_string();
    let (path, session) = relay.open_session(&device).await;
    // Warm: the pool now holds a connection through the proxy.
    assert_calls_work(&relay, &path, &session, 1).await;

    proxy.set(Mode::Slow(Duration::from_secs(3)));
    let started = Instant::now();
    let r = relay.tools_call(&path, &session, 2).await;
    let took = started.elapsed();
    assert_eq!(text_of(&r), MESSAGE, "{}", r.body);
    assert!(
        took >= Duration::from_secs(4) && took < Duration::from_secs(6),
        "took {took:?}"
    );

    // Fast again: works.
    proxy.set(Mode::Open);
    assert_calls_work(&relay, &path, &session, 3).await;
}
