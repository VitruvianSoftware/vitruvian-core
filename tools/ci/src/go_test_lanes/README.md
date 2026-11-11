# Go Test Lanes

## Overview
Component package providing implementation for `tools/ci/src/go_test_lanes`.

## Interface
- `[lib.rs:Cover]`
- `[lib.rs:Report]`
- `[lib.rs:strip_starlark_comments]`
- `[lib.rs:lanes_from_workflow]`
- `[lib.rs:parse_allowlist]`
- `[lib.rs:check]`
- `[lib.rs:ALLOWLIST]`
- `[lib.rs:run]`

## Invariants
- [tests.rs:67]: `.unwrap_or_else(|| panic!("{f} not found: {:?}", r.files))`
- [tests.rs:97]: `assert!(r.ok(), "{:?}", r);`
- [tests.rs:109]: `assert!(!r.ok());`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/go_test_lanes/...`
