# Src

## Overview
Component package providing implementation for `tools/delivery/orchestrate/src`.

## Interface
- `[flags.rs:Flags]`
- `[flags.rs:Outcome]`
- `[flags.rs:usage]`
- `[flags.rs:parse]`
- `[gostd.rs:is_print]`
- `[gostd.rs:quote]`
- `[gostd.rs:quote_rune]`
- `[gostd.rs:clean]`
- `[gostd.rs:join]`
- `[gostd.rs:base]`
- `[gostd.rs:errno_text]`
- `[gostd.rs:path_error]`
- `[gostd.rs:read_file]`
- `[gostd.rs:GoCmd]`
- `[gostd.rs:exit_status_string]`
- `[gostd.rs:getwd]`
- `[json.rs:GoFormatter]`
- `[json.rs:marshal]`
- `[json.rs:marshal_indent]`
- `[json.rs:Val]`

## Invariants
- [flags.rs:133]: `assert!(m.starts_with(`
- [flags.rs:136]: `assert!(run(&["-out"])`
- [flags.rs:140]: `assert!(run(&["---x"])`
- [tests.rs:81]: `assert!(`
- [tests.rs:118]: `.unwrap_or_else(|e| panic!("the real decision engine is missing at {}: {}", r...`
- [tests.rs:234]: `.unwrap_or_else(|| panic!("unit {} missing from manifest: {}", name, self.man...`

## Side Effects
- [gostd.rs:23]: `//! os and os/exec, and exec.LookPath. Each one copies Go's behaviour so that`
- [gostd.rs:197]: `/// exec.LookPath, against the orchestrator's OWN $PATH (exec.Command`
- [gostd.rs:203]: `.map_err(|e| format!("exec: {}: {}", quote(file), e));`
- [lib.rs:28]: `//!  1. DISCOVER — `bazel query` the "delivery" tag, `bazel build` the units,`
- [lib.rs:161]: `"query".into(),`
- [lib.rs:170]: `Some(format!("bazel query for delivery units failed: {}", e)),`
- [tests.rs:21]: `//! main_test.go, ported. bazel is FAKED (a stub printing canned query output`
- [tests.rs:148]: `let mut query = "true".to_string();`
- [tests.rs:150]: `query = "printf '%s\\n'".to_string();`

## Verification
- Run: `bazel test //tools/delivery/orchestrate/src/...`
