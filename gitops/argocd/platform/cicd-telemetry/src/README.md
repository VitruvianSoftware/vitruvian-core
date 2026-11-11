# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/cicd-telemetry/src`.

## Interface
- `[lib.rs:PKG_DIR]`
- `[lib.rs:DEPENDABOT_RUN_NAMES]`
- `[lib.rs:WORKFLOW_NAMES]`
- `[lib.rs:load_collector]`
- `[lib.rs:trace_statements]`
- `[lib.rs:parse_replace_pattern_statement]`
- `[lib.rs:collapse_pipeline_name]`
- `[lib.rs:find_bare_ottl_paths]`
- `[lib.rs:regex_captures]`
- `[lib.rs:regex_is_match]`
- `[lib.rs:regex_replace_anchored]`
- `[yaml.rs:resolve_data_path]`
- `[yaml.rs:parse_all]`
- `[yaml.rs:parse_doc]`

## Invariants
- [lib.rs:72]: `"Require Dev Soak Test",`
- [lib.rs:117]: `.unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));`

## Side Effects
- None

## Verification
- Run: `bazel test //gitops/argocd/platform/cicd-telemetry/src/...`
