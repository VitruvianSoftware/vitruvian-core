# Src

## Overview
Component package providing implementation for `apps/antigravity/plugins/gh-watch/sidecars/panel/src`.

## Interface
- `[lib.rs:DEFAULT_HOLD_MS]`
- `[lib.rs:FLAKE_WINDOW_MS]`
- `[lib.rs:FLAKE_THRESHOLD]`
- `[lib.rs:LANDING_TIMEOUT_MS]`
- `[lib.rs:LANDING_SETTLE_MS]`
- `[lib.rs:LANDING_QUIET_MS]`
- `[lib.rs:CONFLICT_REMINDER_MS]`
- `[lib.rs:MAX_CONFLICT_REMINDERS]`
- `[lib.rs:MAX_FEEDBACK_ITEMS]`
- `[lib.rs:MAX_FEEDBACK_CHARS]`
- `[lib.rs:REVIEW_LIMIT]`
- `[lib.rs:MAX_HIDDEN_REPOS]`
- `[lib.rs:PRESENCE_TTL_MS]`
- `[lib.rs:RETURN_FLOOR_MS]`
- `[lib.rs:NOTE_TTL_MS]`
- `[lib.rs:bucket_of]`
- `[lib.rs:normalise_checks]`
- `[lib.rs:count_checks]`
- `[lib.rs:empty_state]`
- `[lib.rs:decide]`

## Invariants
- None

## Side Effects
- [openui.rs:413]: `if name == "Query" {`

## Verification
- Run: `bazel test //apps/antigravity/plugins/gh-watch/sidecars/panel/src/...`
