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

use crate::auth_lib::{
    generate_refresh_token, hash_refresh_token, refresh_token_expiry, resolve_jwt_secret,
    ACCESS_TOKEN_TTL, REFRESH_TOKEN_TTL_DAYS,
};
use crate::crypto::{now_epoch_ms, now_iso8601};
use crate::errors::{
    format_error_response, handle_arbitrary_error, is_schema_drift_error_value, AppError,
};
use crate::migration_guard::{
    assert_database_schema_current, MigrationLogger, ProbeOptions, RequiredColumn,
    SchemaColumnProbe, REQUIRED_COLUMNS,
};
use crate::presence::{presence_key, presence_member};
use crate::scanner_reject::is_scanner_probe_path;
use crate::schemas::{
    parse_backup_create_schema, parse_backup_list_query, parse_backup_restore_schema,
    parse_note_schema, parse_resource_schema, parse_save_tabs_schema, parse_section_schema,
    parse_space_group_create_schema, parse_space_group_update_schema, parse_sync_pull_schema,
    parse_sync_push_schema, parse_tab_schema, parse_task_schema, parse_user_update_schema,
    parse_workspace_create_schema, parse_workspace_update_schema,
};
use crate::secrets::{
    bootstrap_secrets_with, get_secret_with, reset_secret_cache_for_tests, try_get_secret_with,
    SecretManagerBackend,
};
use crate::server::{authenticate_request, require_tier, AppContext, HttpRequest};
use crate::services::{
    AuthService, BackupService, CollaboratorService, PermissionService, ShareService,
    SpaceGroupService, SyncService, UserService, WorkspaceService,
};
use crate::store::{DataStore, InMemoryRedis, RedisStore, UserRecord};
use crate::tiers::{
    get_limit, get_tier_display_name, get_tier_limits, has_feature_access, is_paid_tier,
    is_within_limit, validate_tier_limit, LimitValue,
};
use crate::tombstones::{is_tombstoned, mark_entity_deleted, tombstone_key, TOMBSTONE_TTL_SECONDS};
use crate::workos::{
    get_workos, get_workos_api_key, get_workos_client_id, WorkOSProvider, WorkOSUser,
};
use serde_json::json;
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex};

// ============================================================================
// 1. auth.lib.test.ts
// ============================================================================

#[test]
fn unit_auth_lib_resolve_jwt_secret_and_refresh_tokens() {
    let mut env = BTreeMap::new();
    env.insert("JWT_SECRET".to_string(), "super-secret-value".to_string());
    assert_eq!(resolve_jwt_secret(&env).unwrap(), "super-secret-value");

    let mut prod_env = BTreeMap::new();
    prod_env.insert("NODE_ENV".to_string(), "production".to_string());
    assert!(resolve_jwt_secret(&prod_env)
        .unwrap_err()
        .contains("JWT_SECRET environment variable must be set in production"));

    let mut prod_empty = BTreeMap::new();
    prod_empty.insert("NODE_ENV".to_string(), "production".to_string());
    prod_empty.insert("JWT_SECRET".to_string(), "   ".to_string());
    assert!(resolve_jwt_secret(&prod_empty).is_err());

    let dev_env = BTreeMap::new();
    let dev_secret = resolve_jwt_secret(&dev_env).unwrap();
    assert!(!dev_secret.is_empty());

    assert_eq!(ACCESS_TOKEN_TTL, "1h");
    assert_eq!(REFRESH_TOKEN_TTL_DAYS, 30);

    let t1 = generate_refresh_token();
    let t2 = generate_refresh_token();
    assert_eq!(t1.len(), 43);
    assert_ne!(t1, t2);

    let h1 = hash_refresh_token("token-a");
    let h2 = hash_refresh_token("token-b");
    assert_eq!(h1.len(), 64);
    assert_eq!(h1, hash_refresh_token("token-a"));
    assert_ne!(h1, h2);

    let base_ms = 1_700_000_000_000i64;
    let exp_ms = refresh_token_expiry(base_ms);
    assert_eq!(exp_ms - base_ms, 30 * 24 * 60 * 60 * 1000);
}

// ============================================================================
// 2. auth.middleware.test.ts
// ============================================================================

#[test]
fn unit_auth_middleware_authenticate_and_require_tier() {
    let ctx = AppContext::new_test();
    let token = ctx.sign_user_token("user-123", "test@example.com", "pro");

    // Valid Bearer token
    let req_ok = HttpRequest::new("GET", "/api/v1/workspaces").with_auth(&token);
    let user = authenticate_request(&req_ok, &ctx.jwt_secret, false).unwrap();
    assert_eq!(user.id, "user-123");
    assert_eq!(user.email, "test@example.com");
    assert_eq!(user.tier, "pro");

    // Missing Authorization header -> 401
    let req_missing = HttpRequest::new("GET", "/api/v1/workspaces");
    let err_missing = authenticate_request(&req_missing, &ctx.jwt_secret, false).unwrap_err();
    assert_eq!(err_missing.status, 401);
    assert_eq!(err_missing.json()["message"], "Invalid or expired token");

    // Invalid token -> 401
    let req_bad = HttpRequest::new("GET", "/api/v1/workspaces").with_auth("invalid.jwt.token");
    let err_bad = authenticate_request(&req_bad, &ctx.jwt_secret, false).unwrap_err();
    assert_eq!(err_bad.status, 401);

    // Tier hierarchy checks
    assert!(require_tier(&user, "free").is_ok());
    assert!(require_tier(&user, "pro").is_ok());
    let err_team = require_tier(&user, "team").unwrap_err();
    assert_eq!(err_team.status, 403);
    assert_eq!(
        err_team.json()["message"],
        "This feature requires team tier or higher"
    );
}

// ============================================================================
// 3. auth.service.test.ts
// ============================================================================

#[test]
fn unit_auth_service_password_hashing_and_verification() {
    let password = "TestPassword123!";
    let hash = AuthService::hash_password(password);
    assert!(hash.starts_with("$2b$12$"));
    assert_ne!(hash, password);

    let hash2 = AuthService::hash_password(password);
    assert_ne!(hash, hash2);

    assert!(AuthService::verify_password(password, &hash));
    assert!(AuthService::verify_password(password, &hash2));
    assert!(!AuthService::verify_password("WrongPassword123!", &hash));
    assert!(!AuthService::verify_password("testpassword123!", &hash));
    assert!(!AuthService::verify_password("", &hash));

    let empty_hash = AuthService::hash_password("");
    assert!(AuthService::verify_password("", &empty_hash));

    let unicode = "Pässwörd™🔒";
    let u_hash = AuthService::hash_password(unicode);
    assert!(AuthService::verify_password(unicode, &u_hash));
}

// ============================================================================
// 4. auth.session.service.test.ts
// ============================================================================

#[test]
fn unit_auth_session_service_create_rotate_revoke() {
    let store = DataStore::new();
    store.clear_all();
    store.put_user(UserRecord {
        id: "user-123".to_string(),
        email: "u@example.com".to_string(),
        password_hash: None,
        name: Some("User".to_string()),
        tier: "pro".to_string(),
        created_at: now_iso8601(),
        updated_at: now_iso8601(),
        last_login_at: None,
        preferences: json!({}),
    });

    let raw_token = AuthService::create_session(
        &store,
        "user-123",
        Some("10.0.0.1".to_string()),
        Some("TestAgent/1.0".to_string()),
        None,
    )
    .unwrap();
    assert_eq!(raw_token.len(), 43);

    // Verify stored session has hashed token, not raw token
    {
        let g = store.inner.lock().unwrap();
        let sess = g.sessions.values().next().unwrap();
        assert_eq!(sess.refresh_token_hash, hash_refresh_token(&raw_token));
        assert_ne!(sess.refresh_token_hash, raw_token);
    }

    // Rotate refresh token
    let rotated = AuthService::rotate_refresh_token(&store, &raw_token)
        .unwrap()
        .expect("should rotate valid token");
    assert_ne!(rotated.refresh_token, raw_token);
    assert_eq!(rotated.user.id, "user-123");
    assert_eq!(rotated.user.tier, "pro");

    // Old token can no longer be used (one-time rotation)
    assert!(AuthService::rotate_refresh_token(&store, &raw_token)
        .unwrap()
        .is_none());

    // Empty token returns None
    assert!(AuthService::rotate_refresh_token(&store, "")
        .unwrap()
        .is_none());

    // Expired session is deleted and returns None
    {
        let mut g = store.inner.lock().unwrap();
        for s in g.sessions.values_mut() {
            s.expires_at_ms = now_epoch_ms() - 1000;
        }
    }
    assert!(
        AuthService::rotate_refresh_token(&store, &rotated.refresh_token)
            .unwrap()
            .is_none()
    );

    // Revoke session
    let token2 = AuthService::create_session(&store, "user-123", None, None, None).unwrap();
    assert!(AuthService::revoke_refresh_token(&store, &token2).unwrap());
    assert!(!AuthService::revoke_refresh_token(&store, &token2).unwrap());
    assert!(!AuthService::revoke_refresh_token(&store, "").unwrap());
}

// ============================================================================
// 5. auth.workos.service.test.ts
// ============================================================================

struct MockWorkOS {
    user: Option<WorkOSUser>,
}

impl WorkOSProvider for MockWorkOS {
    fn get_authorization_url(
        &self,
        client_id: &str,
        provider: &str,
        redirect_uri: &str,
    ) -> Result<String, String> {
        Ok(format!(
            "https://api.workos.com/sso/authorize?client_id={client_id}&provider={provider}&redirect_uri={redirect_uri}"
        ))
    }

    fn authenticate_with_code(&self, _client_id: &str, _code: &str) -> Result<WorkOSUser, String> {
        self.user
            .clone()
            .ok_or_else(|| "WorkOS auth error".to_string())
    }
}

#[test]
fn unit_auth_workos_service_url_and_sync() {
    let store = DataStore::new();
    store.clear_all();

    let mock = MockWorkOS {
        user: Some(WorkOSUser {
            email: Some("alice@example.com".to_string()),
            first_name: Some("Alice".to_string()),
            last_name: Some("Smith".to_string()),
            profile_picture_url: None,
        }),
    };

    let url = AuthService::get_authorization_url(
        &mock,
        "client_test_123",
        "http://localhost:8080/api/v1/auth/callback",
    )
    .unwrap();
    assert!(url.contains("client_id=client_test_123"));
    assert!(url.contains("provider=authkit"));

    let u1 = AuthService::authenticate_and_sync_user(&store, &mock, "client_test_123", "code-1")
        .unwrap();
    assert_eq!(u1.email, "alice@example.com");
    assert_eq!(u1.name.as_deref(), Some("Alice Smith"));

    // First name only
    let mock_first_only = MockWorkOS {
        user: Some(WorkOSUser {
            email: Some("bob@example.com".to_string()),
            first_name: Some("Bob".to_string()),
            last_name: None,
            profile_picture_url: None,
        }),
    };
    let u2 = AuthService::authenticate_and_sync_user(
        &store,
        &mock_first_only,
        "client_test_123",
        "code-2",
    )
    .unwrap();
    assert_eq!(u2.name.as_deref(), Some("Bob"));

    // Email prefix fallback when no names provided
    let mock_no_name = MockWorkOS {
        user: Some(WorkOSUser {
            email: Some("charlie@example.com".to_string()),
            first_name: None,
            last_name: None,
            profile_picture_url: None,
        }),
    };
    let u3 =
        AuthService::authenticate_and_sync_user(&store, &mock_no_name, "client_test_123", "code-3")
            .unwrap();
    assert_eq!(u3.name.as_deref(), Some("charlie"));

    // Missing email throws error
    let mock_no_email = MockWorkOS {
        user: Some(WorkOSUser {
            email: None,
            first_name: Some("NoEmail".to_string()),
            last_name: None,
            profile_picture_url: None,
        }),
    };
    let err = AuthService::authenticate_and_sync_user(
        &store,
        &mock_no_email,
        "client_test_123",
        "code-4",
    )
    .unwrap_err();
    assert!(err.message().contains("User email not provided by WorkOS"));
}

// ============================================================================
// 6. backup.service.test.ts
// ============================================================================

#[test]
fn unit_backup_service_create_list_restore_delete_stats_cleanup() {
    let store = DataStore::new();
    store.clear_all();
    let redis = InMemoryRedis::new();
    let user_id = "user-backup-1";

    let ws_input = parse_workspace_create_schema(&json!({
        "name": "Dev Workspace",
        "tabs": [{ "url": "https://rust-lang.org", "title": "Rust" }],
        "sections": [{ "id": "sec-1", "title": "Docs", "resources": [{ "title": "Book", "url": "https://doc.rust-lang.org" }] }],
        "notes": [{ "title": "Note 1", "content": "Hello" }],
        "tasks": [{ "title": "Task 1", "completed": false }]
    }))
    .unwrap();
    let ws = WorkspaceService::create_workspace(&store, &redis, user_id, "free", ws_input, None)
        .unwrap();
    let ws_id = ws["id"].as_str().unwrap().to_string();

    // Create manual backup
    let b1 = BackupService::create_backup(
        &store,
        user_id,
        "free",
        parse_backup_create_schema(&json!({
            "workspaceId": ws_id,
            "name": "Initial Backup",
            "type": "manual"
        }))
        .unwrap(),
    )
    .unwrap();
    let b1_id = b1["id"].as_str().unwrap().to_string();
    assert_eq!(b1["name"], "Initial Backup");
    assert_eq!(b1["type"], "manual");

    // Free tier allows 10 backups; auto backup at limit evicts oldest auto backup
    for i in 0..9 {
        BackupService::create_backup(
            &store,
            user_id,
            "free",
            parse_backup_create_schema(&json!({
                "name": format!("Auto {i}"),
                "type": "auto"
            }))
            .unwrap(),
        )
        .unwrap();
    }
    // 11th backup as manual should fail limit check
    let manual_err = BackupService::create_backup(
        &store,
        user_id,
        "free",
        parse_backup_create_schema(&json!({ "type": "manual" })).unwrap(),
    )
    .unwrap_err();
    assert!(manual_err.message().contains("maxBackups limit"));

    // 11th backup as auto should evict oldest auto and succeed
    let auto_ok = BackupService::create_backup(
        &store,
        user_id,
        "free",
        parse_backup_create_schema(&json!({ "name": "Auto Evict", "type": "auto" })).unwrap(),
    )
    .unwrap();
    assert_eq!(auto_ok["type"], "auto");

    // List backups
    let list = BackupService::list_backups(
        &store,
        user_id,
        parse_backup_list_query(&HashMap::new()).unwrap(),
    )
    .unwrap();
    assert_eq!(list["total"], 10);

    // Get backup
    let fetched = BackupService::get_backup(&store, user_id, &b1_id)
        .unwrap()
        .unwrap();
    assert_eq!(fetched["id"], b1_id);
    assert!(BackupService::get_backup(&store, "other-user", &b1_id)
        .unwrap()
        .is_none());

    // Restore backup with createNew: true
    let restored_new = BackupService::restore_backup(
        &store,
        user_id,
        &b1_id,
        parse_backup_restore_schema(&json!({ "createNew": true })).unwrap(),
    )
    .unwrap();
    assert_eq!(restored_new.len(), 1);
    assert_ne!(restored_new[0], ws_id);

    // Stats
    let stats = BackupService::get_backup_stats(&store, user_id).unwrap();
    assert_eq!(stats["totalBackups"], 10);
    assert_eq!(stats["manualBackups"], 1);
    assert_eq!(stats["autoBackups"], 9);

    // Delete backup
    assert!(!BackupService::delete_backup(&store, "other-user", &b1_id).unwrap());
    assert!(BackupService::delete_backup(&store, user_id, &b1_id).unwrap());
}

// ============================================================================
// 7. collaborator.service.test.ts
// ============================================================================

#[test]
fn unit_collaborator_service_share_list_role_revoke() {
    let store = DataStore::new();
    store.clear_all();
    store.put_user(UserRecord {
        id: "user-bob".to_string(),
        email: "bob@example.com".to_string(),
        password_hash: None,
        name: Some("Bob".to_string()),
        tier: "free".to_string(),
        created_at: now_iso8601(),
        updated_at: now_iso8601(),
        last_login_at: None,
        preferences: json!({}),
    });

    // Existing user -> status active
    let g1 = CollaboratorService::share_by_email(
        &store,
        "ws-1",
        "owner-1",
        "  Bob@Example.com ",
        "edit",
    )
    .unwrap();
    assert_eq!(g1["inviteeEmail"], "bob@example.com");
    assert_eq!(g1["role"], "edit");
    assert_eq!(g1["status"], "active");
    let g1_id = g1["id"].as_str().unwrap().to_string();

    // Unknown user -> status pending
    let g2 = CollaboratorService::share_by_email(
        &store,
        "ws-1",
        "owner-1",
        "newbie@example.com",
        "view",
    )
    .unwrap();
    assert_eq!(g2["status"], "pending");

    let list = CollaboratorService::list_collaborators(&store, "ws-1").unwrap();
    assert_eq!(list.len(), 2);

    // Update role
    let updated = CollaboratorService::set_role(&store, "ws-1", &g1_id, "view").unwrap();
    assert_eq!(updated["role"], "view");

    // Cross-workspace IDOR guard on set_role and revoke
    assert!(CollaboratorService::set_role(&store, "ws-other", &g1_id, "edit").is_err());
    assert!(CollaboratorService::revoke(&store, "ws-other", &g1_id).is_err());

    // Revoke
    CollaboratorService::revoke(&store, "ws-1", &g1_id).unwrap();
    assert_eq!(
        CollaboratorService::list_collaborators(&store, "ws-1")
            .unwrap()
            .len(),
        1
    );
}

// ============================================================================
// 8. errorHandler.test.ts
// ============================================================================

#[test]
fn unit_error_handler_schema_drift_and_arbitrary_errors() {
    assert!(is_schema_drift_error_value(&json!({
        "name": "PrismaClientKnownRequestError",
        "code": "P2022"
    })));
    assert!(is_schema_drift_error_value(&json!({
        "name": "PrismaClientKnownRequestError",
        "code": "P2021"
    })));
    assert!(!is_schema_drift_error_value(&json!({
        "name": "PrismaClientKnownRequestError",
        "code": "P2002"
    })));

    let drift_resp = handle_arbitrary_error(
        &json!({
            "name": "PrismaClientKnownRequestError",
            "code": "P2022",
            "message": "The column `workspaces.version` does not exist in the current database."
        }),
        false,
    );
    assert_eq!(drift_resp.0, 503);
    assert_eq!(drift_resp.1["error"], "Service Unavailable");

    let status_err = handle_arbitrary_error(
        &json!({
            "statusCode": 429,
            "name": "Too Many Requests",
            "message": "Rate limit exceeded"
        }),
        false,
    );
    assert_eq!(status_err.0, 429);

    let (st, body) = format_error_response(&AppError::not_found("Workspace not found"), false);
    assert_eq!(st, 404);
    assert_eq!(body["error"], "NotFoundError");
}

// ============================================================================
// 9. migrationGuard.test.ts
// ============================================================================

struct MockColumnProbe {
    responses: Mutex<Vec<Result<Vec<(String, String)>, String>>>,
}

impl SchemaColumnProbe for MockColumnProbe {
    fn query_present_columns(&self) -> Result<Vec<(String, String)>, String> {
        let mut g = self.responses.lock().unwrap();
        if g.is_empty() {
            Ok(Vec::new())
        } else {
            g.remove(0)
        }
    }
}

#[derive(Default)]
struct RecordingMigrationLogger {
    warns: Mutex<Vec<String>>,
    errors: Mutex<Vec<String>>,
    fatals: Mutex<Vec<String>>,
}

impl MigrationLogger for RecordingMigrationLogger {
    fn info(&self, _msg: &str) {}
    fn warn(&self, msg: &str) {
        self.warns.lock().unwrap().push(msg.to_string());
    }
    fn error(&self, msg: &str) {
        self.errors.lock().unwrap().push(msg.to_string());
    }
    fn fatal(&self, _missing: &[RequiredColumn], msg: &str) {
        self.fatals.lock().unwrap().push(msg.to_string());
    }
}

#[test]
fn unit_migration_guard_verifies_required_columns_and_retries() {
    let all_present: Vec<(String, String)> = REQUIRED_COLUMNS
        .iter()
        .map(|c| (c.table.to_string(), c.column.to_string()))
        .collect();
    let logger = RecordingMigrationLogger::default();

    // 1. All columns present -> Ok
    let probe_ok = MockColumnProbe {
        responses: Mutex::new(vec![Ok(all_present.clone())]),
    };
    assert!(assert_database_schema_current(
        &probe_ok,
        &logger,
        None,
        ProbeOptions {
            attempts: 3,
            backoff_ms: 0
        }
    )
    .is_ok());

    // 2. Missing columns -> Err(MigrationDriftError) immediately (no retry on drift)
    let partial: Vec<(String, String)> = all_present.iter().skip(2).cloned().collect();
    let probe_drift = MockColumnProbe {
        responses: Mutex::new(vec![Ok(partial), Ok(all_present.clone())]),
    };
    let err = assert_database_schema_current(
        &probe_drift,
        &logger,
        None,
        ProbeOptions {
            attempts: 3,
            backoff_ms: 0,
        },
    )
    .unwrap_err();
    assert_eq!(err.missing.len(), 2);
    assert!(!logger.fatals.lock().unwrap().is_empty());

    // 3. Transient query error -> retries and succeeds
    let probe_retry = MockColumnProbe {
        responses: Mutex::new(vec![Err("ECONNRESET".to_string()), Ok(all_present)]),
    };
    assert!(assert_database_schema_current(
        &probe_retry,
        &logger,
        None,
        ProbeOptions {
            attempts: 3,
            backoff_ms: 0
        }
    )
    .is_ok());

    // 4. TABULA_SKIP_MIGRATION_CHECK=true bypasses probe
    let probe_empty = MockColumnProbe {
        responses: Mutex::new(vec![]),
    };
    assert!(assert_database_schema_current(
        &probe_empty,
        &logger,
        Some("true"),
        ProbeOptions {
            attempts: 1,
            backoff_ms: 0
        }
    )
    .is_ok());
}

// ============================================================================
// 10. permission.service.test.ts
// ============================================================================

#[test]
fn unit_permission_service_roles_and_access() {
    let store = DataStore::new();
    store.clear_all();
    let redis = InMemoryRedis::new();

    let ws = WorkspaceService::create_workspace(
        &store,
        &redis,
        "owner-1",
        "free",
        parse_workspace_create_schema(&json!({ "id": "ws-perm", "name": "Shared Space" })).unwrap(),
        None,
    )
    .unwrap();
    assert_eq!(ws["id"], "ws-perm");

    store.put_user(UserRecord {
        id: "collab-edit".to_string(),
        email: "editor@example.com".to_string(),
        password_hash: None,
        name: None,
        tier: "free".to_string(),
        created_at: now_iso8601(),
        updated_at: now_iso8601(),
        last_login_at: None,
        preferences: json!({}),
    });
    store.put_user(UserRecord {
        id: "collab-view".to_string(),
        email: "viewer@example.com".to_string(),
        password_hash: None,
        name: None,
        tier: "free".to_string(),
        created_at: now_iso8601(),
        updated_at: now_iso8601(),
        last_login_at: None,
        preferences: json!({}),
    });

    CollaboratorService::share_by_email(&store, "ws-perm", "owner-1", "editor@example.com", "edit")
        .unwrap();
    CollaboratorService::share_by_email(&store, "ws-perm", "owner-1", "viewer@example.com", "view")
        .unwrap();

    // Owner has owner, edit, view
    assert_eq!(
        PermissionService::require_role(&store, "owner-1", "ws-perm", "owner").unwrap(),
        "owner"
    );

    // Editor has view and edit, but NOT owner (403 Forbidden)
    assert_eq!(
        PermissionService::require_role(&store, "collab-edit", "ws-perm", "edit").unwrap(),
        "edit"
    );
    assert!(matches!(
        PermissionService::require_role(&store, "collab-edit", "ws-perm", "owner").unwrap_err(),
        AppError::Forbidden { .. }
    ));

    // Viewer has view, but NOT edit (403 Forbidden)
    assert_eq!(
        PermissionService::require_role(&store, "collab-view", "ws-perm", "view").unwrap(),
        "view"
    );
    assert!(matches!(
        PermissionService::require_role(&store, "collab-view", "ws-perm", "edit").unwrap_err(),
        AppError::Forbidden { .. }
    ));

    // Stranger gets 404 NotFound (existence-masked)
    assert!(matches!(
        PermissionService::require_role(&store, "stranger", "ws-perm", "view").unwrap_err(),
        AppError::NotFound { .. }
    ));

    let ids = PermissionService::list_access_user_ids(&store, "ws-perm").unwrap();
    assert_eq!(ids.len(), 3);
    assert!(ids.contains(&"owner-1".to_string()));
    assert!(ids.contains(&"collab-edit".to_string()));
    assert!(ids.contains(&"collab-view".to_string()));

    let shared = PermissionService::list_spaces_shared_with(&store, "collab-edit").unwrap();
    assert_eq!(shared.len(), 1);
    assert_eq!(shared[0]["workspaceId"], "ws-perm");
    assert_eq!(shared[0]["role"], "edit");
}

// ============================================================================
// 11. presence.test.ts
// ============================================================================

#[test]
fn unit_presence_keys_and_members() {
    assert_eq!(presence_key("ws_abc123"), "presence:workspace:ws_abc123");
    assert_eq!(presence_member("user-1", "dev-9"), "user-1:dev-9");
    assert_eq!(presence_member("user-1", "default"), "user-1:default");
}

// ============================================================================
// 12. scannerReject.test.ts
// ============================================================================

#[test]
fn unit_scanner_reject_probes_vs_legitimate_paths() {
    for probe in [
        "/wp-admin/setup-config.php",
        "/wp-login.php",
        "/wp-content/plugins/foo",
        "/xmlrpc.php",
        "/.env",
        "/.env.local",
        "/.git/config",
        "/phpmyadmin/index.php",
    ] {
        assert!(
            is_scanner_probe_path(probe),
            "expected {probe} to be rejected"
        );
    }

    for legit in [
        "/",
        "/health",
        "/api/v1/workspaces",
        "/api/v1/auth/login",
        "/api/v1/sync/stream",
        "/docs",
    ] {
        assert!(
            !is_scanner_probe_path(legit),
            "expected {legit} to be allowed"
        );
    }
}

// ============================================================================
// 13. secrets.test.ts
// ============================================================================

struct CountingSecretBackend {
    calls: Mutex<usize>,
    values: HashMap<String, String>,
}

impl SecretManagerBackend for CountingSecretBackend {
    fn access_secret_version(
        &self,
        resource_name: &str,
        _timeout_ms: u64,
    ) -> Result<Option<String>, String> {
        *self.calls.lock().unwrap() += 1;
        // resource_name is "projects/{project}/secrets/{secret_id}/versions/latest"
        let parts: Vec<&str> = resource_name.split('/').collect();
        let secret_id = parts.get(3).copied().unwrap_or(resource_name);
        self.values
            .get(secret_id)
            .cloned()
            .map(Some)
            .ok_or_else(|| format!("Secret {secret_id} not found in GSM"))
    }
}

#[test]
fn unit_secrets_env_precedence_and_gsm_caching() {
    reset_secret_cache_for_tests();

    let mut gsm_vals = HashMap::new();
    gsm_vals.insert("JWT_SECRET".to_string(), "gsm-jwt-secret".to_string());
    gsm_vals.insert("WORKOS_API_KEY".to_string(), "gsm-workos-key".to_string());
    let backend = Arc::new(CountingSecretBackend {
        calls: Mutex::new(0),
        values: gsm_vals,
    });

    // 1. Env var takes precedence without hitting GSM
    let mut env = BTreeMap::new();
    env.insert("JWT_SECRET".to_string(), "env-jwt-secret".to_string());
    let val = get_secret_with("JWT_SECRET", &env, backend.as_ref()).unwrap();
    assert_eq!(val, "env-jwt-secret");
    assert_eq!(*backend.calls.lock().unwrap(), 0);

    // 2. Falls back to GSM when GOOGLE_CLOUD_PROJECT is set and caches
    let mut gcp_env = BTreeMap::new();
    gcp_env.insert("GOOGLE_CLOUD_PROJECT".to_string(), "proj-123".to_string());
    let w1 = get_secret_with("WORKOS_API_KEY", &gcp_env, backend.as_ref()).unwrap();
    let w2 = get_secret_with("WORKOS_API_KEY", &gcp_env, backend.as_ref()).unwrap();
    assert_eq!(w1, "gsm-workos-key");
    assert_eq!(w2, "gsm-workos-key");
    assert_eq!(*backend.calls.lock().unwrap(), 1);

    // 3. try_get_secret_with returns None on missing secret
    assert!(try_get_secret_with("NONEXISTENT_SECRET", &gcp_env, backend.as_ref()).is_none());

    // 4. bootstrap_secrets_with populates env map
    reset_secret_cache_for_tests();
    bootstrap_secrets_with(&mut gcp_env, backend.clone());
    assert_eq!(gcp_env.get("JWT_SECRET").unwrap(), "gsm-jwt-secret");
    assert_eq!(gcp_env.get("WORKOS_API_KEY").unwrap(), "gsm-workos-key");

    // WorkOS secret helpers
    assert_eq!(
        get_workos_client_id(
            &{
                let mut m = BTreeMap::new();
                m.insert("WORKOS_CLIENT_ID".to_string(), "client_abc".to_string());
                m
            },
            backend.as_ref()
        )
        .unwrap(),
        "client_abc"
    );
    assert_eq!(
        get_workos_api_key(&gcp_env, backend.as_ref()).unwrap(),
        "gsm-workos-key"
    );
    let _ = get_workos();
}

// ============================================================================
// 14. share.service.test.ts
// ============================================================================

#[test]
fn unit_share_service_links_relay_and_role_monotonicity() {
    let store = DataStore::new();
    store.clear_all();
    let redis = InMemoryRedis::new();

    store.put_user(UserRecord {
        id: "owner-1".to_string(),
        email: "owner@example.com".to_string(),
        password_hash: None,
        name: Some("Alice".to_string()),
        tier: "pro".to_string(),
        created_at: now_iso8601(),
        updated_at: now_iso8601(),
        last_login_at: None,
        preferences: json!({}),
    });

    WorkspaceService::create_workspace(
        &store,
        &redis,
        "owner-1",
        "pro",
        parse_workspace_create_schema(&json!({ "id": "ws-share", "name": "Team Roadmap" }))
            .unwrap(),
        None,
    )
    .unwrap();

    // Create edit link
    let edit_link = ShareService::create_link(
        &store,
        "ws-share",
        "owner-1",
        "edit",
        Some("Team link".to_string()),
        None,
    )
    .unwrap();
    let edit_token = edit_link["token"].as_str().unwrap().to_string();
    let edit_relay = edit_link["relayId"].as_str().unwrap().to_string();
    assert_ne!(edit_token, edit_relay);

    // Public info by token & relayId
    let info1 = ShareService::get_link_info(&store, &edit_token).unwrap();
    assert_eq!(info1["workspaceName"], "Team Roadmap");
    assert_eq!(info1["ownerName"], "Alice");
    assert_eq!(info1["role"], "edit");

    let info2 = ShareService::get_relay_info(&store, &edit_relay).unwrap();
    assert_eq!(info2["workspaceId"], "ws-share");

    // Accept edit link as Bob
    let acc_edit =
        ShareService::accept_link(&store, &edit_token, "user-bob", "bob@example.com").unwrap();
    assert_eq!(acc_edit["role"], "edit");

    // Create view link and accept as Bob -> role must NOT downgrade from edit to view!
    let view_link =
        ShareService::create_link(&store, "ws-share", "owner-1", "view", None, None).unwrap();
    let view_relay = view_link["relayId"].as_str().unwrap().to_string();
    let acc_view =
        ShareService::accept_by_relay_id(&store, &view_relay, "user-bob", "bob@example.com")
            .unwrap();
    assert_eq!(acc_view["role"], "edit");

    // Owner accepting their own share link is a no-op returning role: "owner"
    let owner_acc =
        ShareService::accept_link(&store, &edit_token, "owner-1", "owner@example.com").unwrap();
    assert_eq!(owner_acc["role"], "owner");

    // Revoke link -> no longer resolves
    let link_id = edit_link["id"].as_str().unwrap();
    ShareService::revoke_link(&store, "ws-share", link_id).unwrap();
    assert!(ShareService::get_link_info(&store, &edit_token).is_err());
    assert!(ShareService::get_relay_info(&store, &edit_relay).is_err());
}

// ============================================================================
// 15. spacegroup.service.test.ts
// ============================================================================

#[test]
fn unit_spacegroup_service_crud_and_optimistic_concurrency() {
    let store = DataStore::new();
    store.clear_all();
    let redis = InMemoryRedis::new();
    let uid = "user-sg";

    let id1 = SpaceGroupService::generate_id("sg");
    let id2 = SpaceGroupService::generate_id("sg");
    assert!(id1.starts_with("sg_"));
    assert_ne!(id1, id2);

    let g = SpaceGroupService::create_space_group(
        &store,
        &redis,
        uid,
        parse_space_group_create_schema(&json!({
            "title": "Work",
            "color": "#4F46E5",
            "collapsed": false,
            "position": 0
        }))
        .unwrap(),
        None,
    )
    .unwrap();
    assert_eq!(g.version, 0);

    // Update with matching baseVersion -> version increments to 1
    let u1 = SpaceGroupService::update_space_group(
        &store,
        &redis,
        uid,
        &g.id,
        parse_space_group_update_schema(&json!({
            "title": "Work Updated",
            "baseVersion": 0
        }))
        .unwrap(),
        None,
    )
    .unwrap();
    assert_eq!(u1.version, 1);
    assert_eq!(u1.title, "Work Updated");

    // Stale baseVersion -> ConflictError
    let conflict = SpaceGroupService::update_space_group(
        &store,
        &redis,
        uid,
        &g.id,
        parse_space_group_update_schema(&json!({
            "title": "Stale",
            "baseVersion": 0
        }))
        .unwrap(),
        None,
    )
    .unwrap_err();
    assert!(matches!(
        conflict,
        AppError::Conflict {
            current_version: 1,
            ..
        }
    ));

    // Delete space group
    SpaceGroupService::delete_space_group(&store, &redis, uid, &g.id, None).unwrap();
    assert!(SpaceGroupService::get_space_group_by_id(&store, uid, &g.id).is_err());
}

// ============================================================================
// 16. sync.service.test.ts
// ============================================================================

#[test]
fn unit_sync_service_push_pull_status_and_id_squatting_guard() {
    let store = DataStore::new();
    store.clear_all();
    let redis = InMemoryRedis::new();

    // User A creates workspace ws-shared-id via sync push
    let push_a = SyncService::push_changes(
        &store,
        &redis,
        "user-a",
        "pro",
        parse_sync_push_schema(&json!({
            "deviceId": "dev-a1",
            "clientTimestamp": now_iso8601(),
            "changes": [{
                "type": "workspace",
                "action": "create",
                "entityId": "ws-owned-by-a",
                "data": { "name": "A's Workspace" },
                "version": 0
            }]
        }))
        .unwrap(),
    )
    .unwrap();
    assert_eq!(push_a["accepted"], json!(["ws-owned-by-a"]));

    // User B tries to push to User A's workspace id -> rejected (anti-ID-squatting)
    let push_b = SyncService::push_changes(
        &store,
        &redis,
        "user-b",
        "pro",
        parse_sync_push_schema(&json!({
            "deviceId": "dev-b1",
            "clientTimestamp": now_iso8601(),
            "changes": [{
                "type": "workspace",
                "action": "update",
                "entityId": "ws-owned-by-a",
                "data": { "name": "Hijacked" },
                "version": 0
            }]
        }))
        .unwrap(),
    )
    .unwrap();
    assert_eq!(push_b["accepted"], json!([]));
    assert_eq!(push_b["rejected"][0]["entityId"], "ws-owned-by-a");

    // Version conflict on stale version
    let push_conflict = SyncService::push_changes(
        &store,
        &redis,
        "user-a",
        "pro",
        parse_sync_push_schema(&json!({
            "deviceId": "dev-a2",
            "clientTimestamp": now_iso8601(),
            "changes": [{
                "type": "workspace",
                "action": "update",
                "entityId": "ws-owned-by-a",
                "data": { "name": "Stale" },
                "version": 0
            }]
        }))
        .unwrap(),
    )
    .unwrap();
    assert_eq!(push_conflict["conflicts"].as_array().unwrap().len(), 1);

    // Pull changes from another device of user-a
    let pull = SyncService::pull_changes(
        &redis,
        "user-a",
        parse_sync_pull_schema(&json!({
            "deviceId": "dev-a2"
        }))
        .unwrap(),
    )
    .unwrap();
    assert_eq!(pull["changes"].as_array().unwrap().len(), 1);

    // Sync status
    let status = SyncService::get_sync_status(&redis, "user-a").unwrap();
    assert_eq!(status["syncEnabled"], true);
    assert!(status["connectedDevices"].as_u64().unwrap() >= 1);
}

// ============================================================================
// 17. tiers.test.ts
// ============================================================================

#[test]
fn unit_tiers_limits_and_feature_access() {
    let free = get_tier_limits("free");
    assert_eq!(free.max_workspaces, 10);
    assert_eq!(free.max_backups, 10);
    assert!(!free.realtime_sync_enabled);

    let pro = get_tier_limits("pro");
    assert_eq!(pro.max_workspaces, 100);
    assert!(pro.realtime_sync_enabled);

    assert_eq!(get_limit("free", "maxWorkspaces"), LimitValue::Number(10));
    assert!(!has_feature_access("free", "realtimeSyncEnabled"));
    assert!(has_feature_access("pro", "realtimeSyncEnabled"));
    assert!(has_feature_access("team", "realtimeSyncEnabled"));

    assert!(is_within_limit("free", "maxWorkspaces", 9));
    assert!(!is_within_limit("free", "maxWorkspaces", 10));
    assert!(is_within_limit("pro", "maxWorkspaces", 99));

    let v_fail = validate_tier_limit("free", "maxBackups", 10);
    assert!(!v_fail.valid);
    assert!(v_fail.message.unwrap().contains("10"));

    assert_eq!(get_tier_display_name("free"), "Free");
    assert_eq!(get_tier_display_name("pro"), "Pro");
    assert!(!is_paid_tier("free"));
    assert!(is_paid_tier("pro"));
}

// ============================================================================
// 18. tombstones.test.ts
// ============================================================================

#[test]
fn unit_tombstones_mark_and_check_with_fail_open() {
    let redis = InMemoryRedis::new();
    assert_eq!(TOMBSTONE_TTL_SECONDS, 30 * 24 * 60 * 60);
    assert_eq!(
        tombstone_key("u-1", "workspace", "ws-1"),
        "tombstone:u-1:workspace:ws-1"
    );

    assert!(!is_tombstoned(&redis, "u-1", "workspace", "ws-1"));
    let _ = redis.set("sync:version:u-1:workspace:ws-1", "3");
    let _ = redis.set("sync:state:u-1:workspace:ws-1", "{}");

    mark_entity_deleted(&redis, "u-1", "workspace", "ws-1");
    assert!(is_tombstoned(&redis, "u-1", "workspace", "ws-1"));
    assert!(redis
        .get("sync:version:u-1:workspace:ws-1")
        .unwrap()
        .is_none());
    assert!(redis
        .get("sync:state:u-1:workspace:ws-1")
        .unwrap()
        .is_none());

    // Fail-open when Redis errors
    redis.set_fail_error(Some("Redis down"));
    assert!(!is_tombstoned(&redis, "u-1", "workspace", "ws-1"));
}

// ============================================================================
// 19. user.service.test.ts
// ============================================================================

#[test]
fn unit_user_service_profile_and_password_reset_url() {
    let store = DataStore::new();
    store.clear_all();
    store.put_user(UserRecord {
        id: "u-1".to_string(),
        email: "u1@example.com".to_string(),
        password_hash: Some("secret-hash".to_string()),
        name: Some("Initial".to_string()),
        tier: "free".to_string(),
        created_at: now_iso8601(),
        updated_at: now_iso8601(),
        last_login_at: None,
        preferences: json!({}),
    });

    let fetched = UserService::get_user_by_id(&store, "u-1").unwrap().unwrap();
    assert_eq!(fetched["email"], "u1@example.com");
    assert!(fetched.get("passwordHash").is_none());

    let updated = UserService::update_user(
        &store,
        "u-1",
        parse_user_update_schema(&json!({
            "name": "Updated Name",
            "preferences": { "theme": "dark" }
        }))
        .unwrap(),
    )
    .unwrap();
    assert_eq!(updated["name"], "Updated Name");
    assert_eq!(updated["preferences"]["theme"], "dark");

    let url = UserService::get_password_reset_url("http://localhost:8080", "u1@example.com");
    assert_eq!(
        url,
        "http://localhost:8080/api/v1/auth/login?action=reset_password"
    );

    UserService::delete_user(&store, "u-1").unwrap();
    assert!(UserService::get_user_by_id(&store, "u-1")
        .unwrap()
        .is_none());
}

// ============================================================================
// 20. workspace.schema.test.ts
// ============================================================================

#[test]
fn unit_workspace_schema_chrome_wire_aliases_and_lenient_urls() {
    // Chrome extension wire aliases: favIconUrl -> faviconUrl, pinned -> isPinned, index -> position
    let tab = parse_tab_schema(&json!({
        "id": 42,
        "url": "chrome://extensions/?id=abc",
        "title": "Extensions",
        "favIconUrl": "https://example.com/icon.png",
        "pinned": true,
        "index": 7,
        "groupId": "grp_1"
    }))
    .unwrap();
    assert_eq!(
        tab.favicon_url.as_deref(),
        Some("https://example.com/icon.png")
    );
    assert!(tab.is_pinned);
    assert_eq!(tab.position, Some(7));
    assert_eq!(tab.group_id.as_deref(), Some("grp_1"));

    // Null id is tolerated (regression guard for sync wedge)
    let tab_null_id = parse_tab_schema(&json!({
        "id": null,
        "url": "about:blank"
    }))
    .unwrap();
    assert!(tab_null_id.id.is_none());

    // Scheme-less resource URLs and relative faviconUrls are accepted
    let res = parse_resource_schema(&json!({
        "id": null,
        "title": "Internal Wiki",
        "url": "go/wiki",
        "faviconUrl": "/favicon.ico"
    }))
    .unwrap();
    assert_eq!(res.url, "go/wiki");

    // Null IDs on sections, notes, tasks are tolerated
    assert!(parse_section_schema(&json!({ "id": null, "title": "Sec" })).is_ok());
    assert!(parse_note_schema(&json!({ "id": null, "title": "Note", "content": "c" })).is_ok());
    assert!(parse_task_schema(&json!({ "id": null, "title": "Task" })).is_ok());

    let save_tabs = parse_save_tabs_schema(&json!({
        "tabs": [{ "url": "https://example.com", "pinned": true, "index": 3 }]
    }))
    .unwrap();
    assert_eq!(save_tabs.len(), 1);
    assert!(save_tabs[0].is_pinned);
    assert_eq!(save_tabs[0].position, Some(3));
}

// ============================================================================
// 21. workspace.service.test.ts
// ============================================================================

#[test]
fn unit_workspace_service_lease_versioning_and_tab_ids() {
    let store = DataStore::new();
    store.clear_all();
    let redis = InMemoryRedis::new();
    let uid = "user-ws-unit";

    let ws = WorkspaceService::create_workspace(
        &store,
        &redis,
        uid,
        "free",
        parse_workspace_create_schema(&json!({
            "id": "ws-unit-1",
            "name": "Primary",
            "tabs": [{ "id": 777, "url": "https://example.com", "title": "T1" }]
        }))
        .unwrap(),
        Some("dev-A"),
    )
    .unwrap();

    // Server generates fresh tab_... id and preserves client id in metadata.clientTabId
    let tab0 = &ws["tabs"][0];
    let server_tab_id = tab0["id"].as_str().unwrap().to_string();
    assert!(server_tab_id.starts_with("tab_"));
    assert_eq!(tab0["metadata"]["clientTabId"], "777");

    // Device A claims active device lease via tabSync: true
    let u1 = WorkspaceService::update_workspace(
        &store,
        &redis,
        uid,
        "ws-unit-1",
        parse_workspace_update_schema(&json!({
            "name": "Primary v1",
            "tabSync": true
        }))
        .unwrap(),
        Some("dev-A"),
    )
    .unwrap();
    assert_eq!(u1["version"], 1);
    assert_eq!(u1["activeDeviceId"], "dev-A");

    // Device B sends passive tabSync (no claimActiveDevice) while Device A's lease is fresh -> NO-OP!
    let u_passive = WorkspaceService::update_workspace(
        &store,
        &redis,
        uid,
        "ws-unit-1",
        parse_workspace_update_schema(&json!({
            "name": "Should Be Ignored",
            "tabSync": true,
            "baseVersion": 0
        }))
        .unwrap(),
        Some("dev-B"),
    )
    .unwrap();
    assert_eq!(u_passive["version"], 1);
    assert_eq!(u_passive["name"], "Primary v1");
    assert_eq!(u_passive["activeDeviceId"], "dev-A");

    // Device B explicitly claims active device (`claimActiveDevice: true`) -> takes lease and bumps version
    let u_claim = WorkspaceService::update_workspace(
        &store,
        &redis,
        uid,
        "ws-unit-1",
        parse_workspace_update_schema(&json!({
            "name": "Taken Over By B",
            "claimActiveDevice": true,
            "baseVersion": 1
        }))
        .unwrap(),
        Some("dev-B"),
    )
    .unwrap();
    assert_eq!(u_claim["version"], 2);
    assert_eq!(u_claim["activeDeviceId"], "dev-B");

    // Edit collaborator cannot steal owner's active-device lease
    store.put_user(UserRecord {
        id: "collab-1".to_string(),
        email: "c1@example.com".to_string(),
        password_hash: None,
        name: None,
        tier: "free".to_string(),
        created_at: now_iso8601(),
        updated_at: now_iso8601(),
        last_login_at: None,
        preferences: json!({}),
    });
    CollaboratorService::share_by_email(&store, "ws-unit-1", uid, "c1@example.com", "edit")
        .unwrap();
    let u_collab = WorkspaceService::update_workspace(
        &store,
        &redis,
        "collab-1",
        "ws-unit-1",
        parse_workspace_update_schema(&json!({
            "name": "Collab Edit",
            "claimActiveDevice": true
        }))
        .unwrap(),
        Some("dev-collab"),
    )
    .unwrap();
    assert_eq!(u_collab["name"], "Collab Edit");
    assert_eq!(u_collab["activeDeviceId"], "dev-B");
}
