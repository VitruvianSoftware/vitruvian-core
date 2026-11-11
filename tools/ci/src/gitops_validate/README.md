# Gitops Validate

## Overview
Component package providing implementation for `tools/ci/src/gitops_validate`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:473]: `assert!(!result);`

## Side Effects
- [lib.rs:226]: `.spawn(|| {`

## Verification
- Run: `bazel test //tools/ci/src/gitops_validate/...`
