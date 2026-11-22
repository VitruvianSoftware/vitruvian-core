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

//! The relay server binary: reads settings, opens the device store
//! (Postgres), and serves. All logic is in the library (`http.rs` and friends).

use std::sync::Arc;

use tokio::net::TcpListener;
use vitruvian_mcp_auth::{verifier_requiring_role, VerifierConfig};
use vitruvian_relay::config::{wants_version, Settings};
use vitruvian_relay::http::{serve, App, Timing};
use vitruvian_relay::store::{purge_activity_forever, PgStore, Store, ACTIVITY_PURGE_EVERY};
use vitruvian_relay::{log_event, stdout_log, stop_signal};

/// A problem with the system's certificates, as a log line like any other.
fn tls_warning(message: &str) {
    log_event(
        &stdout_log(),
        "tls_warning",
        serde_json::json!({"message": message}),
    );
}

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
    vitruvian_mcp_auth::set_tls_warning_hook(tls_warning);
    let settings = Settings::from_lookup(|k| std::env::var(k).ok())
        .unwrap_or_else(|e| fail(format!("configuration error: {e}")));
    let verifier_for = |client_ids: Vec<String>| {
        verifier_requiring_role(
            VerifierConfig {
                issuer: settings.issuer.clone(),
                project_id: settings.project_id.clone(),
                allowed_client_ids: client_ids,
                allowed_subjects: Vec::new(),
                jwks_uri: settings.jwks_uri.clone(),
                user_agent: format!("vitruvian-relay/{}", env!("CARGO_PKG_VERSION")),
            },
            settings.required_role.clone(),
        )
        .unwrap_or_else(|e| fail(format!("configuration error: {e}")))
    };
    let mcp = verifier_for(settings.mcp_client_ids.clone());
    let connector = verifier_for(vec![settings.connector_client_id.clone()]);
    let dashboard = verifier_for(vec![settings.dashboard_client_id.clone()]);
    let port = settings.port;
    let log = stdout_log();
    log_event(
        &log,
        "start",
        serde_json::json!({
            "port": port,
            "public_url": settings.public_url,
            "required_role": settings.required_role,
        }),
    );
    if std::env::var_os("ALLOWED_SUBJECTS").is_some() {
        log_event(
            &log,
            "setting_ignored",
            serde_json::json!({
                "setting": "ALLOWED_SUBJECTS",
                "why": "access is by the Zitadel role now; remove it from the deployment",
            }),
        );
    }
    let store = PgStore::connect(
        settings.database_url.expose(),
        settings.database_ca_file.as_deref(),
        log.clone(),
    )
    .await
    .unwrap_or_else(|e| fail(format!("cannot open the device store: {e}")));
    log_event(&log, "store_ready", serde_json::json!({}));
    let store: Arc<dyn Store> = Arc::new(store);
    // Calls are kept for 30 days: this clears the older ones once an hour.
    tokio::spawn(purge_activity_forever(
        store.clone(),
        log.clone(),
        ACTIVITY_PURGE_EVERY,
    ));
    let app = App::new(
        settings,
        mcp,
        connector,
        dashboard,
        store,
        Timing::default(),
        log.clone(),
    );
    let listener = TcpListener::bind(("0.0.0.0", port))
        .await
        .unwrap_or_else(|e| fail(format!("cannot listen on port {port}: {e}")));
    let stop = stop_signal().unwrap_or_else(|e| fail(format!("cannot watch for SIGTERM: {e}")));
    tokio::select! {
        _ = serve(listener, app) => {}
        why = stop => log_event(&log, "stop", serde_json::json!({"signal": why})),
    }
}
