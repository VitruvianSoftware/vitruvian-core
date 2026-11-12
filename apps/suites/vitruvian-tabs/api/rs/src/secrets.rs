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

use crate::crypto::{base64_decode, now_epoch_ms};
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
use std::sync::{Arc, Mutex, OnceLock};

pub const CACHE_TTL_MS: i64 = 5 * 60 * 1000;
pub const RPC_TIMEOUT_MS: u64 = 5_000;

/// Trait abstracting Google Cloud Secret Manager version access (`src/lib/secrets.ts`).
pub trait SecretManagerBackend: Send + Sync {
    fn access_secret_version(
        &self,
        resource_name: &str,
        timeout_ms: u64,
    ) -> Result<Option<String>, String>;
}

pub struct DefaultSecretManagerBackend;

impl SecretManagerBackend for DefaultSecretManagerBackend {
    fn access_secret_version(
        &self,
        resource_name: &str,
        timeout_ms: u64,
    ) -> Result<Option<String>, String> {
        let token = match std::env::var("GOOGLE_OAUTH_ACCESS_TOKEN") {
            Ok(t) if !t.trim().is_empty() => t.trim().to_string(),
            _ => {
                let output = std::process::Command::new("curl")
                    .args([
                        "-sS",
                        "-f",
                        "--max-time",
                        "5",
                        "-H",
                        "Metadata-Flavor: Google",
                        "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
                    ])
                    .output()
                    .map_err(|e| format!("Failed to query GCE metadata server: {e}"))?;
                if !output.status.success() {
                    return Err("Metadata token request failed".to_string());
                }
                let json_val: Value = serde_json::from_slice(&output.stdout)
                    .map_err(|e| format!("Invalid metadata token JSON: {e}"))?;
                json_val
                    .get("access_token")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string())
                    .ok_or_else(|| "Missing access_token".to_string())?
            }
        };

        let max_time_secs = (timeout_ms / 1000).max(1).to_string();
        let url = format!("https://secretmanager.googleapis.com/v1/{resource_name}:access");
        let output = std::process::Command::new("curl")
            .args([
                "-sS",
                "-f",
                "--max-time",
                &max_time_secs,
                "-H",
                &format!("Authorization: Bearer {token}"),
                &url,
            ])
            .output()
            .map_err(|e| format!("Failed to invoke curl for Secret Manager: {e}"))?;

        if !output.status.success() {
            return Err("NOT_FOUND".to_string());
        }

        let json_val: Value = serde_json::from_slice(&output.stdout)
            .map_err(|e| format!("Invalid Secret Manager JSON: {e}"))?;
        let Some(data_b64) = json_val
            .get("payload")
            .and_then(|p| p.get("data"))
            .and_then(Value::as_str)
        else {
            return Ok(None);
        };
        let bytes = base64_decode(data_b64).ok_or_else(|| "Invalid base64 payload".to_string())?;
        let val = String::from_utf8(bytes).map_err(|e| e.to_string())?;
        Ok(Some(val))
    }
}

#[derive(Debug, Clone)]
struct CacheEntry {
    value: String,
    expires_at: i64,
}

static SECRET_CACHE: OnceLock<Mutex<HashMap<String, CacheEntry>>> = OnceLock::new();

fn global_cache() -> &'static Mutex<HashMap<String, CacheEntry>> {
    SECRET_CACHE.get_or_init(|| Mutex::new(HashMap::new()))
}

pub fn reset_secret_cache_for_tests() {
    if let Ok(mut guard) = global_cache().lock() {
        guard.clear();
    }
}

/// Resolve a secret by bare name (`getSecret` in `src/lib/secrets.ts`).
/// Checks `env[name]` first, then `${SECRET_PREFIX}${name}` in Secret Manager (cached for 5m).
pub fn get_secret_with(
    name: &str,
    env: &BTreeMap<String, String>,
    backend: &dyn SecretManagerBackend,
) -> Result<String, String> {
    if let Some(from_env) = env.get(name) {
        if !from_env.is_empty() {
            return Ok(from_env.clone());
        }
    }

    let prefix = env.get("SECRET_PREFIX").map(|s| s.as_str()).unwrap_or("");
    let secret_id = format!("{prefix}{name}");
    let now = now_epoch_ms();

    if let Ok(guard) = global_cache().lock() {
        if let Some(hit) = guard.get(&secret_id) {
            if hit.expires_at > now {
                return Ok(hit.value.clone());
            }
        }
    }

    let project = env
        .get("GOOGLE_CLOUD_PROJECT")
        .filter(|s| !s.is_empty())
        .or_else(|| env.get("GCP_PROJECT").filter(|s| !s.is_empty()))
        .ok_or_else(|| {
            format!(
                "Cannot resolve secret {secret_id}: neither env[{name}] nor GOOGLE_CLOUD_PROJECT is set"
            )
        })?;

    let resource_name = format!("projects/{project}/secrets/{secret_id}/versions/latest");
    let data = match backend.access_secret_version(&resource_name, RPC_TIMEOUT_MS) {
        Ok(Some(v)) if !v.is_empty() => v,
        Ok(_) => {
            return Err(format!(
                "Secret {secret_id} (for {name}) NotFound or has an empty payload"
            ))
        }
        Err(_) => {
            return Err(format!(
                "Secret {secret_id} (for {name}) NotFound or unreadable in Secret Manager"
            ))
        }
    };

    if let Ok(mut guard) = global_cache().lock() {
        guard.insert(
            secret_id,
            CacheEntry {
                value: data.clone(),
                expires_at: now + CACHE_TTL_MS,
            },
        );
    }

    Ok(data)
}

pub fn get_secret(name: &str) -> Result<String, String> {
    let env: BTreeMap<String, String> = std::env::vars().collect();
    get_secret_with(name, &env, &DefaultSecretManagerBackend)
}

pub fn try_get_secret_with(
    name: &str,
    env: &BTreeMap<String, String>,
    backend: &dyn SecretManagerBackend,
) -> Option<String> {
    get_secret_with(name, env, backend).ok()
}

pub fn bootstrap_secrets_with(
    env: &mut BTreeMap<String, String>,
    backend: Arc<dyn SecretManagerBackend>,
) {
    for name in [
        "DATABASE_URL",
        "REDIS_URL",
        "JWT_SECRET",
        "WORKOS_API_KEY",
        "WORKOS_CLIENT_ID",
    ] {
        if env.get(name).map(|v| !v.is_empty()).unwrap_or(false) {
            continue;
        }
        if let Some(v) = try_get_secret_with(name, env, backend.as_ref()) {
            env.insert(name.to_string(), v);
        }
    }
}
