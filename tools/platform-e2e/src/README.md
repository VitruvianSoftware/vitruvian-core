# Src

## Overview
Component package providing implementation for `tools/platform-e2e/src`.

## Interface
- `[lib.rs:TIERS]`
- `[lib.rs:TierResult]`
- `[lib.rs:dirname]`
- `[lib.rs:basename]`
- `[lib.rs:resolve_workspace_root]`
- `[lib.rs:count]`
- `[lib.rs:echo_bytes]`
- `[lib.rs:text_report]`
- `[lib.rs:tap_report]`
- `[lib.rs:json_report]`
- `[lib.rs:run]`
- `[lib.rs:is_file]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/platform-e2e/src/...`
