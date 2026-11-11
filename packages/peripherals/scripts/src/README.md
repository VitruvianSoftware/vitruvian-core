# Src

## Overview
Component package providing implementation for `packages/peripherals/scripts/src`.

## Interface
- `[lib.rs:Grade]`
- `[lib.rs:Plan]`
- `[lib.rs:plan]`
- `[lib.rs:build_bazel_flags]`
- `[lib.rs:pick_binary]`
- `[lib.rs:missing_arch]`
- `[lib.rs:main_rc]`
- `[lib.rs:sha256_digest]`
- `[lib.rs:generate_formula]`

## Invariants
- [lib.rs:100]: `// silently replace what was released. Require the tag; never guess it.`

## Side Effects
- None

## Verification
- Run: `bazel test //packages/peripherals/scripts/src/...`
