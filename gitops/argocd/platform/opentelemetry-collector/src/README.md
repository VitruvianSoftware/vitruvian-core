# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/opentelemetry-collector/src`.

## Interface
- `[lib.rs:PKG_DIR]`
- `[lib.rs:DEPRECATED]`
- `[lib.rs:deprecated_replacement]`
- `[lib.rs:load_config]`
- `[lib.rs:load_config_from_str]`
- `[lib.rs:check_exporters_and_connectors_use_current_names]`
- `[lib.rs:check_pipelines_reference_current_names]`
- `[yaml.rs:resolve_data_path]`
- `[yaml.rs:parse_all]`
- `[yaml.rs:parse_doc]`

## Invariants
- [lib.rs:35]: `.unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));`
- [lib.rs:138]: `assert!(err1.contains("use otlp_http") || err1.contains("use span_metrics"));`
- [lib.rs:140]: `assert!(err2.contains("pipeline traces exporters: otlp/tempo"));`

## Side Effects
- [lib.rs:126]: `endpoint: http://loki:3100/otlp`

## Verification
- Run: `bazel test //gitops/argocd/platform/opentelemetry-collector/src/...`
