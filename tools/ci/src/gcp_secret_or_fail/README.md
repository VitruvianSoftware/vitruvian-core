# Gcp Secret Or Fail

## Overview
Component package providing implementation for `tools/ci/src/gcp_secret_or_fail`.

## Interface
- `[lib.rs:secret_or_fail]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:21]: `//! //tools/ci:gcp_secret_or_fail — fetch a GCP Secret Manager secret's latest`
- [tests.rs:46]: `fn fetch(args: &[&str], rc: i32, stdout: &str, stderr: &str) -> Case {`
- [tests.rs:71]: `let c = fetch(`
- [tests.rs:87]: `let c = fetch(&["DATABASE_URL", "prj-x", ""], 0, "", "");`

## Verification
- Run: `bazel test //tools/ci/src/gcp_secret_or_fail/...`
