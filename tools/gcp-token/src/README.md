# Src

## Overview
Component package providing implementation for `tools/gcp-token/src`.

## Interface
- `[lib.rs:disallowed_chars]`
- `[lib.rs:describe_bytes]`
- `[lib.rs:looks_like_email]`
- `[lib.rs:is_token]`
- `[lib.rs:remote_cmd]`
- `[lib.rs:classify]`
- `[lib.rs:order_brokers]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:150]: `exec \"$G\" auth print-access-token --account=",`

## Verification
- Run: `bazel test //tools/gcp-token/src/...`
