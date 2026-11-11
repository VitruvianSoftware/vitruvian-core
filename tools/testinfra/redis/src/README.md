# Src

## Overview
Component package providing implementation for `tools/testinfra/redis/src`.

## Interface
- `[lib.rs:printf_number]`
- `[lib.rs:hex4]`
- `[lib.rs:proc_listeners]`
- `[lib.rs:lsof_listeners]`
- `[lib.rs:mismatch_report]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/testinfra/redis/src/...`
