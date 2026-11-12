# Notarize

## Overview
Component package providing implementation for `apps/desktop/vitruvian-atrium/bazel/src/notarize`.

## Interface
- `[lib.rs:USAGE]`
- `[lib.rs:NotaryEnv]`
- `[lib.rs:NotarizePlan]`
- `[lib.rs:parse_cli_args]`
- `[lib.rs:plan]`
- `[lib.rs:build_notarize_commands]`
- `[lib.rs:notarize]`
- `[lib.rs:run_cli]`

## Invariants
- [lib.rs:247]: `assert!(!NotaryEnv::from_env(&env_map).complete());`
- [lib.rs:251]: `assert!(c.complete() && c.require_notarization);`
- [lib.rs:267]: `assert!(r.calls.is_empty());`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-atrium/bazel/src/notarize/...`
