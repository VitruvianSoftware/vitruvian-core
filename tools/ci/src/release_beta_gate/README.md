# Release Beta Gate

## Overview
Component package providing implementation for `tools/ci/src/release_beta_gate`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:121]: `assert!(cond, "{what}\n{}", self.show());`

## Side Effects
- [tests.rs:40]: `if [ -f "${FX}/$1.rc" ]; then echo "gh: HTTP 502" >&2; exit 1; fi`

## Verification
- Run: `bazel test //tools/ci/src/release_beta_gate/...`
