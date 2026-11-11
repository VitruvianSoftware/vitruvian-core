# Src

## Overview
Component package providing implementation for `tools/ci/prometheus-rule-tests/src`.

## Interface
- `[lib.rs:APPSET_REL_PATH]`
- `[lib.rs:strip_gotemplate_delimiters]`
- `[lib.rs:resolve_here_dir]`
- `[lib.rs:list_test_yml_files]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- [lib.rs:205]: `.spawn()`

## Verification
- Run: `bazel test //tools/ci/prometheus-rule-tests/src/...`
