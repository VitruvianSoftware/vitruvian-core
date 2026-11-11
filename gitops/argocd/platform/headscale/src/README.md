# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/headscale/src`.

## Interface
- `[lib.rs:PKG_DIR]`
- `[lib.rs:load_docs]`
- `[lib.rs:single_doc_of_kind]`
- `[lib.rs:load_headscale_values]`
- `[lib.rs:load_headplane_config]`
- `[lib.rs:check_policy_mode]`
- `[yaml.rs:resolve_data_path]`
- `[yaml.rs:parse_all]`
- `[yaml.rs:parse_doc]`

## Invariants
- [lib.rs:22]: `.unwrap_or_else(|e| panic!("failed to read {}: {e}", path.display()));`
- [lib.rs:23]: `yaml::parse_all(&raw).unwrap_or_else(|e| panic!("failed to parse {}: {e}", pa...`
- [lib.rs:106]: `assert!(target_names.contains(&"headscale"));`

## Side Effects
- [lib.rs:138]: `because Cloudflare Edge strips Upgrade headers on HTTP POST /ts2021."`
- [lib.rs:300]: `let hp = yaml::parse_doc("headscale:\n  url: http://headscale:8080\n").unwrap();`

## Verification
- Run: `bazel test //gitops/argocd/platform/headscale/src/...`
