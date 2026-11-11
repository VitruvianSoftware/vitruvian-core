# Transient Lib

## Overview
Component package providing implementation for `tools/ci/src/transient_lib`.

## Interface
- `[lib.rs:is_transient_network_error]`
- `[lib.rs:is_transient_network_error_file]`
- `[lib.rs:is_transient_go_test_error]`

## Invariants
- [lib.rs:133]: `assert!(is_transient_network_error(`
- [lib.rs:140]: `assert!(is_transient_network_error(`
- [lib.rs:147]: `assert!(is_transient_network_error(`

## Side Effects
- [lib.rs:155]: `b"Get \"https://proxy.golang.org/...\": net/http: TLS handshake timeout"`
- [lib.rs:188]: `b"Get \"https://proxy.golang.org/x\": net/http: request canceled while waitin...`

## Verification
- Run: `bazel test //tools/ci/src/transient_lib/...`
