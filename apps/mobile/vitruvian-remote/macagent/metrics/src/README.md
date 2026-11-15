# Src

## Overview
Component package providing implementation for `apps/mobile/vitruvian-remote/macagent/metrics/src`.

## Interface
- `[argocd.rs:ArgoApp]`
- `[argocd.rs:ArgoApps]`
- `[argocd.rs:parse_argo_apps]`
- `[argocd.rs:short_revision]`
- `[json.rs:JsonMap]`
- `[json.rs:JsonObject]`
- `[json.rs:JsonValue]`
- `[json.rs:write_escaped_str]`
- `[json.rs:escape_json_str]`
- `[metrics.rs:Snapshot]`
- `[metrics.rs:Host]`
- `[metrics.rs:CPU]`
- `[metrics.rs:Memory]`
- `[metrics.rs:Battery]`
- `[metrics.rs:Disk]`
- `[metrics.rs:Network]`
- `[metrics.rs:Thermal]`
- `[metrics.rs:CpuTicks]`
- `[metrics.rs:cpu_percent_from_ticks]`
- `[metrics.rs:parse_load_avg]`

## Invariants
- [argocd.rs:188]: `panic!("fixture {} not found", name);`
- [argocd.rs:204]: `assert!(!a.last_synced.is_zero(), "last_synced did not parse");`
- [argocd.rs:219]: `assert!(`
- [prs.rs:257]: `panic!("fixture {} not found", name);`
- [prs.rs:268]: `assert!(!pr.is_draft);`
- [prs.rs:269]: `assert!(`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/mobile/vitruvian-remote/macagent/metrics/src/...`
