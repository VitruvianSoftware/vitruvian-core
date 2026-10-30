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

use crate::crypto::{hex_encode, random_bytes};
use crate::{base64url_encode, sha256};
use std::collections::BTreeMap;

pub const ACCESS_TOKEN_TTL: &str = "1h";
pub const ACCESS_TOKEN_TTL_SECS: i64 = 3600;
pub const REFRESH_TOKEN_TTL_DAYS: i64 = 30;

const DEV_FALLBACK_SECRET: &str = "tabula-dev-only-insecure-jwt-secret";

/// Resolve the JWT signing secret (`resolveJwtSecret` in `src/lib/auth.ts`).
pub fn resolve_jwt_secret(env: &BTreeMap<String, String>) -> Result<String, String> {
    if let Some(configured) = env.get("JWT_SECRET") {
        let trimmed = configured.trim();
        if !trimmed.is_empty() {
            return Ok(trimmed.to_string());
        }
    }
    let node_env = env.get("NODE_ENV").map(|s| s.as_str()).unwrap_or("");
    if node_env == "production" {
        return Err("JWT_SECRET environment variable must be set in production".to_string());
    }
    Ok(DEV_FALLBACK_SECRET.to_string())
}

pub fn resolve_jwt_secret_from_process_env() -> Result<String, String> {
    let env: BTreeMap<String, String> = std::env::vars().collect();
    resolve_jwt_secret(&env)
}

/// Generate a 256-bit random opaque refresh token encoded as base64url.
pub fn generate_refresh_token() -> String {
    base64url_encode(&random_bytes(32))
}

/// SHA-256 hex digest of a refresh token.
pub fn hash_refresh_token(token: &str) -> String {
    hex_encode(&sha256(token.as_bytes()))
}

/// Compute refresh token expiration timestamp (epoch ms) given `now_ms`.
pub fn refresh_token_expiry(now_ms: i64) -> i64 {
    now_ms + REFRESH_TOKEN_TTL_DAYS * 24 * 60 * 60 * 1000
}
