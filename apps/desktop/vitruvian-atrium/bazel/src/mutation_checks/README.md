# Mutation Checks

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/mutation_checks`.

## Interface
- `[lib.rs:stale_fixtures]`
- `[lib.rs:stale_fixtures_for]`
- `[lib.rs:check]`
- `[lib.rs:run]`
- `[lib.rs:run_mutation_suite]`
- `[lib.rs:run_cli]`
- `[mutations.rs:Mutation]`
- `[mutations.rs:MUTATIONS]`

## Invariants
- [lib.rs:264]: `assert!(`
- [lib.rs:287]: `assert!(problems[0].contains("is not there"));`
- [lib.rs:307]: `assert!(problems[0].contains("0 times"));`

## Side Effects
- [lib.rs:82]: `.spawn()`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/mutation_checks/...`
