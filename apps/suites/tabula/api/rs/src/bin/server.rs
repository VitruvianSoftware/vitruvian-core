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

use std::sync::Arc;
use tabula_api_tools_rs_lib::auth_lib::resolve_jwt_secret_from_process_env;
use tabula_api_tools_rs_lib::migration_guard::{
    assert_database_schema_current, MigrationLogger, ProbeOptions, RequiredColumn,
};
use tabula_api_tools_rs_lib::server::{serve_http, AppContext};
use tabula_api_tools_rs_lib::store::{DataStore, PgClient, RespRedisStore};
use tabula_api_tools_rs_lib::workos::DefaultWorkOSProvider;

struct StdioMigrationLogger;

impl MigrationLogger for StdioMigrationLogger {
    fn info(&self, msg: &str) {
        println!("[migration-guard] {msg}");
    }
    fn warn(&self, msg: &str) {
        eprintln!("[migration-guard] WARN: {msg}");
    }
    fn error(&self, msg: &str) {
        eprintln!("[migration-guard] ERROR: {msg}");
    }
    fn fatal(&self, _missing: &[RequiredColumn], msg: &str) {
        eprintln!("[migration-guard] FATAL: {msg}");
    }
}

fn main() {
    let host = std::env::var("HOST").unwrap_or_else(|_| "0.0.0.0".to_string());
    let port = std::env::var("PORT").unwrap_or_else(|_| "8080".to_string());
    let bind_addr = format!("{host}:{port}");

    let jwt_secret = resolve_jwt_secret_from_process_env()
        .unwrap_or_else(|_| "tabula-dev-only-insecure-jwt-secret".to_string());
    let redis_url = std::env::var("REDIS_URL").ok();
    let redis_enabled = redis_url.as_ref().map(|s| !s.is_empty()).unwrap_or(false);

    let store = DataStore::new();
    if let Ok(db_url) = std::env::var("DATABASE_URL") {
        if let Ok(pg) = PgClient::from_url(&db_url) {
            let skip = std::env::var("TABULA_SKIP_MIGRATION_CHECK")
                .or_else(|_| std::env::var("SKIP_MIGRATION_GUARD"))
                .ok();
            let logger = StdioMigrationLogger;
            let _ = assert_database_schema_current(
                &pg,
                &logger,
                skip.as_deref(),
                ProbeOptions {
                    attempts: 3,
                    backoff_ms: 50,
                },
            );
            store.load_users_from_pg(&pg);
        }
    }

    let ctx = Arc::new(AppContext {
        store,
        redis: Arc::new(RespRedisStore::from_url_or_memory(redis_url.as_deref())),
        workos: Arc::new(DefaultWorkOSProvider),
        jwt_secret,
        workos_client_id: std::env::var("WORKOS_CLIENT_ID")
            .unwrap_or_else(|_| "client_live".to_string()),
        api_url: std::env::var("API_URL").unwrap_or_else(|_| format!("http://localhost:{port}")),
        environment: std::env::var("NODE_ENV").unwrap_or_else(|_| "development".to_string()),
        redis_enabled,
        auth_postmessage_origin: std::env::var("AUTH_POSTMESSAGE_ORIGIN").ok(),
        cors_origin: std::env::var("CORS_ORIGIN").ok(),
    });

    println!("Tabula API (Rust) listening on http://{bind_addr}");
    if let Err(err) = serve_http(ctx, &bind_addr) {
        eprintln!("Failed to start Tabula API server: {err}");
        std::process::exit(1);
    }
}
