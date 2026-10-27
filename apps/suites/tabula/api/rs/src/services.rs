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

use crate::auth_lib::{generate_refresh_token, hash_refresh_token, refresh_token_expiry};
use crate::crypto::{
    epoch_ms_to_iso8601, hash_password, now_epoch_ms, now_iso8601, parse_datetime_ms, uuid_v4,
    verify_password,
};
use crate::errors::AppError;
use crate::ids::{generate_id, generate_opaque_token, hash_token};
use crate::schemas::{
    BackupCreateInput, BackupListQuery, BackupRestoreInput, ParsedNote, ParsedResource,
    ParsedSection, ParsedTab, ParsedTask, SpaceGroupCreateInput, SpaceGroupUpdateInput,
    SyncChangeInput, SyncPullInput, SyncPushInput, UserUpdateInput, WorkspaceCreateInput,
    WorkspaceUpdateInput,
};
use crate::store::{
    BackupRecord, DataStore, NoteRecord, RedisStore, ResourceRecord, SectionRecord, SessionRecord,
    ShareLinkRecord, SpaceCollaboratorRecord, SpaceGroupRecord, TabRecord, TaskRecord, UserRecord,
    WorkspaceRecord,
};
use crate::tiers::{get_tier_limits, is_within_limit, validate_tier_limit};
use crate::tombstones::{is_tombstoned, mark_entity_deleted};
use crate::workos::WorkOSProvider;
use serde::{Deserialize, Serialize};
use serde_json::{json, Map, Value};
use std::collections::HashSet;

pub const ACTIVE_DEVICE_STALE_MS: i64 = 2 * 60 * 1000;

// ============================================================================
// 1. AuthService
// ============================================================================

pub struct AuthService;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RotatedSession {
    pub refresh_token: String,
    pub user: RotatedSessionUser,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RotatedSessionUser {
    pub id: String,
    pub email: String,
    pub tier: String,
}

impl AuthService {
    pub fn hash_password(password: &str) -> String {
        hash_password(password, 12)
    }

    pub fn verify_password(password: &str, hash: &str) -> bool {
        verify_password(password, hash)
    }

    pub fn get_authorization_url(
        workos: &dyn WorkOSProvider,
        client_id: &str,
        redirect_uri: &str,
    ) -> Result<String, AppError> {
        workos
            .get_authorization_url(client_id, "authkit", redirect_uri)
            .map_err(AppError::internal)
    }

    pub fn authenticate_and_sync_user(
        store: &DataStore,
        workos: &dyn WorkOSProvider,
        client_id: &str,
        code: &str,
    ) -> Result<UserRecord, AppError> {
        let w_user = workos
            .authenticate_with_code(client_id, code)
            .map_err(AppError::internal)?;
        let email = w_user
            .email
            .as_deref()
            .filter(|s| !s.is_empty())
            .ok_or_else(|| AppError::internal("User email not provided by WorkOS"))?;

        let name = match (
            w_user.first_name.as_deref().filter(|s| !s.is_empty()),
            w_user.last_name.as_deref().filter(|s| !s.is_empty()),
        ) {
            (Some(first), Some(last)) => format!("{first} {last}"),
            (Some(first), None) => first.to_string(),
            _ => email.split('@').next().unwrap_or(email).to_string(),
        };

        Ok(store.upsert_user_by_email(email, &name))
    }

    pub fn create_session(
        store: &DataStore,
        user_id: &str,
        ip_address: Option<String>,
        user_agent: Option<String>,
        device_info: Option<Value>,
    ) -> Result<String, AppError> {
        store.check_injected_error()?;
        let refresh_token = generate_refresh_token();
        let refresh_token_hash = hash_refresh_token(&refresh_token);
        let now_ms = now_epoch_ms();
        let expires_at_ms = refresh_token_expiry(now_ms);
        let session = SessionRecord {
            id: uuid_v4(),
            user_id: user_id.to_string(),
            refresh_token_hash,
            device_info: device_info.unwrap_or_else(|| json!({})),
            ip_address,
            user_agent,
            expires_at: epoch_ms_to_iso8601(expires_at_ms),
            expires_at_ms,
            created_at: epoch_ms_to_iso8601(now_ms),
        };
        let mut g = store.inner.lock().unwrap();
        g.sessions.insert(session.id.clone(), session);
        Ok(refresh_token)
    }

    pub fn rotate_refresh_token(
        store: &DataStore,
        raw_refresh_token: &str,
    ) -> Result<Option<RotatedSession>, AppError> {
        store.check_injected_error()?;
        if raw_refresh_token.is_empty() {
            return Ok(None);
        }
        let token_hash = hash_refresh_token(raw_refresh_token);
        let now_ms = now_epoch_ms();

        let mut g = store.inner.lock().unwrap();
        let found_id = g
            .sessions
            .values()
            .find(|s| s.refresh_token_hash == token_hash)
            .map(|s| s.id.clone());

        let Some(sess_id) = found_id else {
            return Ok(None);
        };

        let sess = g.sessions.get(&sess_id).unwrap().clone();
        if sess.expires_at_ms <= now_ms {
            g.sessions.remove(&sess_id);
            return Ok(None);
        }

        let user = g
            .users
            .get(&sess.user_id)
            .cloned()
            .unwrap_or_else(|| UserRecord {
                id: sess.user_id.clone(),
                email: "user@example.com".to_string(),
                password_hash: None,
                name: None,
                tier: "free".to_string(),
                created_at: now_iso8601(),
                updated_at: now_iso8601(),
                last_login_at: None,
                preferences: json!({}),
            });

        let next_token = generate_refresh_token();
        let next_hash = hash_refresh_token(&next_token);
        let next_exp_ms = refresh_token_expiry(now_ms);
        if let Some(s_mut) = g.sessions.get_mut(&sess_id) {
            s_mut.refresh_token_hash = next_hash;
            s_mut.expires_at_ms = next_exp_ms;
            s_mut.expires_at = epoch_ms_to_iso8601(next_exp_ms);
        }

        Ok(Some(RotatedSession {
            refresh_token: next_token,
            user: RotatedSessionUser {
                id: user.id,
                email: user.email,
                tier: user.tier,
            },
        }))
    }

    pub fn revoke_refresh_token(
        store: &DataStore,
        raw_refresh_token: &str,
    ) -> Result<bool, AppError> {
        store.check_injected_error()?;
        if raw_refresh_token.is_empty() {
            return Ok(false);
        }
        let token_hash = hash_refresh_token(raw_refresh_token);
        let mut g = store.inner.lock().unwrap();
        let before = g.sessions.len();
        g.sessions.retain(|_, s| s.refresh_token_hash != token_hash);
        Ok(g.sessions.len() < before)
    }
}

// ============================================================================
// 2. UserService
// ============================================================================

pub struct UserService;

impl UserService {
    pub fn get_user_by_id(store: &DataStore, user_id: &str) -> Result<Option<Value>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        Ok(g.users
            .get(user_id)
            .and_then(|u| serde_json::to_value(u).ok()))
    }

    pub fn update_user(
        store: &DataStore,
        user_id: &str,
        input: UserUpdateInput,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let mut g = store.inner.lock().unwrap();
        let Some(u) = g.users.get_mut(user_id) else {
            return Err(AppError::not_found("User not found"));
        };
        if let Some(name) = input.name {
            u.name = Some(name);
        }
        if let Some(prefs) = input.preferences {
            u.preferences = Value::Object(prefs);
        }
        u.updated_at = now_iso8601();
        serde_json::to_value(u.clone()).map_err(|e| AppError::internal(e.to_string()))
    }

    pub fn delete_user(store: &DataStore, user_id: &str) -> Result<(), AppError> {
        store.check_injected_error()?;
        let mut g = store.inner.lock().unwrap();
        g.users.remove(user_id);
        let ws_ids: Vec<String> = g
            .workspaces
            .values()
            .filter(|w| w.user_id == user_id)
            .map(|w| w.id.clone())
            .collect();
        for wid in ws_ids {
            g.workspaces.remove(&wid);
            g.tabs.retain(|_, t| t.workspace_id != wid);
            g.sections.retain(|_, s| s.workspace_id != wid);
            g.resources.retain(|_, r| r.workspace_id != wid);
            g.notes.retain(|_, n| n.workspace_id != wid);
            g.tasks.retain(|_, t| t.workspace_id != wid);
            g.collaborators.retain(|_, c| c.workspace_id != wid);
            g.share_links.retain(|_, l| l.workspace_id != wid);
        }
        g.space_groups.retain(|_, sg| sg.user_id != user_id);
        g.backups.retain(|_, b| b.user_id != user_id);
        g.sessions.retain(|_, s| s.user_id != user_id);
        Ok(())
    }

    pub fn get_password_reset_url(api_url: &str, _email: &str) -> String {
        format!("{api_url}/api/v1/auth/login?action=reset_password")
    }
}

// ============================================================================
// 3. PermissionService
// ============================================================================

pub struct PermissionService;

fn role_rank(role: &str) -> u8 {
    match role {
        "owner" => 3,
        "edit" => 2,
        "view" => 1,
        _ => 0,
    }
}

impl PermissionService {
    pub fn resolve_access(
        store: &DataStore,
        user_id: &str,
        workspace_id: &str,
    ) -> Result<Option<String>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let Some(ws) = g.workspaces.get(workspace_id) else {
            return Ok(None);
        };
        if ws.user_id == user_id {
            return Ok(Some("owner".to_string()));
        }
        let grant = g.collaborators.values().find(|c| {
            c.workspace_id == workspace_id
                && c.user_id.as_deref() == Some(user_id)
                && c.status == "active"
        });
        Ok(grant.map(|g| g.role.clone()))
    }

    pub fn require_role(
        store: &DataStore,
        user_id: &str,
        workspace_id: &str,
        min_role: &str,
    ) -> Result<String, AppError> {
        let Some(role) = Self::resolve_access(store, user_id, workspace_id)? else {
            return Err(AppError::not_found("Workspace not found"));
        };
        if role_rank(&role) < role_rank(min_role) {
            return Err(AppError::forbidden_default());
        }
        Ok(role)
    }

    pub fn list_access_user_ids(
        store: &DataStore,
        workspace_id: &str,
    ) -> Result<Vec<String>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let Some(ws) = g.workspaces.get(workspace_id) else {
            return Ok(Vec::new());
        };
        let mut out = vec![ws.user_id.clone()];
        for c in g.collaborators.values() {
            if c.workspace_id == workspace_id && c.status == "active" {
                if let Some(uid) = &c.user_id {
                    if !out.contains(uid) {
                        out.push(uid.clone());
                    }
                }
            }
        }
        Ok(out)
    }

    pub fn list_spaces_shared_with(
        store: &DataStore,
        user_id: &str,
    ) -> Result<Vec<Value>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let mut grants: Vec<&SpaceCollaboratorRecord> = g
            .collaborators
            .values()
            .filter(|c| c.user_id.as_deref() == Some(user_id) && c.status == "active")
            .collect();
        grants.sort_by(|a, b| a.created_at.cmp(&b.created_at));
        let mut out = Vec::new();
        for c in grants {
            if let Some(ws) = g.workspaces.get(&c.workspace_id) {
                out.push(json!({
                    "workspaceId": c.workspace_id,
                    "role": c.role,
                    "name": ws.name,
                }));
            }
        }
        Ok(out)
    }
}

// ============================================================================
// 4. CollaboratorService
// ============================================================================

pub struct CollaboratorService;

impl CollaboratorService {
    fn to_public_grant(c: &SpaceCollaboratorRecord) -> Value {
        json!({
            "id": c.id,
            "inviteeEmail": c.invitee_email,
            "role": c.role,
            "status": c.status,
            "createdAt": c.created_at,
            "updatedAt": c.updated_at,
        })
    }

    pub fn share_by_email(
        store: &DataStore,
        workspace_id: &str,
        invited_by_user_id: &str,
        raw_email: &str,
        role: &str,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let invitee_email = raw_email.trim().to_ascii_lowercase();
        let mut g = store.inner.lock().unwrap();
        let matched_user_id = g
            .users
            .values()
            .find(|u| u.email.to_ascii_lowercase() == invitee_email)
            .map(|u| u.id.clone());
        let status = if matched_user_id.is_some() {
            "active"
        } else {
            "pending"
        };
        let now = now_iso8601();

        if let Some(existing) = g
            .collaborators
            .values_mut()
            .find(|c| c.workspace_id == workspace_id && c.invitee_email == invitee_email)
        {
            existing.role = role.to_string();
            if let Some(uid) = matched_user_id {
                existing.user_id = Some(uid);
                existing.status = "active".to_string();
            }
            existing.updated_at = now;
            return Ok(Self::to_public_grant(existing));
        }

        let id = generate_id("sc");
        let rec = SpaceCollaboratorRecord {
            id: id.clone(),
            workspace_id: workspace_id.to_string(),
            user_id: matched_user_id,
            invitee_email,
            role: role.to_string(),
            status: status.to_string(),
            invited_by_user_id: invited_by_user_id.to_string(),
            created_at: now.clone(),
            updated_at: now,
        };
        let pub_val = Self::to_public_grant(&rec);
        g.collaborators.insert(id, rec);
        Ok(pub_val)
    }

    pub fn list_collaborators(
        store: &DataStore,
        workspace_id: &str,
    ) -> Result<Vec<Value>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let mut list: Vec<&SpaceCollaboratorRecord> = g
            .collaborators
            .values()
            .filter(|c| c.workspace_id == workspace_id)
            .collect();
        list.sort_by(|a, b| a.created_at.cmp(&b.created_at));
        Ok(list.into_iter().map(Self::to_public_grant).collect())
    }

    pub fn set_role(
        store: &DataStore,
        workspace_id: &str,
        collaborator_id: &str,
        role: &str,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let mut g = store.inner.lock().unwrap();
        let Some(c) = g.collaborators.get_mut(collaborator_id) else {
            return Err(AppError::not_found("Collaborator not found"));
        };
        if c.workspace_id != workspace_id {
            return Err(AppError::not_found("Collaborator not found"));
        }
        c.role = role.to_string();
        c.updated_at = now_iso8601();
        Ok(Self::to_public_grant(c))
    }

    pub fn revoke(
        store: &DataStore,
        workspace_id: &str,
        collaborator_id: &str,
    ) -> Result<(), AppError> {
        store.check_injected_error()?;
        let mut g = store.inner.lock().unwrap();
        let matches = g
            .collaborators
            .get(collaborator_id)
            .map(|c| c.workspace_id == workspace_id)
            .unwrap_or(false);
        if !matches {
            return Err(AppError::not_found("Collaborator not found"));
        }
        g.collaborators.remove(collaborator_id);
        Ok(())
    }
}

// ============================================================================
// 5. ShareService
// ============================================================================

pub struct ShareService;

fn higher_role(a: &str, b: &str) -> String {
    if a == "edit" || b == "edit" {
        "edit".to_string()
    } else {
        "view".to_string()
    }
}

impl ShareService {
    fn to_public_link(l: &ShareLinkRecord) -> Value {
        json!({
            "id": l.id,
            "role": l.role,
            "label": l.label,
            "expiresAt": l.expires_at,
            "revokedAt": l.revoked_at,
            "createdAt": l.created_at,
        })
    }

    pub fn create_link(
        store: &DataStore,
        workspace_id: &str,
        created_by_user_id: &str,
        role: &str,
        label: Option<String>,
        expires_at: Option<String>,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let token = generate_opaque_token();
        let token_hash = hash_token(&token);
        let relay_id = generate_opaque_token();
        let relay_id_hash = hash_token(&relay_id);
        let expires_at_ms = expires_at.as_deref().and_then(parse_datetime_ms);
        let now = now_iso8601();
        let id = generate_id("sl");

        let rec = ShareLinkRecord {
            id: id.clone(),
            workspace_id: workspace_id.to_string(),
            token_hash,
            relay_id_hash: Some(relay_id_hash),
            role: role.to_string(),
            label: label.clone(),
            created_by_user_id: created_by_user_id.to_string(),
            expires_at: expires_at.clone(),
            expires_at_ms,
            revoked_at: None,
            created_at: now.clone(),
        };

        let mut g = store.inner.lock().unwrap();
        g.share_links.insert(id.clone(), rec);

        Ok(json!({
            "id": id,
            "role": role,
            "label": label,
            "expiresAt": expires_at,
            "revokedAt": Value::Null,
            "createdAt": now,
            "token": token,
            "relayId": relay_id,
        }))
    }

    pub fn list_links(store: &DataStore, workspace_id: &str) -> Result<Vec<Value>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let mut list: Vec<&ShareLinkRecord> = g
            .share_links
            .values()
            .filter(|l| l.workspace_id == workspace_id && l.revoked_at.is_none())
            .collect();
        list.sort_by(|a, b| a.created_at.cmp(&b.created_at));
        Ok(list.into_iter().map(Self::to_public_link).collect())
    }

    pub fn revoke_link(
        store: &DataStore,
        workspace_id: &str,
        link_id: &str,
    ) -> Result<(), AppError> {
        store.check_injected_error()?;
        let mut g = store.inner.lock().unwrap();
        let Some(link) = g.share_links.get_mut(link_id) else {
            return Err(AppError::not_found("Share link not found"));
        };
        if link.workspace_id != workspace_id || link.revoked_at.is_some() {
            return Err(AppError::not_found("Share link not found"));
        }
        link.revoked_at = Some(now_iso8601());
        Ok(())
    }

    fn resolve_valid_link_inner<'a>(
        g: &'a crate::store::DataStoreInner,
        by_token_hash: Option<&str>,
        by_relay_hash: Option<&str>,
    ) -> Result<(&'a ShareLinkRecord, &'a WorkspaceRecord, Option<String>), AppError> {
        let now_ms = now_epoch_ms();
        let link = g
            .share_links
            .values()
            .find(|l| {
                if let Some(th) = by_token_hash {
                    l.token_hash == th
                } else if let Some(rh) = by_relay_hash {
                    l.relay_id_hash.as_deref() == Some(rh)
                } else {
                    false
                }
            })
            .ok_or_else(|| AppError::not_found("Share link not found or expired"))?;

        if link.revoked_at.is_some() {
            return Err(AppError::not_found("Share link not found or expired"));
        }
        if let Some(exp_ms) = link.expires_at_ms {
            if exp_ms <= now_ms {
                return Err(AppError::not_found("Share link not found or expired"));
            }
        }
        let ws = g
            .workspaces
            .get(&link.workspace_id)
            .ok_or_else(|| AppError::not_found("Share link not found or expired"))?;
        let owner_name = g.users.get(&ws.user_id).and_then(|u| u.name.clone());
        Ok((link, ws, owner_name))
    }

    pub fn get_link_info(store: &DataStore, raw_token: &str) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let th = hash_token(raw_token);
        let g = store.inner.lock().unwrap();
        let (link, ws, owner_name) = Self::resolve_valid_link_inner(&g, Some(&th), None)?;
        Ok(json!({
            "workspaceId": link.workspace_id,
            "workspaceName": ws.name,
            "ownerName": owner_name,
            "role": link.role,
        }))
    }

    pub fn get_relay_info(store: &DataStore, raw_relay_id: &str) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let rh = hash_token(raw_relay_id);
        let g = store.inner.lock().unwrap();
        let (link, ws, owner_name) = Self::resolve_valid_link_inner(&g, None, Some(&rh))?;
        Ok(json!({
            "workspaceId": link.workspace_id,
            "workspaceName": ws.name,
            "ownerName": owner_name,
            "role": link.role,
        }))
    }

    pub fn accept_link(
        store: &DataStore,
        raw_token: &str,
        user_id: &str,
        user_email: &str,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let th = hash_token(raw_token);
        let mut g = store.inner.lock().unwrap();
        let (link_ws_id, link_role, link_creator, ws_name, ws_owner) = {
            let (link, ws, _) = Self::resolve_valid_link_inner(&g, Some(&th), None)?;
            (
                link.workspace_id.clone(),
                link.role.clone(),
                link.created_by_user_id.clone(),
                ws.name.clone(),
                ws.user_id.clone(),
            )
        };
        Self::materialize_grant_inner(
            &mut g,
            &link_ws_id,
            &link_role,
            &link_creator,
            &ws_name,
            &ws_owner,
            user_id,
            user_email,
        )
    }

    pub fn accept_by_relay_id(
        store: &DataStore,
        raw_relay_id: &str,
        user_id: &str,
        user_email: &str,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let rh = hash_token(raw_relay_id);
        let mut g = store.inner.lock().unwrap();
        let (link_ws_id, link_role, link_creator, ws_name, ws_owner) = {
            let (link, ws, _) = Self::resolve_valid_link_inner(&g, None, Some(&rh))?;
            (
                link.workspace_id.clone(),
                link.role.clone(),
                link.created_by_user_id.clone(),
                ws.name.clone(),
                ws.user_id.clone(),
            )
        };
        Self::materialize_grant_inner(
            &mut g,
            &link_ws_id,
            &link_role,
            &link_creator,
            &ws_name,
            &ws_owner,
            user_id,
            user_email,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn materialize_grant_inner(
        g: &mut crate::store::DataStoreInner,
        workspace_id: &str,
        link_role: &str,
        created_by_user_id: &str,
        workspace_name: &str,
        workspace_owner: &str,
        user_id: &str,
        user_email: &str,
    ) -> Result<Value, AppError> {
        if workspace_owner == user_id {
            return Ok(json!({
                "workspaceId": workspace_id,
                "workspaceName": workspace_name,
                "role": "owner",
            }));
        }

        let invitee_email = user_email.trim().to_ascii_lowercase();
        let now = now_iso8601();

        if let Some(existing) = g
            .collaborators
            .values_mut()
            .find(|c| c.workspace_id == workspace_id && c.invitee_email == invitee_email)
        {
            let effective_role = higher_role(&existing.role, link_role);
            existing.user_id = Some(user_id.to_string());
            existing.role = effective_role.clone();
            existing.status = "active".to_string();
            existing.updated_at = now;
            return Ok(json!({
                "workspaceId": workspace_id,
                "workspaceName": workspace_name,
                "role": effective_role,
            }));
        }

        let id = generate_id("sc");
        let rec = SpaceCollaboratorRecord {
            id: id.clone(),
            workspace_id: workspace_id.to_string(),
            user_id: Some(user_id.to_string()),
            invitee_email,
            role: link_role.to_string(),
            status: "active".to_string(),
            invited_by_user_id: created_by_user_id.to_string(),
            created_at: now.clone(),
            updated_at: now,
        };
        g.collaborators.insert(id, rec);
        Ok(json!({
            "workspaceId": workspace_id,
            "workspaceName": workspace_name,
            "role": link_role,
        }))
    }
}

// ============================================================================
// 6. SpaceGroupService
// ============================================================================

pub struct SpaceGroupService;

impl SpaceGroupService {
    pub fn generate_id(prefix: &str) -> String {
        generate_id(prefix)
    }

    pub fn get_all_space_groups(
        store: &DataStore,
        user_id: &str,
    ) -> Result<Vec<SpaceGroupRecord>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let mut list: Vec<SpaceGroupRecord> = g
            .space_groups
            .values()
            .filter(|sg| sg.user_id == user_id)
            .cloned()
            .collect();
        list.sort_by_key(|sg| sg.position);
        Ok(list)
    }

    pub fn get_space_group_by_id(
        store: &DataStore,
        user_id: &str,
        group_id: &str,
    ) -> Result<SpaceGroupRecord, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let sg = g
            .space_groups
            .get(group_id)
            .filter(|sg| sg.user_id == user_id)
            .cloned()
            .ok_or_else(|| AppError::internal("Space group not found"))?;
        Ok(sg)
    }

    pub fn create_space_group(
        store: &DataStore,
        _redis: &dyn RedisStore,
        user_id: &str,
        input: SpaceGroupCreateInput,
        _device_id: Option<&str>,
    ) -> Result<SpaceGroupRecord, AppError> {
        store.check_injected_error()?;
        let id = input.id.unwrap_or_else(|| Self::generate_id("sg"));
        let now = now_iso8601();
        let rec = SpaceGroupRecord {
            id: id.clone(),
            user_id: user_id.to_string(),
            title: input.title,
            color: input.color,
            collapsed: input.collapsed,
            position: input.position,
            version: 0,
            created_at: now.clone(),
            updated_at: now,
        };
        {
            let mut g = store.inner.lock().unwrap();
            g.space_groups.insert(id.clone(), rec.clone());
        }
        Ok(rec)
    }

    pub fn update_space_group(
        store: &DataStore,
        _redis: &dyn RedisStore,
        user_id: &str,
        group_id: &str,
        input: SpaceGroupUpdateInput,
        _device_id: Option<&str>,
    ) -> Result<SpaceGroupRecord, AppError> {
        store.check_injected_error()?;
        let updated = {
            let mut g = store.inner.lock().unwrap();
            let Some(sg) = g.space_groups.get_mut(group_id) else {
                return Err(AppError::internal("Space group not found"));
            };
            if sg.user_id != user_id {
                return Err(AppError::internal("Space group not found"));
            }
            if let Some(bv) = input.base_version {
                if bv < sg.version {
                    return Err(AppError::conflict(
                        "Space group was modified by another device",
                        sg.version,
                    ));
                }
            }
            if let Some(title) = input.title {
                sg.title = title;
            }
            if let Some(collapsed) = input.collapsed {
                sg.collapsed = collapsed;
            }
            if let Some(position) = input.position {
                sg.position = position;
            }
            if let Some(color) = input.color {
                sg.color = color;
            }
            sg.version += 1;
            sg.updated_at = now_iso8601();
            sg.clone()
        };
        Ok(updated)
    }

    pub fn delete_space_group(
        store: &DataStore,
        _redis: &dyn RedisStore,
        user_id: &str,
        group_id: &str,
        _device_id: Option<&str>,
    ) -> Result<(), AppError> {
        store.check_injected_error()?;
        {
            let mut g = store.inner.lock().unwrap();
            let exists = g
                .space_groups
                .get(group_id)
                .map(|sg| sg.user_id == user_id)
                .unwrap_or(false);
            if !exists {
                return Err(AppError::internal("Space group not found"));
            }
            g.space_groups.remove(group_id);
            for ws in g.workspaces.values_mut() {
                if ws.group_id.as_deref() == Some(group_id) {
                    ws.group_id = None;
                }
            }
        }
        Ok(())
    }
}

// ============================================================================
// 7. WorkspaceService
// ============================================================================

pub struct WorkspaceService;

impl WorkspaceService {
    pub fn generate_id(prefix: &str) -> String {
        generate_id(prefix)
    }

    fn build_tab_rows(workspace_id: &str, tabs: &[ParsedTab]) -> Vec<TabRecord> {
        let now = now_iso8601();
        tabs.iter()
            .enumerate()
            .map(|(index, tab)| {
                let mut meta = tab.metadata.clone();
                meta.insert(
                    "groupId".to_string(),
                    tab.group_id
                        .clone()
                        .filter(|s| !s.is_empty())
                        .map(Value::String)
                        .unwrap_or(Value::Null),
                );
                if let Some(client_id) = &tab.id {
                    let s = match client_id {
                        Value::String(s) => s.clone(),
                        Value::Number(n) => n.to_string(),
                        _ => String::new(),
                    };
                    if !s.is_empty() {
                        meta.insert("clientTabId".to_string(), Value::String(s));
                    }
                }
                TabRecord {
                    id: Self::generate_id("tab"),
                    workspace_id: workspace_id.to_string(),
                    url: tab.url.clone(),
                    title: tab.title.clone(),
                    favicon_url: tab.favicon_url.clone(),
                    position: tab.position.unwrap_or(index as i64),
                    is_pinned: tab.is_pinned,
                    created_at: now.clone(),
                    updated_at: now.clone(),
                    last_accessed_at: now.clone(),
                    metadata: Value::Object(meta),
                }
            })
            .collect()
    }

    fn write_sections(
        g: &mut crate::store::DataStoreInner,
        workspace_id: &str,
        sections: &[ParsedSection],
        resources: Option<&[ParsedResource]>,
    ) {
        let now = now_iso8601();
        let section_rows: Vec<(String, String, i64)> = sections
            .iter()
            .enumerate()
            .map(|(idx, s)| {
                let id =
                    s.id.clone()
                        .filter(|s| !s.is_empty())
                        .unwrap_or_else(|| Self::generate_id("sec"));
                (id, s.title.clone(), s.position.unwrap_or(idx as i64))
            })
            .collect();

        for (id, title, pos) in &section_rows {
            g.sections.insert(
                id.clone(),
                SectionRecord {
                    id: id.clone(),
                    workspace_id: workspace_id.to_string(),
                    title: title.clone(),
                    position: *pos,
                    created_at: now.clone(),
                    updated_at: now.clone(),
                },
            );
        }

        let mut seen_res_ids = HashSet::new();
        for (sec_idx, s) in sections.iter().enumerate() {
            let sec_id = &section_rows[sec_idx].0;
            if let Some(sec_resources) = &s.resources {
                for (r_idx, r) in sec_resources.iter().enumerate() {
                    let rid =
                        r.id.clone()
                            .filter(|s| !s.is_empty())
                            .unwrap_or_else(|| Self::generate_id("res"));
                    seen_res_ids.insert(rid.clone());
                    g.resources.insert(
                        rid.clone(),
                        ResourceRecord {
                            id: rid,
                            workspace_id: workspace_id.to_string(),
                            section_id: Some(sec_id.clone()),
                            title: r.title.clone(),
                            url: r.url.clone(),
                            favicon_url: r.favicon_url.clone(),
                            position: r.position.unwrap_or(r_idx as i64),
                            created_at: now.clone(),
                            updated_at: now.clone(),
                        },
                    );
                }
            }
        }

        if let Some(top_resources) = resources {
            for (r_idx, r) in top_resources.iter().enumerate() {
                if let Some(id) = &r.id {
                    if seen_res_ids.contains(id) {
                        continue;
                    }
                }
                let rid =
                    r.id.clone()
                        .filter(|s| !s.is_empty())
                        .unwrap_or_else(|| Self::generate_id("res"));
                seen_res_ids.insert(rid.clone());
                g.resources.insert(
                    rid.clone(),
                    ResourceRecord {
                        id: rid,
                        workspace_id: workspace_id.to_string(),
                        section_id: r.section_id.clone(),
                        title: r.title.clone(),
                        url: r.url.clone(),
                        favicon_url: r.favicon_url.clone(),
                        position: r.position.unwrap_or(r_idx as i64),
                        created_at: now.clone(),
                        updated_at: now.clone(),
                    },
                );
            }
        }
    }

    fn write_notes(g: &mut crate::store::DataStoreInner, workspace_id: &str, notes: &[ParsedNote]) {
        let now = now_iso8601();
        for (idx, n) in notes.iter().enumerate() {
            let id =
                n.id.clone()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| Self::generate_id("note"));
            g.notes.insert(
                id.clone(),
                NoteRecord {
                    id,
                    workspace_id: workspace_id.to_string(),
                    title: n.title.clone(),
                    content: n.content.clone(),
                    position: n.position.unwrap_or(idx as i64),
                    created_at: now.clone(),
                    updated_at: now.clone(),
                },
            );
        }
    }

    fn write_tasks(g: &mut crate::store::DataStoreInner, workspace_id: &str, tasks: &[ParsedTask]) {
        let now = now_iso8601();
        for (idx, t) in tasks.iter().enumerate() {
            let id =
                t.id.clone()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| Self::generate_id("task"));
            let due_date = t
                .due_date
                .as_deref()
                .and_then(parse_datetime_ms)
                .map(epoch_ms_to_iso8601);
            g.tasks.insert(
                id.clone(),
                TaskRecord {
                    id,
                    workspace_id: workspace_id.to_string(),
                    title: t.title.clone(),
                    completed: t.completed,
                    due_date,
                    position: t.position.unwrap_or(idx as i64),
                    created_at: now.clone(),
                    updated_at: now.clone(),
                },
            );
        }
    }

    fn write_top_resources(
        g: &mut crate::store::DataStoreInner,
        workspace_id: &str,
        resources: &[ParsedResource],
    ) {
        let now = now_iso8601();
        for (idx, r) in resources.iter().enumerate() {
            let id =
                r.id.clone()
                    .filter(|s| !s.is_empty())
                    .unwrap_or_else(|| Self::generate_id("res"));
            g.resources.insert(
                id.clone(),
                ResourceRecord {
                    id,
                    workspace_id: workspace_id.to_string(),
                    section_id: r.section_id.clone(),
                    title: r.title.clone(),
                    url: r.url.clone(),
                    favicon_url: r.favicon_url.clone(),
                    position: r.position.unwrap_or(idx as i64),
                    created_at: now.clone(),
                    updated_at: now.clone(),
                },
            );
        }
    }

    pub fn get_all_workspaces(store: &DataStore, user_id: &str) -> Result<Vec<Value>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let mut owned: Vec<&WorkspaceRecord> = g
            .workspaces
            .values()
            .filter(|w| w.user_id == user_id)
            .collect();
        owned.sort_by_key(|w| w.position);

        let result: Vec<Value> = owned
            .into_iter()
            .map(|w| DataStore::hydrate_workspace_json(&g, w))
            .collect();
        Ok(result)
    }

    pub fn get_workspace_by_id(
        store: &DataStore,
        user_id: &str,
        workspace_id: &str,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        PermissionService::require_role(store, user_id, workspace_id, "view")?;
        let g = store.inner.lock().unwrap();
        let ws = g
            .workspaces
            .get(workspace_id)
            .ok_or_else(|| AppError::not_found("Workspace not found"))?;
        Ok(DataStore::hydrate_workspace_json(&g, ws))
    }

    pub fn create_workspace(
        store: &DataStore,
        _redis: &dyn RedisStore,
        user_id: &str,
        user_tier: &str,
        input: WorkspaceCreateInput,
        _device_id: Option<&str>,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let current_count = {
            let g = store.inner.lock().unwrap();
            g.workspaces
                .values()
                .filter(|w| w.user_id == user_id)
                .count()
        };
        if !is_within_limit(user_tier, "maxWorkspaces", current_count) {
            return Err(AppError::internal(
                "Maximum number of workspaces reached for free tier (10)",
            ));
        }

        let workspace_id = input.id.unwrap_or_else(|| Self::generate_id("ws"));
        let mut settings_map = input.settings;
        if let Some(tg) = input.tab_groups {
            settings_map.insert("tabGroups".to_string(), Value::Array(tg));
        }
        let now = now_iso8601();

        let ws_rec = WorkspaceRecord {
            id: workspace_id.clone(),
            user_id: user_id.to_string(),
            group_id: input.group_id,
            name: input.name,
            description: input.description,
            color: input.color,
            icon: input.icon,
            position: input.position,
            version: 0,
            active_device_id: None,
            active_device_seen_at: None,
            active_device_seen_at_ms: None,
            created_at: now.clone(),
            updated_at: now,
            settings: Value::Object(settings_map),
        };

        let hydrated = {
            let mut g = store.inner.lock().unwrap();
            g.workspaces.insert(workspace_id.clone(), ws_rec.clone());

            if let Some(tabs) = &input.tabs {
                if !tabs.is_empty() {
                    for row in Self::build_tab_rows(&workspace_id, tabs) {
                        g.tabs.insert(row.id.clone(), row);
                    }
                }
            }
            if let Some(sections) = &input.sections {
                if !sections.is_empty() {
                    Self::write_sections(
                        &mut g,
                        &workspace_id,
                        sections,
                        input.resources.as_deref(),
                    );
                } else if let Some(resources) = &input.resources {
                    if !resources.is_empty() {
                        Self::write_top_resources(&mut g, &workspace_id, resources);
                    }
                }
            } else if let Some(resources) = &input.resources {
                if !resources.is_empty() {
                    Self::write_top_resources(&mut g, &workspace_id, resources);
                }
            }
            if let Some(notes) = &input.notes {
                if !notes.is_empty() {
                    Self::write_notes(&mut g, &workspace_id, notes);
                }
            }
            if let Some(tasks) = &input.tasks {
                if !tasks.is_empty() {
                    Self::write_tasks(&mut g, &workspace_id, tasks);
                }
            }

            DataStore::hydrate_workspace_json(&g, &ws_rec)
        };
        Ok(hydrated)
    }

    pub fn update_workspace(
        store: &DataStore,
        _redis: &dyn RedisStore,
        user_id: &str,
        workspace_id: &str,
        input: WorkspaceUpdateInput,
        device_id: Option<&str>,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let role = PermissionService::require_role(store, user_id, workspace_id, "edit")?;

        let mut g = store.inner.lock().unwrap();
        let Some(current) = g.workspaces.get(workspace_id).cloned() else {
            return Err(AppError::not_found("Workspace not found"));
        };

        let now_ms = now_epoch_ms();
        let lease_held_by_other = match (
            device_id,
            current.active_device_id.as_deref(),
            current.active_device_seen_at_ms,
        ) {
            (Some(caller_dev), Some(holder_dev), Some(seen_ms)) => {
                caller_dev != holder_dev && (now_ms - seen_ms) < ACTIVE_DEVICE_STALE_MS
            }
            _ => false,
        };

        let is_passive_tab_sync = input.tab_sync == Some(true)
            && input.claim_active_device != Some(true)
            && lease_held_by_other;

        if is_passive_tab_sync {
            return Ok(DataStore::hydrate_workspace_json(&g, &current));
        }

        if let Some(bv) = input.base_version {
            if bv < current.version {
                return Err(AppError::conflict(
                    "Workspace was modified by another device",
                    current.version,
                ));
            }
        }

        let ws = g.workspaces.get_mut(workspace_id).unwrap();
        if let Some(name) = input.name {
            ws.name = name;
        }
        if let Some(desc) = input.description {
            ws.description = desc;
        }
        if let Some(color) = input.color {
            ws.color = color;
        }
        if let Some(icon) = input.icon {
            ws.icon = icon;
        }
        if let Some(pos) = input.position {
            ws.position = pos;
        }
        if let Some(gid) = input.group_id {
            ws.group_id = gid;
        }

        if input.settings.is_some() || input.tab_groups.is_some() {
            let stored = ws.settings.as_object().cloned().unwrap_or_default();
            let mut merged = input.settings.unwrap_or_else(|| stored.clone());
            if let Some(tg) = input.tab_groups {
                merged.insert("tabGroups".to_string(), Value::Array(tg));
            } else if !merged.contains_key("tabGroups") {
                let stored_tg = stored
                    .get("tabGroups")
                    .cloned()
                    .unwrap_or_else(|| Value::Array(Vec::new()));
                merged.insert("tabGroups".to_string(), stored_tg);
            }
            ws.settings = Value::Object(merged);
        }

        if role == "owner"
            && device_id.is_some()
            && (input.claim_active_device == Some(true)
                || (input.tab_sync == Some(true) && !lease_held_by_other))
        {
            ws.active_device_id = device_id.map(|s| s.to_string());
            ws.active_device_seen_at_ms = Some(now_ms);
            ws.active_device_seen_at = Some(epoch_ms_to_iso8601(now_ms));
        }

        ws.version = current.version + 1;
        ws.updated_at = epoch_ms_to_iso8601(now_ms);

        if let Some(sections) = &input.sections {
            g.sections.retain(|_, s| s.workspace_id != workspace_id);
            g.resources.retain(|_, r| r.workspace_id != workspace_id);
            Self::write_sections(&mut g, workspace_id, sections, input.resources.as_deref());
        } else if let Some(resources) = &input.resources {
            g.resources.retain(|_, r| r.workspace_id != workspace_id);
            Self::write_top_resources(&mut g, workspace_id, resources);
        }

        if let Some(notes) = &input.notes {
            g.notes.retain(|_, n| n.workspace_id != workspace_id);
            Self::write_notes(&mut g, workspace_id, notes);
        }

        if let Some(tasks) = &input.tasks {
            g.tasks.retain(|_, t| t.workspace_id != workspace_id);
            Self::write_tasks(&mut g, workspace_id, tasks);
        }

        if let Some(tabs) = &input.tabs {
            g.tabs.retain(|_, t| t.workspace_id != workspace_id);
            for row in Self::build_tab_rows(workspace_id, tabs) {
                g.tabs.insert(row.id.clone(), row);
            }
        }

        let ws_snap = g.workspaces.get(workspace_id).unwrap().clone();
        Ok(DataStore::hydrate_workspace_json(&g, &ws_snap))
    }

    pub fn delete_workspace(
        store: &DataStore,
        _redis: &dyn RedisStore,
        user_id: &str,
        workspace_id: &str,
        _device_id: Option<&str>,
    ) -> Result<(), AppError> {
        store.check_injected_error()?;
        PermissionService::require_role(store, user_id, workspace_id, "owner")?;

        let mut g = store.inner.lock().unwrap();
        if g.workspaces.remove(workspace_id).is_none() {
            return Err(AppError::not_found("Workspace not found"));
        }
        g.tabs.retain(|_, t| t.workspace_id != workspace_id);
        g.sections.retain(|_, s| s.workspace_id != workspace_id);
        g.resources.retain(|_, r| r.workspace_id != workspace_id);
        g.notes.retain(|_, n| n.workspace_id != workspace_id);
        g.tasks.retain(|_, t| t.workspace_id != workspace_id);
        g.collaborators
            .retain(|_, c| c.workspace_id != workspace_id);
        g.share_links.retain(|_, l| l.workspace_id != workspace_id);
        for b in g.backups.values_mut() {
            if b.workspace_id.as_deref() == Some(workspace_id) {
                b.workspace_id = None;
            }
        }
        Ok(())
    }

    pub fn save_tabs_to_workspace(
        store: &DataStore,
        _redis: &dyn RedisStore,
        user_id: &str,
        workspace_id: &str,
        tabs: &[ParsedTab],
        _device_id: Option<&str>,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        PermissionService::require_role(store, user_id, workspace_id, "edit")?;

        let mut g = store.inner.lock().unwrap();
        let Some(ws) = g.workspaces.get_mut(workspace_id) else {
            return Err(AppError::not_found("Workspace not found"));
        };
        ws.updated_at = now_iso8601();
        let ws_clone = ws.clone();
        g.tabs.retain(|_, t| t.workspace_id != workspace_id);
        if !tabs.is_empty() {
            for row in Self::build_tab_rows(workspace_id, tabs) {
                g.tabs.insert(row.id.clone(), row);
            }
        }
        Ok(DataStore::hydrate_workspace_json(&g, &ws_clone))
    }

    pub fn exists(store: &DataStore, workspace_id: &str) -> bool {
        let g = store.inner.lock().unwrap();
        g.workspaces.contains_key(workspace_id)
    }

    pub fn move_tab(
        store: &DataStore,
        user_id: &str,
        tab_id: &str,
        target_workspace_id: &str,
    ) -> Result<TabRecord, AppError> {
        Self::move_tab_with_position(store, user_id, tab_id, target_workspace_id, None)
    }

    pub fn move_tab_with_position(
        store: &DataStore,
        user_id: &str,
        tab_id: &str,
        target_workspace_id: &str,
        position: Option<i64>,
    ) -> Result<TabRecord, AppError> {
        store.check_injected_error()?;
        PermissionService::require_role(store, user_id, target_workspace_id, "edit")?;
        let source_ws_id = {
            let g = store.inner.lock().unwrap();
            let Some(tab) = g.tabs.get(tab_id) else {
                return Err(AppError::not_found("Tab not found"));
            };
            tab.workspace_id.clone()
        };
        if source_ws_id == target_workspace_id {
            PermissionService::require_role(store, user_id, &source_ws_id, "edit")?;
        } else {
            PermissionService::require_role(store, user_id, &source_ws_id, "owner")?;
        }

        let mut g = store.inner.lock().unwrap();
        let Some(tab) = g.tabs.get_mut(tab_id) else {
            return Err(AppError::not_found("Tab not found"));
        };
        tab.workspace_id = target_workspace_id.to_string();
        tab.position = position.unwrap_or(0);
        tab.updated_at = now_iso8601();
        Ok(tab.clone())
    }

    pub fn bulk_delete_tabs(
        store: &DataStore,
        user_id: &str,
        tab_ids: &[String],
    ) -> Result<usize, AppError> {
        store.check_injected_error()?;
        let ws_ids: Vec<String> = {
            let g = store.inner.lock().unwrap();
            let mut seen = HashSet::new();
            let mut out = Vec::new();
            for id in tab_ids {
                if let Some(t) = g.tabs.get(id) {
                    if seen.insert(t.workspace_id.clone()) {
                        out.push(t.workspace_id.clone());
                    }
                }
            }
            out
        };
        for wid in ws_ids {
            PermissionService::require_role(store, user_id, &wid, "edit")?;
        }
        let mut g = store.inner.lock().unwrap();
        for id in tab_ids {
            g.tabs.remove(id);
        }
        Ok(tab_ids.len())
    }

    pub fn bulk_update_tabs(
        store: &DataStore,
        user_id: &str,
        tab_ids: &[String],
        action: &str,
    ) -> Result<usize, AppError> {
        store.check_injected_error()?;
        let ws_ids: Vec<String> = {
            let g = store.inner.lock().unwrap();
            let mut seen = HashSet::new();
            let mut out = Vec::new();
            for id in tab_ids {
                if let Some(t) = g.tabs.get(id) {
                    if seen.insert(t.workspace_id.clone()) {
                        out.push(t.workspace_id.clone());
                    }
                }
            }
            out
        };
        for wid in ws_ids {
            PermissionService::require_role(store, user_id, &wid, "edit")?;
        }
        let is_pinned = action == "pin";
        let now = now_iso8601();
        let mut g = store.inner.lock().unwrap();
        for id in tab_ids {
            if let Some(tab) = g.tabs.get_mut(id) {
                tab.is_pinned = is_pinned;
                tab.updated_at = now.clone();
            }
        }
        Ok(tab_ids.len())
    }

    pub fn reorder_tab(
        store: &DataStore,
        user_id: &str,
        tab_id: &str,
        new_position: i64,
    ) -> Result<TabRecord, AppError> {
        store.check_injected_error()?;
        let ws_id = {
            let g = store.inner.lock().unwrap();
            let Some(tab) = g.tabs.get(tab_id) else {
                return Err(AppError::not_found("Tab not found"));
            };
            tab.workspace_id.clone()
        };
        PermissionService::require_role(store, user_id, &ws_id, "edit")?;
        let mut g = store.inner.lock().unwrap();
        let Some(tab) = g.tabs.get_mut(tab_id) else {
            return Err(AppError::not_found("Tab not found"));
        };
        tab.position = new_position;
        tab.updated_at = now_iso8601();
        Ok(tab.clone())
    }
}

// ============================================================================
// 8. BackupService
// ============================================================================

pub struct BackupService;

impl BackupService {
    pub fn cleanup_old_backups(
        store: &DataStore,
        user_id: &str,
        tier: &str,
    ) -> Result<usize, AppError> {
        store.check_injected_error()?;
        let limits = get_tier_limits(tier);
        let cutoff_ms =
            now_epoch_ms() - (limits.backup_retention_days as i64) * 24 * 60 * 60 * 1000;
        let mut g = store.inner.lock().unwrap();
        let before = g.backups.len();
        g.backups
            .retain(|_, b| !(b.user_id == user_id && b.created_at_ms < cutoff_ms));
        Ok(before - g.backups.len())
    }

    pub fn create_backup(
        store: &DataStore,
        user_id: &str,
        tier: &str,
        options: BackupCreateInput,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let _ = Self::cleanup_old_backups(store, user_id, tier)?;

        let mut g = store.inner.lock().unwrap();
        let current_count = g.backups.values().filter(|b| b.user_id == user_id).count();
        let validation = validate_tier_limit(tier, "maxBackups", current_count);

        if !validation.valid {
            if options.backup_type == "auto" {
                let oldest_auto = g
                    .backups
                    .values()
                    .filter(|b| b.user_id == user_id && b.backup_type == "auto")
                    .min_by_key(|b| b.created_at_ms)
                    .map(|b| b.id.clone());
                if let Some(evict_id) = oldest_auto {
                    g.backups.remove(&evict_id);
                } else {
                    return Err(AppError::internal(
                        validation
                            .message
                            .unwrap_or_else(|| "Backup limit reached".to_string()),
                    ));
                }
            } else {
                return Err(AppError::internal(
                    validation
                        .message
                        .unwrap_or_else(|| "Backup limit reached".to_string()),
                ));
            }
        }

        let mut workspaces: Vec<&WorkspaceRecord> = g
            .workspaces
            .values()
            .filter(|w| {
                w.user_id == user_id
                    && options
                        .workspace_id
                        .as_deref()
                        .map(|wid| w.id == wid)
                        .unwrap_or(true)
            })
            .collect();
        workspaces.sort_by_key(|w| w.position);

        if options.workspace_id.is_some() && workspaces.is_empty() {
            return Err(AppError::internal("Workspace not found"));
        }

        let mut snapshots = Vec::with_capacity(workspaces.len());
        for ws in workspaces {
            let mut tabs: Vec<Value> = g
                .tabs
                .values()
                .filter(|t| t.workspace_id == ws.id)
                .collect::<Vec<_>>()
                .into_iter()
                .map(|t| {
                    json!({
                        "id": t.id,
                        "url": t.url,
                        "title": t.title,
                        "faviconUrl": t.favicon_url,
                        "position": t.position,
                        "isPinned": t.is_pinned,
                        "metadata": t.metadata,
                    })
                })
                .collect();
            tabs.sort_by_key(|t| t.get("position").and_then(Value::as_i64).unwrap_or(0));

            let mut sections_recs: Vec<&SectionRecord> = g
                .sections
                .values()
                .filter(|s| s.workspace_id == ws.id)
                .collect();
            sections_recs.sort_by_key(|s| s.position);

            let sections: Vec<Value> = sections_recs
                .iter()
                .map(|s| {
                    json!({
                        "id": s.id,
                        "title": s.title,
                        "position": s.position,
                    })
                })
                .collect();

            let mut all_res: Vec<&ResourceRecord> = g
                .resources
                .values()
                .filter(|r| r.workspace_id == ws.id)
                .collect();
            all_res.sort_by_key(|r| r.position);

            let resources: Vec<Value> = all_res
                .into_iter()
                .map(|r| {
                    json!({
                        "id": r.id,
                        "title": r.title,
                        "url": r.url,
                        "faviconUrl": r.favicon_url,
                        "position": r.position,
                        "sectionId": r.section_id,
                    })
                })
                .collect();

            let mut notes_recs: Vec<&NoteRecord> = g
                .notes
                .values()
                .filter(|n| n.workspace_id == ws.id)
                .collect();
            notes_recs.sort_by_key(|n| n.position);
            let notes: Vec<Value> = notes_recs
                .into_iter()
                .map(|n| {
                    json!({
                        "id": n.id,
                        "title": n.title,
                        "content": n.content,
                        "position": n.position,
                    })
                })
                .collect();

            let mut tasks_recs: Vec<&TaskRecord> = g
                .tasks
                .values()
                .filter(|t| t.workspace_id == ws.id)
                .collect();
            tasks_recs.sort_by_key(|t| t.position);
            let tasks: Vec<Value> = tasks_recs
                .into_iter()
                .map(|t| {
                    json!({
                        "id": t.id,
                        "title": t.title,
                        "completed": t.completed,
                        "dueDate": t.due_date,
                        "position": t.position,
                    })
                })
                .collect();

            snapshots.push(json!({
                "workspace": {
                    "id": ws.id,
                    "name": ws.name,
                    "description": ws.description,
                    "color": ws.color,
                    "icon": ws.icon,
                    "position": ws.position,
                    "settings": ws.settings,
                    "groupId": ws.group_id,
                },
                "tabs": tabs,
                "sections": sections,
                "resources": resources,
                "notes": notes,
                "tasks": tasks,
            }));
        }

        let snapshot_val = Value::Array(snapshots);
        let size_bytes = snapshot_val.to_string().len();
        let now_ms = now_epoch_ms();
        let created_at = epoch_ms_to_iso8601(now_ms);
        let id = uuid_v4();

        let rec = BackupRecord {
            id: id.clone(),
            user_id: user_id.to_string(),
            workspace_id: options.workspace_id.clone(),
            name: options.name.clone(),
            backup_type: options.backup_type.clone(),
            snapshot: snapshot_val,
            size_bytes,
            created_at: created_at.clone(),
            created_at_ms: now_ms,
        };
        g.backups.insert(id.clone(), rec);

        Ok(json!({
            "id": id,
            "workspaceId": options.workspace_id,
            "name": options.name,
            "type": options.backup_type,
            "sizeBytes": size_bytes,
            "createdAt": created_at,
        }))
    }

    pub fn list_backups(
        store: &DataStore,
        user_id: &str,
        query: BackupListQuery,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let mut filtered: Vec<&BackupRecord> = g
            .backups
            .values()
            .filter(|b| {
                b.user_id == user_id
                    && query
                        .workspace_id
                        .as_deref()
                        .map(|wid| b.workspace_id.as_deref() == Some(wid))
                        .unwrap_or(true)
                    && query
                        .backup_type
                        .as_deref()
                        .map(|t| b.backup_type == t)
                        .unwrap_or(true)
            })
            .collect();

        filtered.sort_by(|a, b| {
            let cmp = if query.sort_by == "sizeBytes" {
                a.size_bytes.cmp(&b.size_bytes)
            } else {
                a.created_at_ms.cmp(&b.created_at_ms)
            };
            if query.sort_order == "asc" {
                cmp
            } else {
                cmp.reverse()
            }
        });

        let total = filtered.len();
        let page: Vec<Value> = filtered
            .into_iter()
            .skip(query.offset)
            .take(query.limit)
            .map(|b| {
                let ws_name = b
                    .workspace_id
                    .as_deref()
                    .and_then(|wid| g.workspaces.get(wid))
                    .map(|w| w.name.clone());
                json!({
                    "id": b.id,
                    "workspaceId": b.workspace_id,
                    "workspaceName": ws_name,
                    "name": b.name,
                    "type": b.backup_type,
                    "sizeBytes": b.size_bytes,
                    "createdAt": b.created_at,
                })
            })
            .collect();

        Ok(json!({
            "backups": page,
            "total": total,
        }))
    }

    pub fn get_backup(
        store: &DataStore,
        user_id: &str,
        backup_id: &str,
    ) -> Result<Option<Value>, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let Some(b) = g.backups.get(backup_id) else {
            return Ok(None);
        };
        if b.user_id != user_id {
            return Ok(None);
        }
        Ok(Some(json!({
            "id": b.id,
            "workspaceId": b.workspace_id,
            "name": b.name,
            "type": b.backup_type,
            "snapshot": b.snapshot,
            "sizeBytes": b.size_bytes,
            "createdAt": b.created_at,
        })))
    }

    pub fn restore_backup(
        store: &DataStore,
        user_id: &str,
        backup_id: &str,
        options: BackupRestoreInput,
    ) -> Result<Vec<String>, AppError> {
        store.check_injected_error()?;
        let mut g = store.inner.lock().unwrap();
        let Some(backup) = g.backups.get(backup_id).cloned() else {
            return Err(AppError::internal("Backup not found"));
        };
        if backup.user_id != user_id {
            return Err(AppError::internal("Backup not found"));
        }

        let snapshots = backup.snapshot.as_array().cloned().unwrap_or_default();
        if options.target_workspace_id.is_some() && !options.create_new && snapshots.len() > 1 {
            return Err(AppError::internal(
                "Restoring a multi-workspace backup onto a single targetWorkspaceId is not supported; pass createNew: true or omit targetWorkspaceId.",
            ));
        }

        let now = now_iso8601();
        let mut restored_ids = Vec::with_capacity(snapshots.len());

        for snap in snapshots {
            let Some(ws_obj) = snap.get("workspace").and_then(Value::as_object) else {
                continue;
            };
            let snap_ws_id = ws_obj
                .get("id")
                .and_then(Value::as_str)
                .unwrap_or("ws_restored");
            let ws_name = ws_obj
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("Restored Workspace");
            let ws_desc = ws_obj
                .get("description")
                .and_then(Value::as_str)
                .map(|s| s.to_string());
            let ws_color = ws_obj
                .get("color")
                .and_then(Value::as_str)
                .map(|s| s.to_string());
            let ws_icon = ws_obj
                .get("icon")
                .and_then(Value::as_str)
                .map(|s| s.to_string());
            let ws_pos = ws_obj.get("position").and_then(Value::as_i64).unwrap_or(0);
            let ws_settings = ws_obj.get("settings").cloned().unwrap_or_else(|| json!({}));
            let ws_group_id = ws_obj
                .get("groupId")
                .and_then(Value::as_str)
                .map(|s| s.to_string());

            let target_id = if options.create_new {
                let new_id = generate_id("ws");
                g.workspaces.insert(
                    new_id.clone(),
                    WorkspaceRecord {
                        id: new_id.clone(),
                        user_id: user_id.to_string(),
                        group_id: ws_group_id,
                        name: format!("{ws_name} (Restored)"),
                        description: ws_desc,
                        color: ws_color,
                        icon: ws_icon,
                        position: ws_pos,
                        version: 0,
                        active_device_id: None,
                        active_device_seen_at: None,
                        active_device_seen_at_ms: None,
                        created_at: now.clone(),
                        updated_at: now.clone(),
                        settings: ws_settings,
                    },
                );
                new_id
            } else {
                let tid = options
                    .target_workspace_id
                    .clone()
                    .unwrap_or_else(|| snap_ws_id.to_string());
                let exists = g
                    .workspaces
                    .get(&tid)
                    .map(|w| w.user_id == user_id)
                    .unwrap_or(false);
                if exists {
                    if !options.merge {
                        g.tabs.retain(|_, t| t.workspace_id != tid);
                        g.sections.retain(|_, s| s.workspace_id != tid);
                        g.resources.retain(|_, r| r.workspace_id != tid);
                        g.notes.retain(|_, n| n.workspace_id != tid);
                        g.tasks.retain(|_, t| t.workspace_id != tid);
                    }
                    if let Some(existing_ws) = g.workspaces.get_mut(&tid) {
                        existing_ws.name = ws_name.to_string();
                        existing_ws.description = ws_desc;
                        existing_ws.color = ws_color;
                        existing_ws.icon = ws_icon;
                        existing_ws.settings = ws_settings;
                        existing_ws.group_id = ws_group_id;
                        existing_ws.version += 1;
                        existing_ws.updated_at = now.clone();
                    }
                } else {
                    g.workspaces.insert(
                        tid.clone(),
                        WorkspaceRecord {
                            id: tid.clone(),
                            user_id: user_id.to_string(),
                            group_id: ws_group_id,
                            name: ws_name.to_string(),
                            description: ws_desc,
                            color: ws_color,
                            icon: ws_icon,
                            position: ws_pos,
                            version: 0,
                            active_device_id: None,
                            active_device_seen_at: None,
                            active_device_seen_at_ms: None,
                            created_at: now.clone(),
                            updated_at: now.clone(),
                            settings: ws_settings,
                        },
                    );
                }
                tid
            };

            if let Some(tabs) = snap.get("tabs").and_then(Value::as_array) {
                for (idx, t) in tabs.iter().enumerate() {
                    let tid = generate_id("tab");
                    g.tabs.insert(
                        tid.clone(),
                        TabRecord {
                            id: tid,
                            workspace_id: target_id.clone(),
                            url: t
                                .get("url")
                                .and_then(Value::as_str)
                                .unwrap_or("https://example.com")
                                .to_string(),
                            title: t
                                .get("title")
                                .and_then(Value::as_str)
                                .map(|s| s.to_string()),
                            favicon_url: t
                                .get("faviconUrl")
                                .and_then(Value::as_str)
                                .map(|s| s.to_string()),
                            position: t
                                .get("position")
                                .and_then(Value::as_i64)
                                .unwrap_or(idx as i64),
                            is_pinned: t.get("isPinned").and_then(Value::as_bool).unwrap_or(false),
                            created_at: now.clone(),
                            updated_at: now.clone(),
                            last_accessed_at: now.clone(),
                            metadata: t.get("metadata").cloned().unwrap_or_else(|| json!({})),
                        },
                    );
                }
            }

            let mut section_id_map = std::collections::HashMap::new();
            if let Some(sections) = snap.get("sections").and_then(Value::as_array) {
                for (idx, s) in sections.iter().enumerate() {
                    let old_id = s.get("id").and_then(Value::as_str).unwrap_or("");
                    let new_sec_id = generate_id("sec");
                    if !old_id.is_empty() {
                        section_id_map.insert(old_id.to_string(), new_sec_id.clone());
                    }
                    g.sections.insert(
                        new_sec_id.clone(),
                        SectionRecord {
                            id: new_sec_id,
                            workspace_id: target_id.clone(),
                            title: s
                                .get("title")
                                .and_then(Value::as_str)
                                .unwrap_or("Section")
                                .to_string(),
                            position: s
                                .get("position")
                                .and_then(Value::as_i64)
                                .unwrap_or(idx as i64),
                            created_at: now.clone(),
                            updated_at: now.clone(),
                        },
                    );
                }
            }

            if let Some(resources) = snap.get("resources").and_then(Value::as_array) {
                for (idx, r) in resources.iter().enumerate() {
                    let rid = generate_id("res");
                    let mapped_sec = r
                        .get("sectionId")
                        .and_then(Value::as_str)
                        .and_then(|old| section_id_map.get(old).cloned());
                    g.resources.insert(
                        rid.clone(),
                        ResourceRecord {
                            id: rid,
                            workspace_id: target_id.clone(),
                            section_id: mapped_sec,
                            title: r
                                .get("title")
                                .and_then(Value::as_str)
                                .unwrap_or("Resource")
                                .to_string(),
                            url: r
                                .get("url")
                                .and_then(Value::as_str)
                                .unwrap_or("https://example.com")
                                .to_string(),
                            favicon_url: r
                                .get("faviconUrl")
                                .and_then(Value::as_str)
                                .map(|s| s.to_string()),
                            position: r
                                .get("position")
                                .and_then(Value::as_i64)
                                .unwrap_or(idx as i64),
                            created_at: now.clone(),
                            updated_at: now.clone(),
                        },
                    );
                }
            }

            if let Some(notes) = snap.get("notes").and_then(Value::as_array) {
                for (idx, n) in notes.iter().enumerate() {
                    let nid = generate_id("note");
                    g.notes.insert(
                        nid.clone(),
                        NoteRecord {
                            id: nid,
                            workspace_id: target_id.clone(),
                            title: n
                                .get("title")
                                .and_then(Value::as_str)
                                .unwrap_or("Note")
                                .to_string(),
                            content: n
                                .get("content")
                                .and_then(Value::as_str)
                                .unwrap_or("")
                                .to_string(),
                            position: n
                                .get("position")
                                .and_then(Value::as_i64)
                                .unwrap_or(idx as i64),
                            created_at: now.clone(),
                            updated_at: now.clone(),
                        },
                    );
                }
            }

            if let Some(tasks) = snap.get("tasks").and_then(Value::as_array) {
                for (idx, t) in tasks.iter().enumerate() {
                    let tid = generate_id("task");
                    g.tasks.insert(
                        tid.clone(),
                        TaskRecord {
                            id: tid,
                            workspace_id: target_id.clone(),
                            title: t
                                .get("title")
                                .and_then(Value::as_str)
                                .unwrap_or("Task")
                                .to_string(),
                            completed: t.get("completed").and_then(Value::as_bool).unwrap_or(false),
                            due_date: t
                                .get("dueDate")
                                .and_then(Value::as_str)
                                .map(|s| s.to_string()),
                            position: t
                                .get("position")
                                .and_then(Value::as_i64)
                                .unwrap_or(idx as i64),
                            created_at: now.clone(),
                            updated_at: now.clone(),
                        },
                    );
                }
            }

            restored_ids.push(target_id);
        }

        Ok(restored_ids)
    }

    pub fn delete_backup(
        store: &DataStore,
        user_id: &str,
        backup_id: &str,
    ) -> Result<bool, AppError> {
        store.check_injected_error()?;
        let mut g = store.inner.lock().unwrap();
        let owns = g
            .backups
            .get(backup_id)
            .map(|b| b.user_id == user_id)
            .unwrap_or(false);
        if !owns {
            return Ok(false);
        }
        g.backups.remove(backup_id);
        Ok(true)
    }

    pub fn get_backup_stats(store: &DataStore, user_id: &str) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let g = store.inner.lock().unwrap();
        let mut backups: Vec<&BackupRecord> = g
            .backups
            .values()
            .filter(|b| b.user_id == user_id)
            .collect();
        backups.sort_by_key(|b| b.created_at_ms);

        let total_size_bytes: usize = backups.iter().map(|b| b.size_bytes).sum();
        let mut backups_by_workspace: Map<String, Value> = Map::new();
        let mut auto_backups = 0usize;
        let mut manual_backups = 0usize;

        for b in &backups {
            let key = b.workspace_id.as_deref().unwrap_or("full");
            let count = backups_by_workspace
                .get(key)
                .and_then(Value::as_u64)
                .unwrap_or(0)
                + 1;
            backups_by_workspace.insert(key.to_string(), json!(count));
            if b.backup_type == "auto" {
                auto_backups += 1;
            } else {
                manual_backups += 1;
            }
        }

        let oldest = backups
            .first()
            .map(|b| Value::String(b.created_at.clone()))
            .unwrap_or(Value::Null);
        let newest = backups
            .last()
            .map(|b| Value::String(b.created_at.clone()))
            .unwrap_or(Value::Null);

        Ok(json!({
            "totalBackups": backups.len(),
            "totalSizeBytes": total_size_bytes,
            "oldestBackup": oldest,
            "newestBackup": newest,
            "backupsByWorkspace": Value::Object(backups_by_workspace),
            "autoBackups": auto_backups,
            "manualBackups": manual_backups,
        }))
    }
}

// ============================================================================
// 9. SyncService
// ============================================================================

pub struct SyncService;

impl SyncService {
    pub fn push_changes(
        store: &DataStore,
        redis: &dyn RedisStore,
        user_id: &str,
        _tier: &str,
        input: SyncPushInput,
    ) -> Result<Value, AppError> {
        store.check_injected_error()?;
        let server_ts_ms = now_epoch_ms();
        let server_ts_iso = epoch_ms_to_iso8601(server_ts_ms);

        let mut accepted: Vec<String> = Vec::new();
        let mut conflicts: Vec<Value> = Vec::new();
        let mut rejected: Vec<Value> = Vec::new();

        for change in input.changes {
            if change.action != "delete"
                && is_tombstoned(redis, user_id, &change.entity_type, &change.entity_id)
            {
                rejected.push(json!({
                    "entityId": change.entity_id,
                    "reason": "deleted",
                }));
                continue;
            }

            if change.action == "delete" {
                Self::handle_delete(store, redis, user_id, &change)?;
                accepted.push(change.entity_id.clone());

                let change_key = format!("sync:changes:{user_id}");
                let record = json!({
                    "type": change.entity_type,
                    "action": change.action,
                    "entityId": change.entity_id,
                    "data": change.data,
                    "version": change.version,
                    "updatedAt": server_ts_iso,
                    "fromDevice": input.device_id,
                });
                let _ = redis.zadd(&change_key, server_ts_ms as f64, &record.to_string());
                let _ = redis.expire(&change_key, 86400);
                let _ = redis.publish(&format!("sync:updates:{user_id}"), &record.to_string());
                continue;
            }

            let v_key = format!(
                "sync:version:{user_id}:{}:{}",
                change.entity_type, change.entity_id
            );
            let s_key = format!(
                "sync:state:{user_id}:{}:{}",
                change.entity_type, change.entity_id
            );

            let (ok_flag, remote_version) = redis
                .eval_version_check(&v_key, change.version)
                .map_err(AppError::internal)?;

            if ok_flag == 0 {
                let server_state_raw = redis.get(&s_key).ok().flatten();
                let remote_updated_at = server_state_raw
                    .and_then(|s| serde_json::from_str::<Value>(&s).ok())
                    .and_then(|v| {
                        v.get("updatedAt")
                            .and_then(Value::as_str)
                            .map(|s| s.to_string())
                    })
                    .unwrap_or_else(|| server_ts_iso.clone());

                conflicts.push(json!({
                    "entityId": change.entity_id,
                    "entityType": change.entity_type,
                    "localVersion": change.version,
                    "remoteVersion": remote_version,
                    "localUpdatedAt": epoch_ms_to_iso8601(input.client_timestamp_ms),
                    "remoteUpdatedAt": remote_updated_at,
                    "resolution": "pending",
                }));
                continue;
            }

            match Self::handle_upsert(store, user_id, &change, remote_version) {
                Ok(()) => {
                    let state_payload = json!({
                        "data": change.data,
                        "version": remote_version,
                        "updatedAt": server_ts_iso,
                        "deviceId": input.device_id,
                    });
                    let _ = redis.set_ex(&s_key, &state_payload.to_string(), 86400);
                    accepted.push(change.entity_id.clone());

                    let change_key = format!("sync:changes:{user_id}");
                    let record = json!({
                        "type": change.entity_type,
                        "action": change.action,
                        "entityId": change.entity_id,
                        "data": change.data,
                        "version": remote_version,
                        "updatedAt": server_ts_iso,
                        "fromDevice": input.device_id,
                    });
                    let _ = redis.zadd(&change_key, server_ts_ms as f64, &record.to_string());
                    let _ = redis.expire(&change_key, 86400);
                    let _ = redis.publish(&format!("sync:updates:{user_id}"), &record.to_string());
                }
                Err(reason) => {
                    rejected.push(json!({
                        "entityId": change.entity_id,
                        "reason": reason,
                    }));
                }
            }
        }

        let dev_key = format!("sync:devices:{user_id}");
        let _ = redis.sadd(&dev_key, &input.device_id);
        let _ = redis.expire(&dev_key, 300);

        let user_sync_key = format!("sync:user:{user_id}");
        let _ = redis.hset(
            &user_sync_key,
            &[
                ("lastSyncAt", &server_ts_iso),
                ("lastDevice", &input.device_id),
            ],
        );

        Ok(json!({
            "accepted": accepted,
            "conflicts": conflicts,
            "rejected": rejected,
            "serverTimestamp": server_ts_iso,
        }))
    }

    fn handle_delete(
        store: &DataStore,
        redis: &dyn RedisStore,
        user_id: &str,
        change: &SyncChangeInput,
    ) -> Result<(), AppError> {
        {
            let mut g = store.inner.lock().unwrap();
            if change.entity_type == "workspace" {
                let owns = g
                    .workspaces
                    .get(&change.entity_id)
                    .map(|w| w.user_id == user_id)
                    .unwrap_or(false);
                if owns {
                    g.workspaces.remove(&change.entity_id);
                    g.tabs.retain(|_, t| t.workspace_id != change.entity_id);
                    g.sections.retain(|_, s| s.workspace_id != change.entity_id);
                    g.resources
                        .retain(|_, r| r.workspace_id != change.entity_id);
                    g.notes.retain(|_, n| n.workspace_id != change.entity_id);
                    g.tasks.retain(|_, t| t.workspace_id != change.entity_id);
                }
            } else if change.entity_type == "spaceGroup" {
                let owns = g
                    .space_groups
                    .get(&change.entity_id)
                    .map(|sg| sg.user_id == user_id)
                    .unwrap_or(false);
                if owns {
                    g.space_groups.remove(&change.entity_id);
                }
            }
        }
        mark_entity_deleted(redis, user_id, &change.entity_type, &change.entity_id);
        Ok(())
    }

    fn handle_upsert(
        store: &DataStore,
        user_id: &str,
        change: &SyncChangeInput,
        next_version: u64,
    ) -> Result<(), String> {
        let data = change.data.clone().unwrap_or_default();
        let now = now_iso8601();
        let mut g = store.inner.lock().unwrap();

        if change.entity_type == "workspace" {
            if let Some(existing) = g.workspaces.get_mut(&change.entity_id) {
                if existing.user_id != user_id {
                    return Err("Entity id is already in use".to_string());
                }
                if let Some(name) = data.get("name").and_then(Value::as_str) {
                    existing.name = name.to_string();
                }
                if let Some(desc) = data.get("description") {
                    existing.description = desc.as_str().map(|s| s.to_string());
                }
                if let Some(color) = data.get("color") {
                    existing.color = color.as_str().map(|s| s.to_string());
                }
                if let Some(icon) = data.get("icon") {
                    existing.icon = icon.as_str().map(|s| s.to_string());
                }
                if let Some(pos) = data.get("position").and_then(Value::as_i64) {
                    existing.position = pos;
                }
                if let Some(settings) = data.get("settings") {
                    existing.settings = settings.clone();
                }
                if let Some(gid) = data.get("groupId") {
                    existing.group_id = gid.as_str().map(|s| s.to_string());
                }
                existing.version = next_version;
                existing.updated_at = now;
                return Ok(());
            }

            let ws = WorkspaceRecord {
                id: change.entity_id.clone(),
                user_id: user_id.to_string(),
                group_id: data
                    .get("groupId")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string()),
                name: data
                    .get("name")
                    .and_then(Value::as_str)
                    .unwrap_or("Untitled")
                    .to_string(),
                description: data
                    .get("description")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string()),
                color: data
                    .get("color")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string()),
                icon: data
                    .get("icon")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string()),
                position: data.get("position").and_then(Value::as_i64).unwrap_or(0),
                version: next_version,
                active_device_id: None,
                active_device_seen_at: None,
                active_device_seen_at_ms: None,
                created_at: now.clone(),
                updated_at: now,
                settings: data.get("settings").cloned().unwrap_or_else(|| json!({})),
            };
            g.workspaces.insert(change.entity_id.clone(), ws);
            return Ok(());
        }

        if change.entity_type == "spaceGroup" {
            let title_opt = data
                .get("title")
                .or_else(|| data.get("name"))
                .and_then(Value::as_str)
                .map(|s| s.to_string());

            if let Some(existing) = g.space_groups.get_mut(&change.entity_id) {
                if existing.user_id != user_id {
                    return Err("Entity id is already in use".to_string());
                }
                if let Some(t) = title_opt {
                    existing.title = t;
                }
                if let Some(color) = data.get("color") {
                    existing.color = color.as_str().map(|s| s.to_string());
                }
                if let Some(collapsed) = data.get("collapsed").and_then(Value::as_bool) {
                    existing.collapsed = collapsed;
                }
                if let Some(pos) = data.get("position").and_then(Value::as_i64) {
                    existing.position = pos;
                }
                existing.version = next_version;
                existing.updated_at = now;
                return Ok(());
            }

            let sg = SpaceGroupRecord {
                id: change.entity_id.clone(),
                user_id: user_id.to_string(),
                title: title_opt.unwrap_or_else(|| "Untitled Group".to_string()),
                color: data
                    .get("color")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string()),
                collapsed: data
                    .get("collapsed")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                position: data.get("position").and_then(Value::as_i64).unwrap_or(0),
                version: next_version,
                created_at: now.clone(),
                updated_at: now,
            };
            g.space_groups.insert(change.entity_id.clone(), sg);
        }

        Ok(())
    }

    pub fn pull_changes(
        redis: &dyn RedisStore,
        user_id: &str,
        input: SyncPullInput,
    ) -> Result<Value, AppError> {
        let server_ts_ms = now_epoch_ms();
        let server_ts_iso = epoch_ms_to_iso8601(server_ts_ms);
        let since_score = input.last_sync_at_ms.unwrap_or(0) as f64;

        let dev_key = format!("sync:devices:{user_id}");
        let _ = redis.sadd(&dev_key, &input.device_id);
        let _ = redis.expire(&dev_key, 300);

        let change_key = format!("sync:changes:{user_id}");
        let raw_changes = redis
            .zrangebyscore(&change_key, since_score)
            .unwrap_or_default();

        let mut changes = Vec::new();
        for raw in raw_changes {
            let Ok(parsed) = serde_json::from_str::<Value>(&raw) else {
                continue;
            };
            let entity_type = parsed.get("type").and_then(Value::as_str).unwrap_or("");
            let from_device = parsed
                .get("fromDevice")
                .and_then(Value::as_str)
                .unwrap_or("");
            if input.entity_types.iter().any(|t| t == entity_type) && from_device != input.device_id
            {
                changes.push(json!({
                    "type": entity_type,
                    "action": parsed.get("action").cloned().unwrap_or(Value::Null),
                    "entityId": parsed.get("entityId").cloned().unwrap_or(Value::Null),
                    "data": parsed.get("data").cloned().unwrap_or(Value::Null),
                    "version": parsed.get("version").cloned().unwrap_or(json!(0)),
                    "updatedAt": parsed.get("updatedAt").cloned().unwrap_or_else(|| json!(server_ts_iso)),
                }));
            }
        }

        Ok(json!({
            "changes": changes,
            "serverTimestamp": server_ts_iso,
            "hasMore": false,
        }))
    }

    pub fn get_sync_status(redis: &dyn RedisStore, user_id: &str) -> Result<Value, AppError> {
        let user_sync_key = format!("sync:user:{user_id}");
        let dev_key = format!("sync:devices:{user_id}");
        let change_key = format!("sync:changes:{user_id}");

        let state = redis.hgetall(&user_sync_key).unwrap_or_default();
        let connected_devices = redis.scard(&dev_key).unwrap_or(0);
        let pending_changes = redis.zcard(&change_key).unwrap_or(0);

        let last_sync_at = state
            .get("lastSyncAt")
            .cloned()
            .map(Value::String)
            .unwrap_or(Value::Null);

        Ok(json!({
            "lastSyncAt": last_sync_at,
            "pendingChanges": pending_changes,
            "connectedDevices": connected_devices,
            "syncEnabled": true,
        }))
    }
}
