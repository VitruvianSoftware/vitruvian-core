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

//! The relay server binary: reads settings, opens the device store, and
//! serves. All logic is in the library (`http.rs` and friends).

use std::sync::Arc;

use tokio::net::TcpListener;
use vitruvian_mcp_auth::{verifier, VerifierConfig};
use vitruvian_relay::config::{wants_version, Settings};
use vitruvian_relay::devices::FileDeviceStore;
use vitruvian_relay::http::{serve, App, Timing};
use vitruvian_relay::{log_event, stdout_log};

fn fail(msg: String) -> ! {
    eprintln!("{msg}");
    std::process::exit(1);
}

#[tokio::main]
async fn main() {
    if wants_version(std::env::args()) {
        println!("vitruvian-relay {}", env!("CARGO_PKG_VERSION"));
        return;
    }
    let settings = Settings::from_lookup(|k| std::env::var(k).ok())
        .unwrap_or_else(|e| fail(format!("configuration error: {e}")));
    let verifier_for = |client_ids: Vec<String>| {
        verifier(VerifierConfig {
            issuer: settings.issuer.clone(),
            project_id: settings.project_id.clone(),
            allowed_client_ids: client_ids,
            allowed_subjects: settings.allowed_subjects.clone(),
            jwks_uri: settings.jwks_uri.clone(),
            user_agent: format!("vitruvian-relay/{}", env!("CARGO_PKG_VERSION")),
        })
        .unwrap_or_else(|e| fail(format!("configuration error: {e}")))
    };
    let mcp = verifier_for(settings.mcp_client_ids.clone());
    let connector = verifier_for(vec![settings.connector_client_id.clone()]);
    let devices_file = settings.devices_file();
    let store = FileDeviceStore::open(&devices_file).unwrap_or_else(|e| {
        fail(format!(
            "cannot open the device store {}: {e}",
            devices_file.display()
        ))
    });
    let port = settings.port;
    let log = stdout_log();
    log_event(
        &log,
        "start",
        serde_json::json!({
            "port": port,
            "public_url": settings.public_url,
            "devices_file": devices_file.display().to_string(),
        }),
    );
    let app = App::new(
        settings,
        mcp,
        connector,
        Arc::new(store),
        Timing::default(),
        log.clone(),
    );
    let listener = TcpListener::bind(("0.0.0.0", port))
        .await
        .unwrap_or_else(|e| fail(format!("cannot listen on port {port}: {e}")));
    tokio::select! {
        _ = serve(listener, app) => {}
        _ = tokio::signal::ctrl_c() => log_event(&log, "stop", serde_json::json!({})),
    }
}
