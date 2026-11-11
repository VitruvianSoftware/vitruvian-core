# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/tempo/src`.

## Interface
- `[lib.rs:PKG_DIR]`
- `[lib.rs:load_values]`
- `[lib.rs:load_values_from_str]`
- `[lib.rs:check_single_replica_unless_pods_share_a_ring]`
- `[lib.rs:check_flushes_to_backend_on_shutdown]`
- `[lib.rs:check_wal_is_on_a_volume]`
- `[yaml.rs:resolve_data_path]`
- `[yaml.rs:parse_all]`
- `[yaml.rs:parse_doc]`

## Invariants
- [lib.rs:23]: `.unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));`
- [lib.rs:154]: `assert!(`
- [lib.rs:175]: `assert!(check_flushes_to_backend_on_shutdown(&v).is_err());`

## Side Effects
- None

## Verification
- Run: `bazel test //gitops/argocd/platform/tempo/src/...`
