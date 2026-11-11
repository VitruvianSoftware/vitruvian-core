# Src

## Overview
Component package providing implementation for `tools/agent-app/src`.

## Interface
- `[argparse.rs:Kind]`
- `[argparse.rs:Opt]`
- `[argparse.rs:Parser]`
- `[argparse.rs:Values]`
- `[argparse.rs:Exit]`
- `[argparse.rs:help_width]`
- `[argparse.rs:wrap]`
- `[drift.rs:ORG]`
- `[drift.rs:LEVELS]`
- `[drift.rs:OK]`
- `[drift.rs:PENDING]`
- `[drift.rs:DRIFT]`
- `[drift.rs:MISSING]`
- `[drift.rs:UNLISTED]`
- `[drift.rs:UNREAD]`
- `[drift.rs:Agent]`
- `[drift.rs:Perms]`
- `[drift.rs:Declared]`
- `[drift.rs:LoadFail]`
- `[drift.rs:load_agents]`
- Subdirectory: [agent_app](./agent_app/README.md)
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [github.rs:253]: `assert!(decode_json(b"<html>").is_err());`
- [github.rs:254]: `assert!(decode_json(b"").is_err());`
- [json.rs:464]: `assert!(matches!(v.get("b"), Some(Value::Float(f)) if f.is_infinite()));`
- [json.rs:465]: `assert!(loads("[1,]").is_err());`
- [json.rs:466]: `assert!(loads("{} x").is_err());`
- [pyerr.rs:110]: `assert!(`
- [pyerr.rs:115]: `assert!(decode_utf8(b"\xe2\x82")`
- [pystr.rs:233]: `assert!(is_space('\u{1c}'));`
- [pystr.rs:234]: `assert!(!is_space('\u{200b}'));`

## Side Effects
- [github.rs:24]: `use crate::http;`
- [github.rs:74]: `let response = match http::get(&url, &headers, 30) {`
- [github.rs:76]: `Err(http::Error::Http { code, body }) => {`
- [http.rs:22]: `//! the way it fails. `http://` (GITHUB_API_URL pointing at a test server or`
- [http.rs:24]: `//! curl, since the standard library has no TLS. Redirects are followed by`
- [http.rs:57]: `Http { code: u16, body: Vec<u8> },`
- [lib.rs:34]: `pub mod http;`
- [lib.rs:119]: `.spawn()`
- [lib.rs:123]: `let out_reader = std::thread::spawn(move || {`

## Verification
- Run: `bazel test //tools/agent-app/src/...`
