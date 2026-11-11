# Chart Render

## Overview
Component package providing implementation for `tools/ci/src/chart_render`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:412]: `assert!(paths.is_empty());`
- [lib.rs:425]: `assert!(extracted.is_empty());`
- [lib.rs:466]: `assert!(guarded.is_none());`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/chart_render/...`
