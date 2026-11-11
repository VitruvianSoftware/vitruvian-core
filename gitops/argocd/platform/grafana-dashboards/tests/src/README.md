# Src

## Overview
Component package providing implementation for `gitops/argocd/platform/grafana-dashboards/tests/src`.

## Interface
- `[ci_pipelines.rs:EXCLUDE]`
- `[ci_pipelines.rs:find_ci_pipelines_file]`
- `[ci_pipelines.rs:all_panels]`
- `[ci_pipelines.rs:check_ci_pipelines_dashboard]`
- `[ci_pipelines.rs:run_ci_pipelines_on_file]`
- `[ci_pipelines.rs:run_ci_pipelines_test]`
- `[lib.rs:TARGET_DASHBOARDS_6]`
- `[lib.rs:TARGET_DASHBOARDS_5]`
- `[lib.rs:find_dashboards_dir]`
- `[lib.rs:collect_all_panels]`
- `[lib.rs:py_str_repr]`
- `[lib.rs:py_repr]`
- `[lib.rs:py_display_opt]`
- `[lib.rs:TapContext]`
- `[lib.rs:as_json_i64]`
- `[lib.rs:load_json_file]`
- `[runner.rs:TIERS]`
- `[runner.rs:TierResult]`
- `[runner.rs:usage_text]`
- `[runner.rs:resolve_workspace_root]`
- Subdirectory: [bin](./bin/README.md)

## Invariants
- [ci_pipelines.rs:254]: `assert!(out.contains("FAIL  smoke runs not excluded: panel 'Failure rate per ...`
- [ci_pipelines.rs:255]: `assert!(out.contains("FAIL  panel 'Failure rate per stage' uses rate()/increa...`
- [ci_pipelines.rs:256]: `assert!(out.contains("FAIL  panel 'Failure rate per stage' drops restarted po...`
- [runner.rs:411]: `assert!(json_str.contains("\"suite\": \"grafana_dashboards_e2e\""));`
- [runner.rs:412]: `assert!(json_str.contains("\"total_tests\": 110"));`
- [runner.rs:413]: `assert!(json_str.contains("\"passed_tests\": 109"));`
- [tier3.rs:266]: `assert!(out.contains("# Tier 3 Results: 30/30 tests passed"));`
- [tier3.rs:267]: `assert!(out.contains("# Tier 3 Integration & Consistency Test: ALL TESTS PASS...`
- [tier3.rs:278]: `assert!(out.contains("not ok 1 - Kustomization existence"));`

## Side Effects
- [ci_pipelines.rs:6]: `//! Ensures `ci-pipelines.json` excludes `cicd-telemetry smoke.*` runs from e...`
- [ci_pipelines.rs:166]: `let q = match v.get("query") {`
- [ci_pipelines.rs:167]: `Some(Value::Object(obj)) => obj.get("query").and_then(Value::as_str).unwrap_o...`
- [tier1.rs:322]: `let q = v.get("query").and_then(Value::as_str)?;`
- [tier1.rs:469]: `.get("query")`
- [tier1.rs:475]: `"Panel {} target #{} missing 'expr' query",`
- [tier2.rs:326]: `// 1. PromQL Query Syntax and Target Parsing`
- [tier2.rs:377]: `// 2. Template Variables Query Syntax Validation`
- [tier2.rs:390]: `if vtype == "query" {`
- [tier4.rs:7]: `//! in the k3s cluster, verifying metric resolution, query syntax execution, ...`

## Verification
- Run: `bazel test //gitops/argocd/platform/grafana-dashboards/tests/src/...`
