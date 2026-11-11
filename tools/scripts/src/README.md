# Src

## Overview
Component package providing implementation for `tools/scripts/src`.

## Interface
- `[agy.rs:run]`
- `[copilot.rs:run]`
- `[kind_cluster.rs:run]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [agy.rs:77]: `assert!(!is_executable("/nonexistent/path/to/agy"));`
- [agy.rs:82]: `assert!(find_in_path("__nonexistent_tool_xyz__").is_none());`
- [copilot.rs:51]: `assert!(forward.is_empty());`
- [kind_cluster.rs:340]: `assert!(help.contains("create"));`
- [kind_cluster.rs:341]: `assert!(help.contains("delete"));`
- [kind_cluster.rs:342]: `assert!(help.contains("restart"));`

## Side Effects
- [agy.rs:60]: `let err = Command::new(candidate).args(&forward_args).exec();`
- [agy.rs:61]: `eprintln!("exec failed: {err}");`
- [kind_cluster.rs:244]: `- Access services at localhost:8080 (HTTP) or localhost:8443 (HTTPS)`
- [kind_cluster.rs:333]: `- Access services at localhost:8080 (HTTP) or localhost:8443 (HTTPS)`

## Verification
- Run: `bazel test //tools/scripts/src/...`
