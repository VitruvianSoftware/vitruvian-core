# Bundle Info Plist

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/bundle_info_plist`.

## Interface
- `[lib.rs:Config]`
- `[lib.rs:parse_args]`
- `[lib.rs:extract_numeric_version_prefix]`
- `[lib.rs:transform_upstream_info_plist]`
- `[lib.rs:load_version_env]`
- `[lib.rs:parse_version_env]`
- `[lib.rs:render_info_plist]`
- `[lib.rs:strip_key_from_plist]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:260]: `assert!(out.contains("<key>CFBundleShortVersionString</key>\n\t<string>3.4.1<...`
- [lib.rs:261]: `assert!(`
- [lib.rs:298]: `assert!(out.contains("<string>3.85.0</string>"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/bundle_info_plist/...`
