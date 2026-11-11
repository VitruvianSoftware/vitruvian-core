# Publish Tool

## Overview
Component package providing implementation for `apps/desktop/vitruvian-tool-tv/scripts/src/publish_tool`.

## Interface
- `[lib.rs:Config]`
- `[lib.rs:derive_version]`
- `[lib.rs:parse_args]`
- `[lib.rs:read_manifest_version]`
- `[lib.rs:resolve_version]`
- `[lib.rs:check_manifest_version]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:394]: `assert!(err.contains("unknown argument --foo"));`
- [lib.rs:416]: `assert!(read_manifest_version(&dir).is_err());`
- [lib.rs:430]: `assert!(read_manifest_version(&dir).is_err());`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-tool-tv/scripts/src/publish_tool/...`
