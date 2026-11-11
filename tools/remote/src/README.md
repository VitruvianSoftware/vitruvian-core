# Src

## Overview
Component package providing implementation for `tools/remote/src`.

## Interface
- Internal implementation components

## Invariants
- [tests.rs:29]: `let p = std::env::var(var).unwrap_or_else(|_| panic!("{var} not set"));`
- [tests.rs:30]: `fs::canonicalize(&p).unwrap_or_else(|e| panic!("{var}={p}: {e}"))`
- [tests.rs:97]: `fs::read_to_string(&p).unwrap_or_else(|e| panic!("{}: {e}", p.display()))`

## Side Effects
- [tests.rs:85]: `let mut child = c.spawn().expect("spawn");`

## Verification
- Run: `bazel test //tools/remote/src/...`
