# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/prometheus/src`.

## Interface
- `[lib.rs:PKG_DIR]`
- `[lib.rs:QUERIER_SAMPLES_CAP]`
- `[lib.rs:load_values]`
- `[lib.rs:load_values_from_str]`
- `[lib.rs:resource_job]`
- `[lib.rs:prometheus_regex_fullmatch]`
- `[yaml.rs:resolve_data_path]`
- `[yaml.rs:parse_all]`
- `[yaml.rs:parse_doc]`

## Invariants
- [lib.rs:22]: `.unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));`
- [lib.rs:140]: `assert!(args`
- [lib.rs:160]: `assert!(cap > QUERIER_SAMPLES_CAP);`

## Side Effects
- None

## Verification
- Run: `bazel test //gitops/argocd/platform/prometheus/src/...`
