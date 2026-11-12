# Src

## Overview
Component package providing implementation for `apps/mcp/vitruvian-slack-mcp/rs/src`.

## Interface
- `[auth.rs:AuthError]`
- `[auth.rs:audience_scope_for]`
- `[auth.rs:full_scope_string]`
- `[auth.rs:looks_like_jwt]`
- `[auth.rs:extract_bearer_token]`
- `[auth.rs:audience_list]`
- `[auth.rs:JoseErrorCode]`
- `[auth.rs:VerificationFailure]`
- `[auth.rs:is_idp_side_failure]`
- `[auth.rs:KeySourceFn]`
- `[auth.rs:TokenVerifierConfig]`
- `[auth.rs:VerifiedCaller]`
- `[auth.rs:TokenVerifier]`
- `[auth.rs:StandardTokenVerifier]`
- `[auth.rs:create_token_verifier]`
- `[channel_allowlist.rs:ChannelVisibility]`
- `[channel_allowlist.rs:ChannelAllowlistError]`
- `[channel_allowlist.rs:ChannelParam]`
- `[channel_allowlist.rs:read_channel_param]`
- `[channel_allowlist.rs:assert_params_allowed]`

## Invariants
- [auth.rs:217]: `// character, and that must be a refusal, not a panic.`
- [channel_allowlist.rs:379]: `assert!(parse_channel_ids(None).is_empty());`
- [channel_allowlist.rs:380]: `assert!(parse_channel_ids(Some("")).is_empty());`
- [channel_allowlist.rs:381]: `assert!(parse_channel_ids(Some("   ")).is_empty());`
- [config.rs:428]: `assert!(parse_transport_mode(Some("htp")).is_err());`
- [config.rs:429]: `assert!(parse_transport_mode(Some("sse")).is_err());`
- [config.rs:466]: `assert!(parse_write_mode(Some("impersonate"), true).is_err());`
- [dispatch.rs:448]: `assert!(missing.is_empty(), "Missing handlers: {missing:?}");`
- [dispatch.rs:451]: `assert!(orphaned.is_empty(), "Orphaned handlers: {orphaned:?}");`
- [dispatch.rs:459]: `assert!(err.to_string().contains("Unknown tool"));`

## Side Effects
- [auth.rs:21]: `//! Bearer-token checks for the HTTP transport.`
- [auth.rs:414]: `/// The last good key set. Held across a fetch, so concurrent requests`
- [auth.rs:415]: `/// share one fetch instead of each starting their own (jose's`
- [channel_allowlist.rs:108]: `"SLACK_CHANNEL_IDS must list at least one channel ID when MCP_TRANSPORT=http....`
- [channel_allowlist.rs:493]: `read_channel_param(&JsonValue::object(vec![("query", "hello".into())])),`
- [config.rs:29]: `Http,`
- [config.rs:36]: `TransportMode::Http => "http",`
- [config.rs:99]: `pub http: Option<HttpConfig>,`
- [dispatch.rs:263]: `&str_arg(args, "query")?,`
- [dispatch.rs:268]: `&str_arg(args, "query")?,`

## Verification
- Run: `bazel test //apps/mcp/vitruvian-slack-mcp:vitruvian_slack_mcp_test`
