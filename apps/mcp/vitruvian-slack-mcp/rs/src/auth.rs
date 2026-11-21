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

//! Bearer-token checks for the HTTP transport.
//!
//! The checking itself lives in the shared `vitruvian-mcp-auth` crate
//! (packages/mcp-auth in the monorepo, `mcp-auth/` in the
//! standalone repo), which the Vitruvian Relay uses too: one verifier, so a
//! fix to token checking reaches every server at once. It checks an RS256
//! access token from the Zitadel issuer the way the TypeScript server did
//! with jose 6.2.13, with the same error codes and statuses.
//!
//! This module keeps the names the transport and the relay spike were
//! written against, and pins this server to its one OIDC client.

pub use vitruvian_mcp_auth::{audience_scope_for, full_scope_string, AuthError};

/// Who a verified token belongs to.
pub type VerifiedCaller = vitruvian_mcp_auth::Caller;

/// What this server says about itself to check tokens.
#[derive(Debug, Clone)]
pub struct TokenVerifierConfig {
    /// The Zitadel issuer; a trailing slash is trimmed.
    pub issuer: String,
    /// The Zitadel project id the token's audience must include.
    pub project_id: String,
    /// The people allowed in (`sub` claim).
    pub allowed_subjects: Vec<String>,
    /// The one OIDC client whose access tokens are accepted.
    pub allowed_client_id: String,
    /// Where to fetch the key set; defaults to `{issuer}/oauth/v2/keys`.
    pub jwks_uri: Option<String>,
}

/// The transport's view of a verifier, so its tests can stand in their own.
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

/// The credential from an `Authorization: Bearer <token>` header, or
/// [`AuthError::MissingToken`] when there is no usable one.
pub fn extract_bearer_token(header: Option<&str>) -> Result<String, AuthError> {
    vitruvian_mcp_auth::extract_bearer(header)
        .map(str::to_string)
        .ok_or(AuthError::MissingToken)
}

/// The shared verifier, pinned to one client.
pub struct StandardTokenVerifier(vitruvian_mcp_auth::Verifier);

/// Build a verifier. Refuses an empty subject list or client id: either would
/// let in everyone Zitadel is willing to issue a token to.
pub fn create_token_verifier(config: TokenVerifierConfig) -> Result<StandardTokenVerifier, String> {
    vitruvian_mcp_auth::verifier(vitruvian_mcp_auth::VerifierConfig {
        issuer: config.issuer,
        project_id: config.project_id,
        allowed_client_ids: vec![config.allowed_client_id],
        allowed_subjects: config.allowed_subjects,
        required_role: None,
        jwks_uri: config.jwks_uri,
        user_agent: "vitruvian-slack-mcp".to_string(),
    })
    .map(StandardTokenVerifier)
}

impl StandardTokenVerifier {
    /// Check a bearer token. Blocking: it may fetch the issuer's key set.
    pub fn verify_token(&self, token: &str) -> Result<VerifiedCaller, AuthError> {
        self.0.verify(token)
    }

    pub fn verify_header(&self, header: Option<&str>) -> Result<VerifiedCaller, AuthError> {
        self.verify_token(&extract_bearer_token(header)?)
    }
}

impl TokenVerifier for StandardTokenVerifier {
    fn verify(&self, token: &str) -> Result<VerifiedCaller, Result<AuthError, String>> {
        self.verify_token(token).map_err(Ok)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn config(client_id: &str, subjects: &[&str]) -> TokenVerifierConfig {
        TokenVerifierConfig {
            issuer: "https://auth.example.test/".to_string(),
            project_id: "123456789".to_string(),
            allowed_subjects: subjects.iter().map(|s| s.to_string()).collect(),
            allowed_client_id: client_id.to_string(),
            // Never fetched: these tests do not get past the token's shape.
            jwks_uri: Some("https://127.0.0.1:9/keys".to_string()),
        }
    }

    #[test]
    fn construction_refuses_an_open_door() {
        assert!(create_token_verifier(config("", &["user-42"])).is_err());
        assert!(create_token_verifier(config("111222333", &[])).is_err());
        assert!(create_token_verifier(config("111222333", &["user-42"])).is_ok());
    }

    #[test]
    fn a_missing_or_malformed_header_is_a_missing_token() {
        for header in [
            None,
            Some(""),
            Some("Basic abc"),
            Some("Bearer"),
            Some("Bearer   "),
        ] {
            assert_eq!(
                extract_bearer_token(header),
                Err(AuthError::MissingToken),
                "{header:?}"
            );
        }
        assert_eq!(
            extract_bearer_token(Some("bearer  a.b.c ")).as_deref(),
            Ok("a.b.c")
        );
    }

    #[test]
    fn an_opaque_token_is_refused_before_any_fetch() {
        let v = create_token_verifier(config("111222333", &["user-42"])).unwrap();
        assert_eq!(
            v.verify_header(Some("Bearer not-a-jwt")),
            Err(AuthError::OpaqueToken)
        );
        assert_eq!(v.verify_header(None), Err(AuthError::MissingToken));
        assert_eq!(
            TokenVerifier::verify_authorization_header(&v, Some("Bearer opaque")),
            Err(Ok(AuthError::OpaqueToken))
        );
    }
}
