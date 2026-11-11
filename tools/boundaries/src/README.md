# Src

## Overview
Component package providing implementation for `tools/boundaries/src`.

## Interface
- `[lib.rs:LAYER_PLATFORM_TOOLS]`
- `[lib.rs:LAYER_INFRA]`
- `[lib.rs:LAYER_SHARED_PACKAGES]`
- `[lib.rs:LAYER_APPS]`
- `[lib.rs:layer_name]`
- `[lib.rs:get_app_name]`
- `[lib.rs:resolve_target_layer]`
- `[lib.rs:validate_dependency]`

## Invariants
- [lib.rs:383]: `assert!(v.is_empty());`
- [lib.rs:389]: `assert!(v.is_empty());`
- [lib.rs:395]: `assert!(v.is_empty());`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/boundaries/src/...`
