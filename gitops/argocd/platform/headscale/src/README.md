# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/headscale/src`.

## Interface
- `[lib.rs:PKG_DIR]`
- `[lib.rs:load_docs]`
- `[lib.rs:single_doc_of_kind]`
- `[lib.rs:load_headscale_values]`
- `[lib.rs:load_headplane_config]`
- `[lib.rs:POLICY_CONFIGMAP_NAME]`
- `[lib.rs:POLICY_PAUSE_CONFIGMAP_NAME]`
- `[lib.rs:POLICY_SYNC_METRICS_PORT]`
- `[lib.rs:POLICY_SYNC_PORT_NAME]`
- `[lib.rs:POLICY_SYNC_SERVICE_FILENAME]`
- `[lib.rs:check_policy_mode]`
- `[lib.rs:check_policy_lockout_guard]`
- `[lib.rs:check_rendered_headscale_deployment]`
- `[lib.rs:render_policy_configmap]`
- `[lib.rs:check_policy_configmap_drift]`
- `policy_configmap.rs`
- `policy_configmap_drift_test.rs`
- `policy_lockout_guard_test.rs`
- `policy_sync_test.rs`
- `render_check.rs`

## Invariants
- [lib.rs:22]: `.unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));`
- [lib.rs:23]: `yaml::parse_all(&raw).unwrap_or_else(|e| panic!("failed to parse {}: {e}", pa...`
- [lib.rs:106]: `assert!(target_names.contains(&"headscale"));`

## Side Effects
- [lib.rs:138]: `because Cloudflare Edge strips Upgrade headers on HTTP POST /ts2021."`
- [lib.rs:300]: `let hp = yaml::parse_doc("headscale:\n  url: http://headscale:8080\n").unwrap();`

## Verification
- Run: `bazel test //gitops/argocd/platform/headscale/src/...`
