# Build App

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/build_app`.

## Interface
- `[lib.rs:RELEASE_APP_NAME]`
- `[lib.rs:DEV_APP_NAME]`
- `[lib.rs:RELEASE_EXECUTABLE]`
- `[lib.rs:DEV_EXECUTABLE]`
- `[lib.rs:RELEASE_BUNDLE_ID]`
- `[lib.rs:DEV_BUNDLE_ID]`
- `[lib.rs:NOW_PLAYING_ADAPTER]`
- `[lib.rs:TARGET_TRIPLE]`
- `[lib.rs:ENTITLEMENTS_REL]`
- `[lib.rs:LEGACY_IDENTITY]`
- `[lib.rs:PINNED_SDK_PATH]`
- `[lib.rs:FAN_HELPER_SOURCES]`
- `[lib.rs:NOW_PLAYING_SOURCES]`
- `[lib.rs:BuildFlags]`
- `[lib.rs:BuildVariantSpec]`
- `[lib.rs:SigningMode]`
- `[lib.rs:parse_cli_args]`
- `[lib.rs:resolve_variant]`
- `[lib.rs:render_swift_output_file_map]`
- `[lib.rs:resolve_sdk_flags]`

## Invariants
- [lib.rs:340]: `assert!(flags.dev);`
- [lib.rs:341]: `assert!(flags.install);`
- [lib.rs:342]: `assert!(flags.dry_run);`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/build_app/...`
