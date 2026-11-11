# Foundation App Digest Guard

## Overview
Component package providing implementation for `tools/ci/src/foundation_app_digest_guard`.

## Interface
- `[lib.rs:Pair]`
- `[lib.rs:digest_pairs]`
- `[lib.rs:invalid_pairs]`
- `[lib.rs:missing_digest_apps]`
- `[lib.rs:run]`

## Invariants
- [tests.rs:128]: `assert!(`
- [tests.rs:133]: `assert!(`
- [tests.rs:357]: `assert!(!o.stdout.contains("digest guard: OK"), "{o:?}");`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/foundation_app_digest_guard/...`
