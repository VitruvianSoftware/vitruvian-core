# Common

## Overview
Component package providing implementation for `tools/pulumi/tests/common`.

## Interface
- `[mod.rs:bin]`
- `[mod.rs:tempdir]`
- `[mod.rs:write_exec]`
- `[mod.rs:read]`
- `[mod.rs:cmd]`
- `[mod.rs:run]`
- `[mod.rs:code]`
- `[mod.rs:stdout]`
- `[mod.rs:stderr]`

## Invariants
- [mod.rs:37]: `let raw = std::env::var(var).unwrap_or_else(|_| panic!("{var} is not set"));`
- [mod.rs:44]: `assert!(p.is_file(), "{var}={raw} does not exist");`

## Side Effects
- [mod.rs:22]: `//! tool binaries as a subprocess, with stub programs (`pulumi`, `gcloud`,`
- [mod.rs:88]: `c.output().expect("spawn binary under test")`

## Verification
- Run: `bazel test //tools/pulumi/tests/common/...`
