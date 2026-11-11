# Src

## Overview
Component package providing implementation for `tools/shell-compat/src`.

## Interface
- `[lib.rs:env]`
- `[lib.rs:env_or_empty]`
- `[lib.rs:env_or]`
- `[lib.rs:env_set_nonempty]`
- `[lib.rs:os]`
- `[lib.rs:path]`
- `[lib.rs:path_bytes]`
- `[lib.rs:out]`
- `[lib.rs:err]`
- `[lib.rs:enter_bazel_run_cwd]`
- `[lib.rs:cat]`
- `[lib.rs:which]`
- `[lib.rs:subst]`
- `[lib.rs:strip_cr_lf]`
- `[lib.rs:Ran]`
- `[lib.rs:status_code]`
- `[lib.rs:spawn_failure_status]`
- `[lib.rs:spawn_diag]`
- `[lib.rs:capture]`
- `[lib.rs:capture_stdout]`

## Invariants
- None

## Side Effects
- [lib.rs:272]: `match cmd.spawn() {`
- [lib.rs:316]: `let mut child = match cmd.spawn() {`

## Verification
- Run: `bazel test //tools/shell-compat/src/...`
