# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/worktree-band/hooks/src`.

## Interface
- `[lib.rs:is_session_worktree_payload]`
- `[lib.rs:strip_trailing_newlines]`
- `[lib.rs:resolve_inbox_dir]`
- `[lib.rs:handle_payload]`

## Invariants
- [lib.rs:89]: `assert!(is_session_worktree_payload(`
- [lib.rs:92]: `assert!(is_session_worktree_payload(r#"{"cwd":"/repo"}"#));`
- [lib.rs:93]: `assert!(is_session_worktree_payload(`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/worktree-band/hooks/src/...`
