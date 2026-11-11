# Relevant Paths

## Overview
Component package providing implementation for `tools/ci/src/relevant_paths`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:42]: `let text = std::fs::read_to_string(workflow).unwrap_or_else(|e| panic!("{work...`
- [tests.rs:55]: `assert!(`
- [tests.rs:119]: `assert!(got.contains(&want), "{name}: expected {want}, got:\n{got}");`

## Side Effects
- [lib.rs:105]: `.spawn()`

## Verification
- Run: `bazel test //tools/ci/src/relevant_paths/...`
