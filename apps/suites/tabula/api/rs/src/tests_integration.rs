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

use crate::crypto::{now_iso8601, uuid_v4};
use crate::server::{handle_request, AppContext, HttpRequest};
use crate::store::{InMemoryRedis, TabRecord, UserRecord};
use crate::tombstones::mark_entity_deleted;
use crate::workos::{WorkOSProvider, WorkOSUser};
use serde_json::{json, Value};
use std::sync::Arc;

struct TestWorkOS {
    user: Option<WorkOSUser>,
    fail_msg: Option<String>,
}

impl WorkOSProvider for TestWorkOS {
    fn get_authorization_url(
        &self,
        client_id: &str,
        provider: &str,
        redirect_uri: &str,
    ) -> Result<String, String> {
        if let Some(err) = &self.fail_msg {
            return Err(err.clone());
        }
        Ok(format!(
            "https://api.workos.com/sso/authorize?client_id={client_id}&provider={provider}&redirect_uri={redirect_uri}"
        ))
    }

    fn authenticate_with_code(&self, _client_id: &str, _code: &str) -> Result<WorkOSUser, String> {
        if let Some(err) = &self.fail_msg {
            return Err(err.clone());
        }
        self.user
            .clone()
            .ok_or_else(|| "Invalid authorization code".to_string())
    }
}

fn setup_test_ctx() -> (AppContext, Arc<InMemoryRedis>) {
    let redis = Arc::new(InMemoryRedis::new());
    let mut ctx = AppContext::new_test();
    ctx.store.clear_all();
    ctx.redis = redis.clone();
    (ctx, redis)
}

fn seed_user(ctx: &AppContext, id: &str, email: &str, tier: &str) -> String {
    ctx.store.put_user(UserRecord {
        id: id.to_string(),
        email: email.to_string(),
        password_hash: None,
        name: Some("Test User".to_string()),
        tier: tier.to_string(),
        created_at: now_iso8601(),
        updated_at: now_iso8601(),
        last_login_at: Some(now_iso8601()),
        preferences: json!({}),
    });
    ctx.sign_user_token(id, email, tier)
}

// ============================================================================
// 1. app.test.ts
// ============================================================================

#[test]
fn integration_app_health_root_404_scanner_and_schema_drift() {
    let (ctx, _) = setup_test_ctx();
    let token = seed_user(&ctx, "user-app-1", "app@example.com", "free");

    // GET /health
    let res_health = handle_request(&ctx, &HttpRequest::new("GET", "/health"));
    assert_eq!(res_health.status, 200);
    assert_eq!(res_health.json()["status"], "ok");
    assert_eq!(res_health.json()["redis"], "connected");

    // GET /
    let res_root = handle_request(&ctx, &HttpRequest::new("GET", "/"));
    assert_eq!(res_root.status, 200);
    assert_eq!(res_root.json()["name"], "Tabula API");
    assert_eq!(res_root.json()["version"], "1.0.0");

    // Unknown route -> 404
    let res_404 = handle_request(&ctx, &HttpRequest::new("GET", "/nonexistent"));
    assert_eq!(res_404.status, 404);

    // Scanner probe -> 404
    for probe in [
        "/wp-admin/setup-config.php",
        "/.env",
        "/.git/config",
        "/phpmyadmin/index.php",
    ] {
        let r = handle_request(&ctx, &HttpRequest::new("GET", probe));
        assert_eq!(r.status, 404);
    }

    // Schema drift P2022 -> 503 Service Unavailable
    ctx.store.set_schema_drift(Some("P2022"));
    let res_drift = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/workspaces").with_auth(&token),
    );
    assert_eq!(res_drift.status, 503);
    assert_eq!(res_drift.json()["error"], "Service Unavailable");
    ctx.store.set_schema_drift(None);
}

// ============================================================================
// 2. emptyJsonBody.test.ts
// ============================================================================

#[test]
fn integration_empty_json_body_accepted_and_invalid_json_rejected() {
    let (ctx, _) = setup_test_ctx();
    let token = seed_user(&ctx, "user-empty-1", "empty@example.com", "pro");

    // POST /api/v1/auth/logout with Content-Type: application/json and empty body
    let res_logout = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/auth/logout")
            .with_header("content-type", "application/json")
            .with_body(""),
    );
    assert_eq!(res_logout.status, 200);
    assert_eq!(res_logout.json()["success"], true);

    // POST /api/v1/backups with Content-Type: application/json; charset=utf-8 and empty body
    let res_backup = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/backups")
            .with_auth(&token)
            .with_header("content-type", "application/json; charset=utf-8")
            .with_body(""),
    );
    assert_eq!(res_backup.status, 201);
    let backup_id = res_backup.json()["data"]["id"]
        .as_str()
        .unwrap()
        .to_string();

    // POST /api/v1/backups/:id/restore with empty JSON body
    let res_restore = handle_request(
        &ctx,
        &HttpRequest::new("POST", &format!("/api/v1/backups/{backup_id}/restore"))
            .with_auth(&token)
            .with_header("content-type", "application/json")
            .with_body(""),
    );
    assert_eq!(res_restore.status, 200);

    // Non-empty malformed JSON still returns 400
    let res_bad_json = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/backups")
            .with_auth(&token)
            .with_header("content-type", "application/json")
            .with_body("{not valid json"),
    );
    assert_eq!(res_bad_json.status, 400);
}

// ============================================================================
// 3. auth.routes.test.ts
// ============================================================================

#[test]
fn integration_auth_routes_login_callback_xss_utf8_refresh_logout() {
    let (mut ctx, _) = setup_test_ctx();
    ctx.workos = Arc::new(TestWorkOS {
        user: Some(WorkOSUser {
            email: Some("nguyen@example.com".to_string()),
            first_name: Some("James".to_string()),
            last_name: Some("Nguyễn </script><script>alert(1)</script>".to_string()),
            profile_picture_url: None,
        }),
        fail_msg: None,
    });

    // 1. GET /api/v1/auth/login -> 302 redirect with validated origin in state
    let login_res = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/auth/login?origin=http://localhost:3001"),
    );
    assert_eq!(login_res.status, 302);
    let loc = login_res.header("location").unwrap();
    assert!(loc.contains("https://api.workos.com/sso/authorize"));
    assert!(loc.contains("http://localhost:3001"));

    // 2. GET /api/v1/auth/callback missing code -> 400
    let missing_code = handle_request(&ctx, &HttpRequest::new("GET", "/api/v1/auth/callback"));
    assert_eq!(missing_code.status, 400);

    // 3. GET /api/v1/auth/callback JSON response
    let cb_json = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/auth/callback?code=valid_code"),
    );
    assert_eq!(cb_json.status, 200);
    let body = cb_json.json();
    assert!(body["token"].as_str().is_some());
    let rt1 = body["refreshToken"].as_str().unwrap().to_string();
    assert_eq!(body["user"]["email"], "nguyen@example.com");

    // 4. GET /api/v1/auth/callback HTML response: UTF-8 charset, XSS escaping, postMessage origin
    let cb_html = handle_request(
        &ctx,
        &HttpRequest::new(
            "GET",
            "/api/v1/auth/callback?code=valid_code&state=%7B%22origin%22%3A%22https%3A%2F%2Fevil.example.com%22%7D",
        )
        .with_header("accept", "text/html"),
    );
    assert_eq!(cb_html.status, 200);
    assert_eq!(
        cb_html.header("content-type"),
        Some("text/html; charset=utf-8")
    );
    assert!(cb_html.body.contains("<meta charset=\"utf-8\">"));
    assert!(cb_html.body.contains("Authentication Successful"));
    assert!(cb_html.body.contains("Nguyễn"));
    // Must escape `</script>` inside JSON block to prevent reflected XSS
    assert!(!cb_html.body.contains("</script><script>alert(1)"));
    assert!(cb_html.body.contains("\\u003c/script\\u003e"));
    // Evil unallowlisted origin falls back to http://localhost:3000 (never "*")
    assert!(cb_html.body.contains("\"http://localhost:3000\""));
    assert!(!cb_html.body.contains("evil.example.com"));

    // 5. POST /api/v1/auth/refresh rotates refresh token and rejects reuse
    let ref_ok = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/auth/refresh")
            .with_json(&json!({ "refreshToken": rt1 })),
    );
    assert_eq!(ref_ok.status, 200);
    let rt2 = ref_ok.json()["refreshToken"].as_str().unwrap().to_string();
    assert_ne!(rt1, rt2);

    // Reusing rt1 returns 401
    let ref_reuse = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/auth/refresh")
            .with_json(&json!({ "refreshToken": rt1 })),
    );
    assert_eq!(ref_reuse.status, 401);

    // 6. POST /api/v1/auth/logout revokes rt2
    let logout_res = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/auth/logout").with_json(&json!({ "refreshToken": rt2 })),
    );
    assert_eq!(logout_res.status, 200);
    let ref_after_logout = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/auth/refresh")
            .with_json(&json!({ "refreshToken": rt2 })),
    );
    assert_eq!(ref_after_logout.status, 401);

    // 7. HTML error page escapes HTML in error message
    ctx.workos = Arc::new(TestWorkOS {
        user: None,
        fail_msg: Some("<img src=x onerror=alert(1)>".to_string()),
    });
    let cb_err_html = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/auth/callback?code=bad")
            .with_header("accept", "text/html"),
    );
    assert_eq!(cb_err_html.status, 200);
    assert!(cb_err_html.body.contains("Authentication Failed"));
    assert!(cb_err_html
        .body
        .contains("&lt;img src=x onerror=alert(1)&gt;"));
    assert!(!cb_err_html.body.contains("<img src=x"));
}

// ============================================================================
// 4. user.routes.test.ts
// ============================================================================

#[test]
fn integration_user_routes_me_update_delete_password_reset_and_error_masking() {
    let (ctx, _) = setup_test_ctx();
    let token = seed_user(&ctx, "user-me-1", "me@example.com", "free");

    // GET /api/v1/users/me
    let get_me = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/users/me").with_auth(&token),
    );
    assert_eq!(get_me.status, 200);
    assert_eq!(get_me.json()["data"]["email"], "me@example.com");

    // PATCH /api/v1/users/me
    let patch_me = handle_request(
        &ctx,
        &HttpRequest::new("PATCH", "/api/v1/users/me")
            .with_auth(&token)
            .with_json(&json!({
                "name": "Alice Updated",
                "preferences": { "compact": true }
            })),
    );
    assert_eq!(patch_me.status, 200);
    assert_eq!(patch_me.json()["data"]["name"], "Alice Updated");
    assert_eq!(patch_me.json()["data"]["preferences"]["compact"], true);

    // Validation error on empty name -> 400
    let patch_bad = handle_request(
        &ctx,
        &HttpRequest::new("PATCH", "/api/v1/users/me")
            .with_auth(&token)
            .with_json(&json!({ "name": "   " })),
    );
    assert_eq!(patch_bad.status, 400);
    assert_eq!(patch_bad.json()["error"], "Validation Error");

    // POST /api/v1/users/password-reset (no auth required)
    let pw_reset = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/users/password-reset")
            .with_json(&json!({ "email": "me@example.com" })),
    );
    assert_eq!(pw_reset.status, 200);
    assert!(pw_reset.json()["data"]["resetUrl"]
        .as_str()
        .unwrap()
        .contains("/api/v1/auth/login?action=reset_password"));

    // Internal error masking: never leaks raw DB error text
    ctx.store
        .set_internal_error(Some("Raw secret postgres error details"));
    let err_500 = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/users/me").with_auth(&token),
    );
    assert_eq!(err_500.status, 500);
    assert_eq!(err_500.json()["message"], "Failed to get user profile");
    assert!(!err_500.body.contains("Raw secret postgres"));
    ctx.store.set_internal_error(None);

    // DELETE /api/v1/users/me
    let del_me = handle_request(
        &ctx,
        &HttpRequest::new("DELETE", "/api/v1/users/me").with_auth(&token),
    );
    assert_eq!(del_me.status, 204);

    // Subsequent GET /api/v1/users/me -> 404
    let get_after = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/users/me").with_auth(&token),
    );
    assert_eq!(get_after.status, 404);
}

// ============================================================================
// 5. workspace.test.ts
// ============================================================================

#[test]
fn integration_workspace_routes_crud_conflict_tombstone_upsert_and_tabs() {
    let (ctx, redis) = setup_test_ctx();
    let uid = "11111111-1111-4111-8111-111111111111";
    let token = seed_user(&ctx, uid, "ws@example.com", "free");

    // 1. POST /api/v1/workspaces
    let create_res = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/workspaces")
            .with_auth(&token)
            .with_json(&json!({
                "name": "Engineering",
                "color": "#4F46E5",
                "tabGroups": [{ "id": "grp-1", "title": "Docs", "color": "blue", "collapsed": false }],
                "tabs": [{
                    "id": 101,
                    "url": "https://example.com",
                    "title": "Example",
                    "favIconUrl": "https://example.com/fav.ico",
                    "pinned": true,
                    "index": 4,
                    "groupId": "grp-1"
                }]
            })),
    );
    assert_eq!(create_res.status, 201);
    let created = create_res.json()["data"].clone();
    let ws_id = created["id"].as_str().unwrap().to_string();
    assert_eq!(created["name"], "Engineering");
    assert_eq!(created["tabGroups"][0]["id"], "grp-1");
    assert_eq!(created["tabs"][0]["groupId"], "grp-1");
    assert_eq!(
        created["tabs"][0]["favIconUrl"],
        "https://example.com/fav.ico"
    );
    assert_eq!(created["tabs"][0]["pinned"], true);
    assert_eq!(created["tabs"][0]["index"], 4);

    // 2. PUT /api/v1/workspaces/:id updates version and publishes save event
    redis.clear_all();
    let put_res = handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/workspaces/{ws_id}"))
            .with_auth(&token)
            .with_header("x-device-id", "device-7")
            .with_json(&json!({
                "name": "Engineering v1",
                "baseVersion": 0
            })),
    );
    assert_eq!(put_res.status, 200);
    assert_eq!(put_res.json()["data"]["version"], 1);
    let published = redis.published_messages();
    assert_eq!(published.len(), 1);
    assert_eq!(published[0].0, format!("sync:updates:{uid}"));
    let ev: Value = serde_json::from_str(&published[0].1).unwrap();
    assert_eq!(ev["type"], "workspace");
    assert_eq!(ev["action"], "save");
    assert_eq!(ev["entityId"], ws_id);
    assert_eq!(ev["version"], 1);
    assert_eq!(ev["fromDevice"], "device-7");

    // 3. Stale baseVersion -> 409 Conflict with server copy
    let conflict_res = handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/workspaces/{ws_id}"))
            .with_auth(&token)
            .with_json(&json!({
                "name": "Stale Write",
                "baseVersion": 0
            })),
    );
    assert_eq!(conflict_res.status, 409);
    assert_eq!(conflict_res.json()["error"], "Conflict");
    assert_eq!(conflict_res.json()["data"]["name"], "Engineering v1");
    assert_eq!(conflict_res.json()["data"]["version"], 1);

    // 4. Upsert-create on non-existent workspace ID
    let upsert_res = handle_request(
        &ctx,
        &HttpRequest::new("PUT", "/api/v1/workspaces/ws-upserted-1")
            .with_auth(&token)
            .with_json(&json!({
                "name": "Upserted Workspace",
                "position": 1,
                "settings": {}
            })),
    );
    assert_eq!(upsert_res.status, 200);
    assert_eq!(upsert_res.json()["data"]["name"], "Upserted Workspace");

    // 5. Existence-masked 404 when PUTting to another user's workspace ID (never overwrites!)
    let other_token = seed_user(
        &ctx,
        "22222222-2222-4222-8222-222222222222",
        "other@example.com",
        "free",
    );
    let hijack_res = handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/workspaces/{ws_id}"))
            .with_auth(&other_token)
            .with_json(&json!({ "name": "Hijacked" })),
    );
    assert_eq!(hijack_res.status, 404);

    // 6. DELETE /api/v1/workspaces/:id tombstones ID; subsequent PUT returns 410 Gone
    let del_res = handle_request(
        &ctx,
        &HttpRequest::new("DELETE", "/api/v1/workspaces/ws-upserted-1").with_auth(&token),
    );
    assert_eq!(del_res.status, 204);

    let zombie_put = handle_request(
        &ctx,
        &HttpRequest::new("PUT", "/api/v1/workspaces/ws-upserted-1")
            .with_auth(&token)
            .with_json(&json!({ "name": "Zombie" })),
    );
    assert_eq!(zombie_put.status, 410);
    assert_eq!(zombie_put.json()["error"], "Gone");

    // 7. Tab move, reorder, and bulk operations
    let ws2_id = uuid_v4();
    handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/workspaces/{ws2_id}"))
            .with_auth(&token)
            .with_json(&json!({ "name": "Target WS", "position": 2, "settings": {} })),
    );
    let tab_uuid = uuid_v4();
    {
        let mut g = ctx.store.inner.lock().unwrap();
        g.tabs.insert(
            tab_uuid.clone(),
            TabRecord {
                id: tab_uuid.clone(),
                workspace_id: ws_id.clone(),
                url: "https://move-me.example.com".to_string(),
                title: Some("Move Me".to_string()),
                favicon_url: None,
                position: 0,
                is_pinned: false,
                created_at: now_iso8601(),
                updated_at: now_iso8601(),
                last_accessed_at: now_iso8601(),
                metadata: json!({}),
            },
        );
    }

    let move_res = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/workspaces/tabs/move")
            .with_auth(&token)
            .with_json(&json!({
                "tabId": tab_uuid,
                "targetWorkspaceId": ws2_id,
                "position": 2
            })),
    );
    assert_eq!(move_res.status, 200);
    assert_eq!(move_res.json()["data"]["workspaceId"], ws2_id);

    let reorder_res = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/workspaces/tabs/reorder")
            .with_auth(&token)
            .with_json(&json!({
                "tabId": tab_uuid,
                "newPosition": 5
            })),
    );
    assert_eq!(reorder_res.status, 200);
    assert_eq!(reorder_res.json()["data"]["position"], 5);

    let bulk_pin = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/workspaces/tabs/bulk")
            .with_auth(&token)
            .with_json(&json!({
                "tabIds": [tab_uuid],
                "operation": "pin"
            })),
    );
    assert_eq!(bulk_pin.status, 200);
    assert_eq!(bulk_pin.json()["data"]["updated"], 1);

    let bulk_suspend = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/workspaces/tabs/bulk")
            .with_auth(&token)
            .with_json(&json!({
                "tabIds": [tab_uuid],
                "operation": "suspend"
            })),
    );
    assert_eq!(bulk_suspend.status, 400);

    let bulk_close = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/workspaces/tabs/bulk")
            .with_auth(&token)
            .with_json(&json!({
                "tabIds": [tab_uuid],
                "operation": "close"
            })),
    );
    assert_eq!(bulk_close.status, 200);
    assert_eq!(bulk_close.json()["data"]["deleted"], 1);
}

// ============================================================================
// 6. spacegroup.test.ts
// ============================================================================

#[test]
fn integration_spacegroup_routes_crud_conflict_tombstone_and_upsert() {
    let (ctx, redis) = setup_test_ctx();
    let uid = "user-sg-int";
    let token = seed_user(&ctx, uid, "sg@example.com", "free");

    // POST /api/v1/space-groups
    let create_res = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/space-groups")
            .with_auth(&token)
            .with_json(&json!({
                "title": "Clients",
                "color": "#10B981",
                "collapsed": false,
                "position": 0
            })),
    );
    assert_eq!(create_res.status, 201);
    let sg_id = create_res.json()["data"]["id"]
        .as_str()
        .unwrap()
        .to_string();

    // PUT /api/v1/space-groups/:id
    redis.clear_all();
    let put_res = handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/space-groups/{sg_id}"))
            .with_auth(&token)
            .with_header("x-device-id", "dev-sg-1")
            .with_json(&json!({
                "title": "Clients v1",
                "baseVersion": 0
            })),
    );
    assert_eq!(put_res.status, 200);
    assert_eq!(put_res.json()["data"]["version"], 1);
    assert_eq!(redis.published_messages().len(), 1);

    // Stale baseVersion -> 409 Conflict with current group
    let conflict_res = handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/space-groups/{sg_id}"))
            .with_auth(&token)
            .with_json(&json!({
                "title": "Stale",
                "baseVersion": 0
            })),
    );
    assert_eq!(conflict_res.status, 409);
    assert_eq!(conflict_res.json()["data"]["title"], "Clients v1");

    // Delete -> tombstones ID; subsequent PUT returns 410 Gone
    let del_res = handle_request(
        &ctx,
        &HttpRequest::new("DELETE", &format!("/api/v1/space-groups/{sg_id}")).with_auth(&token),
    );
    assert_eq!(del_res.status, 204);

    let gone_res = handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/space-groups/{sg_id}"))
            .with_auth(&token)
            .with_json(&json!({ "title": "Zombie Group" })),
    );
    assert_eq!(gone_res.status, 410);
}

// ============================================================================
// 7. backup.test.ts
// ============================================================================

#[test]
fn integration_backup_routes_create_list_stats_restore_and_multi_workspace_guard() {
    let (ctx, _) = setup_test_ctx();
    let uid = "user-bkp-int";
    let token = seed_user(&ctx, uid, "bkp@example.com", "pro");

    // Create 2 workspaces
    for name in ["WS One", "WS Two"] {
        handle_request(
            &ctx,
            &HttpRequest::new("POST", "/api/v1/workspaces")
                .with_auth(&token)
                .with_json(&json!({ "name": name })),
        );
    }

    // Create full backup (contains 2 workspaces)
    let create_bkp = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/backups")
            .with_auth(&token)
            .with_json(&json!({ "name": "Full Snapshot", "type": "manual" })),
    );
    assert_eq!(create_bkp.status, 201);
    let bkp_id = create_bkp.json()["data"]["id"]
        .as_str()
        .unwrap()
        .to_string();

    // Restoring a multi-workspace backup onto a single targetWorkspaceId without createNew: true -> 400
    let bad_restore = handle_request(
        &ctx,
        &HttpRequest::new("POST", &format!("/api/v1/backups/{bkp_id}/restore"))
            .with_auth(&token)
            .with_json(&json!({
                "targetWorkspaceId": "ws-single-target",
                "createNew": false
            })),
    );
    assert_eq!(bad_restore.status, 400);
    assert!(bad_restore.json()["message"]
        .as_str()
        .unwrap()
        .contains("not supported"));

    // Restore with createNew: true -> 200
    let ok_restore = handle_request(
        &ctx,
        &HttpRequest::new("POST", &format!("/api/v1/backups/{bkp_id}/restore"))
            .with_auth(&token)
            .with_json(&json!({ "createNew": true })),
    );
    assert_eq!(ok_restore.status, 200);
    assert_eq!(
        ok_restore.json()["data"]["restoredWorkspaces"]
            .as_array()
            .unwrap()
            .len(),
        2
    );

    // GET /api/v1/backups/stats
    let stats_res = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/backups/stats").with_auth(&token),
    );
    assert_eq!(stats_res.status, 200);
    assert_eq!(stats_res.json()["data"]["totalBackups"], 1);
}

// ============================================================================
// 8 & 9. sync.test.ts + sync.routes.test.ts
// ============================================================================

#[test]
fn integration_sync_routes_push_pull_status_and_sse_stream() {
    let (ctx, redis) = setup_test_ctx();
    let uid = "user-sync-int";
    let token = seed_user(&ctx, uid, "sync@example.com", "pro");

    // 1. Push create workspace
    let push_res = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/sync/push")
            .with_auth(&token)
            .with_json(&json!({
                "deviceId": "dev-1",
                "clientTimestamp": now_iso8601(),
                "changes": [{
                    "type": "workspace",
                    "action": "create",
                    "entityId": "ws-sync-1",
                    "data": { "name": "Synced WS" },
                    "version": 0
                }]
            })),
    );
    assert_eq!(push_res.status, 200);
    assert_eq!(push_res.json()["data"]["accepted"], json!(["ws-sync-1"]));

    // 2. Tombstoned entity is rejected on non-delete push
    mark_entity_deleted(redis.as_ref(), uid, "workspace", "ws-tombstoned");
    let push_tomb = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/sync/push")
            .with_auth(&token)
            .with_json(&json!({
                "deviceId": "dev-1",
                "clientTimestamp": now_iso8601(),
                "changes": [{
                    "type": "workspace",
                    "action": "update",
                    "entityId": "ws-tombstoned",
                    "data": { "name": "Resurrect" },
                    "version": 1
                }]
            })),
    );
    assert_eq!(push_tomb.status, 200);
    assert_eq!(push_tomb.json()["data"]["rejected"][0]["reason"], "deleted");

    // 3. Pull changes from device-2 via POST and GET
    let pull_post = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/sync/pull")
            .with_auth(&token)
            .with_json(&json!({ "deviceId": "dev-2" })),
    );
    assert_eq!(pull_post.status, 200);
    assert_eq!(
        pull_post.json()["data"]["changes"]
            .as_array()
            .unwrap()
            .len(),
        1
    );

    let pull_get = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/sync/pull?deviceId=dev-2").with_auth(&token),
    );
    assert_eq!(pull_get.status, 200);

    // 4. GET /api/v1/sync/status & /api/v1/sync/state
    let status_res = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/sync/status").with_auth(&token),
    );
    assert_eq!(status_res.status, 200);
    assert_eq!(status_res.json()["data"]["syncEnabled"], true);

    // 5. GET /api/v1/sync/stream with ?token=<jwt> query param
    let stream_res = handle_request(
        &ctx,
        &HttpRequest::new("GET", &format!("/api/v1/sync/stream?token={token}")),
    );
    assert_eq!(stream_res.status, 200);
    assert_eq!(stream_res.header("content-type"), Some("text/event-stream"));
    assert!(stream_res.body.contains("event: connected"));
    assert_eq!(redis.unsubscribe_count(), 1);
    assert_eq!(redis.quit_count(), 1);
}

// ============================================================================
// 10 & 11. sharing.test.ts + relay.test.ts
// ============================================================================

#[test]
fn integration_sharing_and_relay_acl_fanout_and_exfiltration_guard() {
    let (ctx, redis) = setup_test_ctx();
    let owner_id = "11111111-1111-4111-8111-111111111111";
    let bob_id = "22222222-2222-4222-8222-222222222222";
    let carol_id = "33333333-3333-4333-8333-333333333333";

    let owner_token = seed_user(&ctx, owner_id, "alice@example.com", "pro");
    let bob_token = seed_user(&ctx, bob_id, "bob@example.com", "free");
    let carol_token = seed_user(&ctx, carol_id, "carol@example.com", "free");

    // Alice creates a workspace
    let ws_id = uuid_v4();
    handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/workspaces/{ws_id}"))
            .with_auth(&owner_token)
            .with_json(&json!({ "name": "Shared Project", "position": 0, "settings": {} })),
    );

    // Alice invites Bob with view role
    let inv_bob = handle_request(
        &ctx,
        &HttpRequest::new("POST", &format!("/api/v1/workspaces/{ws_id}/collaborators"))
            .with_auth(&owner_token)
            .with_json(&json!({ "email": "bob@example.com", "role": "view" })),
    );
    assert_eq!(inv_bob.status, 201);
    let collab_id = inv_bob.json()["data"]["id"].as_str().unwrap().to_string();

    // Bob sees it in /api/v1/workspaces/shared-with-me and can GET, but cannot PUT or DELETE (403)
    let shared_list = handle_request(
        &ctx,
        &HttpRequest::new("GET", "/api/v1/workspaces/shared-with-me").with_auth(&bob_token),
    );
    assert_eq!(shared_list.status, 200);
    assert_eq!(shared_list.json()["data"][0]["workspaceId"], ws_id);

    let bob_get = handle_request(
        &ctx,
        &HttpRequest::new("GET", &format!("/api/v1/workspaces/{ws_id}")).with_auth(&bob_token),
    );
    assert_eq!(bob_get.status, 200);

    let bob_put_denied = handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/workspaces/{ws_id}"))
            .with_auth(&bob_token)
            .with_json(&json!({ "name": "Bob Edit" })),
    );
    assert_eq!(bob_put_denied.status, 403);

    // Alice upgrades Bob to edit role
    let patch_bob = handle_request(
        &ctx,
        &HttpRequest::new(
            "PATCH",
            &format!("/api/v1/workspaces/{ws_id}/collaborators/{collab_id}"),
        )
        .with_auth(&owner_token)
        .with_json(&json!({ "role": "edit" })),
    );
    assert_eq!(patch_bob.status, 200);

    // Bob can now PUT, and sync event fans out to both Alice and Bob!
    redis.clear_all();
    let bob_put_ok = handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/workspaces/{ws_id}"))
            .with_auth(&bob_token)
            .with_json(&json!({ "name": "Bob Edited" })),
    );
    assert_eq!(bob_put_ok.status, 200);
    let pub_channels: Vec<String> = redis
        .published_messages()
        .into_iter()
        .map(|(ch, _)| ch)
        .collect();
    assert!(pub_channels.contains(&format!("sync:updates:{owner_id}")));
    assert!(pub_channels.contains(&format!("sync:updates:{bob_id}")));

    // Bob still cannot DELETE the shared workspace (403)
    let bob_del_denied = handle_request(
        &ctx,
        &HttpRequest::new("DELETE", &format!("/api/v1/workspaces/{ws_id}")).with_auth(&bob_token),
    );
    assert_eq!(bob_del_denied.status, 403);

    // Cross-space tab exfiltration guard: Bob (edit on ws_id, owner on bob_ws) cannot move a tab out of ws_id
    let bob_ws = uuid_v4();
    handle_request(
        &ctx,
        &HttpRequest::new("PUT", &format!("/api/v1/workspaces/{bob_ws}"))
            .with_auth(&bob_token)
            .with_json(&json!({ "name": "Bob Private", "position": 0, "settings": {} })),
    );
    let shared_tab = uuid_v4();
    {
        let mut g = ctx.store.inner.lock().unwrap();
        g.tabs.insert(
            shared_tab.clone(),
            TabRecord {
                id: shared_tab.clone(),
                workspace_id: ws_id.clone(),
                url: "https://secret.example.com".to_string(),
                title: None,
                favicon_url: None,
                position: 0,
                is_pinned: false,
                created_at: now_iso8601(),
                updated_at: now_iso8601(),
                last_accessed_at: now_iso8601(),
                metadata: json!({}),
            },
        );
    }
    let exfil_res = handle_request(
        &ctx,
        &HttpRequest::new("POST", "/api/v1/workspaces/tabs/move")
            .with_auth(&bob_token)
            .with_json(&json!({
                "tabId": shared_tab,
                "targetWorkspaceId": bob_ws
            })),
    );
    assert_eq!(exfil_res.status, 403);

    // Share link + Relay public preview & authenticated accept
    let link_res = handle_request(
        &ctx,
        &HttpRequest::new("POST", &format!("/api/v1/workspaces/{ws_id}/share-links"))
            .with_auth(&owner_token)
            .with_json(&json!({ "role": "edit", "label": "Relay Link" })),
    );
    assert_eq!(link_res.status, 201);
    let relay_id = link_res.json()["data"]["relayId"]
        .as_str()
        .unwrap()
        .to_string();

    // Unauthenticated GET /api/v1/share-links/relay/:relayId/info
    let relay_info = handle_request(
        &ctx,
        &HttpRequest::new("GET", &format!("/api/v1/share-links/relay/{relay_id}/info")),
    );
    assert_eq!(relay_info.status, 200);
    assert_eq!(relay_info.json()["data"]["workspaceName"], "Bob Edited");
    assert_eq!(relay_info.json()["data"]["role"], "edit");
    assert!(relay_info.json()["data"].get("tabs").is_none());

    // Unauthenticated POST /accept -> 401
    let relay_acc_unauth = handle_request(
        &ctx,
        &HttpRequest::new(
            "POST",
            &format!("/api/v1/share-links/relay/{relay_id}/accept"),
        ),
    );
    assert_eq!(relay_acc_unauth.status, 401);

    // Carol accepts via relayId
    let relay_acc_carol = handle_request(
        &ctx,
        &HttpRequest::new(
            "POST",
            &format!("/api/v1/share-links/relay/{relay_id}/accept"),
        )
        .with_auth(&carol_token),
    );
    assert_eq!(relay_acc_carol.status, 200);
    assert_eq!(relay_acc_carol.json()["data"]["role"], "edit");
}
