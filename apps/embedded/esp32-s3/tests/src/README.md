# Src

## Overview
Component package providing implementation for `apps/embedded/esp32-s3/tests/src`.

## Interface
- `[lib.rs:component_dir]`
- `[lib.rs:repo_root]`
- `[lib.rs:read_component_file]`
- `[lib.rs:XorShift64]`
- `[lib.rs:Rect]`
- `[lib.rs:json_escape_str]`
- `[lib.rs:json_extract_str]`
- `[lib.rs:json_extract_i64]`
- `[lib.rs:json_extract_bool]`

## Invariants
- [lib.rs:97]: `fs::read_to_string(&path).unwrap_or_else(|e| panic!("failed to read {}: {}", ...`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/embedded/esp32-s3/tests/src/...`
