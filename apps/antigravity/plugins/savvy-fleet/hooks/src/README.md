# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/savvy-fleet/hooks/src`.

## Interface
- `[lib.rs:is_subagent_payload]`
- `[lib.rs:strip_trailing_newlines]`
- `[lib.rs:resolve_inbox_dir]`
- `[lib.rs:handle_payload]`

## Invariants
- [lib.rs:90]: `assert!(is_subagent_payload(`
- [lib.rs:93]: `assert!(is_subagent_payload(`
- [lib.rs:100]: `assert!(!is_subagent_payload(""));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/savvy-fleet/hooks/src/...`
