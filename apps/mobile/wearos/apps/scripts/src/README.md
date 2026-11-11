# Src

## Overview
Component package providing implementation for `apps/mobile/wearos/apps/scripts/src`.

## Interface
- `[install_all.rs:detect_android_home]`
- `[install_all.rs:build_adb_args]`
- `[install_all.rs:run]`
- `[publish.rs:strip_version_prefix]`
- `[publish.rs:resolve_version_from_manifest]`
- `[publish.rs:parse_manifest_version]`
- `[publish.rs:apk_filename]`
- `[publish.rs:sha256_command]`
- `[publish.rs:run]`

## Invariants
- [install_all.rs:188]: `assert!(build_adb_args("").is_empty());`
- [install_all.rs:220]: `assert!(!v.is_empty());`
- [publish.rs:405]: `assert!(cmd == "sha256sum" || cmd == "shasum");`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/mobile/wearos/apps/scripts/src/...`
