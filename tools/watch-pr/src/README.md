# Src

## Overview
Component package providing implementation for `tools/watch-pr/src`.

## Interface
- `[arith.rs:ArithError]`
- `[arith.rs:UNBOUND_STATUS]`
- `[arith.rs:Vars]`
- `[arith.rs:variable]`
- `[checks.rs:Parsed]`
- `[checks.rs:parse_checks_json]`
- `[cli.rs:USAGE]`
- `[cli.rs:run]`
- `[post_merge.rs:POST_MERGE_GRACE]`
- `[post_merge.rs:Decision]`
- `[post_merge.rs:EXIT_GREEN]`
- `[post_merge.rs:EXIT_FAILED]`
- `[post_merge.rs:EXIT_TIMEOUT]`
- `[post_merge.rs:decide]`
- `[post_merge.rs:Report]`
- `[post_merge.rs:read_report]`
- `[queue.rs:QUERY]`
- `[queue.rs:Verdict]`
- `[queue.rs:Status]`
- `[queue.rs:parse]`
- `[sh.rs:Captured]`

## Invariants
- [checks.rs:192]: `assert!(bad.stdout.starts_with("PARSE_ERROR: "));`
- [pyjson_test.rs:82]: `assert!(!loads(falsy).unwrap().truthy(), "{falsy}");`
- [pyjson_test.rs:85]: `assert!(loads(truthy).unwrap().truthy(), "{truthy}");`

## Side Effects
- [cli.rs:200]: `sh::run_quiet("git", &["fetch", "origin", "main", "-q"]);`
- [sh.rs:165]: `.spawn();`

## Verification
- Run: `bazel test //tools/watch-pr/src/...`
