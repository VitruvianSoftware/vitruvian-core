# vitruvian-mcp-auth

## What it gives you

An OAuth 2.1 bearer-token verifier (`Verifier`), cached JWKS key fetcher, and RFC 9728 Protected Resource Metadata builder (`protected_resource_metadata`, `audience_scope_for`, `full_scope_string`) for Vitruvian MCP servers backed by Zitadel.

## When to use it

- Building a Rust HTTP MCP server that authenticates callers with Zitadel OAuth 2.1 / OIDC bearer tokens.
- Serving `/.well-known/oauth-protected-resource` metadata and `WWW-Authenticate` challenges for MCP clients.

## When not to use it

- Non-MCP HTTP services or apps using session cookies or web login flows; use your web framework's OIDC middleware or Zitadel web adapter instead.
- Standard CLI tools calling GitHub or local binaries without OAuth bearer verification.

## Example

From `apps/mcp/vitruvian-slack-mcp/rs/src/auth.rs:80-90`:

```rust
pub fn create_token_verifier(config: TokenVerifierConfig) -> Result<StandardTokenVerifier, String> {
    vitruvian_mcp_auth::verifier(vitruvian_mcp_auth::VerifierConfig {
        issuer: config.issuer,
        project_id: config.project_id,
        allowed_client_ids: vec![config.allowed_client_id],
        allowed_subjects: config.allowed_subjects,
        jwks_uri: config.jwks_uri,
        user_agent: "vitruvian-slack-mcp".to_string(),
    })
    .map(StandardTokenVerifier)
}
```

## Depend on it

- `//packages/rust/vitruvian-mcp-auth:vitruvian_mcp_auth` (for consumers on `@vitruvian_relay_crates`)
- `//packages/rust/vitruvian-mcp-auth:vitruvian_mcp_auth_slack_mcp_hub` (for `vitruvian-slack-mcp` on `@vitruvian_slack_mcp_crates`)

## Constraints

- A Rust consumer binary can only link one copy of `ring`, `rustls`, `serde_json`, and `ureq`, so consumers using a different Bazel crate hub must add a dedicated `rust_library` target in `BUILD` pinned to their hub (as `vitruvian_mcp_auth_slack_mcp_hub` does).
- Default package visibility is restricted to `//apps/suites/vitruvian-relay:__subpackages__` and `//apps/mcp/vitruvian-slack-mcp:__subpackages__`.
