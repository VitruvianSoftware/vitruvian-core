# Queue Runner Watch

## Overview
Component package providing implementation for `tools/ci/src/queue_runner_watch`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:107]: `assert!(`
- [tests.rs:117]: `assert!(r.wrote("-f value=off"), "{}", r.why());`
- [tests.rs:123]: `assert!(r.out.code == 0 && r.no_write(), "{}", r.why());`

## Side Effects
- [tests.rs:235]: `/// Bazel's jq (from $JQ_BIN, an exec path the runfiles tree spells `../`).`

## Verification
- Run: `bazel test //tools/ci/src/queue_runner_watch/...`
