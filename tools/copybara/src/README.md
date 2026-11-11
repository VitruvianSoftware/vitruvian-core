# Src

## Overview
Component package providing implementation for `tools/copybara/src`.

## Interface
- `[lib.rs:PyJson]`
- `[lib.rs:py_float_repr]`
- `[lib.rs:py_repr_str]`
- `[lib.rs:py_space]`
- `[lib.rs:universal_newlines]`
- `[lib.rs:py_join]`
- `[lib.rs:strip_major]`
- `[lib.rs:find_map]`
- `[lib.rs:find_pairs]`
- `[lib.rs:to_dict]`
- `[lib.rs:Crash]`
- `[lib.rs:glob_package_jsons]`
- `[lib.rs:Paths]`
- `[lib.rs:Outcome]`
- `[lib.rs:check]`
- `[lib.rs:run]`

## Invariants
- None

## Side Effects
- None

## Verification
- Run: `bazel test //tools/copybara/src/...`
