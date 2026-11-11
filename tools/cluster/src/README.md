# Src

## Overview
Component package providing implementation for `tools/cluster/src`.

## Interface
- `[lib.rs:on_path]`
- `[lib.rs:logical_path]`
- `[lib.rs:UNIQ_WIDTH]`
- `[lib.rs:count_lines]`
- `[lib.rs:filter_namespace]`
- `[lib.rs:first_nonempty_line]`
- `[lib.rs:passthrough_args]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:484]: `assert!(count_lines(b"").is_empty());`

## Side Effects
- [lib.rs:26]: `//! replace this process with kubectl, as `exec` does. The diagnostics do the`
- [lib.rs:43]: `const MC_SCRIPT: &str = "mc alias set local http://localhost:9000 \"$MINIO_RO...`
- [lib.rs:384]: `let exec = kubectl(ctx, &["-n", &ns, "exec", &pod, "--", "sh", "-c", MC_SCRIP...`

## Verification
- Run: `bazel test //tools/cluster/src/...`
