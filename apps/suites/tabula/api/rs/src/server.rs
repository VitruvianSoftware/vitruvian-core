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

use crate::auth_lib::ACCESS_TOKEN_TTL_SECS;
use crate::crypto::{jwt_sign, jwt_verify, now_iso8601};
use crate::device::get_device_id;
use crate::errors::{format_error_response, AppError};
use crate::scanner_reject::is_scanner_probe_path;
use crate::schemas::{
    parse_backup_create_schema, parse_backup_list_query, parse_backup_restore_schema,
    parse_create_share_link_schema, parse_password_reset_schema, parse_save_tabs_schema,
    parse_set_collaborator_role_schema, parse_share_by_email_schema, parse_share_link_token_body,
    parse_space_group_create_schema, parse_space_group_update_schema, parse_sync_pull_schema,
    parse_sync_push_schema, parse_tab_bulk_operation_schema, parse_tab_move_schema,
    parse_tab_reorder_schema, parse_user_update_schema, parse_workspace_create_schema,
    parse_workspace_update_schema,
};
use crate::services::{
    AuthService, BackupService, CollaboratorService, PermissionService, ShareService,
    SpaceGroupService, SyncService, UserService, WorkspaceService,
};
use crate::store::{DataStore, InMemoryRedis, RedisStore};
use crate::sync_events::{publish_sync_event, SyncEventInput};
use crate::tombstones::{is_tombstoned, mark_entity_deleted};
use crate::workos::{DefaultWorkOSProvider, WorkOSProvider};
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::collections::HashMap;
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{TcpListener, TcpStream};
use std::sync::Arc;
use std::time::Duration;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct AuthenticatedUser {
    pub id: String,
    pub email: String,
    pub tier: String,
}

#[derive(Clone)]
pub struct AppContext {
    pub store: DataStore,
    pub redis: Arc<dyn RedisStore>,
    pub workos: Arc<dyn WorkOSProvider>,
    pub jwt_secret: String,
    pub workos_client_id: String,
    pub api_url: String,
    pub environment: String,
    pub redis_enabled: bool,
    pub auth_postmessage_origin: Option<String>,
    pub cors_origin: Option<String>,
}

impl AppContext {
    pub fn new_test() -> Self {
        Self {
            store: DataStore::new(),
            redis: Arc::new(InMemoryRedis::new()),
            workos: Arc::new(DefaultWorkOSProvider),
            jwt_secret: "tabula-test-secret".to_string(),
            workos_client_id: "client_test_123".to_string(),
            api_url: "http://localhost:8080".to_string(),
            environment: "test".to_string(),
            redis_enabled: true,
            auth_postmessage_origin: None,
            cors_origin: None,
        }
    }

    pub fn sign_user_token(&self, id: &str, email: &str, tier: &str) -> String {
        jwt_sign(
            &json!({
                "id": id,
                "email": email,
                "tier": tier,
            }),
            &self.jwt_secret,
            Some(ACCESS_TOKEN_TTL_SECS),
        )
    }
}

#[derive(Debug, Clone)]
pub struct HttpRequest {
    pub method: String,
    pub raw_path: String,
    pub headers: HashMap<String, String>,
    pub body: String,
}

impl HttpRequest {
    pub fn new(method: &str, raw_path: &str) -> Self {
        Self {
            method: method.to_ascii_uppercase(),
            raw_path: raw_path.to_string(),
            headers: HashMap::new(),
            body: String::new(),
        }
    }

    pub fn with_header(mut self, key: &str, value: &str) -> Self {
        self.headers
            .insert(key.to_ascii_lowercase(), value.to_string());
        self
    }

    pub fn with_auth(self, bearer_or_token: &str) -> Self {
        let val = if bearer_or_token.starts_with("Bearer ") {
            bearer_or_token.to_string()
        } else {
            format!("Bearer {bearer_or_token}")
        };
        self.with_header("authorization", &val)
    }

    pub fn with_body(mut self, body: &str) -> Self {
        self.body = body.to_string();
        self
    }

    pub fn with_json(mut self, payload: &Value) -> Self {
        self.headers
            .insert("content-type".to_string(), "application/json".to_string());
        self.body = payload.to_string();
        self
    }

    pub fn header(&self, key: &str) -> Option<&str> {
        let lower = key.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(k, _)| k.to_ascii_lowercase() == lower)
            .map(|(_, v)| v.as_str())
    }

    pub fn path_and_query(&self) -> (&str, HashMap<String, String>) {
        let (path, qs) = match self.raw_path.split_once('?') {
            Some((p, q)) => (p, q),
            None => (self.raw_path.as_str(), ""),
        };
        let mut query = HashMap::new();
        for pair in qs.split('&') {
            if pair.is_empty() {
                continue;
            }
            let (k, v) = match pair.split_once('=') {
                Some((k, v)) => (url_decode(k), url_decode(v)),
                None => (url_decode(pair), String::new()),
            };
            query.insert(k, v);
        }
        (path, query)
    }
}

#[derive(Debug, Clone)]
pub struct HttpResponse {
    pub status: u16,
    pub headers: HashMap<String, String>,
    pub body: String,
}

impl HttpResponse {
    pub fn json_resp(status: u16, body: Value) -> Self {
        let mut headers = HashMap::new();
        headers.insert(
            "content-type".to_string(),
            "application/json; charset=utf-8".to_string(),
        );
        Self {
            status,
            headers,
            body: body.to_string(),
        }
    }

    pub fn empty(status: u16) -> Self {
        Self {
            status,
            headers: HashMap::new(),
            body: String::new(),
        }
    }

    pub fn html(status: u16, html: String) -> Self {
        let mut headers = HashMap::new();
        headers.insert(
            "content-type".to_string(),
            "text/html; charset=utf-8".to_string(),
        );
        Self {
            status,
            headers,
            body: html,
        }
    }

    pub fn redirect(url: &str) -> Self {
        let mut headers = HashMap::new();
        headers.insert("location".to_string(), url.to_string());
        Self {
            status: 302,
            headers,
            body: String::new(),
        }
    }

    pub fn json(&self) -> Value {
        serde_json::from_str(&self.body).unwrap_or(Value::Null)
    }

    pub fn header(&self, key: &str) -> Option<&str> {
        let lower = key.to_ascii_lowercase();
        self.headers
            .iter()
            .find(|(k, _)| k.to_ascii_lowercase() == lower)
            .map(|(_, v)| v.as_str())
    }
}

pub fn url_decode(input: &str) -> String {
    let mut out = Vec::with_capacity(input.len());
    let bytes = input.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'+' {
            out.push(b' ');
            i += 1;
        } else if bytes[i] == b'%' && i + 2 < bytes.len() {
            if let Ok(hex) = std::str::from_utf8(&bytes[i + 1..i + 3]) {
                if let Ok(val) = u8::from_str_radix(hex, 16) {
                    out.push(val);
                    i += 3;
                    continue;
                }
            }
            out.push(bytes[i]);
            i += 1;
        } else {
            out.push(bytes[i]);
            i += 1;
        }
    }
    String::from_utf8_lossy(&out).to_string()
}

pub fn escape_json_for_script(value: &Value) -> String {
    value
        .to_string()
        .replace('<', "\\u003c")
        .replace('>', "\\u003e")
        .replace('&', "\\u0026")
        .replace('\u{2028}', "\\u2028")
        .replace('\u{2029}', "\\u2029")
}

pub fn escape_html(value: &str) -> String {
    value
        .replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&#39;")
}

pub fn transform_workspace_response(workspace: &Value) -> Value {
    let Some(ws_obj) = workspace.as_object() else {
        return workspace.clone();
    };
    let mut out = ws_obj.clone();
    let tab_groups = ws_obj
        .get("settings")
        .and_then(Value::as_object)
        .and_then(|s| s.get("tabGroups"))
        .and_then(Value::as_array)
        .cloned()
        .unwrap_or_default();

    let tabs: Vec<Value> = ws_obj
        .get("tabs")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .map(|tab| {
                    let Some(t_obj) = tab.as_object() else {
                        return tab.clone();
                    };
                    let mut t_out = t_obj.clone();
                    let group_id = t_obj
                        .get("metadata")
                        .and_then(Value::as_object)
                        .and_then(|m| m.get("groupId"))
                        .and_then(Value::as_str)
                        .filter(|s| !s.is_empty())
                        .map(|s| Value::String(s.to_string()))
                        .unwrap_or(Value::Null);
                    let fav_icon = t_obj.get("faviconUrl").cloned().unwrap_or(Value::Null);
                    let pinned = t_obj
                        .get("isPinned")
                        .and_then(Value::as_bool)
                        .unwrap_or(false);
                    let index = t_obj.get("position").cloned().unwrap_or_else(|| json!(0));
                    t_out.insert("groupId".to_string(), group_id);
                    t_out.insert("favIconUrl".to_string(), fav_icon);
                    t_out.insert("pinned".to_string(), Value::Bool(pinned));
                    t_out.insert("index".to_string(), index);
                    Value::Object(t_out)
                })
                .collect()
        })
        .unwrap_or_default();

    out.insert("tabs".to_string(), Value::Array(tabs));
    out.insert("tabGroups".to_string(), Value::Array(tab_groups));
    Value::Object(out)
}

pub fn authenticate_request(
    req: &HttpRequest,
    jwt_secret: &str,
    allow_query_token: bool,
) -> Result<AuthenticatedUser, HttpResponse> {
    let mut token_opt: Option<String> = None;
    if let Some(auth_hdr) = req.header("authorization") {
        if let Some(stripped) = auth_hdr.strip_prefix("Bearer ") {
            let trimmed = stripped.trim();
            if !trimmed.is_empty() {
                token_opt = Some(trimmed.to_string());
            }
        }
    }
    if token_opt.is_none() && allow_query_token {
        let (_, query) = req.path_and_query();
        if let Some(t) = query.get("token").filter(|s| !s.is_empty()) {
            token_opt = Some(t.clone());
        }
    }

    let Some(token) = token_opt else {
        return Err(HttpResponse::json_resp(
            401,
            json!({
                "error": "Unauthorized",
                "message": "Invalid or expired token",
            }),
        ));
    };

    let claims = jwt_verify(&token, jwt_secret).map_err(|_| {
        HttpResponse::json_resp(
            401,
            json!({
                "error": "Unauthorized",
                "message": "Invalid or expired token",
            }),
        )
    })?;

    let id = claims
        .get("id")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .ok_or_else(|| {
            HttpResponse::json_resp(
                401,
                json!({
                    "error": "Unauthorized",
                    "message": "Invalid or expired token",
                }),
            )
        })?
        .to_string();

    let email = claims
        .get("email")
        .and_then(Value::as_str)
        .unwrap_or("user@example.com")
        .to_string();
    let tier = claims
        .get("tier")
        .and_then(Value::as_str)
        .unwrap_or("free")
        .to_string();

    Ok(AuthenticatedUser { id, email, tier })
}

pub fn tier_rank(tier: &str) -> u8 {
    match tier {
        "enterprise" => 3,
        "team" => 2,
        "pro" => 1,
        _ => 0,
    }
}

pub fn require_tier(user: &AuthenticatedUser, required_tier: &str) -> Result<(), HttpResponse> {
    if tier_rank(&user.tier) < tier_rank(required_tier) {
        return Err(HttpResponse::json_resp(
            403,
            json!({
                "error": "Forbidden",
                "message": format!("This feature requires {required_tier} tier or higher"),
            }),
        ));
    }
    Ok(())
}

fn parse_request_json_body(req: &HttpRequest) -> Result<Value, HttpResponse> {
    let ct = req.header("content-type").unwrap_or("");
    if req.body.trim().is_empty() {
        return Ok(Value::Object(Map::new()));
    }
    if ct.to_ascii_lowercase().starts_with("application/json") || !req.body.is_empty() {
        serde_json::from_str::<Value>(&req.body).map_err(|_| {
            HttpResponse::json_resp(
                400,
                json!({
                    "error": "Bad Request",
                    "message": "Invalid JSON body",
                }),
            )
        })
    } else {
        Ok(Value::Object(Map::new()))
    }
}

fn map_app_error(err: AppError) -> HttpResponse {
    let (status, body) = format_error_response(&err, false);
    HttpResponse::json_resp(status, body)
}

fn get_allowed_origins(ctx: &AppContext) -> Vec<String> {
    let mut list = Vec::new();
    if let Some(o) = &ctx.auth_postmessage_origin {
        let t = o.trim();
        if !t.is_empty() {
            list.push(t.to_string());
        }
    }
    if let Some(cors) = &ctx.cors_origin {
        for part in cors.split(',') {
            let trimmed = part.trim();
            if !trimmed.is_empty() && trimmed != "*" && !trimmed.contains('*') {
                list.push(trimmed.to_string());
            }
        }
    }
    if !list.iter().any(|s| s == "http://localhost:3000") {
        list.push("http://localhost:3000".to_string());
    }
    if !list.iter().any(|s| s == "http://localhost:3001") {
        list.push("http://localhost:3001".to_string());
    }
    list
}

fn validate_origin(ctx: &AppContext, candidate: Option<&str>) -> Option<String> {
    let cand = candidate?.trim();
    if cand.is_empty() {
        return None;
    }
    let allowed = get_allowed_origins(ctx);
    if allowed.iter().any(|a| a == cand) {
        Some(cand.to_string())
    } else {
        None
    }
}

fn resolve_postmessage_origin(ctx: &AppContext, req_origin: Option<&str>) -> String {
    if let Some(valid) = validate_origin(ctx, req_origin) {
        return valid;
    }
    if let Some(o) = &ctx.auth_postmessage_origin {
        let t = o.trim();
        if !t.is_empty() && t != "*" && !t.contains('*') {
            return t.to_string();
        }
    }
    if let Some(cors) = &ctx.cors_origin {
        if let Some(first) = cors.split(',').next() {
            let t = first.trim();
            if !t.is_empty() && t != "*" && !t.contains('*') {
                return t.to_string();
            }
        }
    }
    "http://localhost:3000".to_string()
}

fn extract_origin_from_referer(referer: &str) -> Option<String> {
    let (scheme, rest) = referer.split_once("://")?;
    let host_port = rest.split('/').next()?;
    if host_port.is_empty() {
        return None;
    }
    Some(format!("{scheme}://{host_port}"))
}

pub fn handle_request(ctx: &AppContext, req: &HttpRequest) -> HttpResponse {
    let (raw_path, query) = req.path_and_query();
    let path = if raw_path.len() > 1 {
        raw_path.trim_end_matches('/')
    } else {
        raw_path
    };

    if is_scanner_probe_path(path) {
        return HttpResponse::json_resp(404, json!({ "error": "Not Found" }));
    }

    let method = req.method.as_str();

    // 1. Root & Health routes
    if method == "GET" && path == "/health" {
        return HttpResponse::json_resp(
            200,
            json!({
                "status": "ok",
                "timestamp": now_iso8601(),
                "redis": if ctx.redis_enabled { "connected" } else { "disabled" },
            }),
        );
    }

    if method == "GET" && path == "/" {
        return HttpResponse::json_resp(
            200,
            json!({
                "name": "Tabula API",
                "version": "1.0.0",
                "commit": "unknown",
                "revision": Value::Null,
                "environment": ctx.environment,
            }),
        );
    }

    // 2. Auth routes (/api/v1/auth/*)
    if let Some(sub) = path.strip_prefix("/api/v1/auth") {
        return handle_auth_routes(ctx, req, method, sub, &query);
    }

    // 3. User routes (/api/v1/users/*)
    if let Some(sub) = path.strip_prefix("/api/v1/users") {
        return handle_user_routes(ctx, req, method, sub);
    }

    // 4. Public & authenticated share-link / relay routes (/api/v1/share-links/*)
    if let Some(sub) = path.strip_prefix("/api/v1/share-links") {
        return handle_share_links_routes(ctx, req, method, sub);
    }

    // 5. Space group routes (/api/v1/space-groups/*)
    if path == "/api/v1/space-groups" || path.starts_with("/api/v1/space-groups/") {
        let sub = path.strip_prefix("/api/v1/space-groups").unwrap_or("");
        return handle_space_group_routes(ctx, req, method, sub);
    }

    // 6. Backup routes (/api/v1/backups/*)
    if path == "/api/v1/backups" || path.starts_with("/api/v1/backups/") {
        let sub = path.strip_prefix("/api/v1/backups").unwrap_or("");
        return handle_backup_routes(ctx, req, method, sub, &query);
    }

    // 7. Sync routes (/api/v1/sync/*)
    if let Some(sub) = path.strip_prefix("/api/v1/sync") {
        return handle_sync_routes(ctx, req, method, sub, &query);
    }

    // 8. Workspace & sharing routes (/api/v1/workspaces*)
    if path == "/api/v1/workspaces" || path.starts_with("/api/v1/workspaces/") {
        let sub = path.strip_prefix("/api/v1/workspaces").unwrap_or("");
        return handle_workspace_routes(ctx, req, method, sub);
    }

    HttpResponse::json_resp(404, json!({ "error": "Not Found" }))
}

fn handle_auth_routes(
    ctx: &AppContext,
    req: &HttpRequest,
    method: &str,
    sub: &str,
    query: &HashMap<String, String>,
) -> HttpResponse {
    match (method, sub) {
        ("GET", "/login") => {
            let raw_origin = query
                .get("origin")
                .cloned()
                .or_else(|| req.header("referer").and_then(extract_origin_from_referer));
            let validated = validate_origin(ctx, raw_origin.as_deref());
            let redirect_uri =
                format!("{}/api/v1/auth/callback", ctx.api_url.trim_end_matches('/'));
            match AuthService::get_authorization_url(
                ctx.workos.as_ref(),
                &ctx.workos_client_id,
                &redirect_uri,
            ) {
                Ok(mut url) => {
                    if let Some(orig) = validated {
                        let state_json = json!({ "origin": orig }).to_string();
                        if !url.contains("state=") {
                            url.push_str(&format!("&state={state_json}"));
                        }
                    }
                    HttpResponse::redirect(&url)
                }
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Failed to initiate login",
                            "message": e.message(),
                        }),
                    )
                }
            }
        }
        ("GET", "/callback") => {
            let Some(code) = query.get("code").filter(|s| !s.is_empty()) else {
                return HttpResponse::json_resp(400, json!({ "error": "Missing code parameter" }));
            };

            let mut requested_origin: Option<String> = None;
            if let Some(state_str) = query.get("state") {
                if let Ok(parsed) = serde_json::from_str::<Value>(state_str) {
                    if let Some(orig) = parsed.get("origin").and_then(Value::as_str) {
                        requested_origin = Some(orig.to_string());
                    }
                }
            }

            let accept = req.header("accept").unwrap_or("");
            let wants_html = accept.contains("text/html");

            let user = match AuthService::authenticate_and_sync_user(
                &ctx.store,
                ctx.workos.as_ref(),
                &ctx.workos_client_id,
                code,
            ) {
                Ok(u) => u,
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    let msg = e.message();
                    if wants_html {
                        let html = format!(
                            "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Tabula Authentication</title></head><body><h2 style=\"color: red\">Authentication Failed</h2><p>{}</p></body></html>",
                            escape_html(msg)
                        );
                        return HttpResponse::html(200, html);
                    }
                    return HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Authentication failed",
                            "message": msg,
                        }),
                    );
                }
            };

            let token = ctx.sign_user_token(&user.id, &user.email, &user.tier);
            let user_agent = req.header("user-agent").map(|s| s.to_string());
            let refresh_token =
                match AuthService::create_session(&ctx.store, &user.id, None, user_agent, None) {
                    Ok(rt) => rt,
                    Err(e) => return map_app_error(e),
                };

            let response_data = json!({
                "token": token,
                "refreshToken": refresh_token,
                "user": {
                    "id": user.id,
                    "email": user.email,
                    "name": user.name,
                    "tier": user.tier,
                }
            });

            if wants_html {
                let target_origin = resolve_postmessage_origin(ctx, requested_origin.as_deref());
                let escaped_data = escape_json_for_script(&response_data);
                let escaped_origin = escape_json_for_script(&Value::String(target_origin));
                let html = format!(
                    "<!DOCTYPE html><html><head><meta charset=\"utf-8\"><title>Tabula Authentication</title><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'\"></head><body><h2 class=\"success\">Authentication Successful</h2><p>You can close this window now.</p><script id=\"tabula-auth-data\" type=\"application/json\">{escaped_data}</script><script>(function () {{ var el = document.getElementById('tabula-auth-data'); var payload = JSON.parse(el.textContent); if (window.opener) {{ window.opener.postMessage({{ type: 'TABULA_AUTH_SUCCESS', payload: payload }}, {escaped_origin}); setTimeout(function () {{ window.close(); }}, 1500); }} }})();</script></body></html>"
                );
                return HttpResponse::html(200, html);
            }

            HttpResponse::json_resp(200, response_data)
        }
        ("POST", "/refresh") => {
            let body = match parse_request_json_body(req) {
                Ok(b) => b,
                Err(resp) => return resp,
            };
            let Some(rt) = body
                .get("refreshToken")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
            else {
                return HttpResponse::json_resp(
                    400,
                    json!({
                        "error": "Bad Request",
                        "message": "refreshToken is required",
                    }),
                );
            };
            match AuthService::rotate_refresh_token(&ctx.store, rt) {
                Ok(Some(rotated)) => {
                    let token = ctx.sign_user_token(
                        &rotated.user.id,
                        &rotated.user.email,
                        &rotated.user.tier,
                    );
                    HttpResponse::json_resp(
                        200,
                        json!({
                            "token": token,
                            "refreshToken": rotated.refresh_token,
                        }),
                    )
                }
                Ok(None) => HttpResponse::json_resp(
                    401,
                    json!({
                        "error": "Unauthorized",
                        "message": "Invalid or expired refresh token",
                    }),
                ),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Internal Server Error",
                            "message": "Failed to refresh token",
                        }),
                    )
                }
            }
        }
        ("POST", "/logout") => {
            let body = parse_request_json_body(req).unwrap_or_else(|_| json!({}));
            if let Some(rt) = body
                .get("refreshToken")
                .and_then(Value::as_str)
                .filter(|s| !s.is_empty())
            {
                let _ = AuthService::revoke_refresh_token(&ctx.store, rt);
            }
            HttpResponse::json_resp(200, json!({ "success": true }))
        }
        _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
    }
}

fn handle_user_routes(
    ctx: &AppContext,
    req: &HttpRequest,
    method: &str,
    sub: &str,
) -> HttpResponse {
    if method == "POST" && sub == "/password-reset" {
        let body = match parse_request_json_body(req) {
            Ok(b) => b,
            Err(resp) => return resp,
        };
        let email = match parse_password_reset_schema(&body) {
            Ok(e) => e,
            Err(AppError::BadRequest {
                details: Some(details),
                ..
            }) => {
                return HttpResponse::json_resp(
                    400,
                    json!({
                        "error": "Validation Error",
                        "message": "Invalid request body",
                        "details": details,
                    }),
                );
            }
            Err(e) => return map_app_error(e),
        };
        if let Err(e) = ctx.store.check_injected_error() {
            if matches!(e, AppError::SchemaDrift { .. }) {
                return map_app_error(e);
            }
            return HttpResponse::json_resp(
                500,
                json!({
                    "error": "Internal Server Error",
                    "message": "Failed to generate password reset URL",
                }),
            );
        }
        let reset_url = UserService::get_password_reset_url(&ctx.api_url, &email);
        return HttpResponse::json_resp(
            200,
            json!({
                "data": {
                    "resetUrl": reset_url,
                    "message": "Password reset URL generated",
                }
            }),
        );
    }

    let user = match authenticate_request(req, &ctx.jwt_secret, false) {
        Ok(u) => u,
        Err(resp) => return resp,
    };

    match (method, sub) {
        ("GET", "/me") => match UserService::get_user_by_id(&ctx.store, &user.id) {
            Ok(Some(profile)) => HttpResponse::json_resp(200, json!({ "data": profile })),
            Ok(None) => HttpResponse::json_resp(
                404,
                json!({
                    "error": "Not Found",
                    "message": "User not found",
                }),
            ),
            Err(e) => {
                if matches!(e, AppError::SchemaDrift { .. }) {
                    return map_app_error(e);
                }
                HttpResponse::json_resp(
                    500,
                    json!({
                        "error": "Internal Server Error",
                        "message": "Failed to get user profile",
                    }),
                )
            }
        },
        ("PATCH", "/me") => {
            let body = match parse_request_json_body(req) {
                Ok(b) => b,
                Err(resp) => return resp,
            };
            let input = match parse_user_update_schema(&body) {
                Ok(i) => i,
                Err(AppError::BadRequest {
                    details: Some(details),
                    ..
                }) => {
                    return HttpResponse::json_resp(
                        400,
                        json!({
                            "error": "Validation Error",
                            "message": "Invalid request body",
                            "details": details,
                        }),
                    );
                }
                Err(e) => return map_app_error(e),
            };
            match UserService::update_user(&ctx.store, &user.id, input) {
                Ok(updated) => HttpResponse::json_resp(200, json!({ "data": updated })),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Internal Server Error",
                            "message": "Failed to update user profile",
                        }),
                    )
                }
            }
        }
        ("DELETE", "/me") => match UserService::delete_user(&ctx.store, &user.id) {
            Ok(()) => HttpResponse::empty(204),
            Err(e) => {
                if matches!(e, AppError::SchemaDrift { .. }) {
                    return map_app_error(e);
                }
                HttpResponse::json_resp(
                    500,
                    json!({
                        "error": "Internal Server Error",
                        "message": "Failed to delete user account",
                    }),
                )
            }
        },
        _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
    }
}

fn handle_share_links_routes(
    ctx: &AppContext,
    req: &HttpRequest,
    method: &str,
    sub: &str,
) -> HttpResponse {
    // Relay routes: /api/v1/share-links/relay/:relayId/info (public) and /accept (auth)
    if let Some(relay_rest) = sub.strip_prefix("/relay/") {
        if let Some(relay_id) = relay_rest.strip_suffix("/info") {
            if method == "GET" {
                if relay_id.is_empty() || relay_id.len() > 128 {
                    return HttpResponse::json_resp(
                        400,
                        json!({ "error": "Bad Request", "message": "Invalid relayId" }),
                    );
                }
                return match ShareService::get_relay_info(&ctx.store, relay_id) {
                    Ok(info) => HttpResponse::json_resp(200, json!({ "data": info })),
                    Err(e) => map_app_error(e),
                };
            }
        }
        if let Some(relay_id) = relay_rest.strip_suffix("/accept") {
            if method == "POST" {
                let user = match authenticate_request(req, &ctx.jwt_secret, false) {
                    Ok(u) => u,
                    Err(resp) => return resp,
                };
                if let Err(resp) = parse_request_json_body(req) {
                    return resp;
                }
                if relay_id.is_empty() || relay_id.len() > 128 {
                    return HttpResponse::json_resp(
                        400,
                        json!({ "error": "Bad Request", "message": "Invalid relayId" }),
                    );
                }
                return match ShareService::accept_by_relay_id(
                    &ctx.store,
                    relay_id,
                    &user.id,
                    &user.email,
                ) {
                    Ok(res) => HttpResponse::json_resp(200, json!({ "data": res })),
                    Err(e) => map_app_error(e),
                };
            }
        }
    }

    let user = match authenticate_request(req, &ctx.jwt_secret, false) {
        Ok(u) => u,
        Err(resp) => return resp,
    };

    match (method, sub) {
        ("POST", "/info") => {
            let body = match parse_request_json_body(req) {
                Ok(b) => b,
                Err(resp) => return resp,
            };
            let token = match parse_share_link_token_body(&body) {
                Ok(t) => t,
                Err(_) => {
                    return HttpResponse::json_resp(
                        400,
                        json!({ "error": "Bad Request", "message": "Invalid input" }),
                    )
                }
            };
            match ShareService::get_link_info(&ctx.store, &token) {
                Ok(info) => HttpResponse::json_resp(200, json!({ "data": info })),
                Err(e) => map_app_error(e),
            }
        }
        ("POST", "/accept") => {
            let body = match parse_request_json_body(req) {
                Ok(b) => b,
                Err(resp) => return resp,
            };
            let token = match parse_share_link_token_body(&body) {
                Ok(t) => t,
                Err(_) => {
                    return HttpResponse::json_resp(
                        400,
                        json!({ "error": "Bad Request", "message": "Invalid input" }),
                    )
                }
            };
            match ShareService::accept_link(&ctx.store, &token, &user.id, &user.email) {
                Ok(res) => HttpResponse::json_resp(200, json!({ "data": res })),
                Err(e) => map_app_error(e),
            }
        }
        _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
    }
}

fn handle_space_group_routes(
    ctx: &AppContext,
    req: &HttpRequest,
    method: &str,
    sub: &str,
) -> HttpResponse {
    let user = match authenticate_request(req, &ctx.jwt_secret, false) {
        Ok(u) => u,
        Err(resp) => return resp,
    };
    let device_id = get_device_id(&req.headers);

    if sub.is_empty() || sub == "/" {
        match method {
            "GET" => match SpaceGroupService::get_all_space_groups(&ctx.store, &user.id) {
                Ok(groups) => HttpResponse::json_resp(200, json!({ "data": groups })),
                Err(e) => map_app_error(e),
            },
            "POST" => {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let input = match parse_space_group_create_schema(&body) {
                    Ok(i) => i,
                    Err(e) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": e.message() }),
                        )
                    }
                };
                match SpaceGroupService::create_space_group(
                    &ctx.store,
                    ctx.redis.as_ref(),
                    &user.id,
                    input,
                    device_id.as_deref(),
                ) {
                    Ok(group) => HttpResponse::json_resp(201, json!({ "data": group })),
                    Err(e) => {
                        if matches!(e, AppError::SchemaDrift { .. }) {
                            return map_app_error(e);
                        }
                        HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": e.message() }),
                        )
                    }
                }
            }
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else if let Some(group_id) = sub.strip_prefix('/') {
        match method {
            "GET" => match SpaceGroupService::get_space_group_by_id(&ctx.store, &user.id, group_id)
            {
                Ok(group) => HttpResponse::json_resp(200, json!({ "data": group })),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        404,
                        json!({ "error": "Not Found", "message": e.message() }),
                    )
                }
            },
            "PUT" => {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let input = match parse_space_group_update_schema(&body) {
                    Ok(i) => i,
                    Err(e) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": e.message() }),
                        )
                    }
                };
                match SpaceGroupService::update_space_group(
                    &ctx.store,
                    ctx.redis.as_ref(),
                    &user.id,
                    group_id,
                    input,
                    device_id.as_deref(),
                ) {
                    Ok(group) => {
                        publish_sync_event(
                            ctx.redis.as_ref(),
                            &user.id,
                            SyncEventInput {
                                entity_type: "spaceGroup",
                                action: "save",
                                entity_id: group_id,
                                version: Some(group.version),
                                updated_at: group.updated_at.clone(),
                                from_device: device_id.as_deref().unwrap_or("unknown"),
                            },
                        );
                        HttpResponse::json_resp(200, json!({ "data": group }))
                    }
                    Err(AppError::Conflict { .. }) => {
                        match SpaceGroupService::get_space_group_by_id(
                            &ctx.store, &user.id, group_id,
                        ) {
                            Ok(current) => HttpResponse::json_resp(
                                409,
                                json!({ "error": "Conflict", "data": current }),
                            ),
                            Err(e) => map_app_error(e),
                        }
                    }
                    Err(e) if e.message() == "Space group not found" => {
                        if is_tombstoned(ctx.redis.as_ref(), &user.id, "spaceGroup", group_id) {
                            return HttpResponse::json_resp(
                                410,
                                json!({ "error": "Gone", "message": "Entity was deleted" }),
                            );
                        }
                        // Upsert: create then update
                        let mut create_input = match parse_space_group_create_schema(&body) {
                            Ok(ci) => ci,
                            Err(ce) => {
                                return HttpResponse::json_resp(
                                    400,
                                    json!({ "error": "Bad Request", "message": ce.message() }),
                                )
                            }
                        };
                        create_input.id = Some(group_id.to_string());
                        if let Err(ce) = SpaceGroupService::create_space_group(
                            &ctx.store,
                            ctx.redis.as_ref(),
                            &user.id,
                            create_input,
                            device_id.as_deref(),
                        ) {
                            return HttpResponse::json_resp(
                                400,
                                json!({ "error": "Bad Request", "message": ce.message() }),
                            );
                        }
                        let upd_input = parse_space_group_update_schema(&body).unwrap_or_default();
                        match SpaceGroupService::update_space_group(
                            &ctx.store,
                            ctx.redis.as_ref(),
                            &user.id,
                            group_id,
                            upd_input,
                            device_id.as_deref(),
                        ) {
                            Ok(group) => {
                                publish_sync_event(
                                    ctx.redis.as_ref(),
                                    &user.id,
                                    SyncEventInput {
                                        entity_type: "spaceGroup",
                                        action: "save",
                                        entity_id: group_id,
                                        version: Some(group.version),
                                        updated_at: group.updated_at.clone(),
                                        from_device: device_id.as_deref().unwrap_or("unknown"),
                                    },
                                );
                                HttpResponse::json_resp(200, json!({ "data": group }))
                            }
                            Err(ue) => HttpResponse::json_resp(
                                400,
                                json!({ "error": "Bad Request", "message": ue.message() }),
                            ),
                        }
                    }
                    Err(e) => {
                        if matches!(e, AppError::SchemaDrift { .. }) {
                            return map_app_error(e);
                        }
                        HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": e.message() }),
                        )
                    }
                }
            }
            "DELETE" => {
                if let Err(e) = SpaceGroupService::delete_space_group(
                    &ctx.store,
                    ctx.redis.as_ref(),
                    &user.id,
                    group_id,
                    device_id.as_deref(),
                ) {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    return HttpResponse::json_resp(
                        404,
                        json!({ "error": "Not Found", "message": e.message() }),
                    );
                }
                mark_entity_deleted(ctx.redis.as_ref(), &user.id, "spaceGroup", group_id);
                publish_sync_event(
                    ctx.redis.as_ref(),
                    &user.id,
                    SyncEventInput {
                        entity_type: "spaceGroup",
                        action: "delete",
                        entity_id: group_id,
                        version: None,
                        updated_at: now_iso8601(),
                        from_device: device_id.as_deref().unwrap_or("unknown"),
                    },
                );
                HttpResponse::empty(204)
            }
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else {
        HttpResponse::json_resp(404, json!({ "error": "Not Found" }))
    }
}

fn handle_backup_routes(
    ctx: &AppContext,
    req: &HttpRequest,
    method: &str,
    sub: &str,
    query: &HashMap<String, String>,
) -> HttpResponse {
    let user = match authenticate_request(req, &ctx.jwt_secret, false) {
        Ok(u) => u,
        Err(resp) => return resp,
    };

    if sub.is_empty() || sub == "/" {
        match method {
            "GET" => {
                let parsed_q = match parse_backup_list_query(query) {
                    Ok(q) => q,
                    Err(AppError::BadRequest {
                        details: Some(details),
                        ..
                    }) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({
                                "error": "Validation Error",
                                "message": "Invalid query parameters",
                                "details": details,
                            }),
                        )
                    }
                    Err(e) => return map_app_error(e),
                };
                match BackupService::list_backups(&ctx.store, &user.id, parsed_q) {
                    Ok(res) => HttpResponse::json_resp(200, json!({ "data": res })),
                    Err(e) => {
                        if matches!(e, AppError::SchemaDrift { .. }) {
                            return map_app_error(e);
                        }
                        HttpResponse::json_resp(
                            500,
                            json!({
                                "error": "Internal Server Error",
                                "message": "Failed to list backups",
                            }),
                        )
                    }
                }
            }
            "POST" => {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let input = match parse_backup_create_schema(&body) {
                    Ok(i) => i,
                    Err(AppError::BadRequest {
                        details: Some(details),
                        ..
                    }) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({
                                "error": "Validation Error",
                                "message": "Invalid request body",
                                "details": details,
                            }),
                        )
                    }
                    Err(e) => return map_app_error(e),
                };
                match BackupService::create_backup(&ctx.store, &user.id, &user.tier, input) {
                    Ok(backup) => HttpResponse::json_resp(201, json!({ "data": backup })),
                    Err(e) => {
                        if matches!(e, AppError::SchemaDrift { .. }) {
                            return map_app_error(e);
                        }
                        let msg = e.message();
                        if msg.contains("limit") {
                            return HttpResponse::json_resp(
                                403,
                                json!({ "error": "Forbidden", "message": msg }),
                            );
                        }
                        if msg.contains("not found") {
                            return HttpResponse::json_resp(
                                404,
                                json!({ "error": "Not Found", "message": msg }),
                            );
                        }
                        HttpResponse::json_resp(
                            500,
                            json!({
                                "error": "Internal Server Error",
                                "message": "Failed to create backup",
                            }),
                        )
                    }
                }
            }
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else if method == "GET" && sub == "/stats" {
        match BackupService::get_backup_stats(&ctx.store, &user.id) {
            Ok(stats) => HttpResponse::json_resp(200, json!({ "data": stats })),
            Err(e) => {
                if matches!(e, AppError::SchemaDrift { .. }) {
                    return map_app_error(e);
                }
                HttpResponse::json_resp(
                    500,
                    json!({
                        "error": "Internal Server Error",
                        "message": "Failed to get backup stats",
                    }),
                )
            }
        }
    } else if let Some(rest) = sub.strip_prefix('/') {
        if let Some(backup_id) = rest.strip_suffix("/restore") {
            if method == "POST" {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let input = match parse_backup_restore_schema(&body) {
                    Ok(i) => i,
                    Err(AppError::BadRequest {
                        details: Some(details),
                        ..
                    }) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({
                                "error": "Validation Error",
                                "message": "Invalid request body",
                                "details": details,
                            }),
                        )
                    }
                    Err(e) => return map_app_error(e),
                };
                return match BackupService::restore_backup(&ctx.store, &user.id, backup_id, input) {
                    Ok(restored_ids) => HttpResponse::json_resp(
                        200,
                        json!({
                            "data": {
                                "restoredWorkspaces": restored_ids,
                                "message": format!("Successfully restored {} workspace(s)", restored_ids.len()),
                            }
                        }),
                    ),
                    Err(e) => {
                        if matches!(e, AppError::SchemaDrift { .. }) {
                            return map_app_error(e);
                        }
                        let msg = e.message();
                        if msg.contains("not found") {
                            return HttpResponse::json_resp(
                                404,
                                json!({ "error": "Not Found", "message": msg }),
                            );
                        }
                        if msg.contains("not supported") {
                            return HttpResponse::json_resp(
                                400,
                                json!({ "error": "Bad Request", "message": msg }),
                            );
                        }
                        HttpResponse::json_resp(
                            500,
                            json!({
                                "error": "Internal Server Error",
                                "message": "Failed to restore backup",
                            }),
                        )
                    }
                };
            }
        }
        match method {
            "GET" => match BackupService::get_backup(&ctx.store, &user.id, rest) {
                Ok(Some(b)) => HttpResponse::json_resp(200, json!({ "data": b })),
                Ok(None) => HttpResponse::json_resp(
                    404,
                    json!({ "error": "Not Found", "message": "Backup not found" }),
                ),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Internal Server Error",
                            "message": "Failed to get backup",
                        }),
                    )
                }
            },
            "DELETE" => match BackupService::delete_backup(&ctx.store, &user.id, rest) {
                Ok(true) => HttpResponse::empty(204),
                Ok(false) => HttpResponse::json_resp(
                    404,
                    json!({ "error": "Not Found", "message": "Backup not found" }),
                ),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Internal Server Error",
                            "message": "Failed to delete backup",
                        }),
                    )
                }
            },
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else {
        HttpResponse::json_resp(404, json!({ "error": "Not Found" }))
    }
}

fn handle_sync_routes(
    ctx: &AppContext,
    req: &HttpRequest,
    method: &str,
    sub: &str,
    query: &HashMap<String, String>,
) -> HttpResponse {
    if method == "GET" && sub == "/stream" {
        let user = match authenticate_request(req, &ctx.jwt_secret, true) {
            Ok(u) => u,
            Err(resp) => return resp,
        };
        let mut sub_handle = ctx
            .redis
            .subscribe(&format!("sync:updates:{}", user.id))
            .ok();
        let mut body = format!(
            "event: connected\ndata: {}\n\n",
            json!({ "timestamp": now_iso8601() })
        );
        if let Some(ref mut s) = sub_handle {
            while let Ok(msg) = s.receiver.try_recv() {
                body.push_str(&format!("event: sync\ndata: {msg}\n\n"));
            }
            s.close();
        }
        let mut headers = HashMap::new();
        headers.insert("content-type".to_string(), "text/event-stream".to_string());
        headers.insert("cache-control".to_string(), "no-cache".to_string());
        headers.insert("connection".to_string(), "keep-alive".to_string());
        return HttpResponse {
            status: 200,
            headers,
            body,
        };
    }

    let user = match authenticate_request(req, &ctx.jwt_secret, false) {
        Ok(u) => u,
        Err(resp) => return resp,
    };

    match (method, sub) {
        ("POST", "/push") => {
            let body = match parse_request_json_body(req) {
                Ok(b) => b,
                Err(resp) => return resp,
            };
            let input = match parse_sync_push_schema(&body) {
                Ok(i) => i,
                Err(AppError::BadRequest {
                    details: Some(details),
                    ..
                }) => {
                    return HttpResponse::json_resp(
                        400,
                        json!({
                            "error": "Validation Error",
                            "message": "Invalid request body",
                            "details": details,
                        }),
                    )
                }
                Err(e) => return map_app_error(e),
            };
            match SyncService::push_changes(
                &ctx.store,
                ctx.redis.as_ref(),
                &user.id,
                &user.tier,
                input,
            ) {
                Ok(res) => HttpResponse::json_resp(200, json!({ "data": res })),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Internal Server Error",
                            "message": "Failed to push sync changes",
                        }),
                    )
                }
            }
        }
        ("POST", "/pull") | ("GET", "/pull") => {
            let raw_input = if method == "GET" {
                let mut m = Map::new();
                for (k, v) in query {
                    if k == "entityTypes" {
                        let arr: Vec<Value> = v
                            .split(',')
                            .filter(|s| !s.is_empty())
                            .map(|s| Value::String(s.to_string()))
                            .collect();
                        m.insert(k.clone(), Value::Array(arr));
                    } else {
                        m.insert(k.clone(), Value::String(v.clone()));
                    }
                }
                Value::Object(m)
            } else {
                match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                }
            };
            let input = match parse_sync_pull_schema(&raw_input) {
                Ok(i) => i,
                Err(AppError::BadRequest {
                    details: Some(details),
                    ..
                }) => {
                    return HttpResponse::json_resp(
                        400,
                        json!({
                            "error": "Validation Error",
                            "message": "Invalid request body",
                            "details": details,
                        }),
                    )
                }
                Err(e) => return map_app_error(e),
            };
            if let Err(e) = ctx.store.check_injected_error() {
                if matches!(e, AppError::SchemaDrift { .. }) {
                    return map_app_error(e);
                }
                return HttpResponse::json_resp(
                    500,
                    json!({
                        "error": "Internal Server Error",
                        "message": "Failed to pull sync changes",
                    }),
                );
            }
            match SyncService::pull_changes(ctx.redis.as_ref(), &user.id, input) {
                Ok(res) => HttpResponse::json_resp(200, json!({ "data": res })),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Internal Server Error",
                            "message": "Failed to pull sync changes",
                        }),
                    )
                }
            }
        }
        ("GET", "/status") | ("GET", "/state") => {
            if let Err(e) = ctx.store.check_injected_error() {
                if matches!(e, AppError::SchemaDrift { .. }) {
                    return map_app_error(e);
                }
                return HttpResponse::json_resp(
                    500,
                    json!({
                        "error": "Internal Server Error",
                        "message": "Failed to get sync status",
                    }),
                );
            }
            match SyncService::get_sync_status(ctx.redis.as_ref(), &user.id) {
                Ok(status) => HttpResponse::json_resp(200, json!({ "data": status })),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        500,
                        json!({
                            "error": "Internal Server Error",
                            "message": "Failed to get sync status",
                        }),
                    )
                }
            }
        }
        _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
    }
}

fn handle_workspace_routes(
    ctx: &AppContext,
    req: &HttpRequest,
    method: &str,
    sub: &str,
) -> HttpResponse {
    let user = match authenticate_request(req, &ctx.jwt_secret, false) {
        Ok(u) => u,
        Err(resp) => return resp,
    };
    let device_id = get_device_id(&req.headers);

    if sub.is_empty() || sub == "/" {
        match method {
            "GET" => match WorkspaceService::get_all_workspaces(&ctx.store, &user.id) {
                Ok(list) => {
                    let transformed: Vec<Value> =
                        list.iter().map(transform_workspace_response).collect();
                    HttpResponse::json_resp(200, json!({ "data": transformed }))
                }
                Err(e) => map_app_error(e),
            },
            "POST" => {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let input = match parse_workspace_create_schema(&body) {
                    Ok(i) => i,
                    Err(_) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": "Invalid input" }),
                        )
                    }
                };
                match WorkspaceService::create_workspace(
                    &ctx.store,
                    ctx.redis.as_ref(),
                    &user.id,
                    &user.tier,
                    input,
                    device_id.as_deref(),
                ) {
                    Ok(ws) => HttpResponse::json_resp(
                        201,
                        json!({ "data": transform_workspace_response(&ws) }),
                    ),
                    Err(e) => {
                        if matches!(e, AppError::SchemaDrift { .. }) {
                            return map_app_error(e);
                        }
                        if e.message().contains("Maximum number") {
                            return HttpResponse::json_resp(
                                403,
                                json!({ "error": "Forbidden", "message": e.message() }),
                            );
                        }
                        HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": "Invalid input" }),
                        )
                    }
                }
            }
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else if method == "GET" && sub == "/shared-with-me" {
        match PermissionService::list_spaces_shared_with(&ctx.store, &user.id) {
            Ok(spaces) => HttpResponse::json_resp(200, json!({ "data": spaces })),
            Err(e) => map_app_error(e),
        }
    } else if method == "POST" && sub == "/tabs/move" {
        let body = match parse_request_json_body(req) {
            Ok(b) => b,
            Err(resp) => return resp,
        };
        let input = match parse_tab_move_schema(&body) {
            Ok(i) => i,
            Err(_) => {
                return HttpResponse::json_resp(
                    400,
                    json!({ "error": "Bad Request", "message": "Invalid input" }),
                )
            }
        };
        match WorkspaceService::move_tab_with_position(
            &ctx.store,
            &user.id,
            &input.tab_id,
            &input.target_workspace_id,
            input.position,
        ) {
            Ok(tab) => HttpResponse::json_resp(200, json!({ "data": tab })),
            Err(AppError::Forbidden { message }) => {
                HttpResponse::json_resp(403, json!({ "error": "Forbidden", "message": message }))
            }
            Err(e) if e.message().contains("not found") => HttpResponse::json_resp(
                404,
                json!({ "error": "Not Found", "message": e.message() }),
            ),
            Err(e) => {
                if matches!(e, AppError::SchemaDrift { .. }) {
                    return map_app_error(e);
                }
                HttpResponse::json_resp(
                    400,
                    json!({ "error": "Bad Request", "message": "Invalid input" }),
                )
            }
        }
    } else if method == "POST" && sub == "/tabs/reorder" {
        let body = match parse_request_json_body(req) {
            Ok(b) => b,
            Err(resp) => return resp,
        };
        let input = match parse_tab_reorder_schema(&body) {
            Ok(i) => i,
            Err(_) => {
                return HttpResponse::json_resp(
                    400,
                    json!({ "error": "Bad Request", "message": "Invalid input" }),
                )
            }
        };
        match WorkspaceService::reorder_tab(&ctx.store, &user.id, &input.tab_id, input.new_position)
        {
            Ok(tab) => HttpResponse::json_resp(200, json!({ "data": tab })),
            Err(AppError::Forbidden { message }) => {
                HttpResponse::json_resp(403, json!({ "error": "Forbidden", "message": message }))
            }
            Err(e) if e.message().contains("not found") => HttpResponse::json_resp(
                404,
                json!({ "error": "Not Found", "message": e.message() }),
            ),
            Err(e) => {
                if matches!(e, AppError::SchemaDrift { .. }) {
                    return map_app_error(e);
                }
                HttpResponse::json_resp(
                    400,
                    json!({ "error": "Bad Request", "message": "Invalid input" }),
                )
            }
        }
    } else if method == "POST" && sub == "/tabs/bulk" {
        let body = match parse_request_json_body(req) {
            Ok(b) => b,
            Err(resp) => return resp,
        };
        let input = match parse_tab_bulk_operation_schema(&body) {
            Ok(i) => i,
            Err(_) => {
                return HttpResponse::json_resp(
                    400,
                    json!({ "error": "Bad Request", "message": "Invalid input" }),
                )
            }
        };
        match input.operation.as_str() {
            "close" => {
                match WorkspaceService::bulk_delete_tabs(&ctx.store, &user.id, &input.tab_ids) {
                    Ok(deleted) => {
                        HttpResponse::json_resp(200, json!({ "data": { "deleted": deleted } }))
                    }
                    Err(AppError::Forbidden { message }) => HttpResponse::json_resp(
                        403,
                        json!({ "error": "Forbidden", "message": message }),
                    ),
                    Err(AppError::NotFound { message }) => HttpResponse::json_resp(
                        404,
                        json!({ "error": "Not Found", "message": message }),
                    ),
                    Err(e) => {
                        if matches!(e, AppError::SchemaDrift { .. }) {
                            return map_app_error(e);
                        }
                        HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": "Invalid input" }),
                        )
                    }
                }
            }
            "pin" | "unpin" => match WorkspaceService::bulk_update_tabs(
                &ctx.store,
                &user.id,
                &input.tab_ids,
                &input.operation,
            ) {
                Ok(updated) => {
                    HttpResponse::json_resp(200, json!({ "data": { "updated": updated } }))
                }
                Err(AppError::Forbidden { message }) => HttpResponse::json_resp(
                    403,
                    json!({ "error": "Forbidden", "message": message }),
                ),
                Err(AppError::NotFound { message }) => HttpResponse::json_resp(
                    404,
                    json!({ "error": "Not Found", "message": message }),
                ),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        400,
                        json!({ "error": "Bad Request", "message": "Invalid input" }),
                    )
                }
            },
            "suspend" => HttpResponse::json_resp(
                400,
                json!({
                    "error": "Bad Request",
                    "message": "Suspend operation should be handled on client side",
                }),
            ),
            _ => HttpResponse::json_resp(
                400,
                json!({ "error": "Bad Request", "message": "Invalid input" }),
            ),
        }
    } else if let Some(rest) = sub.strip_prefix('/') {
        // Check nested workspace subroutes:
        // /:id/tabs, /:id/collaborators, /:id/collaborators/:collaboratorId, /:id/share-links, /:id/share-links/:linkId
        if let Some((ws_id, tail)) = rest.split_once('/') {
            return handle_workspace_nested_routes(ctx, req, &user, method, ws_id, tail);
        }

        let ws_id = rest;
        match method {
            "GET" => match WorkspaceService::get_workspace_by_id(&ctx.store, &user.id, ws_id) {
                Ok(ws) => HttpResponse::json_resp(
                    200,
                    json!({ "data": transform_workspace_response(&ws) }),
                ),
                Err(e) => {
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    HttpResponse::json_resp(
                        404,
                        json!({ "error": "Not Found", "message": "Workspace not found" }),
                    )
                }
            },
            "PUT" => {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let input = match parse_workspace_update_schema(&body) {
                    Ok(i) => i,
                    Err(_) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": "Invalid input" }),
                        )
                    }
                };
                match WorkspaceService::update_workspace(
                    &ctx.store,
                    ctx.redis.as_ref(),
                    &user.id,
                    ws_id,
                    input,
                    device_id.as_deref(),
                ) {
                    Ok(ws) => {
                        publish_workspace_save_event(
                            ctx,
                            &user.id,
                            ws_id,
                            &ws,
                            device_id.as_deref(),
                        );
                        HttpResponse::json_resp(
                            200,
                            json!({ "data": transform_workspace_response(&ws) }),
                        )
                    }
                    Err(AppError::Conflict { .. }) => {
                        match WorkspaceService::get_workspace_by_id(&ctx.store, &user.id, ws_id) {
                            Ok(current) => HttpResponse::json_resp(
                                409,
                                json!({
                                    "error": "Conflict",
                                    "data": transform_workspace_response(&current),
                                }),
                            ),
                            Err(e) => map_app_error(e),
                        }
                    }
                    Err(AppError::Forbidden { message }) => HttpResponse::json_resp(
                        403,
                        json!({ "error": "Forbidden", "message": message }),
                    ),
                    Err(AppError::NotFound { .. }) => {
                        if is_tombstoned(ctx.redis.as_ref(), &user.id, "workspace", ws_id) {
                            return HttpResponse::json_resp(
                                410,
                                json!({ "error": "Gone", "message": "Entity was deleted" }),
                            );
                        }
                        if WorkspaceService::exists(&ctx.store, ws_id) {
                            return HttpResponse::json_resp(
                                404,
                                json!({
                                    "error": "Not Found",
                                    "message": "Workspace not found",
                                }),
                            );
                        }
                        let mut create_input = match parse_workspace_create_schema(&body) {
                            Ok(ci) => ci,
                            Err(ce) => {
                                return HttpResponse::json_resp(
                                    400,
                                    json!({
                                        "error": "Bad Request",
                                        "message": ce.message(),
                                    }),
                                )
                            }
                        };
                        create_input.id = Some(ws_id.to_string());
                        if let Err(ce) = WorkspaceService::create_workspace(
                            &ctx.store,
                            ctx.redis.as_ref(),
                            &user.id,
                            &user.tier,
                            create_input,
                            device_id.as_deref(),
                        ) {
                            let msg = if ce.message().contains("Maximum number") {
                                ce.message().to_string()
                            } else {
                                "Invalid input for upsert".to_string()
                            };
                            return HttpResponse::json_resp(
                                400,
                                json!({ "error": "Bad Request", "message": msg }),
                            );
                        }
                        let upd_input = parse_workspace_update_schema(&body).unwrap_or_default();
                        match WorkspaceService::update_workspace(
                            &ctx.store,
                            ctx.redis.as_ref(),
                            &user.id,
                            ws_id,
                            upd_input,
                            device_id.as_deref(),
                        ) {
                            Ok(ws) => {
                                publish_workspace_save_event(
                                    ctx,
                                    &user.id,
                                    ws_id,
                                    &ws,
                                    device_id.as_deref(),
                                );
                                HttpResponse::json_resp(
                                    200,
                                    json!({ "data": transform_workspace_response(&ws) }),
                                )
                            }
                            Err(ue) => HttpResponse::json_resp(
                                400,
                                json!({
                                    "error": "Bad Request",
                                    "message": ue.message(),
                                }),
                            ),
                        }
                    }
                    Err(e) => {
                        if matches!(e, AppError::SchemaDrift { .. }) {
                            return map_app_error(e);
                        }
                        let msg = if e.message().contains("Maximum number") {
                            e.message().to_string()
                        } else {
                            "Invalid input".to_string()
                        };
                        HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": msg }),
                        )
                    }
                }
            }
            "DELETE" => {
                let recipients = PermissionService::list_access_user_ids(&ctx.store, ws_id)
                    .unwrap_or_else(|_| vec![user.id.clone()]);
                if let Err(e) = WorkspaceService::delete_workspace(
                    &ctx.store,
                    ctx.redis.as_ref(),
                    &user.id,
                    ws_id,
                    device_id.as_deref(),
                ) {
                    if let AppError::Forbidden { message } = e {
                        return HttpResponse::json_resp(
                            403,
                            json!({ "error": "Forbidden", "message": message }),
                        );
                    }
                    if matches!(e, AppError::SchemaDrift { .. }) {
                        return map_app_error(e);
                    }
                    return HttpResponse::json_resp(
                        404,
                        json!({ "error": "Not Found", "message": e.message() }),
                    );
                }
                let notify_ids = if recipients.is_empty() {
                    vec![user.id.clone()]
                } else {
                    recipients
                };
                for uid in notify_ids {
                    mark_entity_deleted(ctx.redis.as_ref(), &uid, "workspace", ws_id);
                    publish_sync_event(
                        ctx.redis.as_ref(),
                        &uid,
                        SyncEventInput {
                            entity_type: "workspace",
                            action: "delete",
                            entity_id: ws_id,
                            version: None,
                            updated_at: now_iso8601(),
                            from_device: device_id.as_deref().unwrap_or("unknown"),
                        },
                    );
                }
                HttpResponse::empty(204)
            }
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else {
        HttpResponse::json_resp(404, json!({ "error": "Not Found" }))
    }
}

fn publish_workspace_save_event(
    ctx: &AppContext,
    fallback_user_id: &str,
    workspace_id: &str,
    ws: &Value,
    device_id: Option<&str>,
) {
    let version = ws.get("version").and_then(Value::as_u64);
    let updated_at = ws
        .get("updatedAt")
        .and_then(Value::as_str)
        .map(|s| s.to_string())
        .unwrap_or_else(now_iso8601);
    let recipients = match PermissionService::list_access_user_ids(&ctx.store, workspace_id) {
        Ok(ids) if !ids.is_empty() => ids,
        _ => vec![fallback_user_id.to_string()],
    };
    for uid in recipients {
        publish_sync_event(
            ctx.redis.as_ref(),
            &uid,
            SyncEventInput {
                entity_type: "workspace",
                action: "save",
                entity_id: workspace_id,
                version,
                updated_at: updated_at.clone(),
                from_device: device_id.unwrap_or("unknown"),
            },
        );
    }
}

fn handle_workspace_nested_routes(
    ctx: &AppContext,
    req: &HttpRequest,
    user: &AuthenticatedUser,
    method: &str,
    ws_id: &str,
    tail: &str,
) -> HttpResponse {
    if method == "POST" && tail == "tabs" {
        let body = match parse_request_json_body(req) {
            Ok(b) => b,
            Err(resp) => return resp,
        };
        let tabs = match parse_save_tabs_schema(&body) {
            Ok(t) => t,
            Err(_) => {
                return HttpResponse::json_resp(
                    400,
                    json!({ "error": "Bad Request", "message": "Invalid input" }),
                )
            }
        };
        let device_id = get_device_id(&req.headers);
        return match WorkspaceService::save_tabs_to_workspace(
            &ctx.store,
            ctx.redis.as_ref(),
            &user.id,
            ws_id,
            &tabs,
            device_id.as_deref(),
        ) {
            Ok(ws) => HttpResponse::json_resp(200, json!({ "data": ws })),
            Err(AppError::Forbidden { message }) => {
                HttpResponse::json_resp(403, json!({ "error": "Forbidden", "message": message }))
            }
            Err(AppError::NotFound { message }) => {
                HttpResponse::json_resp(404, json!({ "error": "Not Found", "message": message }))
            }
            Err(e) => {
                if matches!(e, AppError::SchemaDrift { .. }) {
                    return map_app_error(e);
                }
                HttpResponse::json_resp(
                    400,
                    json!({ "error": "Bad Request", "message": "Invalid input" }),
                )
            }
        };
    }

    // Sharing routes under /:id/collaborators and /:id/share-links
    if tail == "collaborators" {
        match method {
            "GET" => {
                if let Err(e) =
                    PermissionService::require_role(&ctx.store, &user.id, ws_id, "owner")
                {
                    return map_app_error(e);
                }
                match CollaboratorService::list_collaborators(&ctx.store, ws_id) {
                    Ok(list) => HttpResponse::json_resp(200, json!({ "data": list })),
                    Err(e) => map_app_error(e),
                }
            }
            "POST" => {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let (email, role) = match parse_share_by_email_schema(&body) {
                    Ok(v) => v,
                    Err(_) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": "Invalid input" }),
                        )
                    }
                };
                if let Err(e) =
                    PermissionService::require_role(&ctx.store, &user.id, ws_id, "owner")
                {
                    return map_app_error(e);
                }
                match CollaboratorService::share_by_email(
                    &ctx.store, ws_id, &user.id, &email, &role,
                ) {
                    Ok(grant) => HttpResponse::json_resp(201, json!({ "data": grant })),
                    Err(e) => map_app_error(e),
                }
            }
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else if let Some(collab_id) = tail.strip_prefix("collaborators/") {
        match method {
            "PATCH" => {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let role = match parse_set_collaborator_role_schema(&body) {
                    Ok(r) => r,
                    Err(_) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": "Invalid input" }),
                        )
                    }
                };
                if let Err(e) =
                    PermissionService::require_role(&ctx.store, &user.id, ws_id, "owner")
                {
                    return map_app_error(e);
                }
                match CollaboratorService::set_role(&ctx.store, ws_id, collab_id, &role) {
                    Ok(grant) => HttpResponse::json_resp(200, json!({ "data": grant })),
                    Err(e) => map_app_error(e),
                }
            }
            "DELETE" => {
                if let Err(e) =
                    PermissionService::require_role(&ctx.store, &user.id, ws_id, "owner")
                {
                    return map_app_error(e);
                }
                match CollaboratorService::revoke(&ctx.store, ws_id, collab_id) {
                    Ok(()) => HttpResponse::empty(204),
                    Err(e) => map_app_error(e),
                }
            }
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else if tail == "share-links" {
        match method {
            "GET" => {
                if let Err(e) =
                    PermissionService::require_role(&ctx.store, &user.id, ws_id, "owner")
                {
                    return map_app_error(e);
                }
                match ShareService::list_links(&ctx.store, ws_id) {
                    Ok(links) => HttpResponse::json_resp(200, json!({ "data": links })),
                    Err(e) => map_app_error(e),
                }
            }
            "POST" => {
                let body = match parse_request_json_body(req) {
                    Ok(b) => b,
                    Err(resp) => return resp,
                };
                let input = match parse_create_share_link_schema(&body) {
                    Ok(i) => i,
                    Err(_) => {
                        return HttpResponse::json_resp(
                            400,
                            json!({ "error": "Bad Request", "message": "Invalid input" }),
                        )
                    }
                };
                if let Err(e) =
                    PermissionService::require_role(&ctx.store, &user.id, ws_id, "owner")
                {
                    return map_app_error(e);
                }
                match ShareService::create_link(
                    &ctx.store,
                    ws_id,
                    &user.id,
                    &input.role,
                    input.label,
                    input.expires_at,
                ) {
                    Ok(link) => HttpResponse::json_resp(201, json!({ "data": link })),
                    Err(e) => map_app_error(e),
                }
            }
            _ => HttpResponse::json_resp(404, json!({ "error": "Not Found" })),
        }
    } else if let Some(link_id) = tail.strip_prefix("share-links/") {
        if method == "DELETE" {
            if let Err(e) = PermissionService::require_role(&ctx.store, &user.id, ws_id, "owner") {
                return map_app_error(e);
            }
            return match ShareService::revoke_link(&ctx.store, ws_id, link_id) {
                Ok(()) => HttpResponse::empty(204),
                Err(e) => map_app_error(e),
            };
        }
        HttpResponse::json_resp(404, json!({ "error": "Not Found" }))
    } else {
        HttpResponse::json_resp(404, json!({ "error": "Not Found" }))
    }
}

// ============================================================================
// Native std::net::TcpListener HTTP/1.1 Server
// ============================================================================

pub fn serve_http(ctx: Arc<AppContext>, bind_addr: &str) -> Result<(), String> {
    let listener = TcpListener::bind(bind_addr).map_err(|e| format!("bind {bind_addr}: {e}"))?;
    for incoming in listener.incoming() {
        let Ok(stream) = incoming else {
            continue;
        };
        let ctx_clone = Arc::clone(&ctx);
        std::thread::spawn(move || {
            let _ = handle_tcp_connection(ctx_clone, stream);
        });
    }
    Ok(())
}

fn handle_tcp_connection(ctx: Arc<AppContext>, mut stream: TcpStream) -> std::io::Result<()> {
    let _ = stream.set_read_timeout(Some(Duration::from_secs(10)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(10)));

    let mut reader = BufReader::new(stream.try_clone()?);
    let mut request_line = String::new();
    if reader.read_line(&mut request_line)? == 0 {
        return Ok(());
    }
    let parts: Vec<&str> = request_line.trim().split_whitespace().collect();
    if parts.len() < 2 {
        return Ok(());
    }
    let method = parts[0].to_string();
    let raw_path = parts[1].to_string();

    let mut headers = HashMap::new();
    let mut content_length = 0usize;
    loop {
        let mut line = String::new();
        if reader.read_line(&mut line)? == 0 {
            break;
        }
        let trimmed = line.trim_end_matches(&['\r', '\n'][..]);
        if trimmed.is_empty() {
            break;
        }
        if let Some((k, v)) = trimmed.split_once(':') {
            let key = k.trim().to_ascii_lowercase();
            let val = v.trim().to_string();
            if key == "content-length" {
                content_length = val.parse().unwrap_or(0);
            }
            headers.insert(key, val);
        }
    }

    if method == "OPTIONS" {
        let resp = "HTTP/1.1 204 No Content\r\nAccess-Control-Allow-Origin: *\r\nAccess-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS\r\nAccess-Control-Allow-Headers: Content-Type, Authorization, X-Device-Id\r\nContent-Length: 0\r\n\r\n";
        stream.write_all(resp.as_bytes())?;
        stream.flush()?;
        return Ok(());
    }

    let mut body_bytes = vec![0u8; content_length];
    if content_length > 0 {
        reader.read_exact(&mut body_bytes)?;
    }
    let body = String::from_utf8_lossy(&body_bytes).to_string();

    let req = HttpRequest {
        method,
        raw_path,
        headers,
        body,
    };

    let resp = handle_request(&ctx, &req);
    let status_text = match resp.status {
        200 => "OK",
        201 => "Created",
        204 => "No Content",
        302 => "Found",
        400 => "Bad Request",
        401 => "Unauthorized",
        403 => "Forbidden",
        404 => "Not Found",
        409 => "Conflict",
        410 => "Gone",
        500 => "Internal Server Error",
        503 => "Service Unavailable",
        _ => "OK",
    };

    let mut wire = format!("HTTP/1.1 {} {}\r\n", resp.status, status_text);
    wire.push_str("Access-Control-Allow-Origin: *\r\n");
    wire.push_str("Access-Control-Allow-Credentials: true\r\n");
    for (k, v) in &resp.headers {
        wire.push_str(&format!("{}: {}\r\n", k, v));
    }
    wire.push_str(&format!("Content-Length: {}\r\n\r\n", resp.body.len()));
    stream.write_all(wire.as_bytes())?;
    if !resp.body.is_empty() {
        stream.write_all(resp.body.as_bytes())?;
    }
    stream.flush()?;
    Ok(())
}
