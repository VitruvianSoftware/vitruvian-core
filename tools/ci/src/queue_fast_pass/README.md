# Queue Fast Pass

## Overview
Component package providing implementation for `tools/ci/src/queue_fast_pass`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:58]: `let jq = std::fs::canonicalize(&jq).unwrap_or_else(|e| panic!("jq at {jq}: {e...`
- [tests.rs:201]: `assert!(`
- [tests.rs:214]: `assert!(said(&o, &format!("tree={}", g.tree())), "{o:?}");`

## Side Effects
- [lib.rs:183]: `match cmd.spawn() {`
- [lib.rs:210]: `match cmd.spawn() {`
- [lib.rs:233]: `match cmd.spawn() {`
- [tests.rs:434]: `// The reply is filed under the OLD tree's marker query.`

## Verification
- Run: `bazel test //tools/ci/src/queue_fast_pass/...`
