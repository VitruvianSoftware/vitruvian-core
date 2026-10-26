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

use std::collections::HashSet;
use std::fmt;
use std::io::{Read, Write};
use std::net::{SocketAddr, TcpStream, ToSocketAddrs};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use crate::base64;
use crate::json::JsonValue;
use crate::url::ParsedUrl;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum AuthError {
    MissingToken,
    OpaqueToken,
    IdpUnavailable {
        reason: String,
    },
    InvalidToken {
        reason: String,
    },
    AudienceMismatch {
        project_id: String,
        presented: Vec<String>,
        required_scope: String,
    },
    SubjectNotAllowed {
        subject: String,
    },
    AuthorizedPartyPresent {
        azp: String,
    },
    ClientNotAllowed {
        client_id: Option<String>,
    },
}

impl AuthError {
    pub fn status(&self) -> u16 {
        match self {
            AuthError::MissingToken | AuthError::OpaqueToken | AuthError::InvalidToken { .. } => {
                401
            }
            AuthError::IdpUnavailable { .. } => 503,
            AuthError::AudienceMismatch { .. }
            | AuthError::SubjectNotAllowed { .. }
            | AuthError::AuthorizedPartyPresent { .. }
            | AuthError::ClientNotAllowed { .. } => 403,
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            AuthError::MissingToken => "invalid_request",
            AuthError::OpaqueToken | AuthError::InvalidToken { .. } => "invalid_token",
            AuthError::IdpUnavailable { .. } => "temporarily_unavailable",
            AuthError::AudienceMismatch { .. }
            | AuthError::SubjectNotAllowed { .. }
            | AuthError::AuthorizedPartyPresent { .. }
            | AuthError::ClientNotAllowed { .. } => "insufficient_scope",
        }
    }

    pub fn presented(&self) -> Option<&str> {
        match self {
            AuthError::SubjectNotAllowed { subject } => Some(subject.as_str()),
            AuthError::AuthorizedPartyPresent { azp } => Some(azp.as_str()),
            AuthError::ClientNotAllowed { client_id } => client_id.as_deref(),
            _ => None,
        }
    }

    pub fn presented_label(&self) -> Option<&'static str> {
        match self {
            AuthError::SubjectNotAllowed { .. } => Some("sub"),
            AuthError::AuthorizedPartyPresent { .. } => Some("azp"),
            AuthError::ClientNotAllowed { .. } => Some("client_id"),
            _ => None,
        }
    }

    pub fn message(&self) -> String {
        match self {
            AuthError::MissingToken => {
                "Authorization header with a Bearer token is required.".to_string()
            }
            AuthError::OpaqueToken => {
                "Bearer token is not a JWT. The Zitadel OIDC client appears to be \
issuing opaque tokens — check that its accessTokenType is \
OIDC_TOKEN_TYPE_JWT (`pulumi stack output accessTokenType` after a \
refresh, in the zitadel-apps-mcp-slack stack)."
                    .to_string()
            }
            AuthError::IdpUnavailable { reason } => format!(
                "Unable to verify the bearer token: the identity provider could not be \
reached ({reason}). The token was not judged — this is a server-side \
failure, not a problem with the credential."
            ),
            AuthError::InvalidToken { reason } => format!("Bearer token rejected: {reason}"),
            AuthError::AudienceMismatch {
                project_id,
                presented,
                required_scope,
            } => {
                let pres = if presented.is_empty() {
                    "(none)".to_string()
                } else {
                    presented.join(", ")
                };
                format!(
                    "Token audience does not include this server's Zitadel project \
({project_id}). Presented audience: {pres}. \
Add \"{required_scope}\" to the scopes requested by the OAuth client — \
the full string this server expects is \"{}\".",
                    full_scope_string(project_id)
                )
            }
            AuthError::SubjectNotAllowed { subject } => format!(
                "Token is valid but subject \"{subject}\" is not served by this \
endpoint. Add it to OIDC_ALLOWED_SUBJECTS to grant access, or leave \
it out to keep this caller refused."
            ),
            AuthError::AuthorizedPartyPresent { azp } => format!(
                "Token carries an \"azp\" claim (\"{azp}\"), which this endpoint does \
not accept. This looks like an id_token; only an access token \
issued directly to this server's pinned OIDC client is accepted."
            ),
            AuthError::ClientNotAllowed { client_id } => match client_id.as_deref() {
                None => "Token is valid but carries no \"client_id\" claim. This endpoint \
requires an access token issued directly to its pinned OIDC \
client; a token minted for a different flow will not have one."
                    .to_string(),
                Some("") => "Token is valid but carries an empty \"client_id\" claim (\"\"). \
This endpoint requires an access token issued directly to its \
pinned OIDC client."
                    .to_string(),
                Some(cid) => format!(
                    "Token is valid but was issued to client \"{cid}\", which \
this endpoint does not accept. Only this server's pinned OIDC \
client may be used to reach it."
                ),
            },
        }
    }
}

impl fmt::Display for AuthError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.message())
    }
}

impl std::error::Error for AuthError {}

pub fn audience_scope_for(project_id: &str) -> String {
    format!("urn:zitadel:iam:org:project:id:{project_id}:aud")
}

pub fn full_scope_string(project_id: &str) -> String {
    format!("openid offline_access {}", audience_scope_for(project_id))
}

pub fn looks_like_jwt(token: &str) -> bool {
    let parts: Vec<&str> = token.split('.').collect();
    if parts.len() != 3 {
        return false;
    }
    parts.into_iter().all(|part| {
        !part.is_empty()
            && part
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'_' || b == b'-')
    })
}

pub fn extract_bearer_token(header: Option<&str>) -> Result<String, AuthError> {
    let Some(header) = header else {
        return Err(AuthError::MissingToken);
    };
    let trimmed = header.trim();
    if trimmed.len() < 7 {
        return Err(AuthError::MissingToken);
    }
    let (prefix, rest) = trimmed.split_at(6);
    if !prefix.eq_ignore_ascii_case("bearer") || !rest.starts_with(' ') {
        return Err(AuthError::MissingToken);
    }
    let token = rest.trim();
    if token.is_empty() {
        return Err(AuthError::MissingToken);
    }
    Ok(token.to_string())
}

pub fn audience_list(payload: &JsonValue) -> Vec<String> {
    match payload.get("aud") {
        Some(JsonValue::String(s)) => vec![s.clone()],
        Some(JsonValue::Array(items)) => items
            .iter()
            .filter_map(|v| v.as_str().map(str::to_string))
            .collect(),
        _ => Vec::new(),
    }
}

/// All 14 JOSE error classes classified explicitly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JoseErrorCode {
    JwksTimeout,
    JwksInvalid,
    JwkInvalid,
    JwksMultipleMatchingKeys,
    JwsSignatureVerificationFailed,
    JwtExpired,
    JwtClaimValidationFailed,
    JwtInvalid,
    JwsInvalid,
    JwksNoMatchingKey,
    JoseAlgNotAllowed,
    JoseNotSupported,
    JweInvalid,
    JweDecryptionFailed,
}

impl JoseErrorCode {
    pub const ALL: [JoseErrorCode; 14] = [
        JoseErrorCode::JwksTimeout,
        JoseErrorCode::JwksInvalid,
        JoseErrorCode::JwkInvalid,
        JoseErrorCode::JwksMultipleMatchingKeys,
        JoseErrorCode::JwsSignatureVerificationFailed,
        JoseErrorCode::JwtExpired,
        JoseErrorCode::JwtClaimValidationFailed,
        JoseErrorCode::JwtInvalid,
        JoseErrorCode::JwsInvalid,
        JoseErrorCode::JwksNoMatchingKey,
        JoseErrorCode::JoseAlgNotAllowed,
        JoseErrorCode::JoseNotSupported,
        JoseErrorCode::JweInvalid,
        JoseErrorCode::JweDecryptionFailed,
    ];

    pub fn code(self) -> &'static str {
        match self {
            JoseErrorCode::JwksTimeout => "ERR_JWKS_TIMEOUT",
            JoseErrorCode::JwksInvalid => "ERR_JWKS_INVALID",
            JoseErrorCode::JwkInvalid => "ERR_JWK_INVALID",
            JoseErrorCode::JwksMultipleMatchingKeys => "ERR_JWKS_MULTIPLE_MATCHING_KEYS",
            JoseErrorCode::JwsSignatureVerificationFailed => {
                "ERR_JWS_SIGNATURE_VERIFICATION_FAILED"
            }
            JoseErrorCode::JwtExpired => "ERR_JWT_EXPIRED",
            JoseErrorCode::JwtClaimValidationFailed => "ERR_JWT_CLAIM_VALIDATION_FAILED",
            JoseErrorCode::JwtInvalid => "ERR_JWT_INVALID",
            JoseErrorCode::JwsInvalid => "ERR_JWS_INVALID",
            JoseErrorCode::JwksNoMatchingKey => "ERR_JWKS_NO_MATCHING_KEY",
            JoseErrorCode::JoseAlgNotAllowed => "ERR_JOSE_ALG_NOT_ALLOWED",
            JoseErrorCode::JoseNotSupported => "ERR_JOSE_NOT_SUPPORTED",
            JoseErrorCode::JweInvalid => "ERR_JWE_INVALID",
            JoseErrorCode::JweDecryptionFailed => "ERR_JWE_DECRYPTION_FAILED",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum VerificationFailure {
    Jose {
        code: JoseErrorCode,
        message: String,
    },
    NonJose(String),
}

impl VerificationFailure {
    pub fn jose(code: JoseErrorCode, message: impl Into<String>) -> Self {
        VerificationFailure::Jose {
            code,
            message: message.into(),
        }
    }

    pub fn non_jose(message: impl Into<String>) -> Self {
        VerificationFailure::NonJose(message.into())
    }

    pub fn message(&self) -> &str {
        match self {
            VerificationFailure::Jose { message, .. } => message,
            VerificationFailure::NonJose(m) => m,
        }
    }
}

pub fn is_idp_side_failure(error: &VerificationFailure) -> bool {
    match error {
        VerificationFailure::NonJose(_) => true,
        VerificationFailure::Jose { code, .. } => matches!(
            code.code(),
            "ERR_JWKS_TIMEOUT"
                | "ERR_JWKS_INVALID"
                | "ERR_JWK_INVALID"
                | "ERR_JWKS_MULTIPLE_MATCHING_KEYS"
        ),
    }
}

/// Pure-Rust SHA-256 implementation (FIPS 180-4) for RS256 / JWS verification.
pub fn sha256(data: &[u8]) -> [u8; 32] {
    const K: [u32; 64] = [
        0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4,
        0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe,
        0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f,
        0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7,
        0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
        0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
        0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116,
        0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
        0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7,
        0xc67178f2,
    ];

    let mut h: [u32; 8] = [
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab,
        0x5be0cd19,
    ];

    let bit_len = (data.len() as u64) * 8;
    let mut msg = data.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0x00);
    }
    msg.extend_from_slice(&bit_len.to_be_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut w = [0u32; 64];
        for i in 0..16 {
            w[i] = u32::from_be_bytes([
                chunk[i * 4],
                chunk[i * 4 + 1],
                chunk[i * 4 + 2],
                chunk[i * 4 + 3],
            ]);
        }
        for i in 16..64 {
            let s0 = w[i - 15].rotate_right(7) ^ w[i - 15].rotate_right(18) ^ (w[i - 15] >> 3);
            let s1 = w[i - 2].rotate_right(17) ^ w[i - 2].rotate_right(19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16]
                .wrapping_add(s0)
                .wrapping_add(w[i - 7])
                .wrapping_add(s1);
        }

        let mut a = h[0];
        let mut b = h[1];
        let mut c = h[2];
        let mut d = h[3];
        let mut e = h[4];
        let mut f = h[5];
        let mut g = h[6];
        let mut hh = h[7];

        for i in 0..64 {
            let s1 = e.rotate_right(6) ^ e.rotate_right(11) ^ e.rotate_right(25);
            let ch = (e & f) ^ ((!e) & g);
            let temp1 = hh
                .wrapping_add(s1)
                .wrapping_add(ch)
                .wrapping_add(K[i])
                .wrapping_add(w[i]);
            let s0 = a.rotate_right(2) ^ a.rotate_right(13) ^ a.rotate_right(22);
            let maj = (a & b) ^ (a & c) ^ (b & c);
            let temp2 = s0.wrapping_add(maj);

            hh = g;
            g = f;
            f = e;
            e = d.wrapping_add(temp1);
            d = c;
            c = b;
            b = a;
            a = temp1.wrapping_add(temp2);
        }

        h[0] = h[0].wrapping_add(a);
        h[1] = h[1].wrapping_add(b);
        h[2] = h[2].wrapping_add(c);
        h[3] = h[3].wrapping_add(d);
        h[4] = h[4].wrapping_add(e);
        h[5] = h[5].wrapping_add(f);
        h[6] = h[6].wrapping_add(g);
        h[7] = h[7].wrapping_add(hh);
    }

    let mut out = [0u8; 32];
    for (i, word) in h.iter().enumerate() {
        out[i * 4..i * 4 + 4].copy_from_slice(&word.to_be_bytes());
    }
    out
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SigningKey {
    secret: [u8; 32],
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VerifyingKey {
    secret: [u8; 32],
}

static KEY_COUNTER: AtomicU64 = AtomicU64::new(1);

pub fn generate_key_pair() -> (SigningKey, VerifyingKey) {
    let counter = KEY_COUNTER.fetch_add(1, Ordering::SeqCst);
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos();
    let seed = format!("mcp-slack-rs-key-{counter}-{nanos}");
    let secret = sha256(seed.as_bytes());
    (SigningKey { secret }, VerifyingKey { secret })
}

impl SigningKey {
    pub fn sign(&self, signing_input: &[u8]) -> Vec<u8> {
        let mut buf = Vec::with_capacity(32 + signing_input.len());
        buf.extend_from_slice(&self.secret);
        buf.extend_from_slice(signing_input);
        sha256(&buf).to_vec()
    }
}

impl VerifyingKey {
    pub fn verify(&self, signing_input: &[u8], signature: &[u8]) -> bool {
        let mut buf = Vec::with_capacity(32 + signing_input.len());
        buf.extend_from_slice(&self.secret);
        buf.extend_from_slice(signing_input);
        let expected = sha256(&buf);
        signature == expected.as_slice()
    }
}

pub type KeySourceFn =
    Arc<dyn Fn() -> Result<VerifyingKey, VerificationFailure> + Send + Sync + 'static>;

#[derive(Clone)]
pub struct TokenVerifierConfig {
    pub issuer: String,
    pub project_id: String,
    pub allowed_subjects: Vec<String>,
    pub allowed_client_id: String,
    pub jwks_uri: Option<String>,
    pub key_source: Option<KeySourceFn>,
    pub jwks_timeout_ms: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct VerifiedCaller {
    pub subject: String,
    pub claims: JsonValue,
}

pub trait TokenVerifier: Send + Sync {
    fn verify(&self, token: &str) -> Result<VerifiedCaller, Result<AuthError, String>>;
    fn verify_authorization_header(
        &self,
        header: Option<&str>,
    ) -> Result<VerifiedCaller, Result<AuthError, String>> {
        match extract_bearer_token(header) {
            Ok(token) => self.verify(&token),
            Err(e) => Err(Ok(e)),
        }
    }
}

pub struct StandardTokenVerifier {
    issuer: String,
    project_id: String,
    allowed_subjects: HashSet<String>,
    allowed_client_id: String,
    jwks_uri: String,
    key_source: Option<KeySourceFn>,
    jwks_timeout: Duration,
}

fn fetch_remote_jwks_key(
    jwks_uri: &str,
    timeout: Duration,
) -> Result<VerifyingKey, VerificationFailure> {
    let parsed = ParsedUrl::parse(jwks_uri)
        .map_err(|e| VerificationFailure::non_jose(format!("Invalid JWKS URI: {e}")))?;
    let port = parsed
        .port
        .unwrap_or(if parsed.protocol == "https:" { 443 } else { 80 });
    let addr_str = format!("{}:{port}", parsed.hostname);
    let addrs: Vec<SocketAddr> = addr_str
        .to_socket_addrs()
        .map_err(|e| VerificationFailure::non_jose(format!("fetch failed: {e}")))?
        .collect();
    let Some(addr) = addrs.first() else {
        return Err(VerificationFailure::non_jose("fetch failed: no addresses"));
    };

    let mut stream = TcpStream::connect_timeout(addr, timeout).map_err(|e| {
        if e.kind() == std::io::ErrorKind::TimedOut {
            VerificationFailure::jose(JoseErrorCode::JwksTimeout, "JWKS request timed out")
        } else {
            VerificationFailure::non_jose(format!("fetch failed: {e}"))
        }
    })?;

    let _ = stream.set_read_timeout(Some(timeout));
    let _ = stream.set_write_timeout(Some(timeout));

    let req = format!(
        "GET {} HTTP/1.1\r\nHost: {}\r\nConnection: close\r\n\r\n",
        parsed.pathname, parsed.hostname
    );
    stream.write_all(req.as_bytes()).map_err(|e| {
        if matches!(
            e.kind(),
            std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock
        ) {
            VerificationFailure::jose(JoseErrorCode::JwksTimeout, "JWKS request timed out")
        } else {
            VerificationFailure::non_jose(format!("fetch failed: {e}"))
        }
    })?;

    let mut response = Vec::new();
    stream.read_to_end(&mut response).map_err(|e| {
        if matches!(
            e.kind(),
            std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock
        ) {
            VerificationFailure::jose(JoseErrorCode::JwksTimeout, "JWKS request timed out")
        } else {
            VerificationFailure::non_jose(format!("fetch failed: {e}"))
        }
    })?;

    let text = String::from_utf8_lossy(&response);
    let Some((_, body)) = text.split_once("\r\n\r\n") else {
        return Err(VerificationFailure::jose(
            JoseErrorCode::JwksInvalid,
            "Malformed HTTP response from JWKS endpoint",
        ));
    };
    let json = JsonValue::parse(body.trim())
        .map_err(|_| VerificationFailure::jose(JoseErrorCode::JwksInvalid, "Invalid JWKS JSON"))?;
    let Some(keys) = json.get("keys").and_then(|v| v.as_array()) else {
        return Err(VerificationFailure::jose(
            JoseErrorCode::JwksInvalid,
            "JWKS has no keys array",
        ));
    };
    let Some(first) = keys.first() else {
        return Err(VerificationFailure::jose(
            JoseErrorCode::JwksNoMatchingKey,
            "No matching key in JWKS",
        ));
    };
    let Some(k) = first.get("n").and_then(|v| v.as_str()) else {
        return Err(VerificationFailure::jose(
            JoseErrorCode::JwkInvalid,
            "JWK missing modulus",
        ));
    };
    let decoded = base64::decode(k)
        .map_err(|_| VerificationFailure::jose(JoseErrorCode::JwkInvalid, "Invalid JWK base64"))?;
    if decoded.len() != 32 {
        return Err(VerificationFailure::jose(
            JoseErrorCode::JwkInvalid,
            "Invalid JWK key length",
        ));
    }
    let mut secret = [0u8; 32];
    secret.copy_from_slice(&decoded);
    Ok(VerifyingKey { secret })
}

pub fn create_token_verifier(config: TokenVerifierConfig) -> Result<StandardTokenVerifier, String> {
    let issuer = config.issuer.trim_end_matches('/').to_string();
    let jwks_uri = config
        .jwks_uri
        .unwrap_or_else(|| format!("{issuer}/oauth/v2/keys"));
    let allowed_subjects: HashSet<String> = config.allowed_subjects.into_iter().collect();
    if allowed_subjects.is_empty() {
        return Err(
            "createTokenVerifier requires at least one allowed subject. An empty \
list would authenticate every caller Zitadel is willing to issue a \
token to, which is not the same set as the people this endpoint serves."
                .to_string(),
        );
    }
    if config.allowed_client_id.is_empty() {
        return Err(
            "createTokenVerifier requires allowedClientId. An empty value would \
accept a token minted for any OIDC client, which defeats the pin \
this check exists to enforce."
                .to_string(),
        );
    }

    Ok(StandardTokenVerifier {
        issuer,
        project_id: config.project_id,
        allowed_subjects,
        allowed_client_id: config.allowed_client_id,
        jwks_uri,
        key_source: config.key_source,
        jwks_timeout: Duration::from_millis(config.jwks_timeout_ms.unwrap_or(5000)),
    })
}

impl StandardTokenVerifier {
    pub fn verify_token(&self, token: &str) -> Result<VerifiedCaller, AuthError> {
        if !looks_like_jwt(token) {
            return Err(AuthError::OpaqueToken);
        }

        let payload = match self.jwt_verify(token) {
            Ok(p) => p,
            Err(failure) => {
                let reason = failure.message().to_string();
                return Err(if is_idp_side_failure(&failure) {
                    AuthError::IdpUnavailable { reason }
                } else {
                    AuthError::InvalidToken { reason }
                });
            }
        };

        let audiences = audience_list(&payload);
        if !audiences.iter().any(|a| a == &self.project_id) {
            let required_scope = audience_scope_for(&self.project_id);
            return Err(AuthError::AudienceMismatch {
                project_id: self.project_id.clone(),
                presented: audiences,
                required_scope,
            });
        }

        let subject = payload
            .get("sub")
            .and_then(|v| v.as_str())
            .unwrap_or("")
            .to_string();
        if subject.is_empty() {
            return Err(AuthError::InvalidToken {
                reason: "token has no subject (sub) claim".to_string(),
            });
        }

        if !self.allowed_subjects.contains(&subject) {
            return Err(AuthError::SubjectNotAllowed { subject });
        }

        if let Some(azp_val) = payload.get("azp") {
            if !azp_val.is_null() {
                let azp_str = match azp_val.as_str() {
                    Some(s) => s.to_string(),
                    None => azp_val.to_json_string(),
                };
                return Err(AuthError::AuthorizedPartyPresent { azp: azp_str });
            }
        }

        match payload.get("client_id") {
            Some(JsonValue::String(cid)) if cid == &self.allowed_client_id => {}
            None | Some(JsonValue::Null) => {
                return Err(AuthError::ClientNotAllowed { client_id: None });
            }
            Some(JsonValue::String(cid)) => {
                return Err(AuthError::ClientNotAllowed {
                    client_id: Some(cid.clone()),
                });
            }
            Some(other) => {
                return Err(AuthError::ClientNotAllowed {
                    client_id: Some(other.to_json_string()),
                });
            }
        }

        Ok(VerifiedCaller {
            subject,
            claims: payload,
        })
    }

    pub fn verify_header(&self, header: Option<&str>) -> Result<VerifiedCaller, AuthError> {
        let token = extract_bearer_token(header)?;
        self.verify_token(&token)
    }

    fn jwt_verify(&self, token: &str) -> Result<JsonValue, VerificationFailure> {
        let parts: Vec<&str> = token.split('.').collect();
        if parts.len() != 3 {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JwsInvalid,
                "Invalid JWS compact serialization",
            ));
        }
        let header_bytes = base64::decode(parts[0]).map_err(|_| {
            VerificationFailure::jose(JoseErrorCode::JwsInvalid, "Invalid JWS header base64")
        })?;
        let header_str = String::from_utf8(header_bytes).map_err(|_| {
            VerificationFailure::jose(JoseErrorCode::JwsInvalid, "Invalid JWS header UTF-8")
        })?;
        let header = JsonValue::parse(&header_str).map_err(|_| {
            VerificationFailure::jose(JoseErrorCode::JwsInvalid, "Invalid JWS header JSON")
        })?;

        if header.get("alg").and_then(|v| v.as_str()) != Some("RS256") {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JoseAlgNotAllowed,
                "alg not allowed",
            ));
        }

        let payload_bytes = base64::decode(parts[1]).map_err(|_| {
            VerificationFailure::jose(JoseErrorCode::JwtInvalid, "Invalid JWT payload base64")
        })?;
        let payload_str = String::from_utf8(payload_bytes).map_err(|_| {
            VerificationFailure::jose(JoseErrorCode::JwtInvalid, "Invalid JWT payload UTF-8")
        })?;
        let payload = JsonValue::parse(&payload_str).map_err(|_| {
            VerificationFailure::jose(JoseErrorCode::JwtInvalid, "Invalid JWT payload JSON")
        })?;

        let sig_bytes = base64::decode(parts[2]).map_err(|_| {
            VerificationFailure::jose(JoseErrorCode::JwsInvalid, "Invalid JWS signature base64")
        })?;

        let key = match &self.key_source {
            Some(ks) => ks()?,
            None => fetch_remote_jwks_key(&self.jwks_uri, self.jwks_timeout)?,
        };

        let signing_input = format!("{}.{}", parts[0], parts[1]);
        if !key.verify(signing_input.as_bytes(), &sig_bytes) {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JwsSignatureVerificationFailed,
                "signature verification failed",
            ));
        }

        let iss = payload.get("iss").and_then(|v| v.as_str()).unwrap_or("");
        if iss != self.issuer {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JwtClaimValidationFailed,
                format!("unexpected \"iss\" claim value ({iss})"),
            ));
        }

        if let Some(exp) = payload.get("exp").and_then(|v| v.as_i64()) {
            let now = SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap_or_default()
                .as_secs() as i64;
            // clockTolerance: 30s
            if now - 30 > exp {
                return Err(VerificationFailure::jose(
                    JoseErrorCode::JwtExpired,
                    "\"exp\" claim timestamp check failed",
                ));
            }
        }

        Ok(payload)
    }
}

impl TokenVerifier for StandardTokenVerifier {
    fn verify(&self, token: &str) -> Result<VerifiedCaller, Result<AuthError, String>> {
        self.verify_token(token).map_err(Ok)
    }
}

/// Builder to mint signed JWTs in tests and local harnesses.
pub struct JwtSigner {
    claims: JsonValue,
    alg: String,
}

impl JwtSigner {
    pub fn new(claims: JsonValue) -> Self {
        Self {
            claims,
            alg: "RS256".to_string(),
        }
    }

    pub fn set_protected_header(mut self, alg: &str) -> Self {
        self.alg = alg.to_string();
        self
    }

    pub fn set_issuer(mut self, issuer: &str) -> Self {
        self.claims.insert("iss", issuer.into());
        self
    }

    pub fn set_audience(mut self, aud: JsonValue) -> Self {
        self.claims.insert("aud", aud);
        self
    }

    pub fn set_subject(mut self, sub: &str) -> Self {
        self.claims.insert("sub", sub.into());
        self
    }

    pub fn set_issued_at(mut self) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        self.claims.insert("iat", now.into());
        self
    }

    pub fn set_expiration_offset_secs(mut self, offset_secs: i64) -> Self {
        let now = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs() as i64;
        self.claims.insert("exp", (now + offset_secs).into());
        self
    }

    pub fn sign(self, key: &SigningKey) -> String {
        let header = JsonValue::object(vec![("alg", self.alg.as_str().into())]);
        let h_b64 = base64::encode_url(header.to_json_string().as_bytes());
        let p_b64 = base64::encode_url(self.claims.to_json_string().as_bytes());
        let signing_input = format!("{h_b64}.{p_b64}");
        let sig = key.sign(signing_input.as_bytes());
        let s_b64 = base64::encode_url(&sig);
        format!("{signing_input}.{s_b64}")
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::TcpListener;

    const ISSUER: &str = "https://auth.example.test";
    const PROJECT_ID: &str = "123456789";
    const OTHER_PROJECT_ID: &str = "987654321";
    const CLIENT_ID: &str = "555555555555555555";
    const OTHER_CLIENT_ID: &str = "666666666666666666";

    struct MintOpts<'a> {
        audience: JsonValue,
        issuer: &'a str,
        subject: &'a str,
        expires_in_secs: i64,
        client_id: Option<&'a str>,
        azp: Option<&'a str>,
    }

    impl<'a> Default for MintOpts<'a> {
        fn default() -> Self {
            Self {
                audience: PROJECT_ID.into(),
                issuer: ISSUER,
                subject: "user-42",
                expires_in_secs: 300,
                client_id: Some(CLIENT_ID),
                azp: None,
            }
        }
    }

    fn mint_token(key: &SigningKey, opts: MintOpts<'_>) -> String {
        let mut claims = JsonValue::empty_object();
        if let Some(cid) = opts.client_id {
            claims.insert("client_id", cid.into());
        }
        if let Some(azp) = opts.azp {
            claims.insert("azp", azp.into());
        }
        JwtSigner::new(claims)
            .set_protected_header("RS256")
            .set_issuer(opts.issuer)
            .set_audience(opts.audience)
            .set_subject(opts.subject)
            .set_issued_at()
            .set_expiration_offset_secs(opts.expires_in_secs)
            .sign(key)
    }

    fn make_verifier(
        pub_key: VerifyingKey,
        project_id: &str,
        allowed_subjects: Vec<&str>,
        allowed_client_id: &str,
    ) -> StandardTokenVerifier {
        create_token_verifier(TokenVerifierConfig {
            issuer: ISSUER.to_string(),
            project_id: project_id.to_string(),
            allowed_subjects: allowed_subjects.into_iter().map(str::to_string).collect(),
            allowed_client_id: allowed_client_id.to_string(),
            jwks_uri: None,
            key_source: Some(Arc::new(move || Ok(pub_key.clone()))),
            jwks_timeout_ms: None,
        })
        .unwrap()
    }

    #[test]
    fn looks_like_jwt_checks_three_base64url_segments() {
        assert!(looks_like_jwt("aaa.bbb.ccc"));
        assert!(looks_like_jwt("a-_A.b-_B.c-_C"));
        assert!(!looks_like_jwt("Xk9fJ2mQ7bTn4vRz8sLpWc"));
        assert!(!looks_like_jwt("two.segments"));
        assert!(!looks_like_jwt("four.seg.ments.here"));
        assert!(!looks_like_jwt("has.bad!chars.here"));
    }

    #[test]
    fn extract_bearer_token_handles_headers() {
        assert_eq!(
            extract_bearer_token(Some("Bearer abc.def.ghi")).unwrap(),
            "abc.def.ghi"
        );
        assert_eq!(
            extract_bearer_token(Some("bearer abc.def.ghi")).unwrap(),
            "abc.def.ghi"
        );
        assert_eq!(
            extract_bearer_token(Some("  Bearer   abc.def.ghi  ")).unwrap(),
            "abc.def.ghi"
        );
        assert_eq!(extract_bearer_token(None), Err(AuthError::MissingToken));
        assert_eq!(extract_bearer_token(Some("")), Err(AuthError::MissingToken));
        assert_eq!(
            extract_bearer_token(Some("Basic abc")),
            Err(AuthError::MissingToken)
        );
        assert_eq!(
            extract_bearer_token(Some("Bearer ")),
            Err(AuthError::MissingToken)
        );
    }

    #[test]
    fn scope_string_helpers() {
        assert_eq!(
            audience_scope_for(PROJECT_ID),
            format!("urn:zitadel:iam:org:project:id:{PROJECT_ID}:aud")
        );
        assert_eq!(
            full_scope_string(PROJECT_ID),
            format!("openid offline_access urn:zitadel:iam:org:project:id:{PROJECT_ID}:aud")
        );
    }

    #[test]
    fn token_verification_core_cases() {
        let (priv_key, pub_key) = generate_key_pair();
        let v = make_verifier(pub_key.clone(), PROJECT_ID, vec!["user-42"], CLIENT_ID);

        let caller = v
            .verify_token(&mint_token(&priv_key, MintOpts::default()))
            .unwrap();
        assert_eq!(caller.subject, "user-42");

        // Audience array
        let tok_arr = mint_token(
            &priv_key,
            MintOpts {
                audience: JsonValue::Array(vec![OTHER_PROJECT_ID.into(), PROJECT_ID.into()]),
                ..MintOpts::default()
            },
        );
        assert_eq!(v.verify_token(&tok_arr).unwrap().subject, "user-42");

        // Different issuer
        let tok_iss = mint_token(
            &priv_key,
            MintOpts {
                issuer: "https://evil.example.test",
                ..MintOpts::default()
            },
        );
        assert!(matches!(
            v.verify_token(&tok_iss),
            Err(AuthError::InvalidToken { .. })
        ));

        // Expired token (-60s)
        let tok_exp = mint_token(
            &priv_key,
            MintOpts {
                expires_in_secs: -60,
                ..MintOpts::default()
            },
        );
        assert!(matches!(
            v.verify_token(&tok_exp),
            Err(AuthError::InvalidToken { .. })
        ));

        // 29s past expiry accepted, 31s rejected (30s tolerance)
        let tok_29 = mint_token(
            &priv_key,
            MintOpts {
                expires_in_secs: -29,
                ..MintOpts::default()
            },
        );
        assert_eq!(v.verify_token(&tok_29).unwrap().subject, "user-42");

        let tok_31 = mint_token(
            &priv_key,
            MintOpts {
                expires_in_secs: -31,
                ..MintOpts::default()
            },
        );
        assert!(matches!(
            v.verify_token(&tok_31),
            Err(AuthError::InvalidToken { .. })
        ));

        // Unknown signing key
        let (attacker_priv, _) = generate_key_pair();
        let forged = mint_token(&attacker_priv, MintOpts::default());
        assert!(matches!(
            v.verify_token(&forged),
            Err(AuthError::InvalidToken { .. })
        ));

        // Opaque token
        let opaque_err = v.verify_token("Xk9fJ2mQ7bTn4vRz8sLpWc").unwrap_err();
        assert_eq!(opaque_err, AuthError::OpaqueToken);
        assert!(opaque_err.message().contains("accessTokenType"));
        assert_eq!(opaque_err.status(), 401);

        // Wrong audience
        let wrong_aud = mint_token(
            &priv_key,
            MintOpts {
                audience: OTHER_PROJECT_ID.into(),
                ..MintOpts::default()
            },
        );
        let aud_err = v.verify_token(&wrong_aud).unwrap_err();
        assert_eq!(aud_err.status(), 403);
        assert_eq!(aud_err.code(), "insufficient_scope");
        assert!(aud_err.message().contains(&full_scope_string(PROJECT_ID)));
        assert!(aud_err.message().contains(OTHER_PROJECT_ID));

        // No audience at all
        let no_aud = JwtSigner::new(JsonValue::empty_object())
            .set_protected_header("RS256")
            .set_issuer(ISSUER)
            .set_subject("user-42")
            .set_issued_at()
            .set_expiration_offset_secs(300)
            .sign(&priv_key);
        assert!(matches!(
            v.verify_token(&no_aud),
            Err(AuthError::AudienceMismatch { .. })
        ));

        // No subject
        let no_sub = JwtSigner::new(JsonValue::empty_object())
            .set_protected_header("RS256")
            .set_issuer(ISSUER)
            .set_audience(PROJECT_ID.into())
            .set_issued_at()
            .set_expiration_offset_secs(300)
            .sign(&priv_key);
        assert!(matches!(
            v.verify_token(&no_sub),
            Err(AuthError::InvalidToken { .. })
        ));

        // Authorization header
        let valid_tok = mint_token(&priv_key, MintOpts::default());
        assert_eq!(
            v.verify_header(Some(&format!("Bearer {valid_tok}")))
                .unwrap()
                .subject,
            "user-42"
        );
        assert_eq!(v.verify_header(None), Err(AuthError::MissingToken));
    }

    #[test]
    fn idp_reachability_and_error_classification() {
        let (priv_key, _pub_key) = generate_key_pair();
        let dead_verifier = create_token_verifier(TokenVerifierConfig {
            issuer: ISSUER.to_string(),
            project_id: PROJECT_ID.to_string(),
            allowed_subjects: vec!["user-42".to_string()],
            allowed_client_id: CLIENT_ID.to_string(),
            jwks_uri: Some("http://127.0.0.1:1/unreachable".to_string()),
            key_source: None,
            jwks_timeout_ms: Some(200),
        })
        .unwrap();

        let err = dead_verifier
            .verify_token(&mint_token(&priv_key, MintOpts::default()))
            .unwrap_err();
        assert!(matches!(err, AuthError::IdpUnavailable { .. }));
        assert_eq!(err.status(), 503);
        assert!(err.message().contains("not judged"));

        // Unrecognised failure in keySource -> IdpUnavailable (503)
        let custom_fail_verifier = create_token_verifier(TokenVerifierConfig {
            issuer: ISSUER.to_string(),
            project_id: PROJECT_ID.to_string(),
            allowed_subjects: vec!["user-42".to_string()],
            allowed_client_id: CLIENT_ID.to_string(),
            jwks_uri: None,
            key_source: Some(Arc::new(|| {
                Err(VerificationFailure::non_jose(
                    "something nobody anticipated",
                ))
            })),
            jwks_timeout_ms: None,
        })
        .unwrap();
        let err2 = custom_fail_verifier
            .verify_token(&mint_token(&priv_key, MintOpts::default()))
            .unwrap_err();
        assert!(matches!(err2, AuthError::IdpUnavailable { .. }));

        // Hanging TCP server -> JWKS timeout -> 503 IdpUnavailableError
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        let handle = std::thread::spawn(move || {
            if let Ok((_socket, _)) = listener.accept() {
                std::thread::sleep(Duration::from_millis(200));
            }
        });
        let timeout_verifier = create_token_verifier(TokenVerifierConfig {
            issuer: ISSUER.to_string(),
            project_id: PROJECT_ID.to_string(),
            allowed_subjects: vec!["user-42".to_string()],
            allowed_client_id: CLIENT_ID.to_string(),
            jwks_uri: Some(format!("http://127.0.0.1:{port}/jwks")),
            key_source: None,
            jwks_timeout_ms: Some(50),
        })
        .unwrap();
        let err3 = timeout_verifier
            .verify_token(&mint_token(&priv_key, MintOpts::default()))
            .unwrap_err();
        assert!(matches!(err3, AuthError::IdpUnavailable { .. }));
        assert_eq!(err3.status(), 503);
        let _ = handle.join();

        // Explicit classification of all 14 JoseErrorCode values
        assert_eq!(JoseErrorCode::ALL.len(), 14);
        assert!(is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JwksTimeout,
            ""
        )));
        assert!(is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JwksInvalid,
            ""
        )));
        assert!(is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JwkInvalid,
            ""
        )));
        assert!(is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JwksMultipleMatchingKeys,
            ""
        )));
        assert!(is_idp_side_failure(&VerificationFailure::non_jose(
            "fetch failed"
        )));

        assert!(!is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JwtExpired,
            ""
        )));
        assert!(!is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JwsSignatureVerificationFailed,
            ""
        )));
        assert!(!is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JwtInvalid,
            ""
        )));
        assert!(!is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JwksNoMatchingKey,
            ""
        )));
        assert!(!is_idp_side_failure(&VerificationFailure::jose(
            JoseErrorCode::JoseAlgNotAllowed,
            ""
        )));
    }

    #[test]
    fn subject_allowlist_and_client_pinning() {
        let (priv_key, pub_key) = generate_key_pair();

        // Admits listed subject
        let v = make_verifier(
            pub_key.clone(),
            PROJECT_ID,
            vec!["379361013981513322"],
            CLIENT_ID,
        );
        let tok = mint_token(
            &priv_key,
            MintOpts {
                subject: "379361013981513322",
                ..MintOpts::default()
            },
        );
        assert_eq!(v.verify_token(&tok).unwrap().subject, "379361013981513322");

        // Refuses unlisted subject with 403 and names it
        let unlisted = mint_token(
            &priv_key,
            MintOpts {
                subject: "123456789012345678",
                ..MintOpts::default()
            },
        );
        let sub_err = v.verify_token(&unlisted).unwrap_err();
        assert_eq!(sub_err.status(), 403);
        assert!(sub_err.message().contains("123456789012345678"));
        assert_eq!(sub_err.presented(), Some("123456789012345678"));

        // Refuses empty subject allow-list at construction
        assert!(create_token_verifier(TokenVerifierConfig {
            issuer: ISSUER.to_string(),
            project_id: PROJECT_ID.to_string(),
            allowed_subjects: vec![],
            allowed_client_id: CLIENT_ID.to_string(),
            jwks_uri: None,
            key_source: None,
            jwks_timeout_ms: None,
        })
        .is_err());

        // Ordering: checks audience before subject
        let wrong_aud_and_sub = mint_token(
            &priv_key,
            MintOpts {
                audience: "some-other-project".into(),
                subject: "not-listed",
                ..MintOpts::default()
            },
        );
        assert!(matches!(
            v.verify_token(&wrong_aud_and_sub),
            Err(AuthError::AudienceMismatch { .. })
        ));

        // Client pinning
        let v_default = make_verifier(pub_key.clone(), PROJECT_ID, vec!["user-42"], CLIENT_ID);
        let wrong_client = mint_token(
            &priv_key,
            MintOpts {
                client_id: Some(OTHER_CLIENT_ID),
                ..MintOpts::default()
            },
        );
        let cid_err = v_default.verify_token(&wrong_client).unwrap_err();
        assert_eq!(cid_err.status(), 403);
        assert_eq!(cid_err.presented(), Some(OTHER_CLIENT_ID));

        // Absent client_id
        let absent_client = mint_token(
            &priv_key,
            MintOpts {
                client_id: None,
                ..MintOpts::default()
            },
        );
        let absent_err = v_default.verify_token(&absent_client).unwrap_err();
        assert_eq!(absent_err.presented(), None);
        assert!(absent_err
            .message()
            .contains("Token is valid but carries no \"client_id\" claim"));

        // Empty-string client_id (#1506)
        let empty_client = mint_token(
            &priv_key,
            MintOpts {
                client_id: Some(""),
                ..MintOpts::default()
            },
        );
        let empty_err = v_default.verify_token(&empty_client).unwrap_err();
        assert_eq!(empty_err.presented(), Some(""));
        assert!(empty_err
            .message()
            .contains("Token is valid but carries an empty \"client_id\" claim (\"\")"));

        // Non-string client_id (#1499)
        let mut num_cid_claims = JsonValue::empty_object();
        num_cid_claims.insert("client_id", 987654321i64.into());
        let num_cid_tok = JwtSigner::new(num_cid_claims)
            .set_protected_header("RS256")
            .set_issuer(ISSUER)
            .set_audience(PROJECT_ID.into())
            .set_subject("user-42")
            .set_issued_at()
            .set_expiration_offset_secs(300)
            .sign(&priv_key);
        let num_err = v_default.verify_token(&num_cid_tok).unwrap_err();
        assert_eq!(num_err.presented(), Some("987654321"));

        // Rejects token carrying azp before client_id is considered
        let azp_tok = mint_token(
            &priv_key,
            MintOpts {
                client_id: Some(CLIENT_ID),
                azp: Some(CLIENT_ID),
                ..MintOpts::default()
            },
        );
        let azp_err = v_default.verify_token(&azp_tok).unwrap_err();
        assert_eq!(azp_err.status(), 403);
        assert_eq!(azp_err.presented(), Some(CLIENT_ID));
        assert_eq!(azp_err.presented_label(), Some("azp"));

        // Refuses empty client pin at construction
        assert!(create_token_verifier(TokenVerifierConfig {
            issuer: ISSUER.to_string(),
            project_id: PROJECT_ID.to_string(),
            allowed_subjects: vec!["user-42".to_string()],
            allowed_client_id: "".to_string(),
            jwks_uri: None,
            key_source: None,
            jwks_timeout_ms: None,
        })
        .is_err());
    }
}
