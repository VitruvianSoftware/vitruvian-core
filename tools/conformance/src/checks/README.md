# Checks

## Overview
Component package providing implementation for `tools/conformance/src/checks`.

## Interface
- `[app.rs:get_app_dirs]`
- `[app.rs:check_app_visibility]`
- `[app.rs:check_app_metadata]`
- `[app.rs:check_techdocs]`
- `[brew.rs:problems]`
- `[brew.rs:check_brew_tap_instructions]`
- `[catalog.rs:check_catalog]`
- `[catalog.rs:check_standalone_workspace_deps]`
- `[catalog.rs:catalog_orphan_sweep]`
- `[catalog.rs:advisory_catalog]`
- `[ci.rs:check_merge_queue]`
- `[ci.rs:check_postsubmit_concurrency]`
- `[ci.rs:check_job_timeouts]`
- `[ci.rs:check_sweep_backstop]`
- `[ci.rs:cache_save_expr_guarded]`
- `[ci.rs:yaml_value_of]`
- `[ci.rs:uses_setup_bazel_directly]`
- `[ci.rs:repo_restore_step_guarded]`
- `[ci.rs:repository_restore_problems]`
- `[ci.rs:llvm_restore_branch_problems]`

## Invariants
- [brew.rs:192]: `assert!(problems(text).is_empty(), "{:?}", problems(text));`
- [brew.rs:195]: `assert!(problems(text).is_empty(), "{:?}", problems(text));`
- [brew.rs:206]: `assert!(got[0].contains("brew install <tap>/devx"));`
- [swift_tests.rs:264]: `assert!(rows.contains("apps/a/BUILD"), "{rows}");`
- [swift_tests.rs:265]: `assert!(`
- [swift_tests.rs:269]: `assert!(rows.contains("apps/a/Tests/ATests/More.swift:1"), "{rows}");`

## Side Effects
- [labels.rs:31]: `//! (build, test, run, query, cquery, aquery, coverage), and a YAML value that`
- [labels.rs:36]: `//! How they are resolved: ONE `bazel query --keep_going` over the whole set.`
- [labels.rs:42]: `//! not `//tools/conformance:check`. The query is NOT cheap on a fresh output`
- [security.rs:235]: `"step leaves GITHUB_TOKEN in .git/config where any runner subprocess can read...`

## Verification
- Run: `bazel test //tools/conformance/src/checks/...`
