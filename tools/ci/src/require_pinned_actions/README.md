# Require Pinned Actions

## Overview
Component package providing implementation for `tools/ci/src/require_pinned_actions`.

## Interface
- `[main.rs:unpinned]`

## Invariants
- [main.rs:38]: `//! Ported from require-pinned-actions.sh, which was`
- [tests.rs:25]: `//! require-pinned-actions.sh (the outputs were compared byte for byte).`
- [tests.rs:174]: `std::fs::canonicalize(&r).unwrap_or_else(|e| panic!("RUSTC={r}: {e}"))`
- [tests.rs:193]: `"rustc --edition 2021 -O tools/ci/src/require_pinned_actions/main.rs -o \"$RU...`

## Side Effects
- [tests.rs:22]: `//! a subprocess in throwaway repo trees, and built the way actionlint.yaml`

## Verification
- Run: `bazel test //tools/ci/src/require_pinned_actions/...`
