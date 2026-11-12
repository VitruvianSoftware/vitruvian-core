# Src

## Overview
Component package providing implementation for `apps/suites/vitruvian-tabs/cli/rs/src`.

## Interface
- `[lib.rs:help_text]`
- `[lib.rs:run_cli]`
- Subdirectory: [commands](./commands/README.md)
- Subdirectory: [utils](./utils/README.md)

## Invariants
- [lib.rs:201]: `assert!(p.ends_with(".vitruvian-tabs/extension"));`
- [lib.rs:248]: `assert!(err.contains("manifest.json"));`
- [lib.rs:261]: `assert!(target.join("manifest.json").exists());`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/suites/vitruvian-tabs/cli/rs/src/...`
