# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/thanos/src`.

## Interface
- `[lib.rs:PKG_DIR]`
- `[lib.rs:QUERY_SAMPLES_CAP]`
- `[lib.rs:load_values]`
- `[lib.rs:load_values_from_str]`
- `[lib.rs:flag_value]`
- `[lib.rs:extra_args]`
- `[lib.rs:memory_limit]`
- `[yaml.rs:resolve_data_path]`
- `[yaml.rs:parse_all]`
- `[yaml.rs:parse_doc]`

## Invariants
- [lib.rs:25]: `.unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));`
- [lib.rs:107]: `assert!(args.iter().any(|a| a == "--enable-auto-gomemlimit"));`
- [lib.rs:108]: `assert!(flag_value(&args, "--store.limits.request-series").unwrap() > 0);`

## Side Effects
- [lib.rs:88]: `assert_eq!(memory_limit(&v, "query"), Some("2Gi"));`
- [lib.rs:106]: `let args = extra_args(&v, "query");`
- [lib.rs:110]: `assert!(flag_value(&args, "--query.max-concurrent").unwrap() > 0);`

## Verification
- Run: `bazel test //gitops/argocd/platform/thanos/src/...`
