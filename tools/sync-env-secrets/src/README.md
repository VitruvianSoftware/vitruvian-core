# Src

## Overview
Component package providing implementation for `tools/sync-env-secrets/src`.

## Interface
- `[jq.rs:JqOut]`
- `[jq.rs:status]`
- `[jq.rs:id]`
- `[jq.rs:first_id_or_empty]`
- `[jq.rs:attachment_ids]`
- `[jq.rs:first_attachment_id_or_empty]`
- `[lib.rs:Exit]`
- `[lib.rs:new_item_json]`
- `[lib.rs:run]`

## Invariants
- [jq.rs:267]: `assert!(String::from_utf8(status(b"{").stderr)`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/sync-env-secrets/src/...`
