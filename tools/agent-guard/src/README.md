# Src

## Overview
Component package providing implementation for `tools/agent-guard/src`.

## Interface
- `[classify.rs:GUARDRAIL]`
- `[classify.rs:Verdict]`
- `[classify.rs:Target]`
- `[classify.rs:T_COMMIT]`
- `[classify.rs:T_PUSH]`
- `[classify.rs:T_SYNC]`
- `[classify.rs:T_WT_NEW]`
- `[classify.rs:T_WT_DETACH]`
- `[classify.rs:T_WT_REMOVE]`
- `[classify.rs:T_WT_PRUNE]`
- `[classify.rs:T_WT_LOCK]`
- `[classify.rs:T_WT_DELETE_BRANCH]`
- `[classify.rs:T_PR_CREATE]`
- `[classify.rs:T_PR_ENQUEUE]`
- `[classify.rs:T_RUN_RERUN]`
- `[classify.rs:T_RUN_CANCEL]`
- `[classify.rs:T_WORKFLOW_RUN]`
- `[classify.rs:RUN_NOTE]`
- `[classify.rs:RUN_NO_TARGET_NOTE]`
- `[classify.rs:T_SECRET_SCAN]`

## Invariants
- [hook.rs:27]: `use std::panic::{catch_unwind, AssertUnwindSafe};`
- [hook.rs:110]: `/// What a panic carried, as Python's `repr(exc)` would show the exception.`
- [hook.rs:303]: `assert!(t.ends_with('Z') && &t[4..5] == "-" && &t[10..11] == "T" && &t[19..20...`
- [main.rs:31]: `// A guard bug is caught and logged (hook::main catches the panic);`
- [main.rs:33]: `std::panic::set_hook(Box::new(|_| {}));`
- [paths.rs:28]: `/// catch it; the hook then allows the call and logs the error. A panic is the`
- [paths.rs:32]: `panic!("ValueError: embedded null byte");`
- [paths.rs:267]: `Err(_) => panic!("UnicodeDecodeError: {}", p),`
- [pyutil.rs:491]: `assert!(is_space('\u{a0}') && is_space('\x1c') && !is_space('\u{200b}'));`
- [pyutil.rs:492]: `assert!(is_digit('²') && !is_decimal('²') && is_decimal('٣'));`

## Side Effects
- [classify.rs:280]: `"fetch",`
- [classify.rs:332]: `"--exec-path",`
- [classify.rs:401]: `/// What makes this fetch (or pull) write a ref it names, or "" if nothing does.`
- [gitstate.rs:71]: `let mut child = cmd.spawn().ok()?;`
- [gitstate.rs:75]: `std::thread::spawn(move || {`
- [gitstate.rs:80]: `let reader = std::thread::spawn(move || {`
- [guard.rs:69]: `("kubectl", "kubectl writes (apply, delete, patch, edit, exec, rollout, scale...`
- [guard.rs:73]: `("docker", "docker/podman build, run, push, exec, compose up: building or run...`
- [invocations.rs:284]: `"exec",`
- [invocations.rs:379]: `if p == "direnv" && first == Some("exec") {`

## Verification
- Run: `bazel test //tools/agent-guard/src/...`
