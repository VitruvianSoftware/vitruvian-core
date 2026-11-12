# Uninstall Spaces Tests

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/uninstall_spaces_tests`.

## Interface
- `[lib.rs:ProbeEnv]`
- `[lib.rs:PlistValue]`
- `[lib.rs:spaces_read_domain]`
- `[lib.rs:spaces_recovery_value]`
- `[lib.rs:spaces_dock_preference]`
- `[lib.rs:spaces_dock_pid]`
- `[lib.rs:spaces_leftover]`
- `[lib.rs:spaces_removal_state]`
- `[lib.rs:preflight_guard]`
- `[lib.rs:run_uninstall_spaces_test_suite]`
- `[lib.rs:run_cli]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/uninstall_spaces_tests/...`
