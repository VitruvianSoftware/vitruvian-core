# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/ralph-loop/hooks/src`.

## Interface
- `[json.rs:Value]`
- `[json.rs:Map]`
- `[json.rs:obj]`
- `[json.rs:Error]`
- `[json.rs:parse]`
- `[json.rs:parse_object]`
- `[lib.rs:MIN_ITERATIONS]`
- `[lib.rs:MAX_ITERATIONS_LIMIT]`
- `[lib.rs:DEFAULT_MAX_ITERATIONS]`
- `[lib.rs:check_promise_matched]`
- `[lib.rs:resolve_state_dir]`
- `[lib.rs:handle_stop_payload]`

## Invariants
- [lib.rs:362]: `assert!(check_promise_matched(`
- [lib.rs:366]: `assert!(!check_promise_matched("Still working...", "DONE"));`
- [lib.rs:367]: `assert!(!check_promise_matched("Still working on DONE...", "DONE"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/antigravity/plugins/ralph-loop/hooks/src/...`
