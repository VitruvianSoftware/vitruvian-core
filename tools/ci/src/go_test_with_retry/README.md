# Go Test With Retry

## Overview
Component package providing implementation for `tools/ci/src/go_test_with_retry`.

## Interface
- `[lib.rs:iac_roots_in]`
- `[lib.rs:run]`

## Invariants
- [tests.rs:137]: `assert!(o.stdout.contains("::group::go test apps/x/y/infra\n"));`
- [tests.rs:138]: `assert!(`
- [tests.rs:163]: `assert!(!o.stderr.contains("::warning::"));`

## Side Effects
- [lib.rs:141]: `.spawn()`

## Verification
- Run: `bazel test //tools/ci/src/go_test_with_retry/...`
