# Src

## Overview
Component package providing implementation for `apps/suites/relay/spike/src`.

## Interface
- `[lib.rs:PROTOCOL_VERSIONS]`
- `[lib.rs:SERVER_NAME]`
- `[lib.rs:MAX_BODY_BYTES]`
- `[lib.rs:PING_INTERVAL_SECS]`
- `[lib.rs:MAX_MISSED_PONGS]`
- `[lib.rs:Settings]`
- `[lib.rs:protected_resource_metadata]`
- `[lib.rs:www_authenticate]`
- `[lib.rs:Caller]`
- `[lib.rs:handle_rpc]`
- `[lib.rs:accepts_json]`
- `[lib.rs:unverified_client_id]`

## Invariants
- [lib.rs:375]: `assert!(r.is_err(), "missing {drop} must be refused");`
- [lib.rs:381]: `assert!(r.is_err(), "separators-only subject list must be refused");`
- [lib.rs:386]: `assert!(r.is_err(), "plain http public URL must be refused");`

## Side Effects
- [lib.rs:22]: `//! tested without a network. `main.rs` wires them to HTTP and WebSockets.`
- [lib.rs:91]: `if !public_url.starts_with("https://") && !public_url.starts_with("http://loc...`
- [lib.rs:93]: `"PUBLIC_URL={public_url:?} must be https (or http://localhost for local runs)"`
- [main.rs:21]: `//! HTTP and WebSocket wiring for the relay spike. Logic lives in lib.rs.`
- [main.rs:26]: `//!   POST /mcp                                       MCP over Streamable HTT...`
- [main.rs:35]: `use http::{header, Method, Request, Response, StatusCode};`

## Verification
- Run: `bazel test //apps/suites/relay/spike/src/...`
