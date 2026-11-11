# Resolve Deploy Base

## Overview
Component package providing implementation for `tools/ci/src/resolve_deploy_base`.

## Interface
- `[lib.rs:run]`

## Invariants
- [tests.rs:333]: `assert!(!elsewhere.join("out.txt").exists());`

## Side Effects
- [lib.rs:103]: `b"REPO/GITHUB_REPOSITORY unset -- cannot query run history",`
- [tests.rs:29]: `// A query for the legacy workflow (`-w legacy.yaml`) answers from`
- [tests.rs:42]: `echo "gh: HTTP 404 (legacy)" >&2`
- [tests.rs:49]: `echo "gh: HTTP 502 (something went wrong)" >&2`

## Verification
- Run: `bazel test //tools/ci/src/resolve_deploy_base/...`
