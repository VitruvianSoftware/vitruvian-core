# Vitruvian Tabs Deploy Preflight

## Overview
Component package providing implementation for `tools/ci/src/vitruvian_tabs_deploy_preflight`.

## Interface
- `[lib.rs:run]`

## Invariants
- [lib.rs:67]: `fn require(name: &str) -> Result<Vec<u8>, i32> {`
- [lib.rs:78]: `let deploy_env = match require("DEPLOY_ENV") {`
- [lib.rs:82]: `let gcp_project_id = match require("GCP_PROJECT_ID") {`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/ci/src/vitruvian_tabs_deploy_preflight/...`
