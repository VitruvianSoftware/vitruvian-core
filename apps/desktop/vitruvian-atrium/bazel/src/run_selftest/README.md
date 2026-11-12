# Run Selftest

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/run_selftest`.

## Interface
- `[lib.rs:select_bundle_candidate]`
- `[lib.rs:find_first_app_in_dir]`
- `[lib.rs:is_executable]`
- `[lib.rs:run_cli_with_tools]`
- `[lib.rs:run_cli]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/run_selftest/...`
