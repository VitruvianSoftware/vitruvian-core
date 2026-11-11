# Llvm Cache Key

## Overview
Component package providing implementation for `tools/ci/src/llvm_cache_key`.

## Interface
- `[lib.rs:llvm_cache_key]`
- `[lib.rs:run]`

## Invariants
- [tests.rs:124]: `assert!(!a.is_empty(), "a missing os-release gave an empty key");`
- [tests.rs:131]: `assert!(`
- [tests.rs:142]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/llvm_cache_key/...`
