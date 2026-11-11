# Src

## Overview
Component package providing implementation for `packages/vitruvian-sdk/samples/src`.

## Interface
- `[lib.rs:OUTPUT_REL]`
- `[lib.rs:VERSION_MARK]`
- `[lib.rs:FILES]`
- `[lib.rs:SWIFT_LICENSE_HEADER]`
- `[lib.rs:header_from_python_script]`
- `[lib.rs:header]`
- `[lib.rs:replace_ts_toolkit_pin]`
- `[lib.rs:replace_py_toolkit_pin]`
- `[lib.rs:apply_pins]`
- `[lib.rs:swift_from_dir]`
- `[lib.rs:resolve_dirs]`
- `[lib.rs:run_with_dirs]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:420]: `assert!(out.starts_with("wrote "));`

## Side Effects
- None

## Verification
- Run: `bazel test //packages/vitruvian-sdk/samples/src/...`
