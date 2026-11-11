# Src

## Overview
Component package providing implementation for `tools/pipeline/verifiedrun/src`.

## Interface
- `[http.rs:Response]`
- `[http.rs:post]`
- `[lib.rs:EXIT_VERIFIED]`
- `[lib.rs:EXIT_NOT_VERIFIED]`
- `[lib.rs:EXIT_SETUP]`
- `[lib.rs:EXIT_NOT_RECORDED]`
- `[lib.rs:strict_flags]`
- `[lib.rs:git]`
- `[lib.rs:tree_hash]`
- `[lib.rs:require_clean]`
- `[lib.rs:key_startup]`
- `[lib.rs:PlanEntry]`
- `[lib.rs:PlanResult]`
- `[lib.rs:decode_plan]`
- `[lib.rs:classify]`
- `[lib.rs:RunResult]`
- `[lib.rs:RecordFn]`
- `[lib.rs:Verifier]`
- `[lib.rs:real_main]`
- `[lib.rs:main_with]`

## Invariants
- [tests.rs:62]: `assert!(`
- [tests.rs:108]: `assert!(require_clean(&ctx, &dir).is_err());`
- [tests.rs:123]: `assert!(key_startup(ws, main)`

## Side Effects
- [http.rs:21]: `//! One HTTP POST, for the commit status. `http://` (a test server) goes over`
- [http.rs:22]: `//! a plain socket; `https://` through curl, since the standard library has`
- [http.rs:23]: `//! no TLS. The token reaches curl through its config on stdin, never argv.`
- [lib.rs:32]: `use unitfile::gocompat::exec::{self, Cmd, Ctx, Io};`
- [lib.rs:39]: `mod http;`
- [lib.rs:95]: `let (r, out) = exec::run(&c, ctx);`
- [record.rs:29]: `use unitfile::gocompat::exec::{self, Cmd, Ctx, Io};`
- [record.rs:34]: `use crate::http;`
- [record.rs:146]: `.map(exec::go_trim)`
- [shim.rs:39]: `use unitfile::gocompat::exec::{self, ExecError};`

## Verification
- Run: `bazel test //tools/pipeline/verifiedrun/src/...`
