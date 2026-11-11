# Sync Sources

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/sync_sources`.

## Interface
- `[lib.rs:HEADER]`
- `[lib.rs:NOW_PLAYING_ENTRY]`
- `[lib.rs:NOW_PLAYING_STAGING]`
- `[lib.rs:CORE_IMPORT]`
- `[lib.rs:Config]`
- `[lib.rs:parse_args]`
- `[lib.rs:swift_paths]`
- `[lib.rs:test_sources]`
- `[lib.rs:fan_helper_sources]`
- `[lib.rs:now_playing_sources]`
- `[lib.rs:staged_files]`
- `[lib.rs:now_playing_problems]`
- `[lib.rs:run_test_generator]`
- `[lib.rs:generated_test_sources]`
- `[lib.rs:render]`
- `[lib.rs:resolve_app_dir]`
- `[lib.rs:run_cli]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/sync_sources/...`
