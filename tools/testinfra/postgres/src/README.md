# Src

## Overview
Component package providing implementation for `tools/testinfra/postgres/src`.

## Interface
- `[lib.rs:strerror]`
- `[lib.rs:status_code]`
- `[lib.rs:start_failure]`
- `[lib.rs:exec_failure]`
- `[lib.rs:postgres_args]`
- `[lib.rs:initdb_args]`
- `[lib.rs:isready_args]`
- `[lib.rs:run_postgres]`
- `[lib.rs:check_postgres]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- None

## Side Effects
- [lib.rs:86]: `/// bash's report, and exit status, for an `exec` that failed.`
- [lib.rs:94]: `format!("{argv0}: line {line}: exec: {program}: not found"),`
- [lib.rs:103]: `"{argv0}: line {line}: exec: {program}: cannot execute: {}",`

## Verification
- Run: `bazel test //tools/testinfra/postgres/src/...`
