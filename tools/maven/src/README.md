# Src

## Overview
Component package providing implementation for `tools/maven/src`.

## Interface
- `[lib.rs:PLACEHOLDERS]`
- `[lib.rs:resolve_lock_path]`
- `[lib.rs:find_offenders]`
- `[lib.rs:format_offender_error]`
- `[lib.rs:check_lock_path]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:170]: `assert!(find_offenders(content).is_empty());`
- [lib.rs:196]: `assert!(out.is_empty());`
- [lib.rs:225]: `assert!(err.is_empty());`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/maven/src/...`
