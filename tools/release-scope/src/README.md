# Src

## Overview
Component package providing implementation for `tools/release-scope/src`.

## Interface
- `[cli.rs:Env]`
- `[cli.rs:Outcome]`
- `[cli.rs:py_int]`
- `[cli.rs:terminal_columns]`
- `[cli.rs:format_usage]`
- `[cli.rs:format_help]`
- `[cli.rs:Args]`
- `[cli.rs:traceback]`
- `[cli.rs:main]`
- `[json.rs:MAX_DEPTH]`
- `[json.rs:loads]`
- `[pystr.rs:is_space]`
- `[pystr.rs:is_word]`
- `[pystr.rs:is_printable]`
- `[pystr.rs:decimal]`
- `[pystr.rs:is_surrogate]`
- `[pystr.rs:PyStr]`
- `[pystr.rs:escape]`
- `[pystr.rs:cps]`
- `[pystr.rs:starts_with_at]`

## Invariants
- [json.rs:482]: `assert!(matches!(`

## Side Effects
- [main.rs:186]: `.spawn(move || {`

## Verification
- Run: `bazel test //tools/release-scope/src/...`
