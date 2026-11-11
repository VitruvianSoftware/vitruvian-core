# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/receipts-report/hooks/src`.

## Interface
- `[lib.rs:strip_trailing_newlines]`
- `[lib.rs:contains_bytes]`
- `[lib.rs:resolve_inbox_dir]`
- `[lib.rs:should_record_note]`
- `[lib.rs:handle_payload]`
- `[lib.rs:run_from_stdio]`

## Invariants
- [lib.rs:123]: `assert!(!inbox.exists());`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/receipts-report/hooks/src/...`
