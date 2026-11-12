# Source Lints

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/source_lints`.

## Interface
- `[lib.rs:APP_PREFIX]`
- `[lib.rs:UI_PREFIX]`
- `[lib.rs:PREFERENCES_PATH]`
- `[lib.rs:AGREEMENT_SHEET]`
- `[lib.rs:TOOLS_SECTION]`
- `[lib.rs:BROKER_PREFIX]`
- `[lib.rs:RUNTIME_PREFIX]`
- `[lib.rs:MODIFICATION_LOG_FLOOR]`
- `[lib.rs:RELEASE_SOURCES]`
- `[lib.rs:RUNNER_SOURCES]`
- `[lib.rs:SESSION_TAP_OWNERS]`
- `[lib.rs:MODIFYING_TAP_OWNERS]`
- `[lib.rs:POINTER_THREAD_TAP_OWNERS]`
- `[lib.rs:THREAD_SERVED_TAP_OWNERS]`
- `[lib.rs:UPSTREAM_SECTIONS]`
- `[lib.rs:Repository]`
- `[lib.rs:trim]`
- `[lib.rs:is_comment]`
- `[lib.rs:code_without_comments]`
- `[lib.rs:first_block]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/source_lints/...`
