# Fast Lane Report

## Overview
Component package providing implementation for `tools/ci/src/fast_lane_report`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:366]: `assert!(`
- [lib.rs:375]: `Err(e) => panic!("unexpected error: {}", e),`
- [lib.rs:395]: `assert!(`

## Side Effects
- [lib.rs:257]: `.spawn()`
- [lib.rs:358]: `.spawn();`
- [lib.rs:387]: `.spawn();`

## Verification
- Run: `bazel test //tools/ci/src/fast_lane_report/...`
