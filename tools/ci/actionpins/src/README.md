# Src

## Overview
Component package providing implementation for `tools/ci/actionpins/src`.

## Interface
- `[cli.rs:USAGE]`
- `[cli.rs:run]`
- `[goprint.rs:PRINTABLE]`
- `[goprint.rs:SPACE]`
- `[gostd.rs:decode_rune]`
- `[gostd.rs:decode_last_rune]`
- `[gostd.rs:is_print]`
- `[gostd.rs:is_space]`
- `[gostd.rs:quote]`
- `[gostd.rs:trim_space]`
- `[gostd.rs:MAX_SCAN_TOKEN]`
- `[gostd.rs:scan_lines]`
- `[gostd.rs:ERR_TOO_LONG]`
- `[gostd.rs:errno_text]`
- `[gostd.rs:path_error]`
- `[gostd.rs:clean]`
- `[gostd.rs:join]`
- `[gostd.rs:dir]`
- `[gostd.rs:base]`
- `[gostd.rs:as_path]`

## Invariants
- [gostd.rs:423]: `assert!(!scan_lines(&ok).1);`
- [gostd.rs:425]: `assert!(scan_lines(&long).1);`
- [lib.rs:411]: `assert!(pins.lookup(b"unknown/action").is_err());`
- [lib.rs:414]: `assert!(String::from_utf8(load(p).unwrap_err())`
- [lib.rs:418]: `assert!(String::from_utf8(load(p).unwrap_err())`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/actionpins/src/...`
