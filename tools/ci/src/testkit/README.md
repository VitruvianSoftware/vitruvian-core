# Testkit

## Overview
Component package providing implementation for `tools/ci/src/testkit`.

## Interface
- `[lib.rs:bin]`
- `[lib.rs:TempDir]`
- `[lib.rs:write]`
- `[lib.rs:write_exe]`
- `[lib.rs:read]`
- `[lib.rs:path_with]`
- `[lib.rs:Output]`
- `[lib.rs:Run]`
- `[lib.rs:git]`
- `[lib.rs:git_init]`
- `[lib.rs:commit_file]`
- `[lib.rs:assert_has]`
- `[lib.rs:assert_lacks]`
- `[lib.rs:WorkflowJob]`
- `[lib.rs:workflow_jobs]`
- `[lib.rs:workflow_job_text]`
- `[lib.rs:names_job]`
- `[lib.rs:verdict_fail_open]`
- `[lib.rs:workflow_steps]`
- `[lib.rs:step_value]`

## Invariants
- [lib.rs:39]: `.unwrap_or_else(|| panic!("{var} is not set: the rust_test must pass $(rootpa...`
- [lib.rs:40]: `fs::canonicalize(&rel).unwrap_or_else(|e| panic!("{var}={}: {e}", Path::new(&...`
- [lib.rs:91]: `fs::write(path, contents).unwrap_or_else(|e| panic!("write {}: {e}", path.dis...`

## Side Effects
- [lib.rs:23]: `//! Each test runs the REAL binary as a subprocess, the way CI does, with fake`
- [lib.rs:24]: `//! `gh`/`gcloud`/`curl` scripts first on PATH and throwaway git repos, so no`
- [lib.rs:208]: `let mut child = self.cmd.spawn().expect("spawn the binary under test");`

## Verification
- Run: `bazel test //tools/ci/src/testkit/...`
