# Gitops Values Render

## Overview
Component package providing implementation for `tools/ci/src/gitops_values_render`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:470]: `assert!(is_http(b"http://example.com/charts"));`
- [lib.rs:471]: `assert!(is_http(b"https://charts.example.com"));`
- [lib.rs:472]: `assert!(!is_http(b"ghcr.io/org/charts"));`

## Side Effects
- [lib.rs:84]: `repo.starts_with(b"http://") || repo.starts_with(b"https://")`
- [lib.rs:329]: `b"discovered no chart+values pairs -- the discovery query \`
- [lib.rs:330]: `matched nothing, which means this gate is inert. Fix the query, do not delete...`

## Verification
- Run: `bazel test //tools/ci/src/gitops_values_render/...`
