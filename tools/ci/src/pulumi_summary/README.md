# Pulumi Summary

## Overview
Component package providing implementation for `tools/ci/src/pulumi_summary`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:35]: `std::fs::canonicalize(&p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))`
- [tests.rs:64]: `.unwrap_or_else(|| panic!("no line with {needle:?}\n{out}"))`
- [tests.rs:129]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/pulumi_summary/...`
