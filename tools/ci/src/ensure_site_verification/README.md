# Ensure Site Verification

## Overview
Component package providing implementation for `tools/ci/src/ensure_site_verification`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:340]: `.unwrap_or_else(|e| panic!("JQ_BIN={jq}: {e}"))`
- [tests.rs:408]: `assert!(`
- [tests.rs:413]: `assert!(`

## Side Effects
- [lib.rs:166]: `/// Returns the HTTP code curl printed and curl's own exit status: where the`
- [lib.rs:167]: `/// script ran it under `set -e`, a curl that failed outright ended the run`
- [lib.rs:199]: `let mut cmd = Command::new("curl");`
- [tests.rs:24]: `//! The binary runs with its real curl against an in-process mock of the Site`
- [tests.rs:85]: `fn query(q: &str, key: &str) -> Option<String> {`
- [tests.rs:117]: `query: String,`

## Verification
- Run: `bazel test //tools/ci/src/ensure_site_verification/...`
