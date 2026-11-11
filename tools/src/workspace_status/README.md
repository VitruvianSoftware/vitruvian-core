# Workspace Status

## Overview
Component package providing implementation for `tools/src/workspace_status`.

## Interface
- `[lib.rs:GITHOOKS_MSG_STDERR]`
- `[lib.rs:format_describe_version]`
- `[lib.rs:format_stamp_output]`
- `[lib.rs:format_primary_branch_guard]`
- `[lib.rs:xcode_version_matches]`
- `[lib.rs:check_repo_config_and_head]`
- `[lib.rs:run_in_dir]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:262]: `assert!(status.success(), "git {args:?} failed");`
- [lib.rs:278]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/src/workspace_status/...`
