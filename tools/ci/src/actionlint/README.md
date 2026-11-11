# Actionlint

## Overview
Component package providing implementation for `tools/ci/src/actionlint`.

## Interface
- `[lib.rs:SCRIPT]`
- `[lib.rs:RUNFILES_ACTIONLINT]`
- `[lib.rs:RUNFILES_SHELLCHECK]`
- `[lib.rs:RUNFILES_PIN_CHECK]`
- `[lib.rs:help_text]`
- `[lib.rs:logical_pwd]`
- `[lib.rs:resolve_args]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:266]: `assert!(h.starts_with("actionlint.sh — the required `actionlint` check, run l...`
- [lib.rs:267]: `assert!(h.contains("\nUsage:\n"));`
- [lib.rs:268]: `assert!(`
- [tests.rs:162]: `assert!(!wf_ver.is_empty(), "no ACTIONLINT_VERSION in the workflow");`
- [tests.rs:168]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/actionlint/...`
