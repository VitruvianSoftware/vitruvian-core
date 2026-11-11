# Require Dev Soak

## Overview
Component package providing implementation for `tools/ci/src/require_dev_soak`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:21]: `//! require-dev-soak — refuse to PROMOTE when development is currently RED`
- [lib.rs:51]: `b"require-dev-soak[",`
- [lib.rs:67]: `b"require-dev-soak[",`
- [main.rs:21]: `//! //tools/ci:require-dev-soak: the Rust port.`
- [tests.rs:24]: `//! Ported case for case from the former require-dev-soak_test.sh.`
- [tests.rs:470]: `assert!(`

## Side Effects
- [lib.rs:316]: `b"REPO/GITHUB_REPOSITORY unset \xe2\x80\x94 cannot query run history",`

## Verification
- Run: `bazel test //tools/ci/src/require_dev_soak/...`
