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

//! Bearer-token checks for an MCP endpoint behind Zitadel.
//!
//! A caller presents an RS256 access token from the Zitadel issuer. It is
//! checked the way vitruvian-slack-mcp checks it (which follows jose 6.2.13's
//! `jwtVerify` against `createRemoteJWKSet`), step for step and with the same
//! error codes and messages, because those reach the client in the
//! WWW-Authenticate header and decide 401 versus 503.
//!
//! What differs from the Slack MCP: one verifier accepts a list of client ids,
//! and the public surface is small (`verifier`, `Verifier::verify`).
//!
//! Nothing here is hand-rolled crypto or networking: the signature check is
//! ring's RSASSA-PKCS1-v1_5 / SHA-256, and the key set is fetched over HTTPS
//! with ureq on rustls.
//!
//! One knowing difference in parsing: the token's header and claims, and
//! the key set, are read with `serde_json`, which is stricter than the
//! Slack MCP's JavaScript `JSON.parse` (it refuses, for instance, a lone
//! surrogate in a `\u` escape, which `JSON.parse` accepts). Such input
//! fails here as malformed where the Slack MCP might have read it; never
//! the other way round.

use std::collections::HashSet;
use std::fmt;
use std::io::Read;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use ring::signature::{RsaPublicKeyComponents, RSA_PKCS1_2048_8192_SHA256};
use serde_json::Value;

use crate::prm::{audience_scope_for, full_scope_string};

/// Why a token was refused, with the HTTP status and OAuth error code to
/// answer with.
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

    /// The value the token presented that got it refused (`sub`, `azp` or
    /// `client_id`), for the server's own log line. `None` for refusals that
    /// are not about one claim.
    pub fn presented(&self) -> Option<&str> {
        match self {
            AuthError::SubjectNotAllowed { subject } => Some(subject.as_str()),
            AuthError::AuthorizedPartyPresent { azp } => Some(azp.as_str()),
            AuthError::ClientNotAllowed { client_id } => client_id.as_deref(),
            _ => None,
        }
    }

    /// The claim [`AuthError::presented`] came from.
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
            AuthError::OpaqueToken => "Bearer token is not a JWT. The Zitadel OIDC client \
appears to be issuing opaque tokens: check that its accessTokenType is \
OIDC_TOKEN_TYPE_JWT."
                .to_string(),
            AuthError::IdpUnavailable { reason } => format!(
                "Unable to verify the bearer token: the identity provider could not be \
reached ({reason}). The token was not judged: this is a server-side \
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
Add \"{required_scope}\" to the scopes requested by the OAuth client: \
the full string this server expects is \"{}\".",
                    full_scope_string(project_id)
                )
            }
            AuthError::SubjectNotAllowed { subject } => format!(
                "Token is valid but subject \"{subject}\" is not served by this \
endpoint. Add it to the allowed subjects to grant access, or leave \
it out to keep this caller refused."
            ),
            AuthError::AuthorizedPartyPresent { azp } => format!(
                "Token carries an \"azp\" claim (\"{azp}\"), which this endpoint does \
not accept. This looks like an id_token; only an access token \
issued directly to one of this server's OIDC clients is accepted."
            ),
            AuthError::ClientNotAllowed { client_id } => match client_id.as_deref() {
                None => "Token is valid but carries no \"client_id\" claim. This endpoint \
requires an access token issued directly to one of its OIDC \
clients; a token minted for a different flow will not have one."
                    .to_string(),
                Some("") => "Token is valid but carries an empty \"client_id\" claim (\"\"). \
This endpoint requires an access token issued directly to one of its \
OIDC clients."
                    .to_string(),
                Some(cid) => format!(
                    "Token is valid but was issued to client \"{cid}\", which \
this endpoint does not accept. Only this server's OIDC clients may \
be used to reach it."
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

/// Who a verified token belongs to.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Caller {
    pub subject: String,
    pub client_id: String,
}

/// The credential from an `Authorization: Bearer <token>` header. Same rule as
/// the TS `/^Bearer[ ]+(.+)$/i` on the trimmed header, then a trim of the
/// token: "Bearer" in any case, at least one space, then at least one
/// character and no line terminator. `None` when there is no usable token.
pub fn extract_bearer(header: Option<&str>) -> Option<&str> {
    let trimmed = header?.trim();
    // `get` rather than slicing: byte 6 can fall inside a multi-byte
    // character, and that must be a refusal, not a panic.
    let (prefix, rest) = (trimmed.get(..6)?, trimmed.get(6..)?);
    if !prefix.eq_ignore_ascii_case("bearer") || !rest.starts_with(' ') {
        return None;
    }
    let after_spaces = rest.trim_start_matches(' ');
    if after_spaces.is_empty() || after_spaces.contains(['\n', '\r', '\u{2028}', '\u{2029}']) {
        return None;
    }
    let token = after_spaces.trim();
    if token.is_empty() {
        return None;
    }
    Some(token)
}

/// The `WWW-Authenticate` value for a refusal. A 401 (and no error at all)
/// points the client at the protected-resource metadata so it can sign in; a
/// 403 does not, because signing in again will not help.
pub fn www_authenticate(resource_metadata_url: &str, err: Option<&AuthError>) -> String {
    match err {
        None => format!("Bearer resource_metadata=\"{resource_metadata_url}\""),
        Some(err) => {
            let mut challenge = format!(
                "Bearer error=\"{}\", error_description=\"{}\"",
                err.code(),
                header_safe(&err.message())
            );
            if err.status() == 401 {
                challenge.push_str(&format!(", resource_metadata=\"{resource_metadata_url}\""));
            }
            challenge
        }
    }
}

/// Printable ASCII only, double quotes turned into single ones, runs of
/// whitespace collapsed: safe inside a quoted header parameter.
fn header_safe(message: &str) -> String {
    let mut out = String::with_capacity(message.len());
    let mut last_was_space = false;
    for ch in message.chars() {
        let ch = match ch {
            '"' => '\'',
            c if ('\x20'..='\x7e').contains(&c) => c,
            _ => ' ',
        };
        if ch == ' ' {
            if !last_was_space {
                out.push(' ');
            }
            last_was_space = true;
        } else {
            out.push(ch);
            last_was_space = false;
        }
    }
    out.trim().to_string()
}

fn looks_like_jwt(token: &str) -> bool {
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

fn audience_list(payload: &Value) -> Vec<String> {
    match payload.get("aud") {
        Some(Value::String(s)) => vec![s.clone()],
        Some(Value::Array(items)) => items
            .iter()
            .filter_map(|v| v.as_str().map(str::to_string))
            .collect(),
        _ => Vec::new(),
    }
}

/// The JOSE error classes, each classified explicitly.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum JoseErrorCode {
    JwksTimeout,
    JwksInvalid,
    // jose's full list of classes, so each one is classified explicitly;
    // this port never raises these three (it reads no single JWK, and no
    // JWE).
    #[allow(dead_code)]
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
    #[allow(dead_code)]
    JweInvalid,
    #[allow(dead_code)]
    JweDecryptionFailed,
    /// A plain JOSEError: jose throws it for a key-set response that is not
    /// a 200 or not JSON. Not on the identity-provider list, so 401.
    JoseGeneric,
}

impl JoseErrorCode {
    #[cfg(test)]
    const ALL: [JoseErrorCode; 15] = [
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
        JoseErrorCode::JoseGeneric,
    ];

    #[cfg(test)]
    fn code(self) -> &'static str {
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
            JoseErrorCode::JoseGeneric => "ERR_JOSE_GENERIC",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum VerificationFailure {
    Jose {
        code: JoseErrorCode,
        message: String,
    },
    NonJose(String),
}

impl VerificationFailure {
    fn jose(code: JoseErrorCode, message: impl Into<String>) -> Self {
        VerificationFailure::Jose {
            code,
            message: message.into(),
        }
    }

    fn non_jose(message: impl Into<String>) -> Self {
        VerificationFailure::NonJose(message.into())
    }

    fn message(&self) -> &str {
        match self {
            VerificationFailure::Jose { message, .. } => message,
            VerificationFailure::NonJose(m) => m,
        }
    }
}

/// jose's errors that mean the identity provider's side is at fault (503), as
/// opposed to the token (401).
fn is_idp_side_failure(error: &VerificationFailure) -> bool {
    match error {
        VerificationFailure::NonJose(_) => true,
        VerificationFailure::Jose { code, .. } => matches!(
            code,
            JoseErrorCode::JwksTimeout
                | JoseErrorCode::JwksInvalid
                | JoseErrorCode::JwkInvalid
                | JoseErrorCode::JwksMultipleMatchingKeys
        ),
    }
}

/// jose's defaults for a remote key set: keep a fetched set for 10 minutes
/// (cacheMaxAge), and refetch early for an unknown key at most every 30 seconds
/// (cooldownDuration).
const JWKS_CACHE_MAX_AGE: Duration = Duration::from_secs(600);
const JWKS_COOLDOWN: Duration = Duration::from_secs(30);
/// No key set is anywhere near this; it bounds what a misbehaving issuer can
/// make the server buffer.
const JWKS_MAX_BYTES: u64 = 1024 * 1024;
/// jwtVerify's `clockTolerance: 30`.
const CLOCK_TOLERANCE_SECS: f64 = 30.0;
/// jose's checkModulusLength for RS256.
const MIN_RSA_MODULUS_BITS: usize = 2048;
const DEFAULT_JWKS_TIMEOUT_MS: u64 = 5000;

/// Key material for tests: returns a JSON Web Key Set (`{"keys": [...]}`), the
/// counterpart of handing jose a local key set. Production leaves it unset and
/// fetches the issuer's set.
type KeySourceFn = Arc<dyn Fn() -> Result<Value, VerificationFailure> + Send + Sync + 'static>;

/// What a server needs to say about itself to check tokens.
#[derive(Debug, Clone)]
pub struct VerifierConfig {
    /// The Zitadel issuer, e.g. `https://auth.example.com`. A trailing slash
    /// is trimmed; the token's `iss` must match exactly.
    pub issuer: String,
    /// The Zitadel project id the token's audience must include.
    pub project_id: String,
    /// The OIDC clients whose access tokens are accepted (`client_id` claim).
    pub allowed_client_ids: Vec<String>,
    /// The people allowed in (`sub` claim).
    pub allowed_subjects: Vec<String>,
    /// Where to fetch the key set; defaults to `{issuer}/oauth/v2/keys`.
    pub jwks_uri: Option<String>,
    /// Sent with every key-set fetch.
    pub user_agent: String,
}

/// Build a verifier. Refuses an empty client or subject list: either would
/// let in everyone Zitadel is willing to issue a token to.
pub fn verifier(cfg: VerifierConfig) -> Result<Verifier, String> {
    Verifier::build(cfg, None, None)
}

struct CachedJwks {
    set: Value,
    fetched_at: Instant,
}

pub struct Verifier {
    issuer: String,
    project_id: String,
    allowed_subjects: HashSet<String>,
    allowed_client_ids: HashSet<String>,
    jwks_uri: String,
    key_source: Option<KeySourceFn>,
    agent: ureq::Agent,
    /// The last good key set. Held across a fetch, so concurrent requests
    /// share one fetch instead of each starting their own (jose's
    /// pendingFetch).
    jwks: Mutex<Option<CachedJwks>>,
    cache_max_age: Duration,
    cooldown: Duration,
    /// Seconds since the epoch, read once per token for the `nbf`/`exp`
    /// checks. Always the wall clock in production; tests pin it so the
    /// tolerance boundaries do not depend on when the second ticks over.
    clock: fn() -> f64,
}

impl Verifier {
    fn build(
        cfg: VerifierConfig,
        key_source: Option<KeySourceFn>,
        jwks_timeout_ms: Option<u64>,
    ) -> Result<Verifier, String> {
        let issuer = cfg.issuer.trim_end_matches('/').to_string();
        let jwks_uri = cfg
            .jwks_uri
            .unwrap_or_else(|| format!("{issuer}/oauth/v2/keys"));
        let allowed_subjects: HashSet<String> = cfg.allowed_subjects.into_iter().collect();
        if allowed_subjects.is_empty() {
            return Err("verifier requires at least one allowed subject. An empty \
list would authenticate every caller Zitadel is willing to issue a \
token to, which is not the same set as the people this endpoint serves."
                .to_string());
        }
        let allowed_client_ids: HashSet<String> = cfg.allowed_client_ids.into_iter().collect();
        if allowed_client_ids.is_empty() || allowed_client_ids.contains("") {
            return Err(
                "verifier requires at least one allowed client id, none of them \
empty. An empty value would accept a token minted for any OIDC client, \
which defeats the pin this check exists to enforce."
                    .to_string(),
            );
        }

        // One deadline for the whole fetch, body included, like jose's
        // AbortSignal.timeout. No redirects: jose fetches with
        // `redirect: "manual"`, so a 3xx is just a non-200 answer.
        let agent = ureq::AgentBuilder::new()
            .timeout(Duration::from_millis(
                jwks_timeout_ms.unwrap_or(DEFAULT_JWKS_TIMEOUT_MS),
            ))
            .redirects(0)
            .tls_config(tls_client_config())
            .user_agent(&cfg.user_agent)
            .build();

        Ok(Verifier {
            issuer,
            project_id: cfg.project_id,
            allowed_subjects,
            allowed_client_ids,
            jwks_uri,
            key_source,
            agent,
            jwks: Mutex::new(None),
            cache_max_age: JWKS_CACHE_MAX_AGE,
            cooldown: JWKS_COOLDOWN,
            clock: unix_now,
        })
    }

    /// Check a bearer token (the part after `Bearer `). Blocking: it may
    /// fetch the issuer's key set, so call it from a blocking context.
    pub fn verify(&self, bearer: &str) -> Result<Caller, AuthError> {
        if !looks_like_jwt(bearer) {
            return Err(AuthError::OpaqueToken);
        }

        let payload = match self.jwt_verify(bearer) {
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

        // TS: `azp !== undefined`. Any azp key at all, null included, marks an
        // id_token.
        if let Some(azp) = payload.get("azp") {
            let azp = match azp.as_str() {
                Some(s) => s.to_string(),
                None => azp.to_string(),
            };
            return Err(AuthError::AuthorizedPartyPresent { azp });
        }

        // Absent is reported as absent; anything that is not a string is
        // reported through its JSON text (so null is "null").
        let client_id = match payload.get("client_id") {
            None => return Err(AuthError::ClientNotAllowed { client_id: None }),
            Some(Value::String(cid)) => cid.clone(),
            Some(other) => {
                return Err(AuthError::ClientNotAllowed {
                    client_id: Some(other.to_string()),
                });
            }
        };
        if !self.allowed_client_ids.contains(&client_id) {
            return Err(AuthError::ClientNotAllowed {
                client_id: Some(client_id),
            });
        }

        Ok(Caller { subject, client_id })
    }

    /// jose's `jwtVerify(token, jwks, { issuer, algorithms: ["RS256"],
    /// clockTolerance: 30 })`, in jose's order: header, key, signature, and
    /// only then the claims. Nothing in the payload is read before the
    /// signature over it has been checked.
    fn jwt_verify(&self, token: &str) -> Result<Value, VerificationFailure> {
        let parts: Vec<&str> = token.split('.').collect();
        if parts.len() != 3 {
            return Err(jws_invalid("Invalid Compact JWS"));
        }
        let (encoded_header, encoded_payload, encoded_signature) = (parts[0], parts[1], parts[2]);

        let header = b64url_decode(encoded_header)
            .and_then(|bytes| serde_json::from_slice::<Value>(&bytes).ok())
            .filter(Value::is_object)
            .ok_or_else(|| jws_invalid("JWS Protected Header is invalid"))?;

        let b64 = check_crit_and_b64(&header)?;

        let alg = match header.get("alg") {
            Some(Value::String(alg)) if !alg.is_empty() => alg.as_str(),
            _ => {
                return Err(jws_invalid(
                    "JWS \"alg\" (Algorithm) Header Parameter missing or invalid",
                ))
            }
        };
        if alg != "RS256" {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JoseAlgNotAllowed,
                "\"alg\" (Algorithm) Header Parameter value not allowed",
            ));
        }

        let key = self.resolve_key(alg, header.get("kid"))?;

        let signature = b64url_decode(encoded_signature)
            .ok_or_else(|| jws_invalid("Failed to base64url decode the signature"))?;
        if key.modulus_bits() < MIN_RSA_MODULUS_BITS {
            // A TypeError in jose, not a JOSEError, so it lands on the
            // identity-provider side (503).
            return Err(VerificationFailure::non_jose(
                "RS256 requires key modulusLength to be 2048 bits or larger",
            ));
        }
        let signing_input = format!("{encoded_header}.{encoded_payload}");
        let components = RsaPublicKeyComponents {
            n: key.n.as_slice(),
            e: key.e.as_slice(),
        };
        if components
            .verify(
                &RSA_PKCS1_2048_8192_SHA256,
                signing_input.as_bytes(),
                &signature,
            )
            .is_err()
        {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JwsSignatureVerificationFailed,
                "signature verification failed",
            ));
        }

        let payload_bytes = b64url_decode(encoded_payload)
            .ok_or_else(|| jws_invalid("Failed to base64url decode the payload"))?;
        if !b64 {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JwtInvalid,
                "JWTs MUST NOT use unencoded payload",
            ));
        }
        let claims = serde_json::from_slice::<Value>(&payload_bytes)
            .ok()
            .filter(Value::is_object)
            .ok_or_else(|| {
                VerificationFailure::jose(
                    JoseErrorCode::JwtInvalid,
                    "JWT Claims Set must be a top-level JSON object",
                )
            })?;

        self.validate_claims(&claims, (self.clock)())?;
        Ok(claims)
    }

    /// jose's validateClaimsSet with only `issuer` and `clockTolerance` set.
    fn validate_claims(&self, claims: &Value, now: f64) -> Result<(), VerificationFailure> {
        let iss = match claims.get("iss") {
            None => return Err(claim_failed("missing required \"iss\" claim")),
            Some(iss) => iss,
        };
        if iss.as_str() != Some(self.issuer.as_str()) {
            return Err(claim_failed("unexpected \"iss\" claim value"));
        }
        numeric_date(claims, "iat")?;
        if let Some(nbf) = numeric_date(claims, "nbf")? {
            if nbf > now + CLOCK_TOLERANCE_SECS {
                return Err(claim_failed("\"nbf\" claim timestamp check failed"));
            }
        }
        if let Some(exp) = numeric_date(claims, "exp")? {
            if exp <= now - CLOCK_TOLERANCE_SECS {
                return Err(VerificationFailure::jose(
                    JoseErrorCode::JwtExpired,
                    "\"exp\" claim timestamp check failed",
                ));
            }
        }
        Ok(())
    }

    /// The key for this header: from the test key source, or from the cached
    /// issuer key set, fetching it when it is older than 10 minutes and once
    /// more (at most every 30 seconds) when no key in it matches.
    fn resolve_key(&self, alg: &str, kid: Option<&Value>) -> Result<RsaKey, VerificationFailure> {
        if let Some(source) = &self.key_source {
            return select_key(&source()?, alg, kid);
        }
        let mut cache = self.jwks.lock().unwrap_or_else(|p| p.into_inner());
        let fresh = matches!(&*cache, Some(c) if c.fetched_at.elapsed() < self.cache_max_age);
        if !fresh {
            *cache = Some(self.fetch_jwks()?);
        }
        let (first, cooling_down) = match &*cache {
            Some(cached) => (
                select_key(&cached.set, alg, kid),
                cached.fetched_at.elapsed() < self.cooldown,
            ),
            None => unreachable!("the key set was fetched above"),
        };
        match first {
            Err(VerificationFailure::Jose {
                code: JoseErrorCode::JwksNoMatchingKey,
                ..
            }) if !cooling_down => {
                let refreshed = self.fetch_jwks()?;
                let result = select_key(&refreshed.set, alg, kid);
                *cache = Some(refreshed);
                result
            }
            other => other,
        }
    }

    /// One GET of the issuer's key set, classified the way jose classifies it:
    /// a timeout is ERR_JWKS_TIMEOUT and an unreachable host is not a JOSE
    /// error at all (both 503), while a non-200 or a body that is not JSON is
    /// a generic JOSE error (401).
    fn fetch_jwks(&self) -> Result<CachedJwks, VerificationFailure> {
        let response = match self
            .agent
            .get(&self.jwks_uri)
            .set("Accept", "application/json, application/jwk-set+json")
            .call()
        {
            Ok(response) => response,
            Err(ureq::Error::Status(_, response)) => response,
            Err(ureq::Error::Transport(transport)) => {
                return Err(if transport_timed_out(&transport) {
                    VerificationFailure::jose(JoseErrorCode::JwksTimeout, "request timed out")
                } else {
                    VerificationFailure::non_jose("fetch failed")
                });
            }
        };
        if response.status() != 200 {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JoseGeneric,
                "Expected 200 OK from the JSON Web Key Set HTTP response",
            ));
        }
        let mut body = Vec::new();
        if let Err(e) = response
            .into_reader()
            .take(JWKS_MAX_BYTES)
            .read_to_end(&mut body)
        {
            return Err(
                if matches!(
                    e.kind(),
                    std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock
                ) {
                    VerificationFailure::jose(JoseErrorCode::JwksTimeout, "request timed out")
                } else {
                    VerificationFailure::non_jose("fetch failed")
                },
            );
        }
        let set = serde_json::from_slice::<Value>(&body).map_err(|_| {
            VerificationFailure::jose(
                JoseErrorCode::JoseGeneric,
                "Failed to parse the JSON Web Key Set HTTP response as JSON",
            )
        })?;
        if !is_jwk_set(&set) {
            return Err(jwks_malformed());
        }
        Ok(CachedJwks {
            set,
            fetched_at: Instant::now(),
        })
    }

    #[cfg(test)]
    fn with_cache_timing(mut self, cache_max_age: Duration, cooldown: Duration) -> Self {
        self.cache_max_age = cache_max_age;
        self.cooldown = cooldown;
        self
    }

    #[cfg(test)]
    fn with_clock(mut self, clock: fn() -> f64) -> Self {
        self.clock = clock;
        self
    }
}

/// Where a problem with the system's certificates is reported (once, when
/// the shared TLS setup is first built): stderr unless the program sets its
/// own with [`set_tls_warning_hook`] (the relay writes its JSON log line).
static TLS_WARNING_HOOK: OnceLock<fn(&str)> = OnceLock::new();

/// Sends the TLS setup's warnings to `hook` instead of stderr. Set it before
/// the first verifier is built; only the first call counts.
pub fn set_tls_warning_hook(hook: fn(&str)) {
    let _ = TLS_WARNING_HOOK.set(hook);
}

fn tls_warning(message: &str) {
    match TLS_WARNING_HOOK.get() {
        Some(hook) => hook(message),
        None => eprintln!("vitruvian-mcp-auth: {message}"),
    }
}

/// HTTPS client TLS: rustls on ring, trusting the system certificate store
/// as rustls-native-certs finds it (SSL_CERT_FILE / SSL_CERT_DIR first, then
/// the platform store). Built here rather than through ureq's `native-certs`
/// feature, which pulls in rustls-native-certs 0.7 and with it the
/// unmaintained rustls-pemfile (RUSTSEC-2025-0134). Built once and shared:
/// the key-set fetch uses it, and so does the vrelay connector.
pub fn tls_client_config() -> Arc<rustls::ClientConfig> {
    static CONFIG: OnceLock<Arc<rustls::ClientConfig>> = OnceLock::new();
    CONFIG
        .get_or_init(|| {
            let loaded = rustls_native_certs::load_native_certs();
            let errors: Vec<String> = loaded.errors.iter().map(|e| e.to_string()).collect();
            build_tls_config(loaded.certs, &errors, &tls_warning)
        })
        .clone()
}

fn build_tls_config(
    certs: Vec<rustls::pki_types::CertificateDer<'static>>,
    errors: &[String],
    warn: &dyn Fn(&str),
) -> Arc<rustls::ClientConfig> {
    for err in errors {
        warn(&format!("could not read a system CA certificate: {err}"));
    }
    let mut roots = rustls::RootCertStore::empty();
    let (added, _unparsable) = roots.add_parsable_certificates(certs);
    if added == 0 {
        warn("no CA certificates found; every HTTPS call will fail");
    }
    let provider = Arc::new(rustls::crypto::ring::default_provider());
    Arc::new(
        rustls::ClientConfig::builder_with_provider(provider)
            .with_safe_default_protocol_versions()
            .expect("ring supports rustls's default protocol versions")
            .with_root_certificates(roots)
            .with_no_client_auth(),
    )
}

fn jws_invalid(message: &str) -> VerificationFailure {
    VerificationFailure::jose(JoseErrorCode::JwsInvalid, message)
}

fn claim_failed(message: &str) -> VerificationFailure {
    VerificationFailure::jose(JoseErrorCode::JwtClaimValidationFailed, message)
}

fn jwks_malformed() -> VerificationFailure {
    VerificationFailure::jose(JoseErrorCode::JwksInvalid, "JSON Web Key Set malformed")
}

fn unix_now() -> f64 {
    // jose: Math.floor(Date.now() / 1000).
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as f64
}

/// A present `iat`/`nbf`/`exp` must be a number; absent is fine.
fn numeric_date(claims: &Value, claim: &str) -> Result<Option<f64>, VerificationFailure> {
    match claims.get(claim) {
        None => Ok(None),
        Some(Value::Number(n)) => Ok(n.as_f64()),
        Some(_) => Err(claim_failed(&format!("\"{claim}\" claim must be a number"))),
    }
}

/// jose's validateCrit + validateB64 for a JWS: `b64` is the only extension
/// it recognises. Returns whether the payload is base64url-encoded.
fn check_crit_and_b64(header: &Value) -> Result<bool, VerificationFailure> {
    let Some(crit) = header.get("crit") else {
        return Ok(true);
    };
    let names = match crit.as_array() {
        Some(items) if !items.is_empty() => items
            .iter()
            .map(|item| item.as_str().filter(|s| !s.is_empty()))
            .collect::<Option<Vec<&str>>>(),
        _ => None,
    }
    .ok_or_else(|| {
        jws_invalid(
            "\"crit\" (Critical) Header Parameter MUST be an array of non-empty strings when present",
        )
    })?;
    for name in &names {
        if *name != "b64" {
            return Err(VerificationFailure::jose(
                JoseErrorCode::JoseNotSupported,
                format!("Extension Header Parameter \"{name}\" is not recognized"),
            ));
        }
        if header.get(name).is_none() {
            return Err(jws_invalid(&format!(
                "Extension Header Parameter \"{name}\" is missing"
            )));
        }
    }
    if names.contains(&"b64") {
        return match header.get("b64") {
            Some(Value::Bool(b64)) => Ok(*b64),
            _ => Err(jws_invalid(
                "The \"b64\" (base64url-encode payload) Header Parameter must be a boolean",
            )),
        };
    }
    Ok(true)
}

fn is_jwk_set(value: &Value) -> bool {
    value.is_object()
        && value
            .get("keys")
            .and_then(|keys| keys.as_array())
            .is_some_and(|keys| keys.iter().all(Value::is_object))
}

/// An RSA public key from a JWK, big-endian, leading zeros kept as given.
struct RsaKey {
    n: Vec<u8>,
    e: Vec<u8>,
}

impl RsaKey {
    fn modulus_bits(&self) -> usize {
        match self.n.iter().position(|b| *b != 0) {
            Some(first) => (self.n.len() - first) * 8 - self.n[first].leading_zeros() as usize,
            None => 0,
        }
    }
}

/// jose's createLocalJWKSet lookup: the keys usable for this header; exactly
/// one must remain.
fn select_key(set: &Value, alg: &str, kid: Option<&Value>) -> Result<RsaKey, VerificationFailure> {
    if !is_jwk_set(set) {
        return Err(jwks_malformed());
    }
    let keys = set
        .get("keys")
        .and_then(|k| k.as_array())
        .map_or(&[][..], |k| k.as_slice());
    let candidates: Vec<&Value> = keys
        .iter()
        .filter(|jwk| is_usable_jwk(jwk, alg, kid))
        .collect();
    match candidates.as_slice() {
        [] => Err(VerificationFailure::jose(
            JoseErrorCode::JwksNoMatchingKey,
            "no applicable key found in the JSON Web Key Set",
        )),
        [jwk] => import_rsa_jwk(jwk),
        _ => Err(VerificationFailure::jose(
            JoseErrorCode::JwksMultipleMatchingKeys,
            "multiple matching keys found in the JSON Web Key Set",
        )),
    }
}

/// jose's isUsableJWK for an RSA algorithm. A JSON null is never "absent":
/// jose compares against undefined, and null fails every one of these.
fn is_usable_jwk(jwk: &Value, alg: &str, kid: Option<&Value>) -> bool {
    let ext_ok = match jwk.get("ext") {
        None => true,
        Some(v) => v.as_bool().is_some(),
    };
    let key_ops_ok = match jwk.get("key_ops") {
        None => true,
        Some(Value::Array(ops)) => {
            let names: Option<Vec<&str>> = ops.iter().map(|op| op.as_str()).collect();
            names.is_some_and(|names| {
                let unique: HashSet<&str> = names.iter().copied().collect();
                unique.len() == names.len() && unique.contains("verify")
            })
        }
        Some(_) => false,
    };
    let kty_ok = jwk.get("kty").and_then(|v| v.as_str()) == Some("RSA");
    let kid_ok = match kid {
        None => true,
        Some(Value::String(kid)) => jwk.get("kid").and_then(|v| v.as_str()) == Some(kid.as_str()),
        Some(_) => false,
    };
    let alg_ok = match jwk.get("alg") {
        None => true,
        Some(v) => v.as_str() == Some(alg),
    };
    let use_ok = match jwk.get("use") {
        None => true,
        Some(v) => v.as_str() == Some("sig"),
    };
    ext_ok && key_ops_ok && kty_ok && kid_ok && alg_ok && use_ok
}

fn import_rsa_jwk(jwk: &Value) -> Result<RsaKey, VerificationFailure> {
    let component = |name: &str| {
        jwk.get(name)
            .and_then(|v| v.as_str())
            .and_then(b64url_decode)
            .filter(|bytes| !bytes.is_empty())
    };
    match (component("n"), component("e")) {
        (Some(n), Some(e)) => Ok(RsaKey { n, e }),
        // WebCrypto's importKey rejects it with a DataError, which is not a
        // JOSE error: identity-provider side, 503.
        _ => Err(VerificationFailure::non_jose("Invalid RSA JSON Web Key")),
    }
}

/// Unpadded base64url, as JWS uses it. Like the forgiving decoder jose relies
/// on, it rejects a length that leaves a single dangling character and
/// ignores the unused low bits of the last character.
fn b64url_decode(input: &str) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(input.len() * 3 / 4);
    let mut buffer: u32 = 0;
    let mut bits = 0;
    for byte in input.bytes() {
        let value = match byte {
            b'A'..=b'Z' => byte - b'A',
            b'a'..=b'z' => byte - b'a' + 26,
            b'0'..=b'9' => byte - b'0' + 52,
            b'-' => 62,
            b'_' => 63,
            _ => return None,
        };
        buffer = (buffer << 6) | u32::from(value);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
            buffer &= (1 << bits) - 1;
        }
    }
    if input.len() % 4 == 1 {
        return None;
    }
    Some(out)
}

fn transport_timed_out(transport: &ureq::Transport) -> bool {
    let mut source = std::error::Error::source(transport);
    while let Some(err) = source {
        if let Some(io) = err.downcast_ref::<std::io::Error>() {
            if matches!(
                io.kind(),
                std::io::ErrorKind::TimedOut | std::io::ErrorKind::WouldBlock
            ) {
                return true;
            }
        }
        source = err.source();
    }
    false
}

#[cfg(test)]
mod tests {
    use super::*;
    use ring::rand::SystemRandom;
    use ring::signature::{RsaKeyPair, RSA_PKCS1_SHA256};
    use serde_json::{json, Value};
    use std::io::{BufRead, BufReader, Write};
    use std::net::TcpListener;
    use std::sync::atomic::{AtomicUsize, Ordering};

    const ISSUER: &str = "https://auth.example.test";
    const PROJECT_ID: &str = "123456789";
    const CLIENT_ID: &str = "555555555555555555";
    const OTHER_CLIENT_ID: &str = "777777777777777777";

    // Throwaway 2048-bit RSA keys (PKCS#8 DER, base64url), generated for
    // these tests only and used nowhere else.
    const TEST_KEY_A: &str = concat!(
        "MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQCvutM9Ruknu7rIHzvYC02EWEa-9e1c7uKxV81fV2",
        "RMN-iBE4rlA_sxIccFC8QeISKKeIg8dxlY3V1EbkRjY7TYyGcsie28b6dWUi9uUkZqTCG0cMu5laAR8YxUbWdetOHp",
        "fwiD70KTDd_n2-Mgb84FfjpzEwSvFrdNgwGccDkcPzAqMkQcy7r-vEqKpLfLbw3iile4Tq_PILB6GriFVl63TEsosP",
        "WVyGEncch5YPzngHL94zkoKmUQMKBgR5CTIE7V157bvw_OkXAfjG6LjGDNlS1rUN0nuuO56pZcSdhVNT0qkLainlmh",
        "flaudwusJGEfrBjBXTHYnxZdHFMXUrmDAgMBAAECggEAVa34B5T24hYQhDliUrx0D5aA6-N5V0nsAn6mVhmEf_r0ZF",
        "a0bmPqCfMHl8i8Vtpd_ni1KBIDrEXGDzLaKkF3cAkJ8PfRD4K66oYItTftOC-lcVZbpkEzOfx1KMbs0wrLaS60Zqt1",
        "4MAvjtsxmuOYZio88lVv_7RKLEM3OmCnH8NJ7HJ2AZtk_9pBhWs3gVWNnf2HwZe2g9LpFKEpD1VZLKd9fv7IQ9Pki3",
        "Om1m_EIuJhDTMS2ZtY52E5YDQzixuD2J1CylcofbwOCf02MXEvfWhZw_IzmTFuAr8VaxPBTpF3U_AMCvU5rOT-svEs",
        "lh0ezfMS9FF8gJJhzwlEv82UuQKBgQDjw02gBCXfVmKmUN8PQiFVC7le3tdGREU6DetDeUiCH_fhkZLhZGCJ7XN0pL",
        "FAD0kQy5JgIMRI_AmmCwLy5FBUyKlHCGS064ati-4m0Xu8j_q-MMp1co5J4d_S_b0hf3qyezHqCAiZb30rTTIQHQxI",
        "mHCCW1MOLquW9hJ1kHDAawKBgQDFhBrAg1Xw6RgdhDr7P4UZUKHTWZnUVVL3Coqj5CYd6wSdhJOKG4IwIxELWk_TYl",
        "dHR-LbBLKGTqkGWNxSigjU7bLL2ne7JtDvEJ82StD6Q9BFdifrYUCGNsdpdyTeQ_2fwaVXhpLgpUEyn3whbHZPMvqz",
        "tL8XeUPtcGVAeV5RSQKBgElAyTiL3PpluDixjexEYqANs0L1_NrWnkU7sMz0twNS8NCVl13ygLIbsqRzS6bEw8UpFB",
        "zirP6kQR4sMHiaQdPi7b6wzmL51Uj_1kqZ2WgeDpEY9CSuAWF1yhz8CtY5P-cjhDw29T0UBHfmzhEspoS6soTahm3r",
        "SLi2z90L5ZedAoGAWRs17m_Rz7N426gR69NGOptzxiOAEJjFqwmobjO5NnoWRPHQlde_LfRD9jkyFg0hjtjRcTl3SL",
        "wn6OMh0mLPhTAPH4RZy6bBT3jSOu4ZxS3ewdeCPuBK-cGwyNWlXliSDQaRjyD5Fju3ZB0rJPEHlsdK7tO1-eMNUAsK",
        "wsF-WXECgYEAwPw6ZR4Qkg3Nvgm3gXg6u0kikIRkNwtrh1gFZCTb2OVt6pYGnTXlmv6dsUZEz7k3p7PRMsavi3sd8i",
        "hKXawoJUsQ9-eQi6wO_uiFVIdV566aclIo_0nuVRjs8tQ5KI6eUZ0woMsrqfavYnwZ9H7RfOQW8Sjkc5hG1z5pc2gM",
        "xLI",
    );
    const TEST_KEY_B: &str = concat!(
        "MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQCnHxjqdcU72UAr6bjXnvtc7eQgRNIUxBtjSAYZFf",
        "XOz_KN1GlGGBd7eYoTVVNnQQbUKe54GAqzi0TBoR4baW9q0482j0Jf4UXPzxMk3cwgU9IgLausBlwmWQPeYknNeJVq",
        "Y6o-UI9n2K4cxwzQI7VAYR2Hzz5iX4pyoSzc9fkpFjR2JYha6uGotuiC8uOC8ds5yoP8x_UzzkNC-Ft-mudBVoQb6y",
        "VKfOdbMDsgMhHe9BcRy3HzFXZOXcl9NV-9YL8hpSJ2gs63NpaZguShRxdYKCJ6N31tuapAQdAmLdXpnyfNLbXwlsrU",
        "OxWFHE5zPltTf-cpwLNh8ERuK6drZ3MDAgMBAAECggEAHhFDO1OrA6SHnh7zyZ9p3ANU6tVW8rOBtfAMYNEJo4bYPd",
        "o8gobtGqL4S5grZEVXxC4zIFo6-qiQ20FwmD_08sRTXN6Tc4qlM8kuyZA6HIrYID_3RgDy7VdQkd8fJh-OylBaHdIC",
        "qw1Z7gWF8aCrCIUwefG4aJyF3S_QUYTTqidw8WEfRcO6NvS_-fyrjIVY_9y51Gf2C4L367sKX6NzzeLcPF0QWouOO5",
        "XwA7VTtt68idLO5KxgU-zLNbr5J_fpk2hXigps2dYKyAIYnisr-LgBPiSTQ_kBwCEMTitxP-yPr7l_VUJzL5Rr5ph0",
        "VglAi0fU58MAlAR0U4C4Wb3PIQKBgQDeri8k_BMi8e2Y86bL0b-k22mtxQBlink_itnhCOd26MgnVJ5PHtoAr84sFk",
        "Br3y1cx6DWqA_Kl-qV4OdbAvjZp3ep9fkLWsZqJm5DFBj3TUH64Y3Bkdh4rXcUzBORXynyINISIRAKuYVJqDNbZoJv",
        "1h4U8_N0REYyZpMIZMFjMwKBgQDAILexZ2s1syO9k9e1GKHBL_GBzQHNoy_8sPSCACimRRaT2w0Tff1rx4oEO_WzBZ",
        "A-pwTVtUtBiXufaxpCwlQ8VoHoZQ1b1cky8K8jVkE03cLq8_a2vqv8HebWubQmSe95tfjfhcFnt13w96wopQyLMBTD",
        "WLzNt2cPtRz_zkKw8QKBgHMhY8affdVneAzIjMh8nbVCrBTn8hiNy7qKs7Ohwuq72CBdo6wMq3IHc3Vf29bqAK4jmI",
        "jjQ6bffK4ZJgTsOHVwHHKHdkfkmwlu7TtJPM8_5okr7PrTyTQ7m4HpMYTLywgg5_vvlDe3S66VhFgRXAcukUcMCidm",
        "1VRhrEt-rG35AoGBALhur-fdH02taeHSyn9N5flNzMiNw-1jee1Y8V7aSCtUpxfIcAUGLQAJzLPD21i_PnjmW_3Kyz",
        "Nehw3CArOTWMmTQaGVX_2IfFwqL_X8FxxoxXRGPc-vuemLyszV99nJn9l2ljH8dGzb2ZI4L0vVJPV4cnYT-SqBpK2v",
        "buchWWQBAoGBAJqdrfiXHJ3u_n9fDKcjvQZtClHrgda1QsWFILMIfAXbUuVzqR5ZE_gCol37ruZyhEHHGCfOWi8DNo",
        "I7Hu7J4eOYQTQGuNMqB7-9pOV4kpeyw7dPWOpCab0m57qypesjZSVEr0145gip543VO9gO7_-T4uhA7z62Nff8kAu_",
        "ahZB",
    );

    fn b64url(bytes: &[u8]) -> String {
        const ALPHABET: &[u8] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
        let mut out = String::new();
        for chunk in bytes.chunks(3) {
            let n = chunk.iter().fold(0u32, |acc, b| (acc << 8) | u32::from(*b))
                << (8 * (3 - chunk.len()));
            for i in 0..=chunk.len() {
                out.push(ALPHABET[((n >> (18 - 6 * i)) & 63) as usize] as char);
            }
        }
        out
    }

    fn key_pair(pkcs8_b64url: &str) -> RsaKeyPair {
        RsaKeyPair::from_pkcs8(&b64url_decode(pkcs8_b64url).unwrap()).unwrap()
    }

    fn jwk(pair: &RsaKeyPair, kid: &str) -> Value {
        let public: RsaPublicKeyComponents<Vec<u8>> = pair.public().into();
        json!({
            "kty": "RSA",
            "kid": kid,
            "alg": "RS256",
            "use": "sig",
            "n": b64url(&public.n),
            "e": b64url(&public.e),
        })
    }

    fn key_set(keys: Vec<Value>) -> Value {
        json!({ "keys": keys })
    }

    fn sign_parts(pair: &RsaKeyPair, header: &str, payload: &str) -> String {
        let signing_input = format!("{header}.{payload}");
        let mut signature = vec![0u8; pair.public().modulus_len()];
        pair.sign(
            &RSA_PKCS1_SHA256,
            &SystemRandom::new(),
            signing_input.as_bytes(),
            &mut signature,
        )
        .unwrap();
        format!("{signing_input}.{}", b64url(&signature))
    }

    fn mint(pair: &RsaKeyPair, header: Value, claims: &Value) -> String {
        sign_parts(
            pair,
            &b64url(header.to_string().as_bytes()),
            &b64url(claims.to_string().as_bytes()),
        )
    }

    fn header(kid: &str) -> Value {
        json!({ "alg": "RS256", "kid": kid })
    }

    fn claims() -> Value {
        let now = unix_now();
        json!({
            "iss": ISSUER,
            "aud": [PROJECT_ID, "other"],
            "sub": "user-42",
            "client_id": CLIENT_ID,
            "iat": now,
            "exp": now + 300.0,
        })
    }

    fn with(mut claims: Value, key: &str, value: Value) -> Value {
        claims
            .as_object_mut()
            .unwrap()
            .insert(key.to_string(), value);
        claims
    }

    fn without(mut claims: Value, key: &str) -> Value {
        claims.as_object_mut().unwrap().remove(key);
        claims
    }

    fn config(jwks_uri: Option<String>) -> VerifierConfig {
        VerifierConfig {
            issuer: format!("{ISSUER}/"),
            project_id: PROJECT_ID.to_string(),
            allowed_client_ids: vec![CLIENT_ID.to_string()],
            allowed_subjects: vec!["user-42".to_string()],
            jwks_uri,
            user_agent: "vitruvian-mcp-auth-test".to_string(),
        }
    }

    fn local_verifier(set: Value) -> Verifier {
        Verifier::build(config(None), Some(Arc::new(move || Ok(set.clone()))), None).unwrap()
    }

    fn verifier_a() -> (RsaKeyPair, Verifier) {
        let a = key_pair(TEST_KEY_A);
        let verifier = local_verifier(key_set(vec![jwk(&a, "a")]));
        (a, verifier)
    }

    /// Status and the reason jose would have given.
    fn refusal(result: Result<Caller, AuthError>) -> (u16, String) {
        match result {
            Ok(caller) => panic!("expected a refusal, got {caller:?}"),
            Err(AuthError::InvalidToken { reason }) => (401, reason),
            Err(AuthError::IdpUnavailable { reason }) => (503, reason),
            Err(other) => (other.status(), other.message()),
        }
    }

    #[test]
    fn bearer_extraction_matches_the_ts_regex() {
        assert_eq!(extract_bearer(Some("Bearer abc")), Some("abc"));
        assert_eq!(extract_bearer(Some("  bEaReR    abc  ")), Some("abc"));
        assert_eq!(extract_bearer(Some("Bearer a b")), Some("a b"));
        for bad in [
            None,
            Some(""),
            Some("Bearer"),
            Some("Bearer "),
            Some("Bearerabc"),
            Some("Basic abc"),
            Some("Bearer\tabc"),
            Some("Bearer a\nb"),
        ] {
            assert_eq!(extract_bearer(bad), None, "{bad:?}");
        }
        // Byte 6 inside a multi-byte character: a refusal, not a panic.
        assert_eq!(extract_bearer(Some("Beareé token")), None);
        assert_eq!(extract_bearer(Some("ééééé")), None);
    }

    #[test]
    fn looks_like_jwt_checks_three_base64url_segments() {
        assert!(looks_like_jwt("a.b.c"));
        assert!(looks_like_jwt("aZ09-_.x.y"));
        assert!(!looks_like_jwt("a.b"));
        assert!(!looks_like_jwt("a..c"));
        assert!(!looks_like_jwt("a.b.c.d"));
        assert!(!looks_like_jwt("a.b+.c"));
        assert!(!looks_like_jwt("opaque-token"));
    }

    #[test]
    fn base64url_decoding_is_forgiving_like_jose() {
        assert_eq!(b64url_decode("").unwrap(), b"");
        assert_eq!(b64url_decode("YQ").unwrap(), b"a");
        assert_eq!(b64url_decode("YWI").unwrap(), b"ab");
        assert_eq!(b64url_decode("YWJj").unwrap(), b"abc");
        assert_eq!(b64url_decode("-_8").unwrap(), vec![0xfb, 0xff]);
        // Unused low bits are ignored, as forgiving-base64 does.
        assert_eq!(b64url_decode("YR").unwrap(), b"a");
        assert!(b64url_decode("YWJjZ").is_none());
        assert!(b64url_decode("YW=").is_none());
        assert!(b64url_decode("Y+").is_none());
    }

    #[test]
    fn a_valid_token_is_accepted() {
        let (a, verifier) = verifier_a();
        let caller = verifier.verify(&mint(&a, header("a"), &claims())).unwrap();
        assert_eq!(caller.subject, "user-42");
        assert_eq!(caller.client_id, CLIENT_ID);
    }

    #[test]
    fn accepts_any_listed_client_id() {
        let a = key_pair(TEST_KEY_A);
        let mut cfg = config(None);
        cfg.allowed_client_ids = vec![CLIENT_ID.to_string(), OTHER_CLIENT_ID.to_string()];
        let set = key_set(vec![jwk(&a, "a")]);
        let verifier = Verifier::build(cfg, Some(Arc::new(move || Ok(set.clone()))), None).unwrap();
        for id in [CLIENT_ID, OTHER_CLIENT_ID] {
            let token = mint(&a, header("a"), &with(claims(), "client_id", json!(id)));
            let caller = verifier.verify(&token).unwrap();
            assert_eq!(caller.client_id, id);
            assert_eq!(caller.subject, "user-42");
        }
    }

    #[test]
    fn rejects_unlisted_client_id() {
        let (a, verifier) = verifier_a();
        let token = mint(
            &a,
            header("a"),
            &with(claims(), "client_id", json!(OTHER_CLIENT_ID)),
        );
        let err = verifier.verify(&token).unwrap_err();
        assert_eq!(err.code(), "insufficient_scope");
        assert_eq!(err.status(), 403);
        assert_eq!(
            err,
            AuthError::ClientNotAllowed {
                client_id: Some(OTHER_CLIENT_ID.to_string())
            }
        );
    }

    #[test]
    fn a_token_without_kid_uses_the_only_usable_key() {
        let (a, verifier) = verifier_a();
        let no_kid = json!({ "alg": "RS256" });
        assert!(verifier.verify(&mint(&a, no_kid, &claims())).is_ok());
    }

    #[test]
    fn a_forged_or_tampered_signature_is_rejected() {
        let a = key_pair(TEST_KEY_A);
        let b = key_pair(TEST_KEY_B);
        let verifier = local_verifier(key_set(vec![jwk(&a, "a")]));
        // Signed by B but claiming A's key id.
        assert_eq!(
            refusal(verifier.verify(&mint(&b, header("a"), &claims()))),
            (401, "signature verification failed".to_string())
        );
        // Payload swapped after signing.
        let token = mint(&a, header("a"), &claims());
        let parts: Vec<&str> = token.split('.').collect();
        let forged = with(claims(), "sub", json!("user-43"));
        let tampered = format!(
            "{}.{}.{}",
            parts[0],
            b64url(forged.to_string().as_bytes()),
            parts[2]
        );
        assert_eq!(
            refusal(verifier.verify(&tampered)),
            (401, "signature verification failed".to_string())
        );
    }

    #[test]
    fn the_key_is_picked_by_kid() {
        let a = key_pair(TEST_KEY_A);
        let b = key_pair(TEST_KEY_B);
        let verifier = local_verifier(key_set(vec![jwk(&a, "a"), jwk(&b, "b")]));
        assert!(verifier.verify(&mint(&a, header("a"), &claims())).is_ok());
        assert!(verifier.verify(&mint(&b, header("b"), &claims())).is_ok());
        // Unknown kid: no applicable key (401, jose's JWKSNoMatchingKey).
        assert_eq!(
            refusal(verifier.verify(&mint(&a, header("c"), &claims()))),
            (
                401,
                "no applicable key found in the JSON Web Key Set".to_string()
            )
        );
        // No kid and two usable keys: jose refuses to guess (503).
        let no_kid = json!({ "alg": "RS256" });
        assert_eq!(
            refusal(verifier.verify(&mint(&a, no_kid, &claims()))),
            (
                503,
                "multiple matching keys found in the JSON Web Key Set".to_string()
            )
        );
        // A non-string kid matches nothing.
        let numeric_kid = json!({ "alg": "RS256", "kid": 1 });
        assert_eq!(
            refusal(verifier.verify(&mint(&a, numeric_kid, &claims()))).0,
            401
        );
    }

    #[test]
    fn unusable_keys_are_skipped_like_jose() {
        let a = key_pair(TEST_KEY_A);
        let usable = jwk(&a, "a");
        for (field, value) in [
            ("use", json!("enc")),
            ("use", Value::Null),
            ("alg", json!("RS512")),
            ("alg", Value::Null),
            ("kty", json!("EC")),
            ("ext", json!("yes")),
            ("key_ops", json!(["sign"])),
            ("key_ops", json!(["verify", "verify"])),
            ("key_ops", Value::Null),
        ] {
            let verifier =
                local_verifier(key_set(vec![with(usable.clone(), field, value.clone())]));
            assert_eq!(
                refusal(verifier.verify(&mint(&a, header("a"), &claims()))).0,
                401,
                "{field}={value}"
            );
        }
        for (field, value) in [
            ("ext", json!(true)),
            ("key_ops", json!(["verify", "encrypt"])),
        ] {
            let verifier =
                local_verifier(key_set(vec![with(usable.clone(), field, value.clone())]));
            assert!(
                verifier.verify(&mint(&a, header("a"), &claims())).is_ok(),
                "{field}={value}"
            );
        }
        // No alg or use on the key at all is fine.
        let bare = without(without(usable, "alg"), "use");
        assert!(local_verifier(key_set(vec![bare]))
            .verify(&mint(&a, header("a"), &claims()))
            .is_ok());
    }

    #[test]
    fn a_short_rsa_key_is_an_identity_provider_problem() {
        let a = key_pair(TEST_KEY_A);
        // A 1024-bit modulus: refused before any signature check (jose's
        // checkModulusLength throws a TypeError, so 503).
        let short = with(jwk(&a, "a"), "n", json!(b64url(&[0xc1; 128])));
        assert_eq!(
            refusal(local_verifier(key_set(vec![short])).verify(&mint(&a, header("a"), &claims()))),
            (
                503,
                "RS256 requires key modulusLength to be 2048 bits or larger".to_string()
            )
        );
        let broken = without(jwk(&a, "a"), "n");
        assert_eq!(
            refusal(local_verifier(key_set(vec![broken])).verify(&mint(
                &a,
                header("a"),
                &claims()
            ))),
            (503, "Invalid RSA JSON Web Key".to_string())
        );
    }

    #[test]
    fn modulus_bits_ignore_leading_zeros() {
        assert_eq!(
            RsaKey {
                n: vec![0, 0x80, 0],
                e: vec![1]
            }
            .modulus_bits(),
            16
        );
        assert_eq!(
            RsaKey {
                n: vec![0x01, 0xff],
                e: vec![1]
            }
            .modulus_bits(),
            9
        );
        assert_eq!(
            RsaKey {
                n: vec![0, 0],
                e: vec![1]
            }
            .modulus_bits(),
            0
        );
    }

    #[test]
    fn header_problems_are_reported_like_jose() {
        let (a, verifier) = verifier_a();
        let payload = b64url(claims().to_string().as_bytes());
        let cases: Vec<(String, &str)> = vec![
            (b64url(b"not json"), "JWS Protected Header is invalid"),
            (b64url(b"[]"), "JWS Protected Header is invalid"),
            (b64url(&[0xff, 0xfe]), "JWS Protected Header is invalid"),
            (b64url(br#"{"kid":"a"}"#), "JWS \"alg\" (Algorithm) Header Parameter missing or invalid"),
            (b64url(br#"{"alg":""}"#), "JWS \"alg\" (Algorithm) Header Parameter missing or invalid"),
            (b64url(br#"{"alg":"HS256"}"#), "\"alg\" (Algorithm) Header Parameter value not allowed"),
            (b64url(br#"{"alg":"none"}"#), "\"alg\" (Algorithm) Header Parameter value not allowed"),
            (
                b64url(br#"{"alg":"RS256","crit":[]}"#),
                "\"crit\" (Critical) Header Parameter MUST be an array of non-empty strings when present",
            ),
            (
                b64url(br#"{"alg":"RS256","crit":["exp"],"exp":1}"#),
                "Extension Header Parameter \"exp\" is not recognized",
            ),
            (
                b64url(br#"{"alg":"RS256","crit":["b64"]}"#),
                "Extension Header Parameter \"b64\" is missing",
            ),
            (
                b64url(br#"{"alg":"RS256","crit":["b64"],"b64":"no"}"#),
                "The \"b64\" (base64url-encode payload) Header Parameter must be a boolean",
            ),
        ];
        for (encoded_header, expected) in cases {
            let token = sign_parts(&a, &encoded_header, &payload);
            assert_eq!(
                refusal(verifier.verify(&token)),
                (401, expected.to_string()),
                "{encoded_header}"
            );
        }
    }

    #[test]
    fn an_unencoded_payload_is_refused_after_the_signature_check() {
        let (a, verifier) = verifier_a();
        let header = b64url(br#"{"alg":"RS256","kid":"a","crit":["b64"],"b64":false}"#);
        let token = sign_parts(&a, &header, "abc");
        assert_eq!(
            refusal(verifier.verify(&token)),
            (401, "JWTs MUST NOT use unencoded payload".to_string())
        );
    }

    #[test]
    fn the_claims_must_be_a_json_object() {
        let (a, verifier) = verifier_a();
        let header = b64url(header("a").to_string().as_bytes());
        for payload in [b"[]".to_vec(), b"\"x\"".to_vec(), b"{".to_vec(), vec![0xff]] {
            let token = sign_parts(&a, &header, &b64url(&payload));
            assert_eq!(
                refusal(verifier.verify(&token)),
                (
                    401,
                    "JWT Claims Set must be a top-level JSON object".to_string()
                )
            );
        }
    }

    #[test]
    fn deeply_nested_json_is_refused_without_crashing() {
        let (a, verifier) = verifier_a();
        let nested = "[".repeat(20_000);
        let token = sign_parts(&a, &b64url(nested.as_bytes()), &b64url(b"{}"));
        assert_eq!(
            refusal(verifier.verify(&token)),
            (401, "JWS Protected Header is invalid".to_string())
        );
    }

    #[test]
    fn issuer_and_time_claims_are_checked_like_jose() {
        // The verifier reads this same instant, so the boundaries below are
        // exact: with the wall clock, a second ticking over between here and
        // the check made `nbf = now + 31` acceptable and failed the test.
        const NOW: f64 = 1_800_000_000.0;
        let (a, verifier) = verifier_a();
        let verifier = verifier.with_clock(|| NOW);
        let now = NOW;
        let claims = || {
            let claims = with(claims(), "iat", json!(now));
            with(claims, "exp", json!(now + 300.0))
        };
        let check = |claims: Value| refusal(verifier.verify(&mint(&a, header("a"), &claims)));
        assert_eq!(
            check(without(claims(), "iss")),
            (401, "missing required \"iss\" claim".to_string())
        );
        assert_eq!(
            check(with(claims(), "iss", json!("https://evil.example"))),
            (401, "unexpected \"iss\" claim value".to_string())
        );
        // The configured issuer's trailing slash is trimmed, the claim's is not.
        assert_eq!(
            check(with(claims(), "iss", json!(format!("{ISSUER}/")))),
            (401, "unexpected \"iss\" claim value".to_string())
        );
        assert_eq!(
            check(with(claims(), "iss", Value::Null)).1,
            "unexpected \"iss\" claim value"
        );
        assert_eq!(
            check(with(claims(), "iat", json!("now"))),
            (401, "\"iat\" claim must be a number".to_string())
        );
        assert_eq!(
            check(with(claims(), "exp", Value::Null)),
            (401, "\"exp\" claim must be a number".to_string())
        );
        assert_eq!(
            check(with(claims(), "nbf", json!("soon"))),
            (401, "\"nbf\" claim must be a number".to_string())
        );
        assert_eq!(
            check(with(claims(), "exp", json!(now - 31.0))),
            (401, "\"exp\" claim timestamp check failed".to_string())
        );
        // jose rejects exp <= now - tolerance, so exactly 30s ago is expired.
        assert_eq!(check(with(claims(), "exp", json!(now - 30.0))).0, 401);
        assert_eq!(
            check(with(claims(), "nbf", json!(now + 31.0))),
            (401, "\"nbf\" claim timestamp check failed".to_string())
        );
        let ok = |claims: Value| verifier.verify(&mint(&a, header("a"), &claims)).is_ok();
        // jose accepts nbf <= now + tolerance and exp > now - tolerance.
        assert!(ok(with(claims(), "nbf", json!(now + 30.0))));
        assert!(ok(with(claims(), "exp", json!(now - 29.0))));
        assert!(ok(with(claims(), "exp", json!(now - 25.0))));
        assert!(ok(with(claims(), "nbf", json!(now + 25.0))));
        assert!(ok(without(without(claims(), "exp"), "iat")));
    }

    #[test]
    fn audience_subject_azp_and_client_are_checked_like_the_ts_server() {
        let (a, verifier) = verifier_a();
        let check = |claims: Value| verifier.verify(&mint(&a, header("a"), &claims));

        let err = check(with(claims(), "aud", json!("987654321"))).unwrap_err();
        assert_eq!(err.status(), 403);
        assert!(err.message().contains("Presented audience: 987654321."));
        assert!(err.message().contains(&audience_scope_for(PROJECT_ID)));
        let err = check(without(claims(), "aud")).unwrap_err();
        assert!(err.message().contains("Presented audience: (none)."));

        assert_eq!(
            check(without(claims(), "sub")).unwrap_err(),
            AuthError::InvalidToken {
                reason: "token has no subject (sub) claim".to_string()
            }
        );
        assert_eq!(
            check(with(claims(), "sub", json!("user-7"))).unwrap_err(),
            AuthError::SubjectNotAllowed {
                subject: "user-7".to_string()
            }
        );
        assert_eq!(
            check(with(claims(), "azp", json!("web"))).unwrap_err(),
            AuthError::AuthorizedPartyPresent {
                azp: "web".to_string()
            }
        );
        // azp: null is still an azp (TS: azp !== undefined).
        assert_eq!(
            check(with(claims(), "azp", Value::Null)).unwrap_err(),
            AuthError::AuthorizedPartyPresent {
                azp: "null".to_string()
            }
        );
        assert_eq!(
            check(without(claims(), "client_id")).unwrap_err(),
            AuthError::ClientNotAllowed { client_id: None }
        );
        assert_eq!(
            check(with(claims(), "client_id", Value::Null)).unwrap_err(),
            AuthError::ClientNotAllowed {
                client_id: Some("null".to_string())
            }
        );
        assert_eq!(
            check(with(claims(), "client_id", json!(""))).unwrap_err(),
            AuthError::ClientNotAllowed {
                client_id: Some(String::new())
            }
        );
        assert_eq!(
            check(with(claims(), "client_id", json!(7))).unwrap_err(),
            AuthError::ClientNotAllowed {
                client_id: Some("7".to_string())
            }
        );
        assert_eq!(
            check(with(claims(), "client_id", json!("666"))).unwrap_err(),
            AuthError::ClientNotAllowed {
                client_id: Some("666".to_string())
            }
        );
    }

    #[test]
    fn construction_refuses_an_open_door() {
        let mut no_subjects = config(None);
        no_subjects.allowed_subjects.clear();
        assert!(verifier(no_subjects).is_err());
        let mut no_clients = config(None);
        no_clients.allowed_client_ids.clear();
        assert!(verifier(no_clients).is_err());
        let mut empty_client = config(None);
        empty_client.allowed_client_ids = vec![CLIENT_ID.to_string(), String::new()];
        assert!(verifier(empty_client).is_err());
    }

    #[test]
    fn idp_side_classification_matches_jose() {
        for code in JoseErrorCode::ALL {
            let idp = is_idp_side_failure(&VerificationFailure::jose(code, "x"));
            let expected = matches!(
                code,
                JoseErrorCode::JwksTimeout
                    | JoseErrorCode::JwksInvalid
                    | JoseErrorCode::JwkInvalid
                    | JoseErrorCode::JwksMultipleMatchingKeys
            );
            assert_eq!(idp, expected, "{}", code.code());
        }
        assert!(is_idp_side_failure(&VerificationFailure::non_jose(
            "fetch failed"
        )));
    }

    #[test]
    fn a_refusal_names_the_claim_that_caused_it() {
        let cases = [
            (
                AuthError::SubjectNotAllowed {
                    subject: "u1".into(),
                },
                Some("u1"),
                Some("sub"),
            ),
            (
                AuthError::AuthorizedPartyPresent { azp: "web".into() },
                Some("web"),
                Some("azp"),
            ),
            (
                AuthError::ClientNotAllowed {
                    client_id: Some("c9".into()),
                },
                Some("c9"),
                Some("client_id"),
            ),
            (
                AuthError::ClientNotAllowed { client_id: None },
                None,
                Some("client_id"),
            ),
            (AuthError::MissingToken, None, None),
            (AuthError::InvalidToken { reason: "x".into() }, None, None),
        ];
        for (err, presented, label) in cases {
            assert_eq!(err.presented(), presented, "{err:?}");
            assert_eq!(err.presented_label(), label, "{err:?}");
        }
    }

    #[test]
    fn www_authenticate_carries_the_metadata_url_on_a_401() {
        let url = "https://relay.example.test/.well-known/oauth-protected-resource/mcp";
        assert_eq!(
            www_authenticate(url, None),
            format!("Bearer resource_metadata=\"{url}\"")
        );
        let challenge = www_authenticate(url, Some(&AuthError::OpaqueToken));
        assert!(challenge.starts_with("Bearer error=\"invalid_token\", error_description=\""));
        assert!(challenge.ends_with(&format!("resource_metadata=\"{url}\"")));
        // A 403 is not a request to sign in again, so no metadata url.
        let forbidden = www_authenticate(
            url,
            Some(&AuthError::SubjectNotAllowed {
                subject: "x\r\nInjected: 1".to_string(),
            }),
        );
        assert!(forbidden.starts_with("Bearer error=\"insufficient_scope\""));
        assert!(!forbidden.contains("resource_metadata"));
        assert!(!forbidden.contains(['\r', '\n']));
    }

    /// A one-route HTTP server for the key set: what it answers can change
    /// between requests, and it counts them.
    struct JwksServer {
        url: String,
        hits: Arc<AtomicUsize>,
        reply: Arc<Mutex<(u16, String, Duration)>>,
    }

    impl JwksServer {
        fn start(status: u16, body: String) -> Self {
            let listener = TcpListener::bind("127.0.0.1:0").unwrap();
            let url = format!("http://{}/oauth/v2/keys", listener.local_addr().unwrap());
            let hits = Arc::new(AtomicUsize::new(0));
            let reply = Arc::new(Mutex::new((status, body, Duration::ZERO)));
            let (thread_hits, thread_reply) = (Arc::clone(&hits), Arc::clone(&reply));
            std::thread::spawn(move || {
                for stream in listener.incoming() {
                    let Ok(mut stream) = stream else { continue };
                    let mut reader = BufReader::new(stream.try_clone().unwrap());
                    let mut line = String::new();
                    while reader.read_line(&mut line).is_ok_and(|n| n > 0) && line != "\r\n" {
                        line.clear();
                    }
                    thread_hits.fetch_add(1, Ordering::SeqCst);
                    let (status, body, delay) = thread_reply.lock().unwrap().clone();
                    std::thread::sleep(delay);
                    let location = if status == 302 {
                        "Location: /elsewhere\r\n"
                    } else {
                        ""
                    };
                    let _ = write!(
                        stream,
                        "HTTP/1.1 {status} X\r\n{location}Content-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len()
                    );
                }
            });
            JwksServer { url, hits, reply }
        }

        fn set(&self, status: u16, body: String, delay: Duration) {
            *self.reply.lock().unwrap() = (status, body, delay);
        }

        fn hits(&self) -> usize {
            self.hits.load(Ordering::SeqCst)
        }
    }

    fn remote_verifier(server: &JwksServer, timeout_ms: Option<u64>) -> Verifier {
        Verifier::build(config(Some(server.url.clone())), None, timeout_ms).unwrap()
    }

    #[test]
    fn the_remote_key_set_is_fetched_once_and_cached() {
        let a = key_pair(TEST_KEY_A);
        let server = JwksServer::start(200, key_set(vec![jwk(&a, "a")]).to_string());
        let verifier = remote_verifier(&server, None);
        for _ in 0..3 {
            verifier.verify(&mint(&a, header("a"), &claims())).unwrap();
        }
        assert_eq!(server.hits(), 1);

        // Past the cache age it is fetched again.
        let verifier =
            remote_verifier(&server, None).with_cache_timing(Duration::ZERO, Duration::ZERO);
        verifier.verify(&mint(&a, header("a"), &claims())).unwrap();
        verifier.verify(&mint(&a, header("a"), &claims())).unwrap();
        assert_eq!(server.hits(), 3);
    }

    #[test]
    fn a_rotated_key_is_picked_up_without_waiting_for_the_cache() {
        let a = key_pair(TEST_KEY_A);
        let b = key_pair(TEST_KEY_B);
        let server = JwksServer::start(200, key_set(vec![jwk(&a, "a")]).to_string());

        // Inside the cooldown, an unknown kid does not trigger a fetch.
        let cooling = remote_verifier(&server, None);
        cooling.verify(&mint(&a, header("a"), &claims())).unwrap();
        server.set(
            200,
            key_set(vec![jwk(&a, "a"), jwk(&b, "b")]).to_string(),
            Duration::ZERO,
        );
        assert_eq!(
            refusal(cooling.verify(&mint(&b, header("b"), &claims()))),
            (
                401,
                "no applicable key found in the JSON Web Key Set".to_string()
            )
        );
        assert_eq!(server.hits(), 1);

        // Past the cooldown, it refetches once and finds the new key.
        let rotated = remote_verifier(&server, None)
            .with_cache_timing(Duration::from_secs(600), Duration::ZERO);
        server.set(200, key_set(vec![jwk(&a, "a")]).to_string(), Duration::ZERO);
        rotated.verify(&mint(&a, header("a"), &claims())).unwrap();
        server.set(
            200,
            key_set(vec![jwk(&a, "a"), jwk(&b, "b")]).to_string(),
            Duration::ZERO,
        );
        rotated.verify(&mint(&b, header("b"), &claims())).unwrap();
        assert_eq!(server.hits(), 3);
        // ...and the refreshed set is kept.
        rotated.verify(&mint(&b, header("b"), &claims())).unwrap();
        assert_eq!(server.hits(), 3);
    }

    #[test]
    fn key_set_failures_are_classified_like_jose() {
        let a = key_pair(TEST_KEY_A);
        let token = mint(&a, header("a"), &claims());
        let server = JwksServer::start(500, "{}".to_string());
        let outcome = |server: &JwksServer, timeout: Option<u64>| {
            refusal(remote_verifier(server, timeout).verify(&token))
        };

        assert_eq!(
            outcome(&server, None),
            (
                401,
                "Expected 200 OK from the JSON Web Key Set HTTP response".to_string()
            )
        );
        // No redirect following: a 302 is just not a 200.
        server.set(302, String::new(), Duration::ZERO);
        assert_eq!(
            outcome(&server, None).1,
            "Expected 200 OK from the JSON Web Key Set HTTP response"
        );
        server.set(200, "<html>".to_string(), Duration::ZERO);
        assert_eq!(
            outcome(&server, None),
            (
                401,
                "Failed to parse the JSON Web Key Set HTTP response as JSON".to_string()
            )
        );
        server.set(200, r#"{"keys":"nope"}"#.to_string(), Duration::ZERO);
        assert_eq!(
            outcome(&server, None),
            (503, "JSON Web Key Set malformed".to_string())
        );
        server.set(
            200,
            key_set(vec![jwk(&a, "a")]).to_string(),
            Duration::from_millis(1500),
        );
        assert_eq!(
            outcome(&server, Some(300)),
            (503, "request timed out".to_string())
        );

        // Nobody listening at all.
        let closed = TcpListener::bind("127.0.0.1:0").unwrap();
        let addr = closed.local_addr().unwrap();
        drop(closed);
        let cfg = config(Some(format!("http://{addr}/oauth/v2/keys")));
        assert_eq!(
            refusal(
                Verifier::build(cfg, None, Some(1000))
                    .unwrap()
                    .verify(&token)
            ),
            (503, "fetch failed".to_string())
        );
    }

    #[test]
    fn the_jwks_uri_defaults_to_the_issuers_zitadel_path() {
        let verifier = Verifier::build(config(None), None, None).unwrap();
        assert_eq!(verifier.jwks_uri, format!("{ISSUER}/oauth/v2/keys"));
        assert_eq!(verifier.issuer, ISSUER);
    }

    #[test]
    fn the_shared_tls_config_loads_and_is_reused() {
        let first = tls_client_config();
        let second = tls_client_config();
        assert!(Arc::ptr_eq(&first, &second));
    }

    /// Final-wave deferred item 1b: the setup's warnings go where the
    /// program says (the relay's JSON log), not straight to stderr.
    #[test]
    fn tls_warnings_go_to_the_given_hook() {
        let got = Mutex::new(Vec::new());
        let warn = |m: &str| got.lock().unwrap().push(m.to_string());
        build_tls_config(Vec::new(), &["bad.pem: not a certificate".into()], &warn);
        let got = got.into_inner().unwrap();
        assert_eq!(got.len(), 2, "{got:?}");
        assert!(got[0].contains("bad.pem"), "{got:?}");
        assert!(got[1].contains("no CA certificates"), "{got:?}");
        // Once set, the hook is what every warning goes to.
        static HOOKED: Mutex<Vec<String>> = Mutex::new(Vec::new());
        fn hook(m: &str) {
            HOOKED.lock().unwrap().push(m.to_string());
        }
        set_tls_warning_hook(hook);
        tls_warning("x");
        assert_eq!(*HOOKED.lock().unwrap(), ["x"]);
    }
}
