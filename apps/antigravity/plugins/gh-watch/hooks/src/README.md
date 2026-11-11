# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/gh-watch/hooks/src`.

## Interface
- `[lib.rs:strip_trailing_newlines]`
- `[lib.rs:contains_bytes]`
- `[lib.rs:should_record_note]`
- `[lib.rs:resolve_inbox_dir]`
- `[lib.rs:handle_payload]`
- `[lib.rs:run_from_stdio]`

## Invariants
- [lib.rs:118]: `assert!(!should_record_note(&make_payload("ls -la", "antigravity")));`
- [lib.rs:119]: `assert!(!should_record_note(&make_payload(`
- [lib.rs:123]: `assert!(!should_record_note(&make_payload(`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/gh-watch/hooks/src/...`
