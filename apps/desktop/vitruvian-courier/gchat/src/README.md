# Src

## Overview
Component package providing implementation for `apps/desktop/vitruvian-courier/gchat/src`.

## Interface
- `[auth.rs:XSRF_TTL]`
- `[auth.rs:MAX_MOLE_WORLD_BYTES]`
- `[auth.rs:extract_xsrf_token_from_mole_world_html]`
- `[auth.rs:map_reqwest_error]`
- `[auth.rs:XsrfTokenManager]`
- `[channel.rs:ChannelClock]`
- `[channel.rs:SystemChannelClock]`
- `[channel.rs:ManualChannelClock]`
- `[channel.rs:MAX_CHUNK_UTF16_UNITS]`
- `[channel.rs:PING_INTERVAL]`
- `[channel.rs:READ_INACTIVITY_TIMEOUT]`
- `[channel.rs:SERVER_EVENT_TIMEOUT]`
- `[channel.rs:RECONNECT_BACKOFF_LADDER_MS]`
- `[channel.rs:HANDSHAKE_STEP_TIMEOUT]`
- `[channel.rs:SID_MAX_AGE]`
- `[channel.rs:STABLE_SESSION_MIN]`
- `[channel.rs:session_was_stable]`
- `[channel.rs:GCHAT_EVENT_KIND_EVENT_PROTO]`
- `[channel.rs:GCHAT_EVENT_KIND_AUTH_EXPIRED]`
- `[channel.rs:GCHAT_EVENT_KIND_RESYNC]`
- Subdirectory: [fmt](./fmt/README.md)

## Invariants
- [auth.rs:320]: `assert!(matches!(`
- [auth.rs:327]: `assert!(matches!(`
- [auth.rs:333]: `assert!(matches!(`
- [cookies.rs:347]: `assert!(`
- [cookies.rs:355]: `assert!(`
- [cookies.rs:388]: `assert!(`
- [ffi.rs:354]: `let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {`
- [ffi.rs:361]: `format!("ffi panic: {s}")`
- [ffi.rs:363]: `format!("ffi panic: {s}")`
- [fuzz_tests.rs:66]: `assert!(std::str::from_utf8(round.body.as_bytes()).is_ok());`

## Side Effects
- [auth.rs:7]: `use reqwest::Client;`
- [auth.rs:90]: `pub(crate) fn map_reqwest_error(context: &str, err: reqwest::Error) -> GChatE...`
- [auth.rs:98]: `/// The `hs` query parameter the web client sends to `/u/0/mole/world` (spec ...`
- [channel.rs:10]: `use reqwest::header::{CONTENT_TYPE, COOKIE, USER_AGENT};`
- [channel.rs:11]: `use reqwest::Client;`
- [channel.rs:156]: `/// it counts as a network error. The HTTP client has no timeout of its own, ...`
- [cookies.rs:198]: `if self.allow_loopback_for_test && (url.scheme() == "https" || url.scheme() =...`
- [cookies.rs:405]: `let loopback_url = Url::parse("http://127.0.0.1:8080/u/0/mole/world").unwrap();`
- [ffi.rs:13]: `use reqwest::Client;`
- [ffi.rs:56]: `pub(crate) http: Client,`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-courier/gchat/src/...`
