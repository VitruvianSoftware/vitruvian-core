# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/envoy-gateway/src`.

## Interface
- `[lib.rs:PKG_DIR]`
- `[lib.rs:validate_envoyproxy_docs]`
- `[yaml.rs:resolve_data_path]`
- `[yaml.rs:parse_all]`
- `[yaml.rs:parse_doc]`

## Invariants
- [lib.rs:70]: `.unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));`
- [lib.rs:101]: `assert!(validate_envoyproxy_docs(&docs).is_ok());`
- [lib.rs:126]: `assert!(`

## Side Effects
- [lib.rs:93]: `- name: http-80`
- [lib.rs:121]: `- name: http-80`

## Verification
- Run: `bazel test //gitops/argocd/platform/envoy-gateway/src/...`
