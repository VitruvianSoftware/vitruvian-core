# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/ext-marketplace/hooks/src`.

## Interface
- `[lib.rs:strip_trailing_newlines]`
- `[lib.rs:contains_bytes]`
- `[lib.rs:resolve_inbox_dir]`
- `[lib.rs:should_record_note]`
- `[lib.rs:handle_payload]`
- `[lib.rs:run_from_stdio]`

## Invariants
- [lib.rs:122]: `assert!(!inbox.exists());`
- [lib.rs:141]: `assert!(path.extension().and_then(|e| e.to_str()) == Some("json"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/ext-marketplace/hooks/src/...`
