# Gocompat

## Overview
Component package providing implementation for `tools/pipeline/unitfile/src/gocompat`.

## Interface
- `[exec.rs:Ctx]`
- `[exec.rs:notify_interrupt]`
- `[exec.rs:Io]`
- `[exec.rs:ExecError]`
- `[exec.rs:exit_code]`
- `[exec.rs:signal_name]`
- `[exec.rs:look_path]`
- `[exec.rs:Cmd]`
- `[exec.rs:Output]`
- `[exec.rs:run]`
- `[exec.rs:trim_space]`
- `[exec.rs:go_space]`
- `[exec.rs:go_trim]`
- `[exec.rs:eprint]`
- `[exec.rs:print]`
- `[flag.rs:Value]`
- `[flag.rs:Flag]`
- `[flag.rs:Parsed]`
- `[flag.rs:Exit]`
- `[flag.rs:usage]`

## Invariants
- [flag.rs:385]: `assert!(p.bool("v"));`
- [flag.rs:398]: `assert!(e`
- [flag.rs:404]: `assert!(e.stderr.starts_with("flag needs an argument: -format\n"));`
- [path.rs:213]: `assert!(rel("a", "/a").is_err());`

## Side Effects
- [exec.rs:21]: `//! Go's `os/exec` as the pipeline tools use it: `exec.CommandContext` with a`
- [exec.rs:24]: `//! `exec: "bazel": executable file not found in $PATH`, "context deadline`
- [exec.rs:140]: `/// `exec.LookPath` found nothing; the name as given.`
- [mod.rs:24]: `pub mod exec;`

## Verification
- Run: `bazel test //tools/pipeline/unitfile/src/gocompat/...`
