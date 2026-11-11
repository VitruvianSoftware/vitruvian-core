# Backstage Boot Smoke

## Overview
Component package providing implementation for `tools/ci/src/backstage_boot_smoke`.

## Interface
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:85]: `baseUrl: http://localhost:7007`
- [lib.rs:98]: `baseUrl: http://localhost:7007`
- [lib.rs:191]: `.arg("exec docker logs \"$1\" 2>&1")`

## Verification
- Run: `bazel test //tools/ci/src/backstage_boot_smoke/...`
