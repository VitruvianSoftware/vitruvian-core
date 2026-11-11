# Src

## Overview
Component package providing implementation for `tools/saas-cli/src`.

## Interface
- `[lib.rs:Exit]`
- `[lib.rs:indent_chunk]`
- `[lib.rs:exec_failure]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:131]: `/// `exec "$NPX_BIN" ...` (script line `line`): become the CLI. Returns`
- [lib.rs:133]: `fn exec(&self, line: u32, mut c: Command) -> Exit {`
- [lib.rs:135]: `let e = c.exec();`

## Verification
- Run: `bazel test //tools/saas-cli/src/...`
