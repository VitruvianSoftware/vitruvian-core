# Src

## Overview
Component package providing implementation for `tools/githooks/src`.

## Interface
- `[check_config.rs:GITHOOKS_MSG_STDERR]`
- `[check_config.rs:format_primary_branch_guard]`
- `[check_config.rs:strip_ascii_whitespace]`
- `[check_config.rs:xcode_version_matches]`
- `[check_config.rs:info_plist_path_from_dev_dir]`
- `[check_config.rs:run]`
- `[pre_commit.rs:BAZEL_ENV_FORMAT]`
- `[pre_commit.rs:BAZEL_ENV_GAZELLE]`
- `[pre_commit.rs:parse_nul_delimited_paths]`
- `[pre_commit.rs:run]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [check_config.rs:194]: `assert!(xcode_version_matches(b"27.0", b"27.0"));`
- [check_config.rs:195]: `assert!(xcode_version_matches(b"27.0.1", b"27.0"));`
- [check_config.rs:196]: `assert!(!xcode_version_matches(b"27.1", b"27.0"));`
- [pre_commit.rs:200]: `assert!(parse_nul_delimited_paths(b"").is_empty());`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/githooks/src/...`
