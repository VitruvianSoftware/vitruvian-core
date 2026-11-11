# Src

## Overview
Component package providing implementation for `tools/gitops/src`.

## Interface
- `[argparse.rs:Kind]`
- `[argparse.rs:Opt]`
- `[argparse.rs:Parser]`
- `[argparse.rs:Values]`
- `[argparse.rs:Exit]`
- `[argparse.rs:py_int]`
- `[argparse.rs:help_width]`
- `[argparse.rs:wrap]`
- `[json.rs:Value]`
- `[json.rs:dedup]`
- `[json.rs:JsonError]`
- `[json.rs:loads]`
- `[json.rs:dumps]`
- `[lib.rs:HS300_DEFAULT_IP]`
- `[lib.rs:HS300_DEFAULT_PORT]`
- `[lib.rs:OUTLET_ALIAS_MATCH]`
- `[lib.rs:OUTLET_DEFAULT_CHILD_ID]`
- `[lib.rs:Crash]`
- `[lib.rs:encrypt]`
- `[lib.rs:decrypt]`
- Subdirectory: [bin](./bin/README.md)
- Subdirectory: [ops](./ops/README.md)

## Invariants
- [pystr.rs:203]: `assert!(is_space('\u{1c}'));`
- [pystr.rs:204]: `assert!(!is_space('\u{200b}'));`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/gitops/src/...`
