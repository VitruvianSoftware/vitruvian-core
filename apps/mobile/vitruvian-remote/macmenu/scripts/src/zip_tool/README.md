# Zip Tool

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/macmenu/scripts/src/zip_tool`.

## Interface
- `[lib.rs:PKG]`
- `[lib.rs:Options]`
- `[lib.rs:manifest_version]`
- `[lib.rs:minos_per_arch]`
- `[lib.rs:newer_than]`
- `[lib.rs:package]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:385]: `assert!(newer_than("14.10", "14.9"));`
- [lib.rs:386]: `assert!(newer_than("15.0", "14.99"));`
- [lib.rs:387]: `assert!(!newer_than("14.0", "14.0"));`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/macmenu/scripts/src/zip_tool/...`
