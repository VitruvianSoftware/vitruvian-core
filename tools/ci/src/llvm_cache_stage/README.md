# Llvm Cache Stage

## Overview
Component package providing implementation for `tools/ci/src/llvm_cache_stage`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:84]: `assert!(!l.stage.exists(), "a stage folder exists after a miss");`
- [tests.rs:97]: `assert!(staged.is_file(), "the stage is missing bin/clang");`
- [tests.rs:98]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/llvm_cache_stage/...`
