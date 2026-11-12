# Zip Tool

## Overview
Component package providing implementation for `apps/desktop/home-speaker/scripts/src/zip_tool`.

## Interface
- `[lib.rs:Config]`
- `[lib.rs:parse_args]`
- `[lib.rs:read_manifest_version]`
- `[lib.rs:determine_pkg_dir]`
- `[lib.rs:find_binary]`
- `[lib.rs:stage_files]`
- `[lib.rs:compute_sha256]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:458]: `assert!(`
- [lib.rs:463]: `assert!(`
- [lib.rs:485]: `assert!(`

## Side Effects
- [lib.rs:472]: `let tmp = make_temp("exec-bit");`

## Verification
- Run: `bazel test //apps/desktop/home-speaker/scripts/src/zip_tool/...`
