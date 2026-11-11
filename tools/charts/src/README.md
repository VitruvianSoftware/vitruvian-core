# Src

## Overview
Component package providing implementation for `tools/charts/src`.

## Interface
- `[lib.rs:ORG]`
- `[lib.rs:CHART_DIR]`
- `[lib.rs:logical_pwd]`
- `[lib.rs:is_chart_path]`
- `[lib.rs:find_charts]`
- `[lib.rs:grep_q_anchored]`
- `[lib.rs:chart_name]`
- `[lib.rs:package_glob]`
- `[lib.rs:run]`

## Invariants
- [lib.rs:444]: `assert!(is_chart_path(b"./apps/x/deploy/chart/Chart.yaml"));`
- [lib.rs:445]: `assert!(is_chart_path(b"./deploy/chart/Chart.yaml"));`
- [lib.rs:446]: `assert!(!is_chart_path(b"./bazel-out/x/deploy/chart/Chart.yaml"));`

## Side Effects
- None

## Verification
- Run: `bazel test //tools/charts/src/...`
