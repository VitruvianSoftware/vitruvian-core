# Publish Tool

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/macmenu/scripts/src/publish_tool`.

## Interface
- `[lib.rs:PKG]`
- `[lib.rs:DEFAULT_REPO]`
- `[lib.rs:PROGRAMS]`
- `[lib.rs:ARCHS]`
- `[lib.rs:parse_args]`
- `[lib.rs:resolve_version]`
- `[lib.rs:extract_manifest_version]`
- `[lib.rs:is_valid_min_macos]`
- `[lib.rs:extract_plist_string_key]`
- `[lib.rs:build_bazel_flags]`
- `[lib.rs:select_cquery_output]`
- `[lib.rs:asset_name]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:436]: `assert!(!parse_args(&["publish-tool".into()]).unwrap());`
- [lib.rs:437]: `assert!(parse_args(&["publish-tool".into(), "--dry-run".into()]).unwrap());`
- [lib.rs:461]: `assert!(is_valid_min_macos("14.0"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/macmenu/scripts/src/publish_tool/...`
