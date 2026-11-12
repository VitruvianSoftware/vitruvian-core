# Make Icons

## Overview
Component package providing implementation for `apps/desktop/vitruvian/bazel/src/make_icons`.

## Interface
- `[lib.rs:PRODUCTS]`
- `[lib.rs:Config]`
- `[lib.rs:parse_args]`
- `[lib.rs:run]`
- `[lib.rs:run_cli]`

## Invariants
- None

## Side Effects
- [lib.rs:105]: `.map_err(|e| format!("spawn {}: {}", staged_tool.display(), e))?;`

## Verification
- Run: `bazel test //apps/desktop/vitruvian/bazel/src/make_icons/...`
