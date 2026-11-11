# Src

## Overview
Component package providing implementation for `tools/deploy/src`.

## Interface
- `[lib.rs:bash_echo]`
- `[lib.rs:resolve_smoke_url]`
- `[lib.rs:looks_not_found]`
- `[lib.rs:serving_revision]`
- `[lib.rs:resolve_stable_revision]`
- `[lib.rs:image_env_kv]`
- `[lib.rs:sed_spaced_eq]`
- `[lib.rs:jq_candidate_urls]`
- `[lib.rs:export_name]`
- `[lib.rs:run]`

## Invariants
- [launcher_check.rs:52]: `.unwrap_or_else(|| panic!("{f} is not among the baked args {baked:?}"));`
- [launcher_check.rs:79]: `assert!(`
- [launcher_check.rs:132]: `.unwrap_or_else(|e| panic!("could not start {}: {e}", deploy.display()));`

## Side Effects
- [launcher_check.rs:29]: `//! real pulumi, gcloud or curl can run. `--phase candidate` with a fixed`
- [lib.rs:24]: `//! curl calls and the same <PREFIX>_ variables handed to them.`

## Verification
- Run: `bazel test //tools/deploy/src/...`
