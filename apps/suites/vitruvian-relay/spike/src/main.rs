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

//! HTTP and WebSocket wiring for the relay spike. Logic lives in lib.rs.
//!
//! Routes:
//!   GET  /healthz                                   liveness (not exposed publicly)
//!   GET  /.well-known/oauth-protected-resource[/mcp]  RFC 9728 metadata
//!   POST /mcp                                       MCP over Streamable HTTP (JSON answers)
//!   GET  /connect                                   WebSocket echo + pings (connector token)
//!
//! Tokens are checked by vitruvian-slack-mcp's verifier (signature against Zitadel's
//! JWKS, issuer, expiry, audience, `client_id` pin, subject allowlist), one
//! verifier per allowed client.

use bytes::Bytes;
use futures_util::{SinkExt, StreamExt};
use http::{header, Method, Request, Response, StatusCode};
use http_body_util::{BodyExt, Full, Limited};
use hyper::body::Incoming;
use hyper::server::conn::http1;
use hyper::service::service_fn;
use hyper_util::rt::TokioIo;
use std::collections::HashMap;
use std::convert::Infallible;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use tokio::net::TcpListener;
use tokio_tungstenite::tungstenite::handshake::derive_accept_key;
use tokio_tungstenite::tungstenite::protocol::{Message, Role};
use tokio_tungstenite::WebSocketStream;
use vitruvian_relay_spike::{
    accepts_json, handle_rpc, protected_resource_metadata, unverified_client_id, www_authenticate,
    Caller, Settings, MAX_BODY_BYTES, MAX_MISSED_PONGS, PING_INTERVAL_SECS,
};
use vitruvian_slack_mcp_rs_lib::auth::{
    create_token_verifier, extract_bearer_token, StandardTokenVerifier, TokenVerifierConfig,
};

type Body = Full<Bytes>;

struct App {
    settings: Settings,
    /// client id → verifier, for `/mcp`.
    mcp: HashMap<String, Arc<StandardTokenVerifier>>,
    connector: Arc<StandardTokenVerifier>,
}

fn log(event: &str, fields: serde_json::Value) {
    let ts = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis())
        .unwrap_or(0);
    let mut line = serde_json::json!({"ts_ms": ts, "event": event});
    if let (Some(obj), Some(extra)) = (line.as_object_mut(), fields.as_object()) {
        for (k, v) in extra {
            obj.insert(k.clone(), v.clone());
        }
    }
    println!("{line}");
}

fn verifier(s: &Settings, client_id: &str) -> Result<Arc<StandardTokenVerifier>, String> {
    create_token_verifier(TokenVerifierConfig {
        issuer: s.issuer.clone(),
        project_id: s.project_id.clone(),
        allowed_subjects: s.allowed_subjects.clone(),
        allowed_client_id: client_id.to_string(),
        jwks_uri: s.jwks_uri.clone(),
        key_source: None,
        jwks_timeout_ms: None,
    })
    .map(Arc::new)
}

fn respond(status: StatusCode, content_type: &str, body: impl Into<Bytes>) -> Response<Body> {
    Response::builder()
        .status(status)
        .header(header::CONTENT_TYPE, content_type)
        .header(header::CACHE_CONTROL, "no-store")
        .body(Full::new(body.into()))
        .expect("static response parts are valid")
}

fn json_response(status: StatusCode, v: &serde_json::Value) -> Response<Body> {
    respond(status, "application/json", v.to_string())
}

fn unauthorized(app: &App, error: Option<&str>) -> Response<Body> {
    let mut r = json_response(
        StatusCode::UNAUTHORIZED,
        &serde_json::json!({"error": error.unwrap_or("unauthorized")}),
    );
    if let Ok(v) = www_authenticate(&app.settings, error).parse() {
        r.headers_mut().insert(header::WWW_AUTHENTICATE, v);
    }
    r
}

/// Verifies the bearer token with the verifier for its own client id.
/// The verifier is blocking (it may fetch JWKS), so it runs off the runtime.
async fn authenticate(
    header_value: Option<String>,
    verifiers: Vec<(String, Arc<StandardTokenVerifier>)>,
) -> Result<Caller, &'static str> {
    let token = extract_bearer_token(header_value.as_deref()).map_err(|_| "invalid_request")?;
    let cid = unverified_client_id(&token).ok_or("invalid_token")?;
    let v = verifiers
        .into_iter()
        .find(|(id, _)| *id == cid)
        .map(|(_, v)| v)
        .ok_or("invalid_token")?;
    let caller = tokio::task::spawn_blocking(move || v.verify_token(&token))
        .await
        .map_err(|_| "server_error")?
        .map_err(|e| {
            log(
                "auth_rejected",
                serde_json::json!({"client_id": cid, "reason": e.code()}),
            );
            "invalid_token"
        })?;
    Ok(Caller {
        subject: caller.subject,
        client_id: cid,
    })
}

async fn handle(app: Arc<App>, req: Request<Incoming>) -> Result<Response<Body>, Infallible> {
    let path = req.uri().path().to_string();
    let method = req.method().clone();
    let auth = req
        .headers()
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .map(String::from);

    let resp = match (method, path.as_str()) {
        (Method::GET, "/healthz") => respond(StatusCode::OK, "text/plain", "ok"),
        (Method::GET, "/.well-known/oauth-protected-resource")
        | (Method::GET, "/.well-known/oauth-protected-resource/mcp") => {
            json_response(StatusCode::OK, &protected_resource_metadata(&app.settings))
        }
        (Method::POST, "/mcp") => {
            let accept = req
                .headers()
                .get(header::ACCEPT)
                .and_then(|v| v.to_str().ok())
                .map(String::from);
            let verifiers: Vec<_> = app
                .mcp
                .iter()
                .map(|(k, v)| (k.clone(), v.clone()))
                .collect();
            match authenticate(auth, verifiers).await {
                Err(e) => unauthorized(&app, Some(e).filter(|e| *e != "invalid_request")),
                Ok(caller) if !accepts_json(accept.as_deref()) => {
                    let _ = caller;
                    respond(
                        StatusCode::NOT_ACCEPTABLE,
                        "text/plain",
                        "this server answers application/json",
                    )
                }
                Ok(caller) => match Limited::new(req.into_body(), MAX_BODY_BYTES)
                    .collect()
                    .await
                {
                    Err(_) => respond(
                        StatusCode::PAYLOAD_TOO_LARGE,
                        "text/plain",
                        "body too large",
                    ),
                    Ok(body) => {
                        let bytes = body.to_bytes();
                        let method = serde_json::from_slice::<serde_json::Value>(&bytes)
                            .ok()
                            .and_then(|v| {
                                v.get("method").and_then(|m| m.as_str()).map(String::from)
                            });
                        log(
                            "mcp",
                            serde_json::json!({"method": method, "sub": caller.subject, "client_id": caller.client_id}),
                        );
                        match handle_rpc(&bytes, &caller) {
                            Some(v) => json_response(StatusCode::OK, &v),
                            None => respond(StatusCode::ACCEPTED, "text/plain", ""),
                        }
                    }
                },
            }
        }
        // MCP's optional GET stream and session DELETE: not offered.
        (Method::GET, "/mcp") | (Method::DELETE, "/mcp") => {
            respond(StatusCode::METHOD_NOT_ALLOWED, "text/plain", "POST only")
        }
        (Method::GET, "/connect") => return Ok(upgrade(app, req, auth).await),
        _ => respond(StatusCode::NOT_FOUND, "text/plain", "not found"),
    };
    Ok(resp)
}

/// Spike C: authenticate with a connector token, upgrade to a WebSocket, then
/// echo text frames and ping every PING_INTERVAL_SECS. Logs one line when the
/// socket opens and one when it closes, with how long it lasted and why.
async fn upgrade(
    app: Arc<App>,
    mut req: Request<Incoming>,
    auth: Option<String>,
) -> Response<Body> {
    let is_ws = req
        .headers()
        .get(header::UPGRADE)
        .and_then(|v| v.to_str().ok())
        .map(|v| v.eq_ignore_ascii_case("websocket"))
        .unwrap_or(false);
    let key = req
        .headers()
        .get(header::SEC_WEBSOCKET_KEY)
        .map(|k| derive_accept_key(k.as_bytes()));
    let (true, Some(accept)) = (is_ws, key) else {
        return respond(
            StatusCode::BAD_REQUEST,
            "text/plain",
            "WebSocket upgrade required",
        );
    };
    let caller = match authenticate(
        auth,
        vec![(
            app.settings.connector_client_id.clone(),
            app.connector.clone(),
        )],
    )
    .await
    {
        Ok(c) => c,
        Err(e) => return unauthorized(&app, Some(e)),
    };

    let on_upgrade = hyper::upgrade::on(&mut req);
    tokio::spawn(async move {
        let upgraded = match on_upgrade.await {
            Ok(u) => u,
            Err(e) => {
                log(
                    "ws_upgrade_failed",
                    serde_json::json!({"error": e.to_string()}),
                );
                return;
            }
        };
        let ws = WebSocketStream::from_raw_socket(TokioIo::new(upgraded), Role::Server, None).await;
        run_socket(ws, caller).await;
    });

    Response::builder()
        .status(StatusCode::SWITCHING_PROTOCOLS)
        .header(header::UPGRADE, "websocket")
        .header(header::CONNECTION, "Upgrade")
        .header(header::SEC_WEBSOCKET_ACCEPT, accept)
        .body(Full::new(Bytes::new()))
        .expect("static response parts are valid")
}

async fn run_socket<S>(ws: WebSocketStream<S>, caller: Caller)
where
    S: tokio::io::AsyncRead + tokio::io::AsyncWrite + Unpin,
{
    let started = Instant::now();
    log("ws_open", serde_json::json!({"sub": caller.subject}));
    let (mut tx, mut rx) = ws.split();
    let mut ticker = tokio::time::interval(Duration::from_secs(PING_INTERVAL_SECS));
    ticker.tick().await; // the first tick fires at once
    let mut missed = 0u32;
    let mut frames = 0u64;
    let reason: String = loop {
        tokio::select! {
            _ = ticker.tick() => {
                if missed >= MAX_MISSED_PONGS {
                    break format!("{MAX_MISSED_PONGS} pongs missed");
                }
                missed += 1;
                let now = SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis()).unwrap_or(0);
                if let Err(e) = tx.send(Message::Ping(now.to_string().into_bytes().into())).await {
                    break format!("ping send failed: {e}");
                }
            }
            msg = rx.next() => match msg {
                None => break "client went away".to_string(),
                Some(Err(e)) => break format!("read error: {e}"),
                Some(Ok(Message::Pong(_))) => missed = 0,
                Some(Ok(Message::Text(t))) => {
                    frames += 1;
                    if let Err(e) = tx.send(Message::Text(t)).await {
                        break format!("echo failed: {e}");
                    }
                }
                Some(Ok(Message::Close(frame))) => {
                    break format!("client closed: {:?}", frame.map(|f| f.code));
                }
                // tungstenite answers client pings itself; binary is ignored.
                Some(Ok(_)) => {}
            }
        }
    };
    let _ = tx.close().await;
    log(
        "ws_close",
        serde_json::json!({"sub": caller.subject, "seconds": started.elapsed().as_secs(), "frames": frames, "reason": reason}),
    );
}

#[tokio::main]
async fn main() {
    if std::env::args()
        .skip(1)
        .any(|a| a == "--version" || a == "-V")
    {
        println!("vitruvian-relay-spike {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    let settings = match Settings::from_lookup(|k| std::env::var(k).ok()) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("configuration error: {e}");
            std::process::exit(1);
        }
    };
    let mut mcp = HashMap::new();
    for id in &settings.mcp_client_ids {
        match verifier(&settings, id) {
            Ok(v) => {
                mcp.insert(id.clone(), v);
            }
            Err(e) => {
                eprintln!("configuration error: {e}");
                std::process::exit(1);
            }
        }
    }
    let connector = match verifier(&settings, &settings.connector_client_id) {
        Ok(v) => v,
        Err(e) => {
            eprintln!("configuration error: {e}");
            std::process::exit(1);
        }
    };
    let port = settings.port;
    log(
        "start",
        serde_json::json!({"port": port, "mcp_url": settings.mcp_url()}),
    );
    let app = Arc::new(App {
        settings,
        mcp,
        connector,
    });

    let listener = match TcpListener::bind(("0.0.0.0", port)).await {
        Ok(l) => l,
        Err(e) => {
            eprintln!("cannot listen on port {port}: {e}");
            std::process::exit(1);
        }
    };
    loop {
        tokio::select! {
            _ = tokio::signal::ctrl_c() => {
                log("stop", serde_json::json!({}));
                return;
            }
            accepted = listener.accept() => {
                let Ok((stream, _)) = accepted else { continue };
                let app = app.clone();
                tokio::spawn(async move {
                    let svc = service_fn(move |req| handle(app.clone(), req));
                    let conn = http1::Builder::new()
                        .serve_connection(TokioIo::new(stream), svc)
                        .with_upgrades();
                    let _ = conn.await;
                });
            }
        }
    }
}
