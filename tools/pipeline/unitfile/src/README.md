# Src

## Overview
Component package providing implementation for `tools/pipeline/unitfile/src`.

## Interface
- `[lib.rs:DEFAULT_TIER]`
- `[lib.rs:DEFAULT_RUNNER]`
- `[lib.rs:DEFAULT_PERSONA]`
- `[lib.rs:DEFAULT_TIMEOUT_MINUTES]`
- `[lib.rs:Unit]`
- `[lib.rs:parse]`
- `[lib.rs:parse_bytes]`
- `[lib.rs:read_file]`
- `[lib.rs:discover]`
- `[scan.rs:Kind]`
- `[scan.rs:Token]`
- `[scan.rs:tokenize]`
- `[scan.rs:match_bracket]`
- `[scan.rs:Value]`
- `[scan.rs:read_value]`
- `[scan.rs:Call]`
- `[scan.rs:find_calls]`
- Subdirectory: [gocompat](./gocompat/README.md)

## Invariants
- [tests.rs:28]: `parse(build, pkg).unwrap_or_else(|e| panic!("parse: {e}"))`
- [tests.rs:102]: `assert!(units.is_empty());`
- [tests.rs:186]: `assert!(units.is_empty(), "{units:?}");`

## Side Effects
- [lib.rs:37]: `//! parser, `os/exec` errors and `encoding/json`.`

## Verification
- Run: `bazel test //tools/pipeline/unitfile/src/...`
