# Src

## Overview
Component package providing implementation for `tools/rotate-buildbuddy-key/src`.

## Interface
- `[lib.rs:Style]`
- `[lib.rs:is_yes]`
- `[lib.rs:commits_key]`
- `[lib.rs:Poll]`
- `[lib.rs:classify]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:493]: `assert!(is_yes(y.as_bytes()), "{}", y);`
- [lib.rs:496]: `assert!(!is_yes(n.as_bytes()), "{:?}", n);`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/rotate-buildbuddy-key/src/...`
