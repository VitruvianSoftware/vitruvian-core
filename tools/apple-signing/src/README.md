# Src

## Overview
Component package providing implementation for `tools/apple-signing/src`.

## Interface
- `[lib.rs:Exit]`
- `[lib.rs:PyJson]`
- `[lib.rs:py_load]`
- `[lib.rs:py_dumps_str]`
- `[lib.rs:Field]`
- `[lib.rs:note_doc]`
- `[lib.rs:has_item]`
- `[lib.rs:random_password]`
- `[lib.rs:count_secrets]`
- `[lib.rs:read_env_file]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:24]: `//! xcrun, security, curl and mv, the same output, files and exit codes.`
- [lib.rs:273]: `let mut child = match c.spawn() {`

## Verification
- Run: `bazel test //tools/apple-signing/src/...`
