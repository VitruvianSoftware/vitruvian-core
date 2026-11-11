# Src

## Overview
Component package providing implementation for `apps/desktop/vitruvian-tool-github/tests_rs/src`.

## Interface
- `[conformance.rs:ConformancePaths]`
- `[conformance.rs:resolve_paths]`
- `[conformance.rs:run_conformance]`
- `[mirror_workflows.rs:Step]`
- `[mirror_workflows.rs:Job]`
- `[mirror_workflows.rs:Workflow]`
- `[mirror_workflows.rs:parse_workflow]`
- `[mirror_workflows.rs:find_step_run]`
- `[mirror_workflows.rs:detect]`
- `[mirror_workflows.rs:detect_problems]`
- `[mirror_workflows.rs:notes_problems]`
- `[mirror_workflows.rs:limit_problems]`
- `[mirror_workflows.rs:load_workflow]`
- `[version.rs:semver]`
- `[version.rs:release_please_layout]`
- `[version.rs:check_version]`

## Invariants
- [conformance.rs:99]: `.unwrap_or_else(|e| panic!("failed to run {name}: {e}"));`
- [mirror_workflows.rs:334]: `.unwrap_or_else(|| panic!("release.yml has no job {job_name}"));`
- [mirror_workflows.rs:345]: `.unwrap_or_else(|| panic!("step with {key}={value} has no run"));`
- [mirror_workflows.rs:348]: `panic!("release.yml's {job_name} job has no step with {key} {value:?}")`
- [version.rs:251]: `assert!(formatted.ends_with('\n'));`
- [version.rs:252]: `assert!(formatted.contains("  "));`
- [version.rs:293]: `assert!(parsed < KIT_WITH_STATUS_WORDS);`

## Side Effects
- None

## Verification
- Run: `bazel test //apps/desktop/vitruvian-tool-github/tests_rs/src/...`
