# Src

## Overview
Component package providing implementation for `tools/license/src`.

## Interface
- `[lib.rs:APPS]`
- `[lib.rs:PATHSPECS]`
- `[lib.rs:is_exempt]`
- `[lib.rs:has_holder]`
- `[lib.rs:has_any_header]`
- `[lib.rs:has_mit_grant]`
- `[lib.rs:verify]`
- `[lib.rs:verify_in]`
- `[lib.rs:enter_workspace]`

## Invariants
- [lib.rs:282]: `assert!(has_holder(b"// Copyright (c) 2026 VitruvianSoftware\n"));`
- [lib.rs:283]: `assert!(has_holder(`
- [lib.rs:286]: `assert!(!has_holder(b"Copyright (c) 202 VitruvianSoftware"));`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/license/src/...`
