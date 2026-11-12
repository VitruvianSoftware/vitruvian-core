# Publish

## Overview
Component package providing implementation for `apps/embedded/vitruvian-deck/host_tools/src/publish`.

## Interface
- `[lib.rs:TAG_PREFIX]`
- `[lib.rs:BETA_TAG]`
- `[lib.rs:PKG]`
- `[lib.rs:FLASH_SOURCES]`
- `[lib.rs:FLASH_README]`
- `[lib.rs:Runner]`
- `[lib.rs:RealRunner]`
- `[lib.rs:PublishConfig]`
- `[lib.rs:resolve_root]`
- `[lib.rs:resolve_config]`
- `[lib.rs:read_manifest_version]`
- `[lib.rs:build_info_json]`
- `[lib.rs:beta_notes]`
- `[lib.rs:publish]`

## Invariants
- [lib.rs:161]: `// replace what was released. Require the tag; never guess it.`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/embedded/vitruvian-deck/host_tools/src/publish/...`
