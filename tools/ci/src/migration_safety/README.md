# Migration Safety

## Overview
Component package providing implementation for `tools/ci/src/migration_safety`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:272]: `assert!(is_contract_migration(`
- [lib.rs:279]: `assert!(!is_contract_migration(`
- [lib.rs:286]: `assert!(!is_contract_migration(`

## Side Effects
- [lib.rs:21]: `//! //tools/ci:migration_safety — Squawk migration-safety gate for Tabula's P...`
- [lib.rs:28]: `const MIG_DIR: &str = "apps/suites/tabula/api/prisma/migrations";`
- [lib.rs:103]: `return fail(b"self-test FAILED -- a backward-COMPATIBLE fixture (ADD nullable...`

## Verification
- Run: `bazel test //tools/ci/src/migration_safety/...`
