# Src

## Overview
Component package providing implementation for `apps/suites/tabula/extension/scripts/src`.

## Interface
- `[publish_dev_latest.rs:tag_from_env]`
- `[publish_dev_latest.rs:build_info_json]`
- `[publish_dev_latest.rs:chrome_zip_bazel_bin_path]`
- `[publish_dev_latest.rs:chrome_zip_bazel_target]`
- `[publish_dev_latest.rs:run]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [lib.rs:40]: `assert!(json.contains("\"commit\":\"abc123\""));`
- [lib.rs:41]: `assert!(json.contains("\"builtAt\":\"2026-10-25T12:00:00Z\""));`
- [lib.rs:42]: `assert!(json.contains("\"version\":\"9.9.9\""));`
- [publish_dev_latest.rs:164]: `"require('./apps/suites/tabula/extension/package.json').version",`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/suites/tabula/extension/scripts/src/...`
