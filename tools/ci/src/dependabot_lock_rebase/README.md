# Dependabot Lock Rebase

## Overview
Component package providing implementation for `tools/ci/src/dependabot_lock_rebase`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:216]: `assert!(main_is_ancestor_of(&m.f.bare, "pr1-branch"));`
- [tests.rs:217]: `assert!(`
- [tests.rs:227]: `assert!(main_is_ancestor_of(&m.f.bare, "pr2-branch"));`

## Side Effects
- [lib.rs:119]: `.arg("fetch")`
- [lib.rs:129]: `b": cannot fetch ",`
- [tests.rs:393]: `.contains("::warning::#9: cannot fetch no-such-branch; skipping."),`

## Verification
- Run: `bazel test //tools/ci/src/dependabot_lock_rebase/...`
