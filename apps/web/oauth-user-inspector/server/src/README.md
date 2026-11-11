# Src

## Overview
Component package providing implementation for `apps/web/oauth-user-inspector/server/src`.

## Interface
- `[api_endpoints.rs:ExploreEndpointKind]`
- `[api_endpoints.rs:ExploreEndpointDef]`
- `[api_endpoints.rs:ExploreProvider]`
- `[api_endpoints.rs:EXPLORE_ENDPOINTS]`
- `[api_endpoints.rs:endpoints_for_provider]`
- `[api_endpoints.rs:UnknownExploreEndpointError]`
- `[api_endpoints.rs:explore_endpoint_def]`
- `[api_endpoints.rs:resolve_explore_target]`
- `[logger.rs:Logger]`
- `[logger.rs:now_epoch_ms]`
- `[logger.rs:create_logger]`
- `[logger.rs:create_request_logger]`
- `[logger.rs:log_timing]`
- `[logger.rs:log_error]`
- `[oauth_error_guide.rs:OAuthErrorGuide]`
- `[oauth_error_guide.rs:EnhancedOAuthError]`
- `[oauth_error_guide.rs:enhance_oauth_error]`
- `[oauth_error_guide.rs:is_known_oauth_error]`
- `[oauth_error_guide.rs:get_all_error_guides]`
- `[oauth_session.rs:OAuthSessionInputs]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [lib.rs:80]: `panic!("Unable to read app file '{rel}' from any candidate path: {candidates:...`
- [lib.rs:225]: `assert!(`
- [lib.rs:278]: `assert!(!frontend.is_empty());`

## Side Effects
- [api_endpoints.rs:207]: `/// `issuer_domain` — to the ABSOLUTE URL the server will fetch.`
- [lib.rs:183]: `fn fetch(`
- [lib.rs:325]: `resolve_explore_target("google", "http://169.254.169.254/latest/meta-data/", ...`
- [lib.rs:337]: `/// character) before it resolves or calls curl, whoever built the header.`
- [safe_fetch.rs:32]: `/// server-side logs only (never serialize `reason` into an HTTP response).`
- [safe_fetch.rs:112]: `// Split authority from path/query/fragment`
- [safe_fetch.rs:169]: `"http:" => 80,`
- [security_headers.rs:31]: `/// Return the canonical set of baseline HTTP security headers.`
- [server.rs:57]: `let output = std::process::Command::new("curl")`
- [server.rs:65]: `"http://metadata.google.internal/computeMetadata/v1/instance/service-accounts...`

## Verification
- Run: `bazel test //apps/web/oauth-user-inspector/server/src/...`
