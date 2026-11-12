# Package Release

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/package_release`.

## Interface
- `[lib.rs:APP_BUNDLE_ID]`
- `[lib.rs:FAN_HELPER_ID]`
- `[lib.rs:NOW_PLAYING_ADAPTER_ID]`
- `[lib.rs:MOUSE_TOOL_ID]`
- `[lib.rs:ENTITLEMENTS_REL]`
- `[lib.rs:USAGE]`
- `[lib.rs:BundleLayout]`
- `[lib.rs:bundle_layout]`
- `[lib.rs:ReleaseArtifacts]`
- `[lib.rs:expected_artifacts]`
- `[lib.rs:sign_bundle_commands]`
- `[lib.rs:Packaging]`
- `[lib.rs:ReleaseTools]`
- `[lib.rs:package_release]`
- `[lib.rs:run_cli]`

## Invariants
- [lib.rs:496]: `assert!(r.calls.is_empty());`

## Side Effects
- [lib.rs:204]: `.args(["-exec", "xattr", "-c", "{}", "+"]),`
- [lib.rs:304]: `.args(["-exec", "touch", "{}", "+"]),`

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/package_release/...`
