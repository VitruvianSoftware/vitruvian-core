# Workflow Rustc

## Overview
Component package providing implementation for `tools/ci/src/workflow_rustc`.

## Interface
- Internal implementation components

## Invariants
- [tests.rs:76]: `_ => panic!("RUSTC={r}: expected a path under external/"),`
- [tests.rs:79]: `std::fs::canonicalize(&p).unwrap_or_else(|e| panic!("rustc at {}: {e}", p.dis...`
- [tests.rs:104]: `.unwrap_or_else(|e| panic!("{file}: {e} (missing from the test's data?)"));`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/workflow_rustc/...`
