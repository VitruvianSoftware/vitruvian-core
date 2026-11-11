# Src

## Overview
Component package providing implementation for `tools/lint-naming/src`.

## Interface
- `[cli.rs:Args]`
- `[cli.rs:write_stderr]`
- `[cli.rs:run]`
- `[lib.rs:with_big_stack]`
- `[pystr.rs:SURROGATE_BASE]`
- `[pystr.rs:surrogate_of]`
- `[pystr.rs:surrogate_char]`
- `[pystr.rs:code_point]`
- `[pystr.rs:is_space]`
- `[pystr.rs:is_decimal]`
- `[pystr.rs:decimal_value]`
- `[pystr.rs:is_digit]`
- `[pystr.rs:is_printable]`
- `[pystr.rs:is_xid_start]`
- `[pystr.rs:is_xid_continue]`
- `[pystr.rs:strip]`
- `[pystr.rs:lstrip]`
- `[pystr.rs:strip_chars]`
- `[pystr.rs:py_len]`
- `[pystr.rs:lower]`
- Subdirectory: [pyast](./pyast/README.md)
- Subdirectory: [rules](./rules/README.md)

## Invariants
- [probe.rs:236]: `other => panic!("unknown call {}", other),`
- [pystr.rs:354]: `assert!(is_space('\x1c'));`
- [pystr.rs:355]: `assert!(is_space('\u{3000}'));`
- [pystr.rs:356]: `assert!(!is_space('\u{200b}'));`
- [scanner.rs:458]: `assert!(s.should_ignore("node_modules/pkg/bad_file.go"));`
- [scanner.rs:459]: `assert!(s.should_ignore(".git/hooks/pre-commit"));`
- [scanner.rs:460]: `assert!(s.should_ignore("a\\testdata\\x"));`

## Side Effects
- [lib.rs:39]: `.spawn(f)`
- [lib.rs:40]: `.expect("spawn")`

## Verification
- Run: `bazel test //tools/lint-naming/src/...`
