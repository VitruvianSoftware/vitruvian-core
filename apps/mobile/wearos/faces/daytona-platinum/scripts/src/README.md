# Src

## Overview
Component package providing implementation for `apps/mobile/wearos/faces/daytona-platinum/scripts/src`.

## Interface
- `[build_wff_apk.rs:resolve_sdk_root]`
- `[build_wff_apk.rs:version_sort_key]`
- `[build_wff_apk.rs:find_latest_build_tools]`
- `[build_wff_apk.rs:find_latest_platform_jar]`
- `[build_wff_apk.rs:resolve_pkg_dir]`
- `[build_wff_apk.rs:run]`
- `[install.rs:parse_watch_serial_from_devices]`
- `[install.rs:run]`
- `[publish.rs:strip_version_from_tag]`
- `[publish.rs:parse_version_from_manifest]`
- `[publish.rs:run]`

## Invariants
- [build_wff_apk.rs:405]: `assert!(find_latest_build_tools(tmp.to_str().unwrap()).is_none());`
- [build_wff_apk.rs:431]: `assert!(result.to_str().unwrap().contains("android-35"));`
- [build_wff_apk.rs:445]: `assert!(result.to_str().unwrap().contains("android-34"));`
- [install.rs:305]: `assert!(KNOWN_SERIALS.contains(&"58301WRBNL30SD"));`
- [install.rs:306]: `assert!(KNOWN_SERIALS.contains(&"192.168.86.33"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/mobile/wearos/faces/daytona-platinum/scripts/src/...`
