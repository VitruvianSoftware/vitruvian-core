# Sync Secrets

## Overview
Component package providing implementation for `apps/desktop/vitruvian-speaker/scripts/src/sync_secrets`.

## Interface
- `[lib.rs:read_env_file]`
- `[lib.rs:read_from_env]`
- `[lib.rs:validate_keys]`
- `[lib.rs:escape_swift_string]`
- `[lib.rs:to_lower_camel_case]`
- `[lib.rs:render_swift]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:343]: `assert!(out.exists(), "output file should exist");`
- [lib.rs:345]: `assert!(content.contains("\"cid-test\""), "should contain client id");`
- [lib.rs:346]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-speaker/scripts/src/sync_secrets/...`
