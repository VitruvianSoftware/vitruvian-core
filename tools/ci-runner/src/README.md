# Src

## Overview
Component package providing implementation for `tools/ci-runner/src`.

## Interface
- `[lib.rs:read_version_id]`
- `[lib.rs:run]`
- `[lib.rs:android_sdk_problems]`
- `[lib.rs:rustc_version_is]`

## Invariants
- [lib.rs:301]: `assert!(android_sdk_problems(dir.to_str().unwrap()).is_empty());`
- [lib.rs:307]: `assert!(rustc_version_is(`
- [lib.rs:311]: `assert!(!rustc_version_is("rustc 1.75.01 (x)", "1.75.0"));`

## Side Effects
- [lib.rs:30]: `"curl",`

## Verification
- Run: `bazel test //tools/ci-runner/src/...`
