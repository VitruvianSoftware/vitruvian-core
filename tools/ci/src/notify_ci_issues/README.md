# Notify Ci Issues

## Overview
Component package providing implementation for `tools/ci/src/notify_ci_issues`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:500]: `assert!(s.ends_with('Z'));`
- [tests.rs:133]: `let p = std::fs::canonicalize(&rel).unwrap_or_else(|e| panic!("JQ_BIN={rel}: ...`

## Side Effects
- [lib.rs:58]: `match cmd.spawn() {`
- [lib.rs:141]: `Command::new("curl")`
- [tests.rs:24]: `//! grouping, as on the runner) and a fake `curl` that records each ntfy POST`
- [tests.rs:50]: `echo "HTTP 404: Not Found" >&2; exit 1`
- [tests.rs:57]: `[ -n "${FAKE_COMMITS_FAIL:-}" ] && { echo "HTTP 502" >&2; exit 1; }`

## Verification
- Run: `bazel test //tools/ci/src/notify_ci_issues/...`
