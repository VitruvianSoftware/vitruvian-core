# Src

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/tools/src`.

## Interface
- `[boot_smoke.rs:rlocation]`
- `[boot_smoke.rs:find_adb_path]`
- `[boot_smoke.rs:parse_device_list]`
- `[boot_smoke.rs:pick_device]`
- `[boot_smoke.rs:logcat_contains_displayed]`
- `[boot_smoke.rs:crash_buffer_has_pkg]`
- `[boot_smoke.rs:run]`
- `[publish.rs:strip_version_prefix]`
- `[publish.rs:version_from_manifest]`
- `[publish.rs:version_from_build_file]`
- `[publish.rs:resolve_version]`
- `[publish.rs:run]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/tools/src/...`
